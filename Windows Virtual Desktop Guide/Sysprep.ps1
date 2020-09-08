#This script will remove WVD agent software and disable Windows Update (and installer)
#Author: Maran Verweij - Ingram Micro
#Version: 1.0
#No warranty implied

#Run as Administrator

#Uninstall WVD Agent software via Win32_Product class (Control Panel Software) in case MSI uninstallers missed a legacy version
Try { 
    $WVDSoftware = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -match "Agent Boot Loader" -or $_.Name -match "Remote Desktop Services" }
    $WVDSoftware.Uninstall() 
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

Start-Job -ScriptBlock { Start-Process -FilePath C:\Windows\System32\Sysprep\Sysprep.exe -ArgumentList ‘/generalize /oobe /shutdown’ }
