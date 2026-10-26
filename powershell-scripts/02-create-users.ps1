<#
.SYNOPSIS
    Active Directory Organizational Unit (OU) & User Provisioning Automation.

.DESCRIPTION
    This script automates the creation of standard departmental Organizational Units (OUs)
    and bulk-provisions employee accounts from an external CSV file (users.csv).
    
    Workflow:
      1. Verifies the ActiveDirectory PowerShell module is available.
      2. Creates target Organizational Units: HR, IT, Sales, and Workstations.
      3. Validates the existence and format of the input CSV file.
      4. Iterates through each user record, checking if the account already exists.
      5. Provisions the user account with standard enterprise attributes:
         - SamAccountName (Pre-Windows 2000 login name)
         - UserPrincipalName (Modern login format: user@corp.contoso.local)
         - GivenName, Surname, DisplayName, Department, JobTitle, Email
         - Initial temporary password with 'ChangePasswordAtLogon' enforced.
      6. Outputs a comprehensive summary report of the provisioning process.

.PARAMETER CSVPath
    The path to the CSV file containing user details. Defaults to 'users.csv' in the script folder.

.PARAMETER DefaultPassword
    The temporary password assigned to newly created users. Enforces complexity requirements.

.PARAMETER DomainName
    The FQDN of the Active Directory domain (corp.contoso.local).

.EXAMPLE
    .\02-create-users.ps1
    Executes provisioning using default parameters and the local users.csv file.

.EXAMPLE
    .\02-create-users.ps1 -CSVPath "C:\Data\employees.csv" -DefaultPassword "TempPass2026!"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$CSVPath = "$PSScriptRoot\users.csv",

    [Parameter(Mandatory = $false)]
    [string]$DefaultPassword = "ContosoTemp2026!",

    [Parameter(Mandatory = $false)]
    [string]$DomainName = "corp.contoso.local"
)

# ==============================================================================
# Helper Functions: Formatting & Logging
# ==============================================================================
function Write-Header {
    param ([string]$Title)
    Write-Host "`n====================================================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor White
    Write-Host "====================================================================" -ForegroundColor Cyan
}

