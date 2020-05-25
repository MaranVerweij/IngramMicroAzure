#This script creates an Azure Service Principal (Azure AD Application service principal) and assigns it permissions on the WVD tenant/workspace and specified Azure subscription.
#Author: Maran Verweij - Ingram Micro
#Version: 1.0
#No warranty implied

#Run as Administrator
#Fill in the variables below

$UserName = "you@companyname.onmicrosoft.com" #Azure account name in UPN format
$Password = "password_here" #Password for Azure account
$Azure_sub = "vvvvvvvvvv-01ca-abcd-8984-6645544" #Azure subscription ID

$SVP_Displayname = "SVP_WVD_1" #Display name of the service principal
$SVP_Password = "password_here" #Specify service principal password, Max 850 characters, it is highly recommended to utilize the maximum for security concerns
$Role_Scope = "/subscriptions/$Azure_sub" #Scope of service principal RBAC role assignment, leave default if unsure 

#No more manual input required as of this line, the script can be run now.
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

#Assign azure sub contributor permissions
Try {
New-AzRoleAssignment -RoleDefinitionName "Contributor" -ApplicationId $SVP.ApplicationId -Scope $Role_Scope -ErrorAction Stop
}
Catch {
New-AzRoleAssignment -RoleDefinitionName "Contributor" -ApplicationId $SVP.ApplicationId
}

Write-Host "Document the following string, this is the Service Principal (Application) ID:" $SVP.ApplicationId
