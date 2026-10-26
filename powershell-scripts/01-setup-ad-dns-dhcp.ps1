<#
.SYNOPSIS
    Automated Setup Script for Active Directory Domain Services (AD DS), DNS, and DHCP.

.DESCRIPTION
    This script automates the configuration of a Windows Server 2019/2022 into a 
    Primary Domain Controller for the domain 'corp.contoso.local'.
    
    The script operates in two modular phases:
      - Phase 1 (Pre-Reboot):
          1. Validates Administrator privileges.
          2. Configures a static IP address (192.168.10.10/24), Gateway, and DNS.
          3. Installs Windows Server Roles: AD DS, DNS, DHCP, and RSAT Management Tools.
          4. Promotes server to a Domain Controller (creates new AD Forest: corp.contoso.local).
          5. Initiates automated reboot.
      - Phase 2 (Post-Reboot):
          1. Detects Domain Controller status.
          2. Creates and configures DHCP Security Groups.
          3. Authorizes the DHCP server in Active Directory (prevents rogue DHCP warning).
          4. Creates IPv4 DHCP Scope (192.168.10.50 - 192.168.10.150).
          5. Configures DHCP Scope Options (Router 003, DNS 006, Domain Name 015).
          6. Activates scope and validates service operational status.

.NOTES
    Lab Domain   : corp.contoso.local
    NetBIOS Name : CORP
    Server IP    : 192.168.10.10 / 24
    Gateway      : 192.168.10.1
    DNS          : 127.0.0.1 (Loopback for local DNS resolver)
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Auto", "Phase1", "Phase2")]
    [string]$ExecutionMode = "Auto",

    [Parameter(Mandatory = $false)]
    [string]$DomainName = "corp.contoso.local",

    [Parameter(Mandatory = $false)]
    [string]$DomainNetbiosName = "CORP",

    [Parameter(Mandatory = $false)]
    [string]$StaticIP = "192.168.10.10",

    [Parameter(Mandatory = $false)]
    [int]$SubnetPrefixLength = 24, # 255.255.255.0

    [Parameter(Mandatory = $false)]
    [string]$DefaultGateway = "192.168.10.1",

    [Parameter(Mandatory = $false)]
    [string]$DHCPScopeID = "192.168.10.0",

    [Parameter(Mandatory = $false)]
    [string]$DHCPScopeName = "Corporate-LAN",

    [Parameter(Mandatory = $false)]
    [string]$DHCPStartRange = "192.168.10.50",

    [Parameter(Mandatory = $false)]
    [string]$DHCPEndRange = "192.168.10.150",

    [Parameter(Mandatory = $false)]
    [string]$DHCPSubnetMask = "255.255.255.0"
)

# ==============================================================================
# Helper Function: Banner & Logging
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

function Write-Failure {
    param ([string]$Message)
    Write-Host "[-] $Message" -ForegroundColor Red
}

# ==============================================================================
# 0. Administrator Privilege Check
# ==============================================================================
$currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Failure "This script must be executed in an elevated PowerShell session (Run as Administrator)."
    Exit 1
}

# Determine if machine is already a Domain Controller
# DomainRole 4 = Backup Domain Controller, 5 = Primary Domain Controller
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$isDomainController = ($computerSystem.DomainRole -ge 4)

if ($ExecutionMode -eq "Auto") {
    if (-not $isDomainController) {
        $ExecutionMode = "Phase1"
    } else {
        $ExecutionMode = "Phase2"
    }
}