function Write-Step {
    param ([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Yellow
}

function Write-Success {
    param ([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-WarningMsg {
    param ([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor DarkYellow
}

function Write-Failure {
    param ([string]$Message)
    Write-Host "[-] $Message" -ForegroundColor Red
}

# ==============================================================================
# 1. Prerequisite Checks
# ==============================================================================
Write-Header "ACTIVE DIRECTORY USER PROVISIONING"

Write-Step "Checking for ActiveDirectory PowerShell module..."
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Failure "ActiveDirectory PowerShell module is not installed."
    Write-Host "  Run this script on a Domain Controller or a workstation with RSAT installed." -ForegroundColor Red
    Exit 1
}

Import-Module ActiveDirectory -ErrorAction Stop
Write-Success "ActiveDirectory module loaded."

# Resolve Domain Base Distinguished Name (e.g. DC=corp,DC=contoso,DC=local)
try {
    $domainObj = Get-ADDomain -Identity $DomainName -ErrorAction Stop
    $baseDN = $domainObj.DistinguishedName
    Write-Success "Connected to Domain: $($domainObj.DNSRoot) (Base DN: $baseDN)"
}
catch {
    Write-Failure "Could not connect to domain '$DomainName'. Ensure DNS points to DC."
    Exit 1
}

# ==============================================================================
# 2. Create Organizational Units (OUs)
# ==============================================================================
Write-Header "STEP 1: CREATING ORGANIZATIONAL UNITS (OUs)"

# Required OUs as specified: HR, IT, Sales, and Workstations
$targetOUs = @("HR", "IT", "Sales", "Workstations")

foreach ($ouName in $targetOUs) {
    $ouDN = "OU=$ouName,$baseDN"
    
    # Check if OU already exists
    $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouDN'" -ErrorAction SilentlyContinue

    if (-not $existingOU) {
        Write-Step "Creating OU: '$ouName' at '$baseDN'..."
        try {
            # ProtectedFromAccidentalDeletion prevents inadvertent deletion via ADUC console or scripts
            New-ADOrganizationalUnit -Name $ouName `
                                     -Path $baseDN `
                                     -ProtectedFromAccidentalDeletion $true `
                                     -Description "Departmental OU for $ouName department" `
                                     -ErrorAction Stop
            Write-Success "Created OU: $ouName ($ouDN)"
        }
        catch {
            Write-Failure "Failed to create OU '$ouName': $_"
        }
    } else {
        Write-Success "OU already exists: $ouName ($ouDN)"
    }
}

# ==============================================================================
# 3. Validate and Parse CSV File
# ==============================================================================
Write-Header "STEP 2: IMPORTING USER DATA FROM CSV"

Write-Step "Locating user data file at: $CSVPath"
if (-not (Test-Path -Path $CSVPath)) {
    Write-Failure "CSV file not found at path: $CSVPath"
    Exit 1
}

$userList = Import-Csv -Path $CSVPath -ErrorAction Stop
$totalRecords = $userList.Count
Write-Success "Found $totalRecords employee record(s) in CSV."

# Validate required columns
$requiredColumns = @("FirstName", "LastName", "Username", "Department", "JobTitle", "Email")
$csvColumns = ($userList | Get-Member -MemberType NoteProperty).Name

foreach ($col in $requiredColumns) {
    if ($csvColumns -notcontains $col) {
        Write-Failure "Missing required column in CSV: '$col'. Please check headers."
        Exit 1
    }
}
Write-Success "CSV column headers validated successfully."

# Prepare SecureString password for account creation
$securePassword = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force

# ==============================================================================
# 4. Provision Accounts
# ==============================================================================
Write-Header "STEP 3: PROVISIONING ACTIVE DIRECTORY USERS"

$createdCount = 0
$skippedCount = 0
$errorCount   = 0

foreach ($user in $userList) {
    $firstName   = $user.FirstName.Trim()
    $lastName    = $user.LastName.Trim()
    $username    = $user.Username.Trim().ToLower()
    $dept        = $user.Department.Trim()
    $title       = $user.JobTitle.Trim()
    $email       = $user.Email.Trim()
    $displayName = "$firstName $lastName"
    $upn         = "$username@$DomainName"

    Write-Step "Processing: $displayName ($username) - Department: $dept..."

    # Check if user already exists
    $existingUser = Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue

    if ($existingUser) {
        Write-WarningMsg "Account '$username' already exists in AD. Skipping creation."
        $skippedCount++
        continue
    }

    # Determine Target OU based on Department
    # If the department matches one of our created OUs, place it there; otherwise default to BaseDN
    if ($targetOUs -contains $dept) {
        $targetOU = "OU=$dept,$baseDN"
    } else {
        Write-WarningMsg "Department '$dept' does not match defined OUs. Defaulting to CN=Users,$baseDN."
        $targetOU = "CN=Users,$baseDN"
    }

    try {
        # Create AD User
        New-ADUser `
            -Name $displayName `
            -GivenName $firstName `
            -Surname $lastName `
            -DisplayName $displayName `
            -SamAccountName $username `
            -UserPrincipalName $upn `
            -EmailAddress $email `
            -Department $dept `
            -Title $title `
            -Path $targetOU `
            -AccountPassword $securePassword `
            -Enabled $true `
            -ChangePasswordAtLogon $true `
            -ErrorAction Stop

        Write-Success "Created user '$username' in '$targetOU'."
        $createdCount++
    }
    catch {
        Write-Failure "Failed to create user '$username': $_"
        $errorCount++
    }
}

# ==============================================================================
# 5. Provisioning Summary & Verification
# ==============================================================================
Write-Header "PROVISIONING SUMMARY REPORT"

Write-Host "  Total CSV Records Parsed : $totalRecords" -ForegroundColor White
Write-Host "  Accounts Created         : $createdCount" -ForegroundColor Green
Write-Host "  Accounts Skipped (Exists): $skippedCount" -ForegroundColor Yellow
Write-Host "  Errors / Failures        : $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Green" })
Write-Host "  Temporary Initial Password: $DefaultPassword" -ForegroundColor Cyan
Write-Host "  Policy: Enforced 'User must change password at next logon'" -ForegroundColor DarkCyan

Write-Header "VERIFYING CREATED USERS BY OU"
foreach ($ou in @("HR", "IT", "Sales")) {
    $ouDN = "OU=$ou,$baseDN"
    $members = Get-ADUser -Filter * -SearchBase $ouDN -Properties Title, EmailAddress | Select-Object Name, SamAccountName, Title, EmailAddress
    
    Write-Host "`n-- OU: $ou ($($members.Count) User(s)) --" -ForegroundColor Yellow
    $members | Format-Table Name, SamAccountName, Title, EmailAddress -AutoSize | Out-String | Write-Host
}

Write-Success "User import script execution finished successfully!"
