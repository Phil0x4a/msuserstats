#!/usr/local/bin/pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName="ImportExcel"; ModuleVersion="7.4.1" }
#Requires -Modules @{ ModuleName="ExchangeOnlineManagement"; ModuleVersion="3.7.1"}
#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Groups

<#
.SYNOPSIS
    Maintain and cleanup inactive user accounts from Entra ID and Active Directory. Support enforcement of MFA. 

.PARAMETER Name
    msuserstats.ps1

.DESCRIPTION
    Get all users from Entra ID and ActiveDirectory. Merge accounts into a single list of all users and avoid duplicates through synced accounts by mapping Entra ID users
    back to Active Directory. Collect additional information for all users such as last sign-in, group memberships, Exchange mailbox type and MFA methods.

    LICENSE: GPL-3.0 license
    SOURCE: https://github.com/Phil0x4a/msuserstats

.EXAMPLE
    Run on any platform with configured settings in config.ps1:
    ./msuserstats.ps1

    Two-Step process with exporting first on Windows x64 with RSAT tools and complete on any other system:
    1. Export your Active Directory Users on x64 Windows with RSAT Tools installed (if you want to include Active Directory)
    ./msuserstats.ps1 -ExportDomainUsers $true
    2. Complete on any other system
    ./msuserstats.ps1
#>

<###################################
    SCRIPT PARAMETER
####################################>
param (
    # Used to set the requested users Any or just Member or Guest account types
    [ValidateSet("Guest", "Member", "Any")]
    [string]$UserType = "Any",
    # Export only Active Directory users on a Windows based machine
    [bool]$ExportDomainUsers = $false,
    # Force to import Domain Users from a file even on Windows based machines
    [bool]$ForceImportDomainUsers = $false
)

<###################################
    INCLUDE CONFIGURATION
####################################>
. ./config.ps1

<###################################
    IMPORTS
####################################>
Import-Module Microsoft.Graph.Users, Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Groups
Import-Module ImportExcel
Import-Module ExchangeOnlineManagement

# Importing Active Directory Module on Windows platforms
if ($IsWindows) {
    Import-Module ActiveDirectory
}

<###################################
    POWERSHELL OPTIONS
####################################>
# Stop on Error
$ErrorActionPreference = "Stop"
# Log Informational messages
$InformationPreference = "Continue"
# Enable StrictMode
Set-StrictMode -Version Latest

<###################################
    CLASS DEFINITIONS
####################################>

<#
    .Description
    The main class to manage the users inside the script. A class object also works best with exporting these objects into XLSX or CSV.
    All class attributes also reflect the resulting name in Excel or CSV. Prefix EID = Entra ID, Prefix AD = Active Directory as Source.
#>
class UserStatsUser {
    [string]$DisplayName = ""
    [string]$Id = ""
    [string]$Mail = ""
    [string]$UserType = ""
    [string]$GivenName = ""
    [string]$Surname = ""
    [string]$EIDUserPrincipalName = ""
    [string]$EIDAccountEnabled = ""
    [string]$EIDCreatedDateTime = ""
    [string]$EIDLastPasswordChangeDateTime = ""
    [string]$EIDonPremisesDomainName = ""
    [string]$EIDonPremisesSecurityIdentifier = ""
    [string]$EIDGroupMemberships = ""
    [string]$EIDLastSignIn = ""
    [string]$EIDBusinessContact = ""
    [string]$EIDCompanyName = ""
    [string]$EIDAlternateMail = ""
    [string]$EIDMfaGroups = ""
    [string]$EIDMfaAuthMethods = ""
    [string]$EIDBlockedO365 = ""
    [string]$EXOMailBoxType = ""
    [string]$ADDomain = ""
    [string]$ADUserPrincipalName = ""
    [string]$ADSamAccountName = ""
    [string]$ADMobilePhone = ""
    [string]$ADLastLogonDate = ""
    [string]$ADPasswordNeverExpires = ""
    [string]$ADPasswordLastSet = ""
    [string]$ADPasswordExpired = ""
    [string]$ADLockedOut = ""
    [string]$ADlogonCount = ""
    [string]$ADAccountExpirationDate = ""
    [string]$ADLastBadPasswordAttempt = ""
    [string]$ADDistinguishedName = ""
    [string]$ADCompany = ""
    [string]$ADCreated = ""
    [string]$ADadminDescription = ""
    [string]$ADAccountEnabled = ""
    [string]$ADDNCountry = ""
    [string]$ADDNOrg = ""
    [string]$ADDNAccountType = "EID-Only"
    [string]$ADPasswordQuality = ""
    [string]$ADPasswordLength = ""
    [string]$ADPasswordPolicyDeviation = ""
    [string]$LastSignInCheckDateTime = ""
    [string]$HybridLastSignIn = ""
    [string]$HybridLastSignInSource = ""
    [string]$LastActivityDaysCategory = ""
    [string]$CleanupException = ""
    [string]$ProcessingRemark = ""
}

<#
    .Description
    Class to manage an organizational units inside the script
#>
class UserStatsEntity {
    [string]$Country = ""
    [string]$Entity = ""
    [string]$Comments = ""
}

<#
    .Description
    Class to export the complete user dataset into a sheet with most important and feedback columns
#>
class UserStatsExportUser {
    [string]$ReviewReason = ""
    [string]$AccountType = ""
    [string]$Id = ""
    [string]$UserPrincipalName = ""
    [string]$DisplayName = ""
    [string]$Mail = ""
    [string]$GivenName = ""
    [string]$Surname = ""
    [string]$Company = ""
    [string]$ADMobilePhone = ""
    [string]$AdminDescription = ""
    [string]$AccountEnabled = ""
    [string]$EIDBlockedO365 = ""
    [string]$EIDCreatedDateTime = ""
    [string]$EIDLastPasswordChangeDateTime = ""
    [string]$ADDomain = ""
    [string]$ADCreated = ""
    [string]$ADPasswordLastSet = ""
    [string]$ADPasswordExpired = ""
    [string]$ADLockedOut = ""
    [string]$ADPasswordNeverExpires = ""
    [string]$EXOMailBoxType = ""
    [string]$ADPasswordQuality = ""
    [string]$ADPasswordLength = ""
    [string]$ADPasswordPolicyDeviation = ""
    [string]$LastSignIn = ""
    [string]$Delete = "Yes"
    [string]$InactiveBusinessReason = ""
    [string]$InactiveExceptionUntil = ""
    [string]$Comments = ""
}

<#
    .Description
    Class to manage cleanup exceptions
#>
class UserStatsCleanupException {
    [bool]$Expired = ""
    [string]$ExcludeFilter = ""
    [string]$Requestor = ""
    [string]$ValidUntil = ""
    [string]$Comments = ""
}

<#
    .Description
    Class to manage AD users with a limited set of attributes
#>
class UserStatsADUser {
    
    [string]$AccountExpirationDate = ""
    [string]$adminDescription = ""
    [string]$CanonicalName = ""
    [string]$Company = ""
    [string]$Created = ""
    [string]$DisplayName = ""
    [string]$DistinguishedName = ""
    [string]$Enabled = ""
    [string]$GivenName = ""
    [string]$LastBadPasswordAttempt = ""
    [string]$LastLogonDate = ""
    [string]$LockedOut = ""
    [string]$logonCount = ""
    [string]$Mail = ""
    [string]$Mobile = ""
    [string]$Name = ""
    [string]$ObjectClass = ""
    [string]$ObjectGUID = ""
    [string]$PasswordExpired = ""
    [string]$PasswordLastSet = ""
    [string]$PasswordNeverExpires = ""
    [string]$SamAccountName = ""
    [string]$SID = ""
    [string]$Surname = ""
    [string]$UserPrincipalName = ""
}

<###################################
    FUNCTIONS
####################################>

<#
    .Description
    Returns multiple input date formats as ISO date format
#>
function GetDateTime{
    param (
        [parameter(Mandatory=$true)]
        [AllowNull()]
        $date
    )
    # Check if Value is null
    if ( $null -eq $date -or $date -eq "" ) { return $null }
    # Check if value is date and convert to ISO format
    elseif ($date.GetType().Name -eq "DateTime") {
        return $date.ToString("s")
    }
    elseif ($date -as [DateTime]) { 
        return ([DateTime]$date).ToString("s") 
    }
    elseif ([regex]::Matches($date, '\d{2}/\d{2}/\d{4} (\d{2}):(\d{2}):(\d{2})')) { 
        return [DateTime]::parseexact($date, 'dd/MM/yyyy HH:mm:ss', $null).ToString("s")
    }   
    else {
        Write-Error "Failed to parse date: $($date). Exiting."
        Throw "Failed to parse date: $($date)."
    }
}

<#
    .Description
    Retrieves groups from Entra ID to check if users are member of these groups
