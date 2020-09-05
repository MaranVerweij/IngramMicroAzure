#This script will make an Azure Storage Account ready to host Azure File shares based on a traditional AD DS environment. The script will create a service account in AD DS. 
#Author: Maran Verweij - Ingram Micro
#Version: 1.0
#No warranty implied

#Run as Administrator
#Fill in the variables below

$Azure_Sub_ID = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXX" #Azure subscription ID
$StorageAccount_Name = "fslogixmaran" #Specify the Storage Account name. Ensure this is 17 characters or less, or the service account will fail to be created.  
$ResourceGroup_Name = "WVD-Backend" #Specify the Resource Group where the Storage account is located in. 
$SVC_Account_OU = "OU=azfiles,DC=ingram,DC=dc" #Provide an OU path where the service account will be created. Example specifies an OU 'azfiles' in the domain 'ingram.dc'. 

#Verify that all required variables (declared above) have been filled in correctly. 
#The script can be run now. 

$Execution_Policy = Get-ExecutionPolicy #Get current Execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force #Run this line seperately if ambigious module errors are thrown while running the script, then run the entire script again

if (!(Get-PackageProvider -Name NuGet -ErrorAction silentlycontinue -Force)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    }

Register-PSRepository -Default -InstallationPolicy Trusted -ErrorAction silentlycontinue

if (!(Get-InstalledModule Az.Accounts -ErrorAction silentlycontinue)) {
    Install-Module -Name Az.Accounts -Confirm:$False -Force -AllowClobber
    }
Import-Module -Name Az.Accounts

if (!(Get-InstalledModule Az.Storage -ErrorAction silentlycontinue)) {
    Install-Module -Name Az.Storage -Confirm:$False -Force -AllowClobber
    }
Import-Module -Name Az.Storage

Connect-AzAccount 

Try {
    Select-AzSubscription -SubscriptionId $Azure_Sub_ID -ErrorAction Stop
}
Catch {
    Write-Host "Could not select Azure subscription. Verify that the Azure AD account has the Owner role assigned on Azure subscription ID: $Azure_Sub_ID "
}

$Domain_info = Get-ADdomain -Current LocalComputer
$SVC_Name = "Az_$StorageAccount_Name"
$DNSHostname = $SVC_Name + '.' + $Domain_info.DNSRoot
$SPN = 'cifs/' + $StorageAccount_Name + '.file.core.windows.net'

# Create the Kerberos key on the storage account and get the Kerb1 key as the password for the AD identity to represent the storage account
New-AzStorageAccountKey -ResourceGroupName $ResourceGroup_Name -Name $StorageAccount_Name -KeyName kerb1
$Key = Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup_Name -Name $StorageAccount_Name -ListKerbKey | where-object{$_.Keyname -contains "kerb1"}

[System.Security.SecureString]$SVC_Password = ConvertTo-SecureString -String $Key.Value -AsPlainText -Force #Create creds from previous input

Try {
    Remove-ADUser -Identity $SVC_Name -Confirm:$False -ErrorAction Stop
    Write-Host "Account with name: $SVC_Name already existed prior to running this script. The script will now attempt to remove and re-create it."
    }
Catch {
    Write-Host "Account with name: $SVC_Name does not exist. The script will attempt to create this account and configure it." 
}

Try {
    New-ADUser -ErrorAction Stop `
        -Name $SVC_Name `
        -DisplayName $SVC_Name `
        -Description "Service account for Azure File share integration with traditional AD DS." `
        -PasswordNeverExpires $True `
        -AccountPassword $SVC_Password `
        -ServicePrincipalNames $SPN `
        -Enabled $True `
        -Path $SVC_Account_OU
}
Catch {
    Write-Host "Service account could not be created (New-ADUser), try creating it again. Ensure your Storage Account name is 17 characters or less, or the service account will fail to be created.  "
}

Try {
    $ServiceAccount = Get-ADUser -Identity $SVC_Name -ErrorAction Stop
}
Catch {
    Write-Host "Service account could not be found, try creating it again."
}

Try {
Set-AzStorageAccount -ErrorAction Stop `
        -ResourceGroupName $ResourceGroup_Name `
        -Name $StorageAccount_Name `
        -EnableActiveDirectoryDomainServicesForFile $true `
        -ActiveDirectoryDomainName $Domain_info.DNSRoot `
        -ActiveDirectoryNetBiosDomainName $Domain_info.NetBIOSName `
        -ActiveDirectoryForestName $Domain_info.Forest `
        -ActiveDirectoryDomainGuid $Domain_info.ObjectGUID.Guid `
        -ActiveDirectoryDomainsid $Domain_info.DomainSID.Value `
        -ActiveDirectoryAzureStorageSid $ServiceAccount.SID.Value
}
Catch {
Write-Output "Could not run Set-AzStorageAccount succesfully. Verify the parameters and arguments, then run the CMDlet manually."
}

Set-ExecutionPolicy -ExecutionPolicy $Execution_Policy -Scope CurrentUser -Force #Restore initial Execution policy
