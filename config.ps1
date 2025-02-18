<#
.SYNOPSIS
    Configuration file for msuserstats.ps1
#>

<###################################
    BASICS
####################################>
# Entra Tenant ID
$CONF_TENANT_ID = "12345-67890-13c-2143-32fczzzQw93"

# Include all users from Active Directory
$CONF_INCLUDE_ACTIVE_DIRECTORY = $false

# Query Exchange Online for mailbox types
$CONF_QUERY_EXCHANGE_ONLINE = $false

# Days before a user is marked as inactive without a sign-in
$CONF_INACTIVE_DAYS = 90

<###################################
    ADVANCED
####################################>
# Group for blocking access to all Microsoft online services if no MFA methods after 30 days. Group shall be used in a Conditional Access Policy to block access. 
$CONF_BLOCKED_SECURITY_GROUP = ""

# Groups with MFA enabled users - if users are not enabled for MFA by default
$CONF_MFA_ENABLED_SECURITY_GROUPS = @()

# Groups containing user with MFA exceptions
$CONF_MFA_EXCEPTION_SECURITY_GROUPS = @()

<# Domains with Mimikatz files available to check for password quality. 
The filename must begin with the following syntax: Mimikatz_<domainname>... The remaining file name is free to choose.
Recommended filename: Mimikatz_<yourdomain.company.private>_20240827.csv. 
The expected fileformat is CSV (delimiter ",") with 3 columns in the following order: 'Domain','samAccountName','PasswordLength'
The file must only contain accounts with crackable passwords. Users matching this list will be marked with Weak Password
#>
$CONF_MIMIKATZ_DOMAINS = @()
$CONF_MIMIKATZ_FILES_PATH = ""

# Create user review list for all company entities. Set $CONF_AD_DN_COUNTRY_LEVEL and/or $CONF_AD_DN_ENTITY_LEVEL to find entity from AD OU. 
$CONF_CREATE_ENTITY_INACTIVE_USERLISTS = $false
$CONF_ENTITY_FILE = ""
# Path to create Entity files
$CONF_ENTITY_OUTPUT_PATH = $CONF_MY_WORKDIR
# Discover AD admin accounts by searching the AD sAMAccountname with -match
$CONF_AD_ADMIN_SEARCH = @('admin')
# Discover EID admin accounts by searching the EID UPN with -match
$CONF_EID_ADMIN_SEARCH = @('admin')

# Discover account type by searching the AD distinguished name (DN). Contains is used to search inside DN - all lower case
$CONF_ACCOUNT_TYPE_SEARCH = @{ 
    "External User" = ",ou=externals,"
    "Service Account" = ",ou=service accounts,"
    "Internal User" = ",ou=users"
}

# Search groups where users are member of. Membership will be checked for all groups listed here.
# Groups are selected using a Contains search on DisplayName using this setting
$CONF_GROUP_MEMBERSHIP = @()
# To limit the amount of groups to search for, enter a common prefix like "sec-"
$CONF_GROUP_MEMBERSHIP_FILTER_PREFIX = ""

# Cleanup Exceptions
$CONF_FILE_CLEANUPEXCEPTIONLIST = ""

# Delete Guest users that are inactive
$CONF_DELETE_GUEST_USERS = $false

# Determine country and organization unit from AD distinguished name if you use OUs in AD
# Set 0 to disable
# Example DN: CN=Mustermann\, Max,OU=Users,OU=Sub,OU=DE,DC=europe,DC=company,DC=org
# Use the DN and count from left to right along equal signs to find the position of country. Adjust if needed to your AD OU structure.
$CONF_AD_DN_COUNTRY_LEVEL = 0
# Use the DN and count from left to right along equal signs to find the position of the OU. Adjust if needed to your AD OU structure. 
$CONF_AD_DN_ENTITY_LEVEL = 0

<###################################
    OPTIONS
####################################>
# Working directory of this script
$CONF_MY_WORKDIR = $PWD.Path

# Delimiter to use in CSV files
$CONF_CSV_DELIMITER = ";"

# Selected users temporary working file
$CONF_FILE_REQUESTEDTYPE = "$($CONF_MY_WORKDIR)/user_type_$($UserType)"

# Export final file with requested users as Excel sheet in addition to this directory. It will always be exported to $CONF_MY_WORKDIR
$CONF_EXCEL_EXPORT_PATH = ""

# Marker/Keyword for inactive user category
$CONF_INACTIVE_KEYWORD = "Inactive"

# Report file for inactive guests to be deleted
$CONF_REPORT_INACTIVE_GUEST_ACCOUNTS = "$($CONF_MY_WORKDIR)/ReportNewInactiveGuestAccounts"

# Report file for accounts to be blocked due to missing MFA methods
$CONF_REPORT_BLOCKED_ACCOUNTS = "$($CONF_MY_WORKDIR)/ReportNewBlockedAccounts"