#>
function GetGroupMemberShips {
    # User groups
    $groups = @{}
    $GroupMembership = @{}
    # Checking if Group Membership has been configured
    if ( $CONF_GROUP_MEMBERSHIP.Count -eq 0 ) {
        return @{}
    }
    
    # Checking if a group filter exists
    if ($CONF_GROUP_MEMBERSHIP_FILTER_PREFIX -eq "") {
        Write-Warning "Please configure a group prefix to limit group results for group membership checking."
        return @{}
    }
    # Getting license groups
    Write-Information "Getting a list of groups for membership..."
    $AllSelectedGroups = Get-MgGroup -All -Filter "startsWith(DisplayName, '$CONF_GROUP_MEMBERSHIP_FILTER_PREFIX')"
    # Iterating groups
    $AllSelectedGroups | ForEach-Object {
        for ($i = 0; $i -lt $CONF_GROUP_MEMBERSHIP.Count; $i++) {
            if ( $_.DisplayName.Contains($CONF_GROUP_MEMBERSHIP[$i]) ) {
                # Groupname contains one of the keywords
                $groups[$_.Id] = $_.DisplayName
            }
        }
    }
    Write-Information "Selected $($groups.Count) groups for membership analysis."
    Write-Information "Creating list of memberships to groups..."
    $groups.Keys | ForEach-Object {
        # Get all group members
        $members = Get-MgGroupMember -All -GroupId $_
        $GroupName = $groups[$_]
        # Add member/user ID to hash of Users and include DisplayName as Value
        $members | ForEach-Object {
            if ( -not $GroupMembership.ContainsKey($_.Id) ) {
                $GroupMembership[$_.Id] = New-Object System.Collections.Generic.List[System.Object]
                $GroupMembership[$_.Id].Add($GroupName)
            } else {
                $GroupMembership[$_.Id].Add($GroupName)
            }
        }
    }
    Write-Information "Found $($GroupMembership.Count) memberships to selected groups."
    return $GroupMembership
}

<#
    .Description
    Retrieves all users from Active Directory. Function either only exports or creates a hash of all AD users
#>
function GetAllADDomainUsers {
    $DateToday = Get-Date -Format "yyyyMMdd"
    if ($IsWindows -and -not $ForceImportDomainUsers) {
        # List of all users
        $AllAdDomainUsers = $null
        # Getting credentials
        $ADCredential = Get-Credential -Message "Credentials are required to access Active Directory. Enter a non-admin user account to read AD. "
        # Get all AD domains
        $Domains = (Get-ADForest -Credential $ADCredential).Domains
        # Getting all active directory users
        $Domains | ForEach-Object {
            # Getting DC for domain
            $DC = Get-ADDomainController -DomainName $_ -Discover -Service PrimaryDC | Select-Object -ExpandProperty hostname
            Write-Information "Getting user from domain: $_ (DC: $DC)"
            $DomainUserList = Get-ADUser -server $DC -Credential $ADCredential -Filter * -Properties DisplayName, SID, Mail, UserPrincipalName, CanonicalName, Enabled, Created, PasswordLastSet, Givenname, Surname, SamAccountName, Mobile, LastLogonDate,PasswordNeverExpires,PasswordExpired,LockedOut,logonCount,LastBadPasswordAttempt,DistinguishedName,Company,adminDescription, AccountExpirationDate
            if ($null -eq $AllAdDomainUsers) {
                $AllAdDomainUsers = $DomainUserList
            }
            else {
                $AllAdDomainUsers += $DomainUserList
            }
        }
        # Reading all details from AD by exporting which does online requests against AD to query additional details
        Write-Information "Exporting all AD domain users... This can take several hours. Started at: $(Get-Date)"
        $ExportUserList = New-Object System.Collections.Generic.List[System.Object]
        $export_counter = 0
        $export_count = $AllAdDomainUsers.Count
        $AllAdDomainUsers | ForEach-Object {
            $ExportUserList.Add( (GetADExportUser -ADUser $_) )
            $export_counter++
            $percent_complete = [math]::round(($export_counter/$export_count)*100,2)
            Write-Progress -Activity "Exporting..." -Status "$percent_complete %" -PercentComplete $percent_complete
        }
        Write-Progress -Activity "Exporting..." -Completed
        # Checking if export of all users is requested
        if ($ExportDomainUsers) {
            $ExportUserList | Export-Csv -Path "$CONF_MY_WORKDIR/domain_users_export_$DateToday.csv" -IncludeTypeInformation -Encoding UTF8 -Delimiter $CONF_CSV_DELIMITER
            Write-Information "All AD domain users have been exported to: $CONF_MY_WORKDIR/domain_users_export_$DateToday.csv. Export completed."
            return
        }
        else {
            $AllAdDomainUsers = $ExportUserList
        }
    }
    else {
        # Importing domain users from files
        $FILE = (Get-Item "$($CONF_MY_WORKDIR)/*" -Include "domain_users_export_*").Name
        Write-Information "Importing AD users from file: $FILE"
        $AllAdDomainUsers = Import-Csv -Path "$($CONF_MY_WORKDIR)/$FILE" -Encoding UTF8 -Delimiter $CONF_CSV_DELIMITER -ErrorAction Stop
        Write-Information "Successfully imported $($AllAdDomainUsers.Count) domain users from file."
    }
    
    # Creating user hash of all domain users
    $AllDomainsUserHash = @{}
    $AllAdDomainUsers | ForEach-Object {
        $AllDomainsUserHash[$_.SID] = $_
    }
    return $AllDomainsUserHash
}

<#
    .Description
    Creates an ADUser class object
#>
function GetADExportUser{
    param (
        $ADUser
    )
    $nu = [UserStatsADUser]::new()
    $nu.AccountExpirationDate = GetDateTime -date $ADUser.AccountExpirationDate
    $nu.adminDescription = $ADUser.adminDescription
    $nu.CanonicalName = $ADUser.CanonicalName
    $nu.Company = $ADUser.Company
    $nu.Created = GetDateTime -date $ADUser.Created
    $nu.DisplayName = $ADUser.DisplayName
    $nu.DistinguishedName = $ADUser.DistinguishedName
    $nu.Enabled = $ADUser.Enabled
    $nu.GivenName = $ADUser.GivenName
    $nu.LastBadPasswordAttempt = GetDateTime -date $ADUser.LastBadPasswordAttempt
    $nu.LastLogonDate = GetDateTime -date $ADUser.LastLogonDate
    $nu.LockedOut = $ADUser.LockedOut
    $nu.logonCount = $ADUser.logonCount
    $nu.Mail = $ADUser.Mail
    $nu.Mobile = $ADUser.Mobile
    $nu.Name = $ADUser.Name
    $nu.ObjectClass = $ADUser.ObjectClass
    $nu.ObjectGUID = $ADUser.ObjectGUID
    $nu.PasswordExpired = $ADUser.PasswordExpired
    $nu.PasswordLastSet = GetDateTime -date $ADUser.PasswordLastSet
    $nu.PasswordNeverExpires = $ADUser.PasswordNeverExpires
    $nu.SamAccountName = $ADUser.SamAccountName
    $nu.SID = $ADUser.SID
    $nu.Surname = $ADUser.Surname
    $nu.UserPrincipalName = $ADUser.UserPrincipalName
    return $nu
}

<#
    .Description
    Loads the exception cleanup list to mark accounts excepted from cleanup process
#>
function LoadCleanupExceptionList {
    # Init hash
    $CleanupExceptionHash = @{}
    # Importing Cleanup exception list
    if (Test-Path -Path $CONF_FILE_CLEANUPEXCEPTIONLIST) {
        $CleanupExceptionListImport = Import-Csv -Path $CONF_FILE_CLEANUPEXCEPTIONLIST -Encoding UTF8 -Delimiter $CONF_CSV_DELIMITER -Header 'Enabled','Upn','Requestor','ValidUntil','Comments'
    }
    else {
        if ( $CONF_FILE_CLEANUPEXCEPTIONLIST -ne "" ) {
            Write-Warning "WARNING: No file found for Cleanup Exceptions at the following path: $($CONF_FILE_CLEANUPEXCEPTIONLIST)"
        }
        return $CleanupExceptionHash
    }
    # Iterating all cleanup entries and check syntax and expiry
    $Linecounter = 1
    foreach ($li In $CleanupExceptionListImport) {
        if ( $li.Enabled.ToLower() -eq "on" ) {
            # Checking Lifetime date and parse it
            $result = [regex]::Matches($li.ValidUntil, '(\d{4})(\d{2})(\d{2})')
            if ( $result.Count -gt 0 -and $result.Groups[1].Value.StartsWith('20') -and [int]($result.Groups[2].Value) -le 12 -and [int]($result.Groups[2].Value) -le 31 -and $li.Upn.Length -gt 5) {
                # Check if UPN already exists
                if ( $CleanupExceptionHash.ContainsKey($li.Upn.ToLower()) ) {
                    Write-Warning "Duplicate cleanup UPN for: $($li.Upn) | Valid Until: $($li.ValidUntil) | Line: $($Linecounter)"
                    continue
                }
                $ValidUntil = [DateTime]::parseexact($li.ValidUntil, 'yyyyMMdd', $null)
                # Create new exception
                $ne = [UserStatsCleanupException]::new()
                $ne.ExcludeFilter = $li.Upn.Trim()
                $ne.Requestor = $li.Requestor
                $ne.ValidUntil = $li.ValidUntil
                $ne.Comments = $li.Comments
                # Checking if exceptions has not expired
                if ( $ValidUntil.AddDays(1) -ge (Get-Date) ) {
                    $ne.Expired = $false
                    $CleanupExceptionHash.Add( $li.Upn.Trim().ToLower(), $ne )
                }
                else {
                    $ne.Expired = $true
                    $CleanupExceptionHash.Add( $li.Upn.Trim().ToLower(), $ne )
                    Write-Warning "Cleanup exception expired for: $($li.Upn) | Valid Until: $($li.ValidUntil) | Line: $($Linecounter)"
                }
            }
            else {
                Write-Warning "Cleanup exception invalid: $($li.Upn) | Valid Until: $($li.ValidUntil) | Line: $($Linecounter)."
            }
        }
        $Linecounter++
    }
    Write-Information "Valid cleanup exceptions loaded: $($CleanupExceptionHash.Count)"
    return $CleanupExceptionHash
}