# ==============================================================================
# PHASE 1: Network Configuration, Role Installation & AD DS Forest Creation
# ==============================================================================
if ($ExecutionMode -eq "Phase1") {
    Write-Header "PHASE 1: Static IP Configuration & AD Forest Deployment"

    # Step 1.1: Identify Primary Network Adapter
    Write-Step "Detecting active network adapter..."
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false } | Select-Object -First 1
    if (-not $adapter) {
        # Fallback to any active adapter (for virtual lab environments)
        $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    }

    if (-not $adapter) {
        Write-Failure "No active network adapter found! Connect a virtual network adapter and retry."
        Exit 1
    }
    Write-Success "Using Network Adapter: $($adapter.Name) ($($adapter.InterfaceDescription))"

    # Step 1.2: Apply Static IP Configuration
    Write-Step "Configuring Static IP: $StaticIP/$SubnetPrefixLength with Gateway: $DefaultGateway..."
    try {
        # Remove existing IP addresses and default gateway if present
        Remove-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue

        # Assign new static IP address
        New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex `
                         -IPAddress $StaticIP `
                         -PrefixLength $SubnetPrefixLength `
                         -DefaultGateway $DefaultGateway `
                         -ErrorAction Stop | Out-Null

        # Set Primary DNS to loopback (127.0.0.1) as this server will be its own DNS server
        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex `
                                   -ServerAddresses @("127.0.0.1") `
                                   -ErrorAction Stop

        Write-Success "Network adapter successfully configured with static IP $StaticIP."
    }
    catch {
        Write-Failure "Failed to configure static IP address: $_"
        Exit 1
    }

    # Step 1.3: Install Windows Server Roles and Features
    Write-Step "Installing AD DS, DNS, and DHCP roles along with RSAT management tools..."
    $features = @(
        "AD-Domain-Services",
        "DNS",
        "DHCP",
        "RSAT-ADDS",
        "RSAT-DHCP",
        "RSAT-DNS-Server"
    )

    try {
        Install-WindowsFeature -Name $features -IncludeManagementTools -ErrorAction Stop | Out-Null
        Write-Success "Windows Server features successfully installed."
    }
    catch {
        Write-Failure "Error installing Windows features: $_"
        Exit 1
    }

    # Step 1.4: Install Active Directory Forest
    Write-Step "Preparing to promote server to Domain Controller for '$DomainName'..."
    Write-Host "  NOTE: In a production environment, use a secure password vault." -ForegroundColor DarkGray

    # Set Directory Services Restore Mode (DSRM) Safe Mode Administrator Password
    $dsrmPassword = ConvertTo-SecureString "ContosoLab2026!Safe" -AsPlainText -Force

    Write-Step "Executing Install-ADDSForest. The server will automatically restart upon completion..."
    
    try {
        Install-ADDSForest `
            -DomainName $DomainName `
            -DomainNetbiosName $DomainNetbiosName `
            -InstallDns:$true `
            -SafeModeAdministratorPassword $dsrmPassword `
            -Force:$true
        
        Write-Success "Forest creation command executed. Server will restart shortly."
        Write-Host "After reboot, log in as CORP\Administrator and re-run this script to execute Phase 2 (DHCP configuration)." -ForegroundColor Cyan
    }
    catch {
        Write-Failure "Failed to install AD DS Forest: $_"
        Exit 1
    }
}

# ==============================================================================
# PHASE 2: Post-Reboot DHCP Configuration & Verification
# ==============================================================================
if ($ExecutionMode -eq "Phase2") {
    Write-Header "PHASE 2: DHCP Authorization, Scope Setup & Validation"

    # Step 2.1: Verify AD DS Status
    Write-Step "Verifying Active Directory Domain Services status..."
    $adService = Get-Service -Name "NTDS" -ErrorAction SilentlyContinue
    if ($adService.Status -eq "Running") {
        Write-Success "AD DS service (NTDS) is active and running."
    } else {
        Write-Failure "AD DS service is not running. Ensure this machine is a promoted Domain Controller."
        Exit 1
    }

    # Step 2.2: Add DHCP Security Groups
    Write-Step "Adding DHCP server security groups (DHCP Administrators & DHCP Users)..."
    try {
        Add-DhcpServerSecurityGroup -Confirm:$false -ErrorAction SilentlyContinue
        Restart-Service -Name "DHCPServer" -Force -ErrorAction SilentlyContinue
        Write-Success "DHCP Security Groups created and service restarted."
    }
    catch {
        Write-Failure "Warning during DHCP Security Group creation: $_"
    }

    # Step 2.3: Authorize DHCP in Active Directory
    Write-Step "Authorizing DHCP Server in Active Directory domain '$DomainName'..."
    try {
        $fqdn = "$($env:COMPUTERNAME).$DomainName"
        $authorizedServers = Get-DhcpServerInDC -ErrorAction SilentlyContinue
        $isAuthorized = $authorizedServers | Where-Object { $_.IPAddress -eq $StaticIP }

        if (-not $isAuthorized) {
            Add-DhcpServerInDC -DnsName $fqdn -IPAddress $StaticIP -ErrorAction Stop
            Write-Success "DHCP server '$fqdn' ($StaticIP) authorized in Active Directory."
        } else {
            Write-Success "DHCP server '$fqdn' is already authorized in Active Directory."
        }
    }
    catch {
        Write-Failure "Failed to authorize DHCP server in AD: $_"
    }

    # Step 2.4: Create IPv4 DHCP Scope
    Write-Step "Checking for DHCP Scope '$DHCPScopeID'..."
    $existingScope = Get-DhcpServerv4Scope -ScopeId $DHCPScopeID -ErrorAction SilentlyContinue

    if (-not $existingScope) {
        Write-Step "Creating new IPv4 DHCP Scope: $DHCPScopeName ($DHCPScopeID)..."
        try {
            Add-DhcpServerv4Scope -Name $DHCPScopeName `
                                  -StartRange $DHCPStartRange `
                                  -EndRange $DHCPEndRange `
                                  -SubnetMask $DHCPSubnetMask `
                                  -State Active `
                                  -LeaseDuration (New-TimeSpan -Days 8) `
                                  -ErrorAction Stop
            Write-Success "DHCP Scope '$DHCPScopeName' created successfully."
        }
        catch {
            Write-Failure "Failed to create DHCP Scope: $_"
            Exit 1
        }
    } else {
        Write-Success "DHCP Scope '$DHCPScopeName' ($DHCPScopeID) already exists."
    }

    # Step 2.5: Configure DHCP Scope Options
    # Option 003: Router (Default Gateway)
    # Option 006: DNS Servers
    # Option 015: Domain Name
    Write-Step "Configuring DHCP Scope Options (Router, DNS, Domain Name)..."
    try {
        # Option 003 - Router
        Set-DhcpServerv4OptionValue -ScopeId $DHCPScopeID `
                                    -OptionId 3 `
                                    -Value $DefaultGateway `
                                    -ErrorAction Stop

        # Option 006 - DNS Server
        Set-DhcpServerv4OptionValue -ScopeId $DHCPScopeID `
                                    -OptionId 6 `
                                    -Value $StaticIP `
                                    -ErrorAction Stop

        # Option 015 - Domain Name
        Set-DhcpServerv4OptionValue -ScopeId $DHCPScopeID `
                                    -OptionId 15 `
                                    -Value $DomainName `
                                    -ErrorAction Stop

        Write-Success "DHCP Scope options configured (Router: $DefaultGateway, DNS: $StaticIP, Domain: $DomainName)."
    }
    catch {
        Write-Failure "Failed to configure DHCP Scope Options: $_"
    }

    # Step 2.6: Restart DHCP Service & Final Verification
    Write-Step "Restarting DHCP Server service to apply changes..."
    Restart-Service -Name "DHCPServer" -Force

    Write-Header "DEPLOYMENT VERIFICATION SUMMARY"
    
    # 1. Check AD Domain
    $domainInfo = Get-ADDomain -Identity $DomainName -ErrorAction SilentlyContinue
    if ($domainInfo) {
        Write-Host "  [OK] Domain FQDN       : $($domainInfo.DNSRoot)" -ForegroundColor Green
        Write-Host "  [OK] Domain NetBIOS    : $($domainInfo.NetBIOSName)" -ForegroundColor Green
        Write-Host "  [OK] Domain Mode       : $($domainInfo.DomainMode)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Unable to query AD Domain." -ForegroundColor Red
    }

    # 2. Check DNS Service
    $dnsService = Get-Service -Name "DNS" -ErrorAction SilentlyContinue
    if ($dnsService.Status -eq "Running") {
        Write-Host "  [OK] DNS Server Status : Running" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] DNS Server Status: $($dnsService.Status)" -ForegroundColor Red
    }

    # 3. Check DHCP Scope
    $scopeSummary = Get-DhcpServerv4Scope -ScopeId $DHCPScopeID -ErrorAction SilentlyContinue
    if ($scopeSummary) {
        Write-Host "  [OK] DHCP Scope Name   : $($scopeSummary.Name)" -ForegroundColor Green
        Write-Host "  [OK] DHCP Scope Range  : $($scopeSummary.StartRange) - $($scopeSummary.EndRange)" -ForegroundColor Green
        Write-Host "  [OK] DHCP Scope State  : $($scopeSummary.State)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] DHCP Scope not detected." -ForegroundColor Red
    }

    Write-Host "`nSetup complete! The Domain Controller is fully operational." -ForegroundColor Cyan
    Write-Host "Proceed to '02-create-users.ps1' to create OUs and provision user accounts." -ForegroundColor White
}
