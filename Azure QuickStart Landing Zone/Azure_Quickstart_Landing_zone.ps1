#This script deploys the Azure QuickStart Landing Zone
#Script must be run with an (Azure AD) Global admin with User access switch set to 'Yes'
#Author: Maran Verweij - Ingram Micro
#Version: 1.0
#No warranty implied

#Specify variables below:

$Blueprint_Files_Path = "E:\Azure_QuickStart_Landing_Zone" #File path to the !UNZIPPED! folder where the Blueprint file are located
$Root_Owners_Group_Name = "Root_Owners" #Azure AD Group that will be granted the Owner role on the Root Management Group
$CA_Policy_state = "Enabled" #"Disabled" to create CA policies with them being initially disabled

#Optional:
#Apply Foreign Principal to Root Management Group scope (leave blank if not needed)
$GDAP_Group_ID = "" #Azure AD Group ID of the Group that is linked to a !PRE-EXISTING! GDAP relationship
$Foreign_Principal_Role = "Owner" #Azure resource role name

#Script may be run now

$PSModuleScope = "CurrentUser" #Alternative is: AllUsers

if (!(Get-PackageProvider -Name NuGet -ErrorAction silentlycontinue -Force)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    }

Register-PSRepository -Default -InstallationPolicy Trusted -ErrorAction silentlycontinue

if (!(Get-InstalledModule Az.Accounts -ErrorAction silentlycontinue)) {
    Install-Module -Name Az.Accounts -Confirm:$False -Force -AllowClobber -Scope $PSModuleScope
    }
Import-Module -Name Az.Accounts

if (!(Get-InstalledModule Az.Blueprint -ErrorAction silentlycontinue)) {
    Install-Module -Name Az.Blueprint -Confirm:$False -Force -AllowClobber -Scope $PSModuleScope
    }
Import-Module Az.Blueprint

if (!(Get-InstalledModule AzureAD -ErrorAction silentlycontinue)) {
    Install-Module -Name AzureAD -Confirm:$False -Force -AllowClobber -Scope $PSModuleScope
    } 
Import-Module -Name AzureAD 

#Connect to tenant
Disconnect-AzureAD
Do {
Disconnect-AzAccount
Start-Sleep 2
$Check_Signins = Get-AzContext
}
While ($Check_Signins -ne $null)

Connect-AzAccount
Connect-AzureAD

#Create dummy management group to activate Managemount Group functionality
New-AzManagementGroup -GroupId "Dummy_Empty_To_Be_Removed"
Start-Sleep 2

Remove-AzManagementGroup -GroupId "Dummy_Empty_To_Be_Removed"
Start-Sleep 2 

$Get_User_UPN = Get-AzContext | Select Account
$User_UPN = $Get_User_UPN.Account.Id

$Create_Root_Owners_group = New-AzADGroup -DisplayName $Root_Owners_Group_Name -MailNickname $Root_Owners_Group_Name
Start-Sleep 10

Add-AzADGroupMember -TargetGroupObjectId $Create_Root_Owners_group.Id -MemberUserPrincipalName $User_UPN
Start-Sleep 2

New-AzRoleAssignment -ObjectId $Create_Root_Owners_group.Id -RoleDefinitionName Owner -Scope "/providers/Microsoft.Management/managementGroups/$GetTenantID"

if ($GDAP_Group_ID -ne $null -and $Foreign_Principal_Role -ne $null) {
    New-AzRoleAssignment -ObjectId $GDAP_Group_ID -RoleDefinitionName $Foreign_Principal_Role -Scope "/providers/Microsoft.Management/managementGroups/$GetTenantID" -ObjectType 'ForeignGroup'
}

Write-Output "Please use the pop-up authentication screen to sign in again, to allow the Azure Blueprint deployment to start."

#Request re-sign in to refresh credentials:
Do {
Disconnect-AzAccount
Start-Sleep 2
$Check_Signins = Get-AzContext
}
While ($Check_Signins -ne $null)

Connect-AzAccount

#Get Root Management Group ID (equivelent to Azure AD Tenant ID)
$GetTenantID = Get-AzTenant

$Blueprint_Name = "Azure_QuickStart_Landing_Zone"
Import-AzBlueprintWithArtifact -ManagementGroupId $GetTenantID.Id -InputPath $Blueprint_Files_Path -Name $Blueprint_Name

$BlueprintObject = Get-AzBlueprint -ManagementGroupId $GetTenantID.Id -Name $Blueprint_Name

Publish-AzBlueprint -Blueprint $BlueprintObject -Version 1.0

$Sub_list = Get-AzSubscription
foreach ($Sub in $Sub_list) {
New-AzBlueprintAssignment -Name "Azure_QuickStart_Landing_Zone" -Blueprint $BlueprintObject -Location "West Europe" -SubscriptionId $Sub.id
}