<#
    .Description
    Returns a Cleanup Exception
#>
function GetCleanupException {
    param (
        $UsersUPN,
        $UsersMail,
        $UsersId,
        $CleanupExceptionHash
    )
    foreach ($exc In $CleanupExceptionHash.Keys) {
        if ( $UsersUPN.Contains($exc) -or $UsersMail.Contains($exc) -or $UsersId -eq $exc ) {
            return $CleanupExceptionHash[$exc]
        }
    }
    return $null
}

<#
    .Description
    Returns a valid cleanup exception as String
#>
function GetNonExpiredCleanupExceptionString {
    param (
        $UsersUPN,
        $UsersMail,
        $UsersId,
        $CleanupExceptionHash
    )
    $Exception = GetCleanupException $UsersUPN $UsersMail $UsersId $CleanupExceptionHash
    if ( $null -ne $Exception -and $Exception.Expired -ne $true ) {
        return "Excluded by: $($Exception.ExcludeFilter)"
    }
    else {
        return ""
    }
}

<#
    .Description
    Loading company legal entities if configured
#>
function LoadEntities {
    $EntityList = New-Object System.Collections.Generic.List[System.Object]
     if (Test-Path -Path $CONF_ENTITY_FILE ) {
        $EntityImport = Import-Csv -Path $CONF_ENTITY_FILE  -Encoding UTF8 -Delimiter $CONF_CSV_DELIMITER -Header 'Enabled','Country','Entity','Comments'
    }
    else {
        Write-Warning "No file found for local Entities at the following path: $($CONF_ENTITY_FILE)"
        return $EntityList
    }
    $EntityImport | ForEach-Object {
        if ( $_.Enabled.ToLower() -eq "on" ) {
            $newEntity = [UserStatsEntity]::new()
            $newEntity.Country = $_.Country
            $newEntity.Entity = $_.Entity
            $newEntity.Comments = $_.Comments
            $EntityList.Add($newEntity)
        }
    }
    return $EntityList
}

<#
    .Description
    Creating list of inactive users per company legal entity
#>
function CreateEntityFiles {
    param (
        $AllUsers
    )
    # Checking is sub-folder exists
    if ($CONF_ENTITY_OUTPUT_PATH -ne "") {
        if (-not (Test-Path -Path $CONF_ENTITY_OUTPUT_PATH) ) {
            Write-Warning "Error: Path to entity files does not exist."
            return
        }
    }
    else {
        $CONF_ENTITY_OUTPUT_PATH = "$($CONF_MY_WORKDIR)\EntityFiles"
        if (-not (Test-Path -Path $CONF_ENTITY_OUTPUT_PATH) ) {
            New-Item -ItemType Directory -Force -Path $CONF_ENTITY_OUTPUT_PATH > $null
        }
    }
    
    # List of users which have been exported into Entity lists. The remaining users will be exported in remaining export. 
    $ExportedEntitiyUsersIDs = New-Object System.Collections.Generic.List[System.Object]

    # Creating list of inactive users only    
    $InactiveEntityUsers = $AllUsers | Where-Object { ($_.UserType -eq "Member" -and $_.LastActivityDaysCategory -eq $CONF_INACTIVE_KEYWORD -and $_.CleanupException -eq "") -or ($_.ADPasswordQuality -eq "Weak" -and ( $_.EIDAccountEnabled -eq "True" -or $_.ADAccountEnabled -eq "True" ) ) }
    
    # Exporting list of incactive users
    $AllInactiveExportUsers = New-Object System.Collections.Generic.List[System.Object]
    foreach ($user in $InactiveEntityUsers) {
        $AllInactiveExportUsers.Add( (GetUserStatsExportUser($user)) )
    }
    $AllInactiveExportUsers | Export-Excel -Path "$($CONF_ENTITY_OUTPUT_PATH)/All_InactiveUsers_$(Get-Date -Format "yyyyMMdd").xlsx" -ClearSheet

    # Exporting list of inactive admin users
    $AllInactiveExportAdminUsers = New-Object System.Collections.Generic.List[System.Object]
    foreach ($user in $InactiveEntityUsers ) {
        $match = $false
        # Matching Entra admins
        foreach ($expr in $CONF_EID_ADMIN_SEARCH ) {
            if ( $user.EIDUserPrincipalName -match $expr ) {
                $match = $true
                break
            }
        }
        
        # Matching AD admins if no match yet
        if ( -not $match ) {
            foreach ($expr in $CONF_AD_ADMIN_SEARCH ) {
                if ( $user.ADSamAccountName -match $expr ) {
                    $match = $true
                    break
                }
            }
        }
                
        # Adding inactive admin to export list
        if ( $match ) {
            $AllInactiveExportAdminUsers.Add( (GetUserStatsExportUser($user)) )
            $ExportedEntitiyUsersIDs.Add($user.Id)
        }
    }
    # Creating list for inactive admin users
    if ( $AllInactiveExportAdminUsers.Count -gt 0 ) {
        $AllInactiveExportAdminUsers | Export-Excel -Path "$($CONF_ENTITY_OUTPUT_PATH)/All_InactiveWeakAdmins_$(Get-Date -Format "yyyyMMdd").xlsx" -ClearSheet
    }
    
    # Creating list for each entity
    foreach ($entity In LoadEntities) {
        Write-Information "Creating entity list for $($entity.Country) $($entity.Entity)..."
        $EntityUserList = New-Object System.Collections.Generic.List[System.Object]
        foreach ($user In $InactiveEntityUsers) {
            if ( $user.ADDNCountry -like $entity.Country -and $user.ADDNOrg -like $entity.Entity ) {
                $EntityUserList.Add( (GetUserStatsExportUser($user)) )
                $ExportedEntitiyUsersIDs.Add($user.Id)
            }
        }
        if ( $entity.Entity -eq "*" ) { $entity.Entity = "ALL" }
        $FILEPATH = "$($CONF_ENTITY_OUTPUT_PATH)/$($entity.Country)/$($entity.Entity)"
        if (-not (Test-Path -Path $FILEPATH) ) {
            New-Item -ItemType Directory -Force -Path $FILEPATH > $null
        }
        $EXPORT_FILENAME = "$($entity.Country)_$($entity.Entity)_$(Get-Date -Format "yyyyMMdd").xlsx" 
        $EntityUserList | Export-Excel -Path "$($FILEPATH)/$($EXPORT_FILENAME)" -ClearSheet
        Write-Information "Entity list for $($entity.Country) $($entity.Entity) has been created at: $($EXPORT_FILENAME)"
    }

    # Creating Remaining inactive users list
    $RemainingUserList = New-Object System.Collections.Generic.List[System.Object]
    foreach ($user In $InactiveEntityUsers) {
        if ( -not ($ExportedEntitiyUsersIDs.Contains($user.Id) ) ) {
            $RemainingUserList.Add( (GetUserStatsExportUser($user)) )
        }
    }
    $EXPORT_FILENAME = "RemainingUsers_$(Get-Date -Format "yyyyMMdd").xlsx"
    $RemainingUserList | Export-Excel -Path "$($CONF_ENTITY_OUTPUT_PATH)/$($EXPORT_FILENAME)"
    Write-Information "Entity list for remaining users has been created at: $($CONF_ENTITY_OUTPUT_PATH)/$($EXPORT_FILENAME)"
}

<#
    .Description
    Get a user dataset in a simplified format for company legal entity lists
#>
function GetUserStatsExportUser{
    param (
        $user
    )
    $nu = [UserStatsExportUser]::new()
    $nu.AccountType = $user.ADDNAccountType
    $nu.Id = $user.Id
    $nu.UserPrincipalName = $user.EIDUserPrincipalName
    $nu.DisplayName = $user.DisplayName
    $nu.Mail = $user.Mail
    $nu.GivenName = $user.GivenName
    $nu.Surname = $user.Surname
    $nu.Company = $user.ADCompany
    $nu.ADMobilePhone = $user.ADMobilePhone
    $nu.AdminDescription = $user.ADadminDescription
    $nu.AccountEnabled = $user.EIDAccountEnabled -or $user.ADAccountEnabled
    $nu.EIDBlockedO365 = $user.EIDBlockedO365
    $nu.EIDCreatedDateTime = $user.EIDCreatedDateTime
    $nu.LastSignIn = $user.HybridLastSignIn
    $nu.EIDLastPasswordChangeDateTime = $user.EIDLastPasswordChangeDateTime
    $nu.ADDomain = $user.ADDomain
    $nu.ADCreated = $user.ADCreated
    $nu.ADPasswordLastSet = $user.ADPasswordLastSet
    $nu.ADPasswordExpired = $user.ADPasswordExpired
    $nu.ADLockedOut = $user.ADLockedOut
    $nu.ADPasswordNeverExpires = $user.ADPasswordNeverExpires
    $nu.EXOMailBoxType = $user.EXOMailBoxType
    $nu.ADPasswordQuality = $user.ADPasswordQuality
    $nu.ADPasswordLength = $user.ADPasswordLength
    $nu.ADPasswordPolicyDeviation = $user.ADPasswordPolicyDeviation
    if ($user.LastActivityDaysCategory -eq $CONF_INACTIVE_KEYWORD -and $user.CleanupException -eq "") {
        $nu.ReviewReason = "Inactive"
    }
    if ( $user.ADPasswordQuality -eq "Weak" -and ($user.EIDAccountEnabled -eq "True" -or $user.ADAccountEnabled -eq "True") ) {
        $nu.ReviewReason += "|Weak Password"
    }
    $nu.ReviewReason = $nu.ReviewReason.Trim("|")
    if ( $nu.ReviewReason -eq "Weak Password" ) {
        $nu.Delete = "No"
    }
    return $nu
}

