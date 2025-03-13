# msuserstats

Managing a consistent **user account base across a hybrid Microsoft environment** with Entra ID and Active Directory can be challenging.
Member-, guest-, service- and admin-accounts may have different requirements when it comes to review. 

IT-Security policies require **frequent reviews and deactivation of inactive accounts.** Strong MFA methods are required to protect users
identities and accounts shall be disabled if they don't enroll to MFA after some time. Leaving accounts in not enrolled state creates security risks.  

msuserstats has been developed for some time to **support user account reviews and MFA enforcement.** It is a comprehensive tool to manage user accounts in Microsoft environments of typical mid-size companies written in Powershell. By intention it is all in one Powershell file - except the configuration. 

The script generates multiple **output files in CSV and XLSX format** for sharing and review inside organizations.

Initially the project started to get a unified view on user accounts across Entra ID and ActiveDirectory, without duplicates (**Entra ID and AD accounts get mapped**) and identify inactive accounts for deletion. 

Later it has been extended with several useful features to manage accounts especially in the light of IT-Security. 

## Features

**Basics**:
- Unified Excel sheet of all user accounts including member and guest accounts with detailed information on every user
- Support of Entra ID and Active Directory where accounts get automatically mapped avoiding duplicates
- Active Directory support for multiple domains in a forest which get fully or partially synced to Entra ID
- Determination of last sign-in on both Entra ID and Active Directory. Publishing of the last recent sign-in date across both. 
- Existing MFA methods are reported for all Entra ID users including support for Hardware Tokens (OATH)
- The mailbox type is being retrieved for every user from Exchange Online to help categorize users between UserMailbox, SharedMailbox, RoomMailbox, ...
- Support of Powershell 7 and multi platform. Except Active Directory User export which requires a x64 Windows with RSAT tools installed

**Advanced**:
- Users can be blocked to access O365 services if no MFA methods have been configured latest 30 days after account creation
- Special Entra ID exception groups can be used for MFA exceptions such as Service Accounts
- Creation of Excel sheets for reviewing and feedback processes. Legal sub entities can be configured and determined by an existing AD OU structure.
- An exception list can be applied for accounts not to be marked as inactive, eg. for Service Accounts, Shared Mailboxes, Long Leavers, .... Exceptions can be managed with comments and always require a lifetime after which another review is required. 
- Guest users can be automatically deleted from Entra ID for guest user governance and cleanup
- Classify user account types by utilizing keywords to search in distinguish names (DN) for Active Directory users. This can be used if your organization used OUs containing account types like Service Accounts, Users, ... in Active Directory
- Structure accounts by Country and Entity if your organization used AD OUs to setup country and entity structures
- If you frequently pentest your organization (eg. with Mimikatz) for weak passwords you can include output files to mark user accounts with weak passwords (known to be crackable)
- Depending on the size of your user base and the connection speed to your AD environment the script can easily take hours up to a day to complete. If it breaks, a recent state is saved frequently and can be continued. 

## Get started

Clone the repository and change config.ps1 to your needs. The documentation will be updated with more information on the
advanced settings soon. 

### Install the following Powershell modules:

**Microsoft Graph:**

    Install-Module Microsoft.Graph.Users

    Install-Module Microsoft.Graph.Identity.SignIns

    Install-Module Microsoft.Graph.Groups

**Exchange Online:** 

    Install-Module ExchangeOnlineManagement

**ImportExcel - used to export to XLSX:** 

    Install-Module ImportExcel

## Run the script

#### For Entra ID only: run on any platform with your configured settings in config.ps1:

    ./msuserstats.ps1  #(defaults to all users)

    ./msuserstats.ps1 -UserType Guest (for Guest users only)

    ./msuserstats.ps1 -UserType Member (for Member users only)

#### For Entra ID and Active Directory: run on a x64 Windows with RSAT tools installed and change $CONF_INCLUDE_ACTIVE_DIRECTORY to $true

    ./msuserstats.ps1  #(defaults to all users)

    ./msuserstats.ps1 -UserType Guest (for Guest users only)

    ./msuserstats.ps1 -UserType Member (for Member users only)

#### For Entra ID and Active Directory in a two step process for non-Windows platforms: change $CONF_INCLUDE_ACTIVE_DIRECTORY to $true

