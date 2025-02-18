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

**ImportExcel:** 

    Install-Module ImportExcel

**Exchange Online:** 

    Install-Module ExchangeOnlineManagement

**Microsoft Graph:**

    Install-Module Microsoft.Graph.Users

    Install-Module Microsoft.Graph.Identity.SignIns

    Install-Module Microsoft.Graph.Groups

### Run the script

Change $CONF_TENANT_ID to your tenant ID.

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

Change the configuration to your needs

### $CONF_TENANT_ID

Set $CONF_TENANT_ID to your Entra tenant ID

Example: $CONF_TENANT_ID = "12345-67890-13c-2143-32fczzzQw93"

### $CONF_INCLUDE_ACTIVE_DIRECTORY

Set $CONF_INCLUDE_ACTIVE_DIRECTORY to $true to include your Active Directory. The script will automatically determine your
domains from your AD forest. It is recommended using a read-only user for authentication. 

Set $CONF_INCLUDE_ACTIVE_DIRECTORY to $false to start with all your Entra ID users only. 

Example: $CONF_INCLUDE_ACTIVE_DIRECTORY = $false

### $CONF_INACTIVE_DAYS

Set $CONF_INACTIVE_DAYS to the days after which an account is marked as inactive with a sign-in

Example: $CONF_INACTIVE_DAYS = 90

... to be continued ...