<#
    .Description
    Delete inactive guest users
#>
function DeleteGuestUsers {
    param (
        $AllAccounts
    )
    if ( $CONF_DELETE_GUEST_USERS -ne $true ) {
        # Guest user deletion is off
        return
    }

    # Getting list of all guest users to delete
    $RemovalList = $AllAccounts | Where-Object { $_.UserType -eq "Guest"  -and $_.LastActivityDaysCategory -eq $CONF_INACTIVE_KEYWORD -and $_.CleanupException -eq ""}

    # Creating list of guest accounts for deletion
    $FILE_NEW_INACTIVE_GUESTS = "$($CONF_REPORT_INACTIVE_GUEST_ACCOUNTS)_$(Get-Date -Format "yyyyMMdd").xlsx"
    $RemovalList | Export-Excel -Path $FILE_NEW_INACTIVE_GUESTS -ClearSheet
    Write-Information "Please check guest accounts for deletion before confirming at: $($FILE_NEW_INACTIVE_GUESTS)"

    # Waiting for confirmation
    $UserConfDeleteGuests = Read-Host "Please confirm with ""yes"" to delete $($RemovalList.Count) guest users. [No]"
    if ( $UserConfDeleteGuests -like "yes") {
        Write-Information "Deleting $($RemovalList.Count) guest users from Entra ID..."
        # Gaining write access to Microsoft Graph
        ConnectEntraID -ReadWrite $true
        $counter = 0
        # Deleting guest users
        foreach ($usr In $RemovalList) {
            Write-Information "Deleting user with ID: $($usr.Id)..."
            try {
                #Write-Information "Remove-MgUser -PassThru -UserId $($usr.Id)"
                Remove-MgUser -PassThru -UserId $($usr.Id)
                if ( $true -eq $? ) { 
                    Write-Information "Sucessfully removed user: $($usr.Id), $($usr.EIDUserPrincipalName)"
                }
                else {
                    Write-Warning "Failed to remove: $($usr.Id), $($usr.EIDUserPrincipalName)"
                }
            }
            catch {
                Write-Warning "Failed to remove: $($usr.Id), $($usr.EIDUserPrincipalName)"
                Write-Warning "$Error[0]"
            }
            $counter++
            Write-Information "Progress: $($counter)/$($RemovalList.Count)"
            # Start slowly
            if ( $counter -lt 10 ) {
                Start-Sleep 3
            }
        }
    } else {
        Write-Warning "Cancelled deletion of guest user accounts."
    }   
}

<#
    .Description
    Get Entra ID group memberships including nested groups
#>
function GetNestedGroupMembers {
    param (
        $GroupID
    )
    $members = Get-MgGroupMember -All -GroupId $GroupID
    $mlist = New-Object System.Collections.Generic.List[System.Object]
    foreach ($u in $members) {
        if ( $u.AdditionalProperties."@odata.type" -match "#microsoft.graph.group" ) {
            # Nested group in group
            $nestedmlist = GetNestedGroupMembers -GroupID $u.Id
            foreach ($nu in $nestedmlist) {
                $mlist.Add($nu)
            }
        }
        else {
            # User in group
            $mlist.Add($u.Id)
        }
    }
    return $mlist
}

<#
    .Description
    Loading MFA groups of MFA excepted users and/or enabled users
#>
function LoadMFAGroups {
    $MfaGroups = @{}
    # Setting MFA Enabled Groups
    foreach ( $group in $CONF_MFA_ENABLED_SECURITY_GROUPS ) {
        # Getting group name
        $GroupName = (Get-MgGroup -GroupId $group).DisplayName
        $MfaGroups[$group] = @{'NAME' = $GroupName; 'TYPE' = "ENABLED"}
    }
    # Setting MFA Exception Groups
    foreach ( $group in $CONF_MFA_EXCEPTION_SECURITY_GROUPS ) {
        # Getting group name
        $GroupName = (Get-MgGroup -GroupId $group).DisplayName
        $MfaGroups[$group] = @{'NAME' = $GroupName; 'TYPE' = "EXCEPTION"}
    }

    # Getting MFA Group Memberships
    if ( $MfaGroups.Count -gt 0 ) {
        Write-Information "Fetching MFA group memberships..."
        foreach ($group In $MfaGroups.Keys) {
            $MfaGroups[$group]['MEMBERS'] = GetNestedGroupMembers -GroupID $group
        }
    }
    return $MfaGroups
}

<#
    .Description
    Loading MFA hardware tokens from file
#>
function LoadMFAHardwareTokens {
    # Selecting files
    $TOKEN_CSV_FILE = (Get-Item "$($CONF_MY_WORKDIR)/*" -Include "exportTokens_*")
        
    # Importing CSV Files
    if ($null -ne $TOKEN_CSV_FILE) {
        $MFA_HARDWARE_TOKENS = Import-Csv $TOKEN_CSV_FILE.Name -Encoding UTF8 -Delimiter ","
        Write-Information "Loaded $($MFA_HARDWARE_TOKENS.Count) Hardware Tokens."
        return $MFA_HARDWARE_TOKENS
    }
    else {
        return $null
    }
}

<#
    .Description
    Getting users MFA methods
#>
function GetUsersMFA {
    param (
        $UserObjectID,
        $UPN,
        $MfaGroups,
        $MfaHardwareTokens
    )
    # RETURN
    $RETURN_INFO = @{}

    # Checking membership of the user in MFA enabled or exception group
    $RETURN_INFO["MfaEnabled"] = ""
    foreach ($group In $MfaGroups.Keys) {
        if ( $MfaGroups[$group]["MEMBERS"].Contains($UserObjectID) ) {
            if ( $RETURN_INFO["MfaEnabled"].Length -gt 0 ) {
                # Adding delimiter
                $RETURN_INFO["MfaEnabled"] += "|"    
            }
            $RETURN_INFO["MfaEnabled"] += "$($MfaGroups[$group]["TYPE"]):$($MfaGroups[$group]["NAME"])"
        }
    }

    # Getting MFA Authentication Methods
    $success = $false
    while ( -not $success ) {
        try {
            $AuthMethods = Get-MgUserAuthenticationMethod -UserId $UserObjectID -ErrorAction Stop
            $success = $true
        }
        catch {
            if ( $_.Exception.Message -eq "[accessDenied] : Request Authorization failed" ) {
                Write-Warning "MFA Authentication Methods: Authorization failed for user: $UserObjectID - User probably meanwhile deleted"
                $RETURN_INFO["MfaAuthMethods"] = "Authorization Failed"
                return $RETURN_INFO
            }
            else {
                Write-Warning "Exception while querying MFA authentication methods. Retrying..."
                Write-Warning "Details: $($Error)"
                Write-Warning "UserObjectId: $UserObjectID"
                Start-Sleep(5)
            }
        }
    }
    
    $RETURN_INFO["MfaAuthMethods"] = ""
    foreach ($method In $AuthMethods) {
        If ($method.additionalproperties."@odata.type" -match "#microsoft.graph.phoneAuthenticationMethod") {
            $RETURN_INFO["MfaAuthMethods"] += "Phone:$($method.additionalproperties.phoneNumber)|"
        }
        elseif ($method.additionalproperties."@odata.type" -match "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod") {
            $RETURN_INFO["MfaAuthMethods"] += "MicrosoftAuthenticator|"
        }
        elseif ($method.additionalproperties."@odata.type" -match "#microsoft.graph.emailAuthenticationMethod") {
            $RETURN_INFO["MfaAuthMethods"] += "Email|"
        }
        elseif ($method.additionalproperties."@odata.type" -match "#microsoft.graph.windowsHelloForBusinessAuthenticationMethod") {
            $RETURN_INFO["MfaAuthMethods"] += "HelloForBusiness|"
        }
        elseif ($method.additionalproperties."@odata.type" -match "#microsoft.graph.fido2AuthenticationMethod") {
            $RETURN_INFO["MfaAuthMethods"] += "Fido2|"
        }
        elseif ($method.additionalproperties."@odata.type" -match "#microsoft.graph.passwordAuthenticationMethod") {
            # Password is not a MFA factor
            continue
        }
        elseif ($method.additionalproperties."@odata.type" -match "#microsoft.graph.passwordlessMicrosoftAuthenticatorAuthenticationMethod") {
            $RETURN_INFO["MfaAuthMethods"] += "PasswordLess|"
        }
        else {
            $RETURN_INFO["MfaAuthMethods"] += "Other: $($method.additionalproperties."@odata.type")|"
        }
    }
    # Adding MFA Hardware Token
    if ( $null -ne $MfaHardwareTokens ) {
        $TOKEN = $MfaHardwareTokens | Where-Object { $_.Upn.ToLower() -eq $UPN.ToLower() }
        if ( $null -ne $TOKEN ) {
            if ( $TOKEN -is [array] ) {
                $TOKEN | ForEach-Object {
                    $RETURN_INFO["MfaAuthMethods"] += "HardwareToken:$($_.SerialNumber)|"
                }
            }
            else {
                $RETURN_INFO["MfaAuthMethods"] += "HardwareToken:$($TOKEN.SerialNumber)|"
            }   
        }
    }

    # Trim final delimiter
    if ( $RETURN_INFO["MfaAuthMethods"].Length -gt 0 ) {
        $RETURN_INFO["MfaAuthMethods"] = $RETURN_INFO["MfaAuthMethods"].Substring(0,$RETURN_INFO["MfaAuthMethods"].Length-1)
    }
    
    return $RETURN_INFO
}