1. Export your Active Directory Users on x64 Windows with RSAT Tools installed
    
        ./msuserstats.ps1 -ExportDomainUsers $true

    Users will be exported to a CSV file.

2. Complete on any other non-Windows system:
    
        ./msuserstats.ps1

    AD Users from step 1 will imported

## Configuration Basics

Change the configuration file config.ps1 to your individual requirements. 

### Active Directory

You can include Active Directory which allows you to list your AD accounts in addition to your Entra ID accounts. To avoid duplicates the Entra ID users are mapped to their corresponding AD account. Finally the export contains your hybrid synced users, the AD only users and Entra ID only users. 
The script will automatically determine your domains from your AD forest. It is recommended using a read-only user for authentication. To query the AD a x64 Windows with RSAT tools installed is required. 

Example: $CONF_INCLUDE_ACTIVE_DIRECTORY = $true

### Inactivity timeframe

You can configure the days after which an account is marked as inactive. 

Example: $CONF_INACTIVE_DAYS = 90

### Exchange Online

Exchange Online can be queried to get all mailboxes. The script uses the mailbox type and populates this. That information can help to identify accounts that are not directly used by interactive users, such as SharedMailbox or SchedulingMailbox.

Example: $CONF_QUERY_EXCHANGE_ONLINE = $true

## Advanced Configuration

### Blocking access for users not enrolled to MFA

After enabling MFA, users are required to enroll and configure authentication methods. Unless they have not completed this task, the account is still unprotected and can also be enrolled from a potential attacker. Therefore it is recommended to block users 30 days after creation if they don't enroll. 

Set this configuration to a group ID which is being used in your conditional access policies to block access to O365 services and Entra ID. 

Example: $CONF_BLOCKED_SECURITY_GROUP = "12345-12456-12355-12453445"

Related: MFA Exceptions

### MFA Exceptions

If you have user accounts which have an exception for MFA, you can configure groups that hold these exceptional accounts. The script queries these groups and checks if a user has an MFA exception. This can be used for reporting but also with $CONF_BLOCKED_SECURITY_GROUP these users are not getting blocked without MFA methods. 

Example: $CONF_MFA_EXCEPTION_SECURITY_GROUPS = @("12345-12456-12355-12453445","12345-12456-12355-124534667")

### MFA Enabled 

Enabling MFA per default is strongly recommended. However, sometimes this is not suitable, eg. during a phased rollout of MFA. In these situations you can report on users which are enabled for MFA if you add these groups. 

Example: $CONF_MFA_ENABLED_SECURITY_GROUPS = @("12345-12456-12355-9875445","12345-12456-12355-789378")

### Custom Group Memberships

Custom group memberships can be reported as well. This is especially useful if you have groups for licensing purposes, special applications or permissions which you want to report for every user.

An example usecase can be: Check for membership in all groups that contain License in DisplayName and prefilter all groups only to groups that start with sec-. The prefiltering is just for performance reasons to limit the count of groups. 

Example: 
$CONF_GROUP_MEMBERSHIP = @("License")
$CONF_GROUP_MEMBERSHIP_FILTER_PREFIX = "SEC-"

### Inactive Cleanup Exceptions

Inactive users are typically candidates for deletion. In many cases inactivity can also result from special accounts such as SharedMailboxes with delegation, long leavers or other service accounts. To add reporting on such accounts you can maintain a list of cleanup exceptions and mark them as inactive exception. Such an exception requires an email address, UPN or ID, a requestor, expiry date and comment. That ensures that also these exceptions are being reviewed again after some time. 

The email address/upn is used with an -contains condition on UPN or email address. An ID is compared with users ID. 

Create a CSV file and add the following colums. Otherwise download use the CleanupException.csv example file in this repository. 

    Enabled; email address/upn/ID; Requestor; Valid until (YYYYMMDD); Comments

Configure the exceptions file to be used. After the Valid until date is reached, the exception is no longer applied. 

Semicolon is used as delimiter for CSV files. If you want to use something else like comma, change $CONF_CSV_DELIMITER accordingly.

Example: $CONF_FILE_CLEANUPEXCEPTIONLIST = "CleanupExceptions.csv"