#Create CA Location for country NL
$Create_CA_Location = New-AzureADMSNamedLocationPolicy -CountriesAndRegions "NL" -DisplayName "Privileged_Access_Allowed_Locations" -OdataType "#microsoft.graph.countryNamedLocation" -IsTrusted $false
$Create_CA_Location.Id

Start-Sleep 10

#Create Privileged Access CA Policy
$name = "Privileged_Access"
$state = $CA_Policy_state

#Conditions 
    $conditions = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessConditionSet

    #Applications
    $conditions.Applications = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessApplicationCondition
    $conditions.Applications.IncludeApplications = "All"

    #Users
    $conditions.Users = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessUserCondition
    $conditions.Users.IncludeRoles = "62e90394-69f5-4237-9190-012177145e10",
    "f2ef992c-3afb-46b9-b7cf-a126ee74c451",
    "194ae4cb-b126-40b2-bd5b-6091b380977d",
    "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9",
    "966707d0-3269-4727-9be2-8c3a10f19b9d",
    "729827e3-9c14-49f7-bb1b-9608f156bbb8",
    "fdd7a751-b60b-444a-984c-02652fe8fa1c"
    $conditions.Users.IncludeGroups = $Create_Root_Owners_group.Id
    $conditions.Users.ExcludeRoles = "d29b2b05-8046-44ba-8758-1e26182fcf32" #Azure AD Connect role

    #Locations
    $conditions.Locations = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessLocationCondition
    $conditions.Locations.IncludeLocations = $Create_CA_Location.Id

#Controls
    $controls = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessGrantControls
    $controls._Operator = "OR"
    $controls.BuiltInControls = "Mfa"

New-AzureADMSConditionalAccessPolicy -DisplayName $name -State $state -Conditions $conditions -GrantControls $controls

Start-Sleep 3

#Create Block Privileged Access CA Policy
$name = "Block_Privileged_Access"
$state = $CA_Policy_state

#Conditions 
    $conditions = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessConditionSet

    #Applications
    $conditions.Applications = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessApplicationCondition
    $conditions.Applications.IncludeApplications = "All"

    #Users
    $conditions.Users = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessUserCondition
    $conditions.Users.IncludeRoles = "62e90394-69f5-4237-9190-012177145e10",
    "f2ef992c-3afb-46b9-b7cf-a126ee74c451",
    "194ae4cb-b126-40b2-bd5b-6091b380977d",
    "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9",
    "966707d0-3269-4727-9be2-8c3a10f19b9d",
    "729827e3-9c14-49f7-bb1b-9608f156bbb8",
    "fdd7a751-b60b-444a-984c-02652fe8fa1c"
    $conditions.Users.IncludeGroups = $Create_Root_Owners_group.Id
    $conditions.Users.ExcludeRoles = "d29b2b05-8046-44ba-8758-1e26182fcf32" #Azure AD Connect role

    #Locations
    $conditions.Locations = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessLocationCondition
    $conditions.Locations.ExcludeLocations = $Create_CA_Location.Id
    $conditions.Locations.IncludeLocations = "All"

#Controls
    $controls = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessGrantControls
    $controls._Operator = "OR"
    $controls.BuiltInControls = "Block"

New-AzureADMSConditionalAccessPolicy -DisplayName $name -State $state -Conditions $conditions -GrantControls $controls

Start-Sleep 3

#Create Standard User Access CA Policy
$name = $null
$name = "Standard_User_Access"
$state = $CA_Policy_state

#Conditions 
    $conditions = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessConditionSet

    #Applications
    $conditions.Applications = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessApplicationCondition
    $conditions.Applications.IncludeApplications = "All"

    #Users
    $conditions.Users = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessUserCondition
    $conditions.Users.IncludeUsers = "All"
    $conditions.Users.ExcludeRoles = "d29b2b05-8046-44ba-8758-1e26182fcf32", #Azure AD Connect role
    "62e90394-69f5-4237-9190-012177145e10",
    "f2ef992c-3afb-46b9-b7cf-a126ee74c451",
    "194ae4cb-b126-40b2-bd5b-6091b380977d",
    "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9",
    "966707d0-3269-4727-9be2-8c3a10f19b9d",
    "729827e3-9c14-49f7-bb1b-9608f156bbb8",
    "fdd7a751-b60b-444a-984c-02652fe8fa1c"

#Controls
    $controls = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessGrantControls
    $controls._Operator = "OR"
    $controls.BuiltInControls = "Mfa"

New-AzureADMSConditionalAccessPolicy -DisplayName $name -State $state -Conditions $conditions -GrantControls $controls