<#
    .Description
    Returns the account type based on path in distinguished name
#>
function GetUsersAccountType {
    param (
        $ADDistinguishedName
    )
    # Getting account type of OU membership
    $TmpDN = $ADDistinguishedName.ToLower()

    # Searching all configured accounts types
    foreach ($AccountType in $CONF_ACCOUNT_TYPE_SEARCH.Keys) {
        if ( $TmpDN.Contains($CONF_ACCOUNT_TYPE_SEARCH[$AccountType]) ) {
            return $AccountType
        }
    }

    # No account type found, return Unknown
    return "Unknown"
}

<#
    .Description
    Returns the user country and company from distinguished name
#>
function GetUsersCountryOrg {
    param (
        $ADDistinguishedName
    )
    # Getting account type of OU membership
    $TmpDN = $ADDistinguishedName.Replace("\,","_-_")
    $DNlist = $TmpDN.split(",")

    $Country = ""
    $Entity = ""

    # Extracting Country from DN
    if ( $CONF_AD_DN_COUNTRY_LEVEL -gt 0 -and $DNlist.Count -ge $CONF_AD_DN_COUNTRY_LEVEL ) {
        $Country = $DNlist[$DNlist.Count - $CONF_AD_DN_COUNTRY_LEVEL].Split("=")[1]
    }
    # Extracting Entity
    if ( $CONF_AD_DN_ENTITY_LEVEL -gt 0 -and $DNlist.Count -ge $CONF_AD_DN_ENTITY_LEVEL ) {
        $Entity = $DNlist[$DNlist.Count - $CONF_AD_DN_ENTITY_LEVEL].Split("=")[1]
    }  
        
    return ($Country,$Entity)
}

<#
    .Description
    Loading all Exchange Online Mailboxes. Mailbox types help to identify user types like shared or service accounts
#>
function LoadEXOMailboxes {
    $EXO_MAILBOXES = @{}
    if ( $CONF_QUERY_EXCHANGE_ONLINE ) {
        # Path to import mailboxes if already loaded
        $EXO_FILEPATH = "$($CONF_MY_WORKDIR)/exo_mailboxes_$(Get-Date -Format "yyyyMMdd").csv"
        if (Test-Path -Path $EXO_FILEPATH) {
            Write-Information "Importing EXO mailboxes from $EXO_FILEPATH..."
            $Exo_Tmp_List = Import-Csv $EXO_FILEPATH -Encoding UTF8 -Delimiter $CONF_CSV_DELIMITER
            $Exo_Tmp_List.psobject.properties | ForEach-Object {
                $EXO_MAILBOXES[$_.Name] = $_.Value
            }
        }
        else {
            # Connecting to Exchange Online
            Write-Host "Connecting to Exchange Online API..."
            Connect-ExchangeOnline -Device -ShowBanner:$false
            Write-Information "Fetching mailbox list from Exchange Online. This can take up to 20min..."
            $Exo_Tmp_List = Get-Recipient -ResultSize unlimited -RecipientTypeDetails SchedulingMailbox,SharedMailbox,RoomMailbox,EquipmentMailbox,UserMailbox
            Write-Information "Preparing mailbox list..."
            foreach ($mb in $Exo_Tmp_List) {
                $EXO_MAILBOXES[$mb.ExternalDirectoryObjectId] = $mb.RecipientTypeDetails
            }
            Write-Information "Completed. Creating local copy of mailbox list..."
            $EXO_MAILBOXES | Export-Csv -Path $EXO_FILEPATH -IncludeTypeInformation -Encoding UTF8 -Delimiter $CONF_CSV_DELIMITER
        }
    }
    return $EXO_MAILBOXES
}

<#
    .Description
    # Returns the MailboxType of the supplied User
#>
function GetUsersMailboxType {
    param (
        $EIDObjectID,
        $MailboxHash
    )
    # Returning mailbox type or None
    $MbType = $MailboxHash[$EIDObjectID]
    if ( $null -ne $MbType ) {
        return $MbType
    }
    else {
        return "None"
    }
}

<#
    .Description
    # Loading Password Audit Files created with eg. Mimikatz
#>
function LoadPasswordAuditFiles {
    $MIMIKATZ = @{}
    $PassCount = 0
    # Loading Mimikatz Files
    foreach ($domain in $CONF_MIMIKATZ_DOMAINS) {
        $FileSelector = "mimikatz_$($domain)*"
        $FILE = (Get-Item "$($CONF_MIMIKATZ_FILES_PATH)/*" -Include $FileSelector).Name
        if ($null -ne $FILE) {
            Write-Information "Found Mimikatz file for domain $($domain): $FILE"
            $MIMIKATZ[$domain] = Import-Csv "$($CONF_MIMIKATZ_FILES_PATH)/$($FILE)" -Encoding UTF8 -Delimiter "," -Header 'Domain','samAccountName','PasswordLength'
            $PassCount += $MIMIKATZ[$domain].Count
        }
        else {
            Write-Error "Failed to load Domain Mimikatz File for domain: $domain"
        }
    }
    if ( $CONF_MIMIKATZ_DOMAINS.Count -gt 0 ) {
        Write-Information "Loaded $PassCount Mimikatz accounts with weak passwords"
    } 
    return $MIMIKATZ
}

<#
    .Description
    # Updating O365 block group to include users that have not configured MFA after 4 weeks since creation 
#>
function UpdateBlockedAccessGroup {
    param (
        $AllAccounts
    )
    # Checking if Access group is configured otherwise skip blocking
    if ( $CONF_BLOCKED_SECURITY_GROUP -eq "" ) {
        return
    } 
    # Filtering to be blocked accounts
    $ToBeBlockedAccounts = $AllAccounts | Where-Object { $_.EIDBlockedO365 -eq "Block" }
    # Getting current list of blocked accounts
    $BlockedMembers = Get-MgGroupMember -All -GroupId $CONF_BLOCKED_SECURITY_GROUP
    # Blocked Account Count
    $BlockedAccountCount = $BlockedMembers.Count
    Write-Information "Current count of blocked member accounts: $($BlockedAccountCount)"
    # Creating hash of ToBe Account List
    $ToBeAccountsHash = @{}
    $ToBeBlockedAccounts | ForEach-Object {
        $ToBeAccountsHash.Add($_.Id, $_)
    }
    
    # Run through all IDs existing in Blocked Group
    $BlockedMembers | ForEach-Object {
        if ($ToBeAccountsHash.ContainsKey($_.Id) ){
            # Account still blocked and already in blocked group
            $ToBeAccountsHash.Remove($_.Id)
        }
    }

    # Creating list of accounts to be blocked for checking before blocking
    $FILE_NEW_BLOCKED_ACCOUNTS = "$($CONF_REPORT_BLOCKED_ACCOUNTS)_$(Get-Date -Format "yyyyMMdd").xlsx"
    $ToBeAccountsHash.Values | Export-Excel -Path $FILE_NEW_BLOCKED_ACCOUNTS -ClearSheet
    Write-Information "Please check new blocked accounts before confirming at: $($FILE_NEW_BLOCKED_ACCOUNTS)"
    
    # Adding new members to blocked group
    $UserConfBlockUsers = Read-Host "Please confirm with ""yes"" to add $($ToBeAccountsHash.Count) users to blocklist. [No]"
    if ( $UserConfBlockUsers -like "yes") {
         # Connecting ReadWrite
        Write-Information "Connecting to EntraID with ReadWrite permissions to modify blocked group."
        ConnectEntraID -ReadWrite $true
        Write-Information "Adding $($ToBeAccountsHash.Count) users to blocked access group."
        $ToBeAccountsHash.Keys | ForEach-Object {
            try {
                New-MgGroupMember -GroupId $CONF_BLOCKED_SECURITY_GROUP -DirectoryObjectId $_
                $BlockedAccountCount++
            }
            catch {
                Write-Information "Failed to add user to blocked group: $_"
            }
        }
        # Final statement
        Write-Information "New total count of blocked accounts: $($BlockedAccountCount)"
    } else {
        Write-Warning "Cancelled to add accounts into blocklist."
    }   
}

<#
    .Description
    # Connecting to Entra ID
#>
function ConnectEntraID{
    param (
        $ReadWrite = $false
    )
    Write-Host "Checking authentication to Microsoft Graph..."
    # Checking authentication to Microsoft Graph with adm user and right TenantID
    $MgContext = Get-MgContext
    if ( $null -eq $MgContext -or -not $MgContext.Account.StartsWith("adm.") -or -not $MgContext.TenantId -eq $CONF_TENANT_ID ) {
        Write-Host "Connecting to Microsoft Graph, please provide admin credentials."
        if ( $ReadWrite ) {
            Connect-MgGraph -UseDeviceCode -NoWelcome -Scopes @("User.ReadWrite.All","UserAuthenticationMethod.Read.All","Group.ReadWrite.All")
        } else {
            Connect-MgGraph -UseDeviceCode -NoWelcome -Scopes @("UserAuthenticationMethod.Read.All","User.Read.All")
        }
    }
    else {
        if ( $ReadWrite ) {
            # Checking if current Mg Scope contains ReadWrite
            if ( $null -eq ( $MgContext.Scopes | Where-Object { $_ -eq "Group.ReadWrite.All" } ) ) {
                # Increasing permission to RW
                Write-Host "Re-Connecting to Microsoft Graph with Read-Write permissions, please provide admin credentials."
                Connect-MgGraph -UseDeviceCode -NoWelcome -Scopes @("User.ReadWrite.All","UserAuthenticationMethod.Read.All","Group.ReadWrite.All")
            }
        }
    }
}

