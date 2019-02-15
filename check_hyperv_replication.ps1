# Powershell script executed by nagios to check health of Microsoft Hyper-V Replicas


# CHANGE LOG
# ----------
#  2019/02/11	Nick Jeffrey	Script created
#  2019/02/14	Nick Jeffrey	Try to automatically resume replication when problems are found
#  2019/02/15	Nick Jeffrey	Add VM names to output


# FUTURE ENHANCEMENTS
# -------------------
#  1. Document how to use this script if the Windows host is running the OpenSSH daemon available in Win10 / Win2019
#  2. Document how to set SSH preshared keys for OpenSSH daemon on Windows and powershellserver.com daemon
#  3. Document how to use Powershell remoting from Linux to Windows
#  4. Add nagios perfdata to output


# USAGE NOTES
# -----------
#
# If your Windows host has a working SSH daemon, you can use check_by_ssh on the nagios server.
# For example, add the following section to services.cfg on the nagios server:
#    # Define a service to check Hyper-V Replica status on a Windows server with running SSH daemon from www.powershellserver.com
#    # This check assumes the default shell used by the SSH daemon is powershell.exe
#    define service{
#       use                            generic-14x7-service
#       hostgroup_name                 all_hyperv
#       service_description            Hyper-V Replica
#       check_command                  check_by_ssh!"C:/util/check_hyperv_replication.ps1"
#       }
#
# 
# If your Windows host is using NRPE or NSClient++ to listen for requests from the nagios server:
#  Add an external command to your nsclient.ini on the Windows host similar to the following: 
#     checkhypervreplica=cmd /c echo scripts\check-hypervreplica.ps1; exit($lastexitcode) | powershell.exe -command - 
#  On the nagios server, add a section similar to the following to commands.cfg:
#     # 'check_hyperv_replica' command definition
#     # This is a slightly tweaked version of check_nt
#     define command{
#        command_name    check_hyperv_replica
#        command_line    $USER1$/check_nrpe -H $HOSTADDRESS$ 
#        }
#  On the nagios server, add a section similar to the following to services.cfg:
#     # Define a service to check a Windows box over nrpe (nc_net or nsclient++)
#     define service{
#             use                             generic-14x7-service
#             hostgroup_name                  all_hyperv
#             service_description             Hyper-V Replica
#             check_command                   check_hyperv_replica
#             }




 

 

# declare variables
$ComputerName=$env:COMPUTERNAME
$OK        = 0    #nagios return codes
$Warning   = 1    #nagios return codes
$Critical  = 2    #nagios return codes 
$Unknown   = 3    #nagios return codes
$CheckName = "Hyper-V Replica"


# Confirm Hyper-V Replica has been configured
$VMs = Measure-VMReplication | select VMName  # Get a list of all replication-enabled virtual machines on the local Hyper-V host
$VMs = $($VMs.VMname)
if (!($VMs)) {
   Write-Host "$CheckName has not been configured on this machine.  No virtual machines are set to replicate to another host. `n" 
   exit $Unknown 
}


# Check the replication health status of each virtual machine
$HealthyVMs   = Measure-VMReplication -ComputerName $ComputerName -ErrorAction Stop | Where-Object {$_.ReplicationHealth -eq "Normal"} 
$UnhealthyVMs = Measure-VMReplication -ComputerName $ComputerName -ErrorAction Stop | Where-Object {$_.ReplicationHealth -ne "Normal"} 




# NOTE: This section will try to automatically resume any VMReplication processes that are not in a healthy state.
#       The "Resume-VMReplication" command does require admin privileges, so this command will fail if running from a low privilege account
# Try to resume replication for any virtual machines that have stopped replication
# Only resume on the primary copy, not the replica
foreach ($vm in $UnhealthyVMs) {
   if ($vm.ReplicationMode -eq "Primary" ) {    #ReplicationMode can be Primary or Replica
      #Write-Host "Attempting to resume replication for " $vm.VMname 
      Resume-VMReplication $vm.VMname -ErrorAction SilentlyContinue
   }
}


# Alert if there are any errors
if ($UnhealthyVMs) { 
   # If we have VMs then we need to determine if we need to return critical or warning. 
   $CriticalVMs = $UnhealthyVMs | Where-Object -Property ReplicationHealth -eq "Critical" 
   $WarningVMs  = $UnhealthyVMs | Where-Object -Property ReplicationHealth -eq "Warning" 
   if ($CriticalVMs) { 
      Write-Host "$CheckName CRITICAL for $($CriticalVMs.Name). $($CriticalVMs.ReplicationHealthDetails) `n" 
      exit $Critical 
   } 
   elseif ($WarningVMs) { 
     Write-Host "$CheckName WARNING for $($WarningVMs.Name). $($WarningVMs.ReplicationHealthDetails) `n" 
     exit $Warning 
   } 
   else { 
      Write-Host "$CheckName UNKNOWN problem with $($UnhealthyVMs.name). `n" 
     exit $Unknown 
   } 
} 
if ($HealthyVMs) { 
   # No Replication Problems Found 
   Write-Host "$CheckName OK - replication health is normal for $($HealthyVMs.name) `n" 
   exit $OK 
} 
else {    #should never get this far
   Write-Host "$CheckName UNKNOWN replication health - inconceivable result from script! `n" 
  exit $Unknown 
} 
