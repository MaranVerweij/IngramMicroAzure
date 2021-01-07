#This script will remove WVD agent software and disable Windows Update. Optionally disables additional services. 
#Author: Maran Verweij - Ingram Micro
#Version: 1.3
#No warranty implied

#Run as Administrator in PowerShell x64 (not x86)

#Fill in the variables below

$Disable_Windows_Modules_Installer = "No" #Default is No. As of version 1.3 this script contains a VM mode Sysprep parameter to prevent issues (slow first boot) with this service. Switch to 'Yes' if still experiencing issues.
$Disable_Windows_Search = "No" #Default is No. Switch to 'Yes' if experiencing slow/freezing navigation in the WVD user session.

#No more manual input required as of this line, the script can be implemented/run now.

$Repository = "C:\WVD_Disable_Services\"
New-Item $Repository -ItemType Directory -Force
icacls $Repository /inheritance:r
icacls $Repository /grant "System:(OI)(CI)(F)" 
icacls $Repository /grant "BUILTIN\Administrators:(OI)(CI)(F)"

if ($Disable_Windows_Modules_Installer -eq "Yes") {
    #Disable and stop Windows Module Installer to prevent issues (via a Scheduled Task at startup)
    $Scriptname = "Disable_Windows_Modules_Installer.ps1"
    $Scriptcode = "Set-Service TrustedInstaller -Status Stopped -StartupType Disabled"

    New-Item -Path $Repository -Name $Scriptname  -ItemType "file" -Value $Scriptcode

        Do
        {
            $PS = "Powershell.exe"
            $Arguments = "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $Repository$Scriptname"
            $Taskname = "Disable Windows Modules Installer"
            $Taskdescription = "Disable and stop Windows Modules Installer to prevent issues."
            $Action = New-ScheduledTaskAction -Execute $PS -Argument $Arguments
            $Trigger = New-ScheduledTaskTrigger -AtStartup 
            $Settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
            Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName $Taskname -Description $Taskdescription -Settings $Settings -User "System" -RunLevel Highest
            
            Start-Sleep 5
            
            $Check_task = Get-Scheduledtask $Taskname
        }
        while ($Check_task -eq $null)
    }

if ($Disable_Windows_Search -eq "Yes") {
    #Disable and stop Windows Module Installer to prevent issues (via a Scheduled Task at startup)
    $Scriptname = "Disable_Windows_Search.ps1"
    $Scriptcode = "Set-Service WSearch -Status Stopped -StartupType Disabled"

    New-Item -Path $Repository -Name $Scriptname  -ItemType "file" -Value $Scriptcode

        Do
        {
            $PS = "Powershell.exe"
            $Arguments = "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $Repository$Scriptname"
            $Taskname = "Disable Windows Search"
            $Taskdescription = "Disable and stop Windows Search to prevent issues."
            $Action = New-ScheduledTaskAction -Execute $PS -Argument $Arguments
            $Trigger = New-ScheduledTaskTrigger -AtStartup 
            $Settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
            Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName $Taskname -Description $Taskdescription -Settings $Settings -User "System" -RunLevel Highest
            
            Start-Sleep 5
            
            $Check_task = Get-Scheduledtask $Taskname
        }
        while ($Check_task -eq $null)
    }

#Uninstall WVD Agent software via Win32_Product class (Control Panel Software).
Try { 
    $WVDSoftware = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -match "Agent Boot Loader" -or $_.Name -match "Remote Desktop Services" }
    $WVDSoftware.Uninstall() 
}
Catch {
    #Not installed, continue
}

#Uninstall Microsoft Monitoring Agent and Dependency Agent, if previously installed
Try { 
    $WVDSoftware = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -eq "Dependency Agent" -or $_.Name -match "Microsoft Monitoring Agent" }
    $WVDSoftware.Uninstall()
    
    $Uninstaller_path = 'C:\Program Files\Microsoft Dependency Agent'
    $Uninstaller = Get-ChildItem "$Uninstaller_path\Uninstall*"
    $Uninstaller_name = $Uninstaller.Name

    cd $Uninstaller_path
    & .\$Uninstaller_Name /S
}
Catch {
    #Not installed, continue
}

#Disable Windows Update for future boot ups
Set-Service wuauserv -StartupType Disabled

$Reg_path = "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"
If (-Not (Test-Path $reg_path)) { New-Item $Reg_path -Force }
Set-ItemProperty $Reg_path -Name NoAutoUpdate -Value 1
Set-ItemProperty $Reg_path -Name AUOptions -Value 3

#Start Windows Module Installer (as Sysprep requires it)
Set-Service TrustedInstaller -Status Running -StartupType Automatic

Start-Process -FilePath C:\Windows\System32\Sysprep\Sysprep.exe -ArgumentList ‘/generalize /oobe /shutdown /mode:vm’