<#
    .Description
    # Creating UserStatsUser objects
#>
function GetUserStatsUser {
    param (
        $User,
        $Type
    )
    # Common attributes
    $newUser = [UserStatsUser]::new()
    $newUser.DisplayName = $User.DisplayName
    $newUser.GivenName = $User.GivenName
    $newUser.Surname = $User.Surname
    $newUser.Mail = $User.Mail

    # EID Attributes
    if ($Type -eq "EID") {
        $newUser.Id = $User.Id.ToString()
        $newUser.UserType = $User.UserType
        $newUser.EIDUserPrincipalName = $User.UserPrincipalName.ToLower()
        $newUser.EIDAccountEnabled = if ($null -ne $User.AccountEnabled) { $User.AccountEnabled } else { "UNKNOWN" }
        $newUser.EIDCreatedDateTime = if ($null -ne $User.CreatedDateTime) { $User.CreatedDateTime.ToString("s") }
        $newUser.EIDLastPasswordChangeDateTime = if ($User.LastPasswordChangeDateTime) { $User.LastPasswordChangeDateTime.ToString("s") }
        $newUser.EIDCompanyName = $User.CompanyName
        $newUser.EIDBusinessContact = $User.EmployeeType
        # Getting additional email addresses
        if ( $User.OtherMails.Count -gt 0 )
        {
            $newUser.EIDAlternateMail = [system.String]::Join("|", $User.OtherMails)
        }
        $newUser.EIDonPremisesDomainName = $User.onPremisesDomainName
        $newUser.EIDonPremisesSecurityIdentifier = $User.onPremisesSecurityIdentifier
        # Getting Last SignIn from Entra ID
        $newUser.EIDLastSignIn = GetDateTime -date $User.SignInActivity.LastSignInDateTime
        # Checking for Cleanup exceptions
        $newUser.CleanupException = GetNonExpiredCleanupExceptionString $newUser.EIDUserPrincipalName $newUser.Mail $newUser.Id $CleanupExceptionHash
    } 
    # AD attributes
    elseif ($Type -eq "AD") {
        $newUser.Id = $User.SID.ToString()
        $newUser.UserType = "Member"
        # Checking UPN
        if ( $null -eq $User.UserPrincipalName ) {
            $newUser.ADUserPrincipalName = "ADEmptyUPN"
        }
        else {
            # Setting both UPNs to AD User principal name
            $newUser.EIDUserPrincipalName = $User.UserPrincipalName.ToLower()
            $newUser.ADUserPrincipalName = $User.UserPrincipalName.ToLower()
        }
        $newUser.ADMobilePhone = $User.Mobile
        $newUser.ADSamAccountName = $User.SamAccountName
        $newUser.ADAccountEnabled = if ( $null -ne $User.Enabled ) { $User.Enabled } else { "UNKNOWN" } 
        $newUser.ADCreated = GetDateTime -date $User.created
        $newUser.ADPasswordLastSet = GetDateTime -date $User.PasswordLastSet
        $newUser.ADDomain = $User.CanonicalName.Split("/")[0]
        $newUser.ADLastLogonDate = GetDateTime -date $User.LastLogonDate
        $newUser.ADPasswordNeverExpires = $User.PasswordNeverExpires
        $newUser.ADPasswordLastSet = GetDateTime -date $User.PasswordLastSet
        $newUser.ADPasswordExpired = $User.PasswordExpired
        $newUser.ADLockedOut = $User.LockedOut
        $newUser.ADlogonCount = $User.logonCount
        $newUser.ADLastBadPasswordAttempt = GetDateTime -date $User.LastBadPasswordAttempt
        $newUser.ADDistinguishedName = $User.DistinguishedName
        $newUser.ADCompany = $User.Company
        $newUser.ADCreated = GetDateTime -date $User.Created
        $newUser.ADadminDescription = $User.adminDescription
        $newUser.ADAccountExpirationDate = GetDateTime -date $User.AccountExpirationDate
        # Getting account type of OU membership
        $newUser.ADDNAccountType = GetUsersAccountType -ADDistinguishedName $newUser.ADDistinguishedName
        $newUser.ADDNCountry, $newUser.ADDNOrg = GetUsersCountryOrg -ADDistinguishedName $newUser.ADDistinguishedName
        $newUser.ProcessingRemark += "AD Only User;"
        # Checking for Cleanup exceptions
        $newUser.CleanupException = GetNonExpiredCleanupExceptionString $newUser.ADUserPrincipalName $newUser.Mail $newUser.Id $CleanupExceptionHash
    }
    return $newUser
}

<#
    .Description
    # Update UserStatsUser objects with Active Directory details
#>
function UpdateUserStatsUserADDetails {
    param (
        $CurrentUser,
        $ADDetails
    )
    $CurrentUser.ADSamAccountName = $ADDetails.SamAccountName
    if ( $null -eq $ADDetails.UserPrincipalName ) {
        $CurrentUser.ADUserPrincipalName = "ADEmptyUPN"
    }
    else {
        $CurrentUser.ADUserPrincipalName = $ADDetails.userPrincipalName.ToLower()
    }
    $CurrentUser.ADMobilePhone = $ADDetails.Mobile
    $CurrentUser.ADAccountEnabled = if ( $null -ne $ADDetails.Enabled ) { $ADDetails.Enabled } else { "UNKNOWN" } 
    $CurrentUser.ADCreated = GetDateTime -date $ADDetails.created
    $CurrentUser.ADPasswordLastSet = GetDateTime -date $ADDetails.PasswordLastSet
    $CurrentUser.ADDomain = $CurrentUser.EIDonPremisesDomainName
    $CurrentUser.ADLastLogonDate = GetDateTime -date $ADDetails.LastLogonDate
    $CurrentUser.ADPasswordNeverExpires = $ADDetails.PasswordNeverExpires
    $CurrentUser.ADPasswordLastSet = GetDateTime -date $ADDetails.PasswordLastSet
    $CurrentUser.ADPasswordExpired = $ADDetails.PasswordExpired
    $CurrentUser.ADLockedOut = $ADDetails.LockedOut
    $CurrentUser.ADlogonCount = $ADDetails.logonCount
    $CurrentUser.ADLastBadPasswordAttempt = GetDateTime -date $ADDetails.LastBadPasswordAttempt
    $CurrentUser.ADDistinguishedName = $ADDetails.DistinguishedName
    $CurrentUser.ADCompany = $ADDetails.Company
    $CurrentUser.ADCreated = GetDateTime -date $ADDetails.Created
    $CurrentUser.ADadminDescription = $ADDetails.adminDescription
    $CurrentUser.ADAccountExpirationDate = GetDateTime -date $ADDetails.AccountExpirationDate
    $CurrentUser.ADDNAccountType = GetUsersAccountType -ADDistinguishedName $CurrentUser.ADDistinguishedName
    $CurrentUser.ADDNCountry, $CurrentUser.ADDNOrg = GetUsersCountryOrg -ADDistinguishedName $CurrentUser.ADDistinguishedName
    # Checking if Account is in AD Cleanup OU
    return $CurrentUser
}

<#
    .Description
    # Retrieve all users from AD and Entra ID either from existing files or retrieve directly
