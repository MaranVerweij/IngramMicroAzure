#This script creates an Azure Service Principal (Azure AD Application service principal) and assigns it permissions on the WVD tenant/workspace and specified Azure subscription.
#Author: Maran Verweij - Ingram Micro
#Version: 1.2
#No warranty implied

#Run as Administrator
#Fill in the variables below

$UserName = "" #Azure account name in UPN format
$Password = "" #Password for Azure account
$Azure_sub = "" #Azure subscription ID

$SVP_Displayname = "SVP_WVD_1" #Display name of the new service principal
$SVP_Password = "" #Max 850 characters

#No more manual input required as of this line, the script can be run now.

$Role_Scope = "/subscriptions/$Azure_sub" #Scope of service principal RBAC role assignment, leave default if unsure 

$Execution_Policy = Get-ExecutionPolicy #Get current Execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force #Run this line seperately if ambigious module errors are thrown while running the script, then run the entire script again

if (!(Get-PackageProvider -Name NuGet -ErrorAction silentlycontinue -Force)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Confirm:$False -Force
    }

if (!(Get-InstalledModule Az -ErrorAction silentlycontinue)) {
    Install-Module -Name Az -Confirm:$False -Force
    }
Import-Module -Name Az

Set-ExecutionPolicy -ExecutionPolicy $Execution_Policy -Scope CurrentUser -Force #Restore initial Execution policy

[System.Security.SecureString]$SecPwd = ConvertTo-SecureString -String $Password -AsPlainText -Force #Create creds from previous input
$Credentials = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $UserName, $SecPwd

Try {
Connect-AzAccount -Credential $Credentials -Subscription $Azure_sub -ErrorAction Stop #Authenticate to Azure (Az Powershell module)
}
Catch {
Connect-AzAccount -Subscription $Azure_sub #Authenticate to Azure (Az Powershell module) with interactive modern authentication screen
} 

$credentials = New-Object Microsoft.Azure.Commands.ActiveDirectory.PSADPasswordCredential -Property @{ StartDate=Get-Date; EndDate=Get-Date -Year 3000; Password=$SVP_Password}
$SVP = New-AzAdServicePrincipal -DisplayName $SVP_Displayname -PasswordCredential $credentials 

Start-Sleep 10

$JSON = 
'{
    "name": "WVD - Operational Maintenance",
    "description": "Windows Virtual Desktop role for Operational Maintenance. Allows for: User session management and Session host management.",
    "assignableScopes": [
        "/subscriptions/PLACEHOLDER"
    ],
    "actions": [
        "Microsoft.DesktopVirtualization/workspaces/providers/Microsoft.Insights/logDefinitions/read",
        "Microsoft.DesktopVirtualization/workspaces/providers/Microsoft.Insights/diagnosticSettings/write",
        "Microsoft.DesktopVirtualization/workspaces/providers/Microsoft.Insights/diagnosticSettings/read",
        "Microsoft.DesktopVirtualization/workspaces/read",
        "Microsoft.DesktopVirtualization/hostpools/sessionhosts/usersessions/*",
        "Microsoft.DesktopVirtualization/hostpools/sessionhosts/delete",
        "Microsoft.DesktopVirtualization/hostpools/sessionhosts/write",
        "Microsoft.DesktopVirtualization/hostpools/sessionhosts/read",
        "Microsoft.DesktopVirtualization/hostpools/providers/Microsoft.Insights/logDefinitions/read",
        "Microsoft.DesktopVirtualization/hostpools/providers/Microsoft.Insights/diagnosticSettings/write",
        "Microsoft.DesktopVirtualization/hostpools/providers/Microsoft.Insights/diagnosticSettings/read",
        "Microsoft.DesktopVirtualization/hostpools/read",
        "Microsoft.DesktopVirtualization/hostpools/write",
        "Microsoft.DesktopVirtualization/register/action"
    ],
        "notActions": [],
        "dataActions": [],
        "notDataActions": []
}'

$Adjusted_JSON = $JSON -replace ('PLACEHOLDER', $Azure_sub) 
$Adjusted_JSON > WVDOperationalMaintenance.json 
New-AzRoleDefinition -InputFile "WVDOperationalMaintenance.json"
Remove-Item WVDOperationalMaintenance.json

$JSON = 
'{
    "name": "VM and VMSS Operator",
    "description": "Virtual Machine and Virtual Machine Scale Set Operator. Allows for redeploying, stopping, starting and deallocating for VMs and VMSS.",
    "assignableScopes": [
        "/subscriptions/PLACEHOLDER"
    ],
    "actions": [
        "Microsoft.Compute/virtualMachines/deallocate/action",
        "Microsoft.Compute/virtualMachines/restart/action",
        "Microsoft.Compute/virtualMachines/redeploy/action",
        "Microsoft.Compute/virtualMachines/powerOff/action",
        "Microsoft.Compute/virtualMachines/start/action",
        "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/redeploy/action",
        "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/deallocate/action",
        "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/restart/action",
        "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/powerOff/action",
        "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/start/action",
        "Microsoft.Compute/virtualMachineScaleSets/redeploy/action",
        "Microsoft.Compute/virtualMachineScaleSets/start/action",
        "Microsoft.Compute/virtualMachineScaleSets/restart/action",
        "Microsoft.Compute/virtualMachineScaleSets/powerOff/action",
        "Microsoft.Compute/virtualMachineScaleSets/deallocate/action",
        "Microsoft.Compute/virtualMachines/read",
        "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/read",
        "Microsoft.Compute/virtualMachineScaleSets/instanceView/read",
        "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/instanceView/read",
        "Microsoft.Compute/virtualMachineScaleSets/read"
    ],
        "notActions": [],
        "dataActions": [],
        "notDataActions": []
}'

$Adjusted_JSON = $JSON -replace ('PLACEHOLDER', $Azure_sub) 
$Adjusted_JSON > VMandVMSSOperator.json 
New-AzRoleDefinition -InputFile "VMandVMSSOperator.json" 
Remove-Item VMandVMSSOperator.json

#Assign role: 'WVD - Operational Maintenance' to the Service Principal
Try {
    New-AzRoleAssignment -RoleDefinitionName "WVD - Operational Maintenance" -ApplicationId $SVP.ApplicationId -Scope $Role_Scope -ErrorAction Stop
    }
    Catch {
    New-AzRoleAssignment -RoleDefinitionName "Contributor" -ApplicationId $SVP.ApplicationId
    Write-Host "WARNING: Assigned Contributor role to the Service Principal because 'WVD - Operational Maintenance' could not be assigned. If you also received an error from 'New-AzRoleAssignment' the Contributor role could not be assigned either, most likely because the Service Principal could not be created."
    }

#Assign role: 'VM and VMSS Operator' to the Service Principal
Try {
    New-AzRoleAssignment -RoleDefinitionName "VM and VMSS Operator" -ApplicationId $SVP.ApplicationId -Scope $Role_Scope -ErrorAction Stop
    }
    Catch {
    New-AzRoleAssignment -RoleDefinitionName "Contributor" -ApplicationId $SVP.ApplicationId
    Write-Host "WARNING: Assigned Contributor role to the Service Principal because 'VM and VMSS Operator' could not be assigned. If you also received an error from 'New-AzRoleAssignment' the Contributor role could not be assigned either, most likely because the Service Principal could not be created."
    }
    
Write-Host "Document the following string, this is the Service Principal (Application) ID:" $SVP.ApplicationId  