#>
function LoadAllUsers {
    # ALL users
    $all_users_coll = New-Object System.Collections.Generic.List[System.Object]
    Write-Information "Getting a list of all users from Entra ID..."
    # Getting all users and save only selected properties
    $all_users_aad = Get-MgUser -All -Property 'DisplayName, Id, Mail, UserPrincipalName, UserType, AccountEnabled, CreatedDateTime, LastPasswordChangeDateTime, GivenName, Surname, OnPremisesDomainName, OnPremisesSecurityIdentifier, CompanyName, EmployeeType, otherMails, SignInActivity'
    # Creating user objects for all EID users
    $ProgressCounter = 0
    $all_users_aad | ForEach-Object {
        $all_users_coll.Add( (GetUserStatsUser -User $_ -Type "EID") )
        $ProgressCounter++
        $percent_complete = [math]::round( ($ProgressCounter/($all_users_aad.Count) )*100 ,2)
        Write-Progress -Activity "Creating user list..." -Status "$percent_complete %" -PercentComplete $percent_complete
    }
    # Closing progress bar
    Write-Progress -Activity "Creating user list..." -Completed
    # Setting List of EID to null
    $all_users_aad = $null
    # Getting all ActiveDirectory accounts
    if ($CONF_INCLUDE_ACTIVE_DIRECTORY) {
        # Loading AD users and mapping to Azure AD / Entra ID users
        Write-Information "Getting a list of all users from AD..."
        # Creating list of all member users, guests not relevant for AD
        $member_users_coll = New-Object System.Collections.Generic.List[System.Object]
        $all_users_tmp = $all_users_coll.ToArray()
        # New collection of updated or skipped guest users
        $all_users_coll = New-Object System.Collections.Generic.List[System.Object]
        $all_users_tmp | ForEach-Object {
            if ( $_.UserType -eq "Member" ) {
                $member_users_coll.Add($_)
            }
            else {
                $all_users_coll.Add($_)
            }
        }
        # Getting all active directory users
        $AllDomainsUserHash = GetAllADDomainUsers
        
        # Some counters
        $ADOnlyUsers = 0
        $UpdatedEIDUsers = 0
        $EIDOnlyUsers = 0
        $ProgressCounter = 0
        
        # Mapping AD users to Entra ID users
        foreach ($mu In $member_users_coll) {
            try {
                if ( $mu.EIDonPremisesSecurityIdentifier -eq "" -or $mu.EIDonPremisesDomainName -eq "" ) {
                    # Skipping for users which are EID only
                    $mu.ProcessingRemark += "EID Only user;"
                    $all_users_coll.Add($mu)
                    $EIDOnlyUsers++
                }
                else {
                    $ADuser = $AllDomainsUserHash[$mu.EIDonPremisesSecurityIdentifier]
                    if ($null -ne $ADuser) {
                        $AllDomainsUserHash.Remove($mu.EIDonPremisesSecurityIdentifier)
                        # Update user with AD details and add to final collection
                        $all_users_coll.Add( (UpdateUserStatsUserADDetails -CurrentUser $mu -ADDetails $ADuser) )
                        $UpdatedEIDUsers++
                    }
                    else {
                        # User not found in AD
                        $mu.ProcessingRemark += "SID not found in AD;"
                        $all_users_coll.Add($mu)
                        $EIDOnlyUsers++
                    }
                }
                $ProgressCounter++
                $percent_complete = [math]::round( ($ProgressCounter/($member_users_coll.Count) )*100 ,2)
                Write-Progress -Activity "Mapping EID users to On-Premise AD..." -Status "$percent_complete %" -PercentComplete $percent_complete
            }
            catch {
                Write-Error "Exception while Mapping EID users to On-Premise AD"
                Write-Error "$Error[0]"
                exit
            }
        }
        # Closing progress bar
        Write-Progress -Activity "Mapping EID users to On-Premise AD..." -Completed
        Write-Information "Updated $UpdatedEIDUsers users of EID with AD details."

        # Adding EID only users
        $AllDomainsUserHash.Keys | ForEach-Object {
                try {
                    # Getting user
                    $au = $AllDomainsUserHash[$_]
                    # Creating and adding AD-Only user
                    $all_users_coll.Add( (GetUserStatsUser -User $au -Type "AD") )
                    $ADOnlyUsers++
                }
                catch {
                    Write-Warning "Error: $($Error[0])"
                    Write-Warning "Failed to add AD-Only User: $($au)"
                    continue
                }
        }
        Write-Information "Added $AdOnlyUsers AD only users | Added $EIDOnlyUsers Entra ID Only users."
        # Sorting
        $all_users = $all_users_coll | Sort-Object -Property DisplayName
    }
    else {
        $all_users = $all_users_coll | Sort-Object -Property DisplayName
    }
    return $all_users
}

<#
    .Description
    # Filter users if only guests or member users are required
#>
function GetRequestedUsers {
    # Requested Users: Import existing users csv to continue or create a new version
    if (Test-Path -Path $($CONF_FILE_REQUESTEDTYPE + ".csv")) {
        Write-Information "Importing requested users from csv (UserType: $($UserType))..."
        return Import-Csv $($CONF_FILE_REQUESTEDTYPE + ".csv") -Encoding UTF8 -Delimiter $CONF_CSV_DELIMITER
    }
    else {
        # No working files available to import. Loading all users. 
        # Creating a new list with all users from Azure AD / Entra ID
        $all_users = LoadAllUsers
        Write-Information "Count of all users: $($all_users.Count)"
        if ( $UserType -eq "Any" ) {
            # Using all users
            return $all_users
        }
        else {
            # Using only selected users
            return $all_users | Where-Object { $_.UserType -eq $UserType }
        }
    }   
}

<#
    .Description
    Check if a given user is marked with a weak password in last mimikatz audits
#>
function GetUserPasswordAuditResult {
    param (
        $User
    )
    # Checking Password Audit results for User
    # Creating Mimikatz Variable name
    if ( $CONF_MIMIKATZ_DOMAINS.Count -gt 0 -and $CONF_MIMIKATZ_DOMAINS -contains $User.ADDomain -and $User.ADDomain -ne "" ) {
        $UsersBadPass = $Mimikatz[$User.ADDomain] | Where-Object { $_.samAccountName -eq $User.ADSamAccountName }
        if ( $null -ne $UsersBadPass ) {
            $User.ADPasswordQuality = "Weak"
            $User.ADPasswordLength = $UsersBadPass.PasswordLength
            if ('Service Account','Admin Account','Resource Account' -contains $User.ADDNAccountType ) {
                if ( [int]$User.ADPasswordLength -lt 16 ) {
                    $User.ADPasswordPolicyDeviation = "Yes"
                }
                else {
                    $User.ADPasswordPolicyDeviation = "No"
                }
            }
            else {
                if ( [int]$User.ADPasswordLength -lt 12 ) {
                    $User.ADPasswordPolicyDeviation = "Yes"
                }
                else {
                    $User.ADPasswordPolicyDeviation = "No"
                }
            }   
        }
    }
    else {
        if ( $CONF_MIMIKATZ_DOMAINS.Count -gt 0 -and $User.ADDomain -ne "" ) {
            Write-Error "Failed to use Mimikatz password list. List not loaded for domain: $($u.ADDomain)"
        }
    }
    return $User
}

<#
    .Description
    Calcuate and compare last sign-in dates and fill the results
#>
function GetUserInactivity {
    param (
        $User
    )
    # Comparing last sign-in on Entra ID with AD
    if ($User.UserType -eq "Member") {
        # Checking which date is younger in the past and populate to final sign-in
        if ( $null -eq $User.EIDLastSignIn -or $User.EIDLastSignIn -eq "" ) {
            # No EID SignIn. Checking if AD has logon last $CONF_INACTIVE_DAYS days
            if ( $User.ADLastLogonDate -ne "" ) {
                $User.HybridLastSignIn = $User.ADLastLogonDate
                $User.HybridLastSignInSource = "AD"
            }
            else {
                if ( $User.Id.StartsWith("S-") ) {
                    $User.HybridLastSignInSource = "AD"
                }
                else {
                    $User.HybridLastSignInSource = "Both"
                }
            }
        }
        else {
            # Check if AD logon is younger than EID
            if ( $User.ADLastLogonDate -ne "" -and [DateTime]$User.ADLastLogonDate -gt [DateTime]$User.EIDLastSignIn ) {
                $User.HybridLastSignIn = $User.ADLastLogonDate
                $User.HybridLastSignInSource = "AD"
            }
            else {
                $User.HybridLastSignIn = $User.EIDLastSignIn
                $User.HybridLastSignInSource = "EID"
            }
        }
    }
    else {
        # Updating final hybrid sign-in date with EID date
        $User.HybridLastSignIn = $User.EIDLastSignIn
        $User.HybridLastSignInSource = "EID"
    }
    
    # Checking if created date is in last $CONF_INACTIVE_DAYS days
    if ( $User.EIDCreatedDateTime -ne "" -and ([DateTime]$User.EIDCreatedDateTime) -gt $dates["Inactive"] ) {
        if ( -not ( $User.HybridLastSignIn -ne "" -and [DateTime]$User.HybridLastSignIn -gt [DateTime]$User.EIDCreatedDateTime ) ){
            $User.HybridLastSignIn = $User.EIDCreatedDateTime
            $User.HybridLastSignInSource = "EID-CreatedDate"
        }
    }
    elseif ($User.ADCreated -ne "" -and ([DateTime]$User.ADCreated) -gt $dates["Inactive"]) {
        if ( -not ( $User.HybridLastSignIn -ne "" -and [DateTime]$User.HybridLastSignIn -gt [DateTime]$User.ADCreated ) ){
            $User.HybridLastSignIn = $User.ADCreated
            $User.HybridLastSignInSource = "AD-CreatedDate"
        }
    }
    return $User
}

<#
    .Description
    Fill user details with some statistics on the latest sign-in
#>
function GetUserSignInStatistics {
    param (
        $User
    )
    # Calculate statistics based on Hybrid Last SignIn
    if ( $null -eq $User.HybridLastSignIn -or $User.HybridLastSignIn -eq "" -or [DateTime]$User.HybridLastSignIn -lt $dates["Inactive"] ) {
        # Set LastActivityCategory
        $User.LastActivityDaysCategory = $CONF_INACTIVE_KEYWORD
    }
    else {
        # Add some statistics
        $lastSignInDateTime = [DateTime]$User.HybridLastSignIn
        if ( $lastSignInDateTime -lt $dates["-60"] ) {
            $User.LastActivityDaysCategory = "90"
        }
        elseif ( $lastSignInDateTime -lt $dates["-30"] ) {
            $User.LastActivityDaysCategory = "60"
        }
        elseif ( $lastSignInDateTime -lt $dates["-14"] ) {
            $User.LastActivityDaysCategory = "30"
        }
        else {
            $User.LastActivityDaysCategory = "14"
        }
    }
    return $User
}

<#
    .Description
    Delete old working files after user confirmation
#>
function DeleteOldWorkingFiles {
    $EXISTING_FILES = @($CONF_FILE_REQUESTEDTYPE, "$($CONF_MY_WORKDIR)/exo_mailboxes", $CONF_REPORT_BLOCKED_ACCOUNTS, $CONF_REPORT_INACTIVE_GUEST_ACCOUNTS)
    $TEST_EXISTING_FILES = $false
    $UserConfExistingFiles = "No"

    # Checking for existing files
    foreach ($FileSelector In $EXISTING_FILES) {
        $item = Get-Item "$($FileSelector)*"
        if ( $null -ne $item ) {
            # At least one file exists
            $TEST_EXISTING_FILES = $true
            $UserConfExistingFiles = Read-Host "Please confirm with ""yes"" to remove old working files and start a new process. Otherwise existing files will be continued. [No]"
            break
        }
    }
    # Removing existing files
    if ( $UserConfExistingFiles -like "yes" ) {
        # Remove temporary existing files
        Write-Information "Removing existing working files..."
        foreach ($FileSelector in $EXISTING_FILES ) {
            Write-Information "Removing: $($FileSelector)*"
            Remove-Item "$($FileSelector)*"
        }
    } elseif ($TEST_EXISTING_FILES) {
        Write-Information "Continuing with existing working files..."
    }
}

#===============================================================================
#      SECTION: PARAMETERS AND SUBFUNCTIONS
#===============================================================================
# Welcome banner
Write-Host "`n#### msuserstats - user statistics and cleanup for Microsoft Entra ID and Active Directory ####`n"

# Continue or fresh start?
DeleteOldWorkingFiles

# Exporting domain users only parameter
if ($ExportDomainUsers) {
    # Exporting all AD domain users
    if ($IsWindows) {
        GetAllADDomainUsers
        exit
    }
    else {
        Write-Error "Exporting AD domain users is only supported on Windows."
        exit
    }
}
#===============================================================================
#      SECTION:  USER COLLECTION
#===============================================================================
# Connecting to Entra ID
ConnectEntraID -ReadWrite $false

# Loading Mailboxes of Exchange Online
$EXOMailBoxes = LoadEXOMailboxes

# Loading MFA information: Groups
$MfaGroups = LoadMFAGroups
# Loading MFA information: Hardware Tokens
$MfaHardwareTokens = LoadMFAHardwareTokens

# Loading Mimikatz Files
$Mimikatz = LoadPasswordAuditFiles

# Loading Cleanup exception
$CleanupExceptionHash = LoadCleanupExceptionList

# Loading Groups for Membership check
$GroupMemberShip = GetGroupMemberShips

# Logging the request user type
Write-Information "Collecting user statistics for users of type: $($UserType)"

# Getting requested users list
$requested_users = GetRequestedUsers
# Logging requested users count
Write-Information "Count of users of requested type $($UserType): $($requested_users.Count)"

#===============================================================================
#      SECTION:  Processing requested users
#===============================================================================

# Counting time
$start_time = Get-Date
$user_counter = 0

# Statistical dates
$dates = @{}
$dates["-14"] = (Get-Date).AddDays(-14)
$dates["-30"] = (Get-Date).AddDays(-30)
$dates["-60"] = (Get-Date).AddDays(-60)
$dates["Inactive"] = (Get-Date).AddDays($CONF_INACTIVE_DAYS * -1)

# Processing users, comparing sign-in dates, get MFA information and collect everything into user dataset
for ($i = 0; $i -lt $requested_users.Count; $i++) {
    try {
        # getting current user and upn
        $u = [UserStatsUser]$requested_users[$i]

        # Continuing existing files by checking if a LastActivityDaysCategory already exists
        if ( $null -ne $u.LastActivityDaysCategory -and $u.LastActivityDaysCategory -ne "" ) {
            $user_counter++
            continue
        }

        # Setting time of this check
        $u.LastSignInCheckDateTime = $(Get-Date).ToString("s")
        
        # Increase counter for processed user
        $user_counter++

        # Calculating user inactivity
        $u = GetUserInactivity -User $u

        # Fill sign-in statistics        
        $u = GetUserSignInStatistics -User $u

        # Checking license group membership of user
        if ( $GroupMemberShip.ContainsKey($u.Id) ) {
            # Fill license property
            $u.EIDGroupMemberships = $GroupMemberShip[$u.Id] -join "|"
        }

        # Getting Users MFA information and Exchange Online MailboxType for EID Users
        if ( -not $u.Id.StartsWith("S-") ) {
            # Getting MFA methods
            $Mfa = GetUsersMFA -UserObjectID $u.Id $u.EIDUserPrincipalName -MfaGroups $MfaGroups -MfaHardwareTokens $MfaHardwareTokens
            $u.EIDMfaGroups = $Mfa["MfaEnabled"]
            $u.EIDMfaAuthMethods = $Mfa["MfaAuthMethods"]
            # Getting EXO Mailbox
            if ( $u.UserType -ne "Guest" -and $CONF_QUERY_EXCHANGE_ONLINE ) {
                # Getting Exchange Online Mailbox Type
                $u.EXOMailBoxType = GetUsersMailboxType -EIDObjectID $U.Id -MailboxHash $EXOMailBoxes
            } 
        }

         # Checking if user needs to be blocked for o365
         if ( -not $u.Id.StartsWith("S-") -and $u.EIDMfaAuthMethods -eq "" -and (-not $u.EIDMfaGroups.Contains("EXCEPTION:") ) ) {
            # No authentication method configured, checking created date
            if ( [datetime]$u.EIDCreatedDateTime -lt $dates["-30"] ) {
                # Account created more than 30 days ago
                $u.EIDBlockedO365 = "Block"
            }
        }

        # Checking Password Audit results for User
        $u = GetUserPasswordAuditResult -User $u
        
        # Write user back
        $requested_users[$i] = $u

        # Calculating progress and remaining time
        $percent = [math]::round( ($i / $requested_users.Count) * 100 , 2)
        $ts = New-TimeSpan -Start $start_time -End (Get-Date)
        $total_mins = $ts.TotalMinutes
        if ( $total_mins -lt 1) {
            $total_mins = 1
        }
        $AverageRequestsPerMinute = $user_counter / $total_mins
        $RemainingTime = [math]::Round( ( ($requested_users.Count - $user_counter) / $AverageRequestsPerMinute) / 60, 2)
        
        # Displaying progress bar
        if ( $u.DisplayName -eq "" ) { $StatsUserName = "Empty" }
        else { $StatsUserName = $u.DisplayName.Substring(0,[System.Math]::Min(15, $u.DisplayName.Length)) }
        Write-Progress -Activity "Processing..." -Status "$percent % | $StatsUserName | ETA/h: $($RemainingTime) | Req/min: $([math]::Round($AverageRequestsPerMinute))" -PercentComplete $percent
        
        # Creating intermediate exports to save progress
        Write-Debug "Creating an intermediate export..."
        if ( $i % 50 -eq 0 ) { 
            try {
                $requested_users | Export-Csv -Path $($CONF_FILE_REQUESTEDTYPE + ".csv") -Encoding UTF8 -IncludeTypeInformation -Delimiter $CONF_CSV_DELIMITER -Force
            }
            catch {
                Write-Warning "$('[{0:MM/dd/yyyy} {0:HH:mm:ss}]' -f (Get-Date))Failed to create intermediate export. File potentially open elsewhere."
            }
        }
    } 
    catch {
        Write-Warning "$('[{0:MM/dd/yyyy} {0:HH:mm:ss}]' -f (Get-Date))Error while processing user: $($u.EIDUserPrincipalName)"
        Write-Warning "$('[{0:MM/dd/yyyy} {0:HH:mm:ss}]' -f (Get-Date))$Error[0]"
        break
    }
}

# Closing progress bar
Write-Progress -Activity "Processing..." -Completed

# Saving current progress
Write-Information "Exporting results of UserType $($UserType) to csv..."
$requested_users | Export-Csv -Path $($CONF_FILE_REQUESTEDTYPE + ".csv") -Encoding UTF8 -IncludeTypeInformation -Delimiter $CONF_CSV_DELIMITER -Force

# Checking if all users are processed and creating files
if ( $user_counter -lt $requested_users.Count ) {
    # Not complete, display current stats
    Write-Information "`n Processing interrupted. Processed $($user_counter) users ouf of $($requested_users.Count)."
}
else {
    # Processing completed. Creating exports. 
    Write-Information "`nProcessing completed. Creating files..."
    if ( $UserType -in "Any", "Member" -and $CONF_CREATE_ENTITY_INACTIVE_USERLISTS ) {
        CreateEntityFiles $requested_users
    }
    # Create two Excel Exports: Workdir and to $CONF_EXCEL_EXPORT_PATH
    $requested_users | Export-Excel -Path "$($CONF_FILE_REQUESTEDTYPE)_$(Get-Date -Format "yyyyMMdd").xlsx" -ClearSheet
    $OUTFILENAME = Split-Path "$($CONF_FILE_REQUESTEDTYPE)_$(Get-Date -Format "yyyyMMdd").xlsx" -leaf
    if ( $CONF_EXCEL_EXPORT_PATH -ne "" -and $CONF_EXCEL_EXPORT_PATH -ne $CONF_MY_WORKDIR ) {
        $requested_users | Export-Excel -Path "$($CONF_EXCEL_EXPORT_PATH)/$($OUTFILENAME)" -ClearSheet
    }
    # Update O365 Block Group to block users without MFA methods
    UpdateBlockedAccessGroup -AllAccounts $requested_users
    # Remove Guest User Accounts
    DeleteGuestUsers -AllAccounts $requested_users
}