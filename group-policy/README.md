# Group Policy Objects (GPO) Design & Implementation

This directory documents the Enterprise Group Policy architecture deployed within the `corp.contoso.local` Active Directory domain on Domain Controller `DC01`.

---

## 1. GPO Deployment Structure

The organizational Group Policy hierarchy follows the principle of least privilege, standardized baseline enforcement, and modular inheritance:

```
corp.contoso.local (Domain Root)
│
├── [GPO] Default Domain Policy (Domain Password, Kerberos & Account Lockout)
│
├── [GPO] IT Security Baseline (Workstation Hardening, Inactivity Lock, Elevation Prompts)
│
├── OU=IT Department
│   └── [GPO] GPO-IT-Admin-Tools (RSAT, Remote Administration, Elevated Event Auditing)
│
├── OU=HR
│   └── [GPO] GPO-HR-Drive-Mappings (Maps H: Personal Home, S: HR-Confidential)
│
├── OU=Sales
│   └── [GPO] GPO-Sales-Drive-Mappings (Maps H: Personal Home, S: Sales-Shared)
│
└── OU=Workstations
    ├── [GPO] GPO-Workstation-Security-Baseline (Screen Lock, Inactivity, UAC)
    └── [GPO] GPO-Network-Firewall-Rules (Allow ICMP, Remote Management)
```

![GPMC IT Security Baseline](../screenshots/dc01-gpo-it-security-baseline.png)
*Figure 1: Group Policy Management Console on `DC01` showing `IT Security Baseline` GPO linked to domain `corp.contoso.local`.*

---

## 2. Implemented Policies & Baselines

### Policy 1: Default Domain Password & Lockout Policy
Applied at domain root (`corp.contoso.local`) to safeguard credentials across all domain accounts.

| Setting | Value | Operational Rationale |
| :--- | :--- | :--- |
| **Minimum Password Length** | 12 characters | Mitigates brute-force attacks |
| **Password Complexity** | Enabled (Uppercase, Lowercase, Number, Symbol) | Enforces character entropy |
| **Max Password Age** | 90 days | Industry credential rotation standard |
| **Password History** | 24 passwords remembered | Prevents password cycling |
| **Account Lockout Threshold** | 5 invalid logon attempts | Mitigates automated brute-force / password spraying |
| **Account Lockout Duration** | 30 minutes | Auto-reset window for help desk relief |
| **Reset Lockout Counter After** | 30 minutes | Rolling failure counter window |

---

### Policy 2: IT Security Baseline GPO
Applied at the domain level to enforce consistent baseline workstation security across domain-joined assets:

* **Inactivity Screen Lockout**:
  * *Policy Path*: `User Configuration > Administrative Templates > Control Panel > Personalization`
  * *Screen Saver timeout*: `900 seconds` (15 minutes).
  * *Password protect the screen saver*: `Enabled`.
* **User Account Control (UAC) Hardening**:
  * *Policy Path*: `Computer Configuration > Windows Settings > Security Settings > Local Policies > Security Options`
  * *Behavior of the elevation prompt for standard users*: `Prompt for credentials`.
* **Removable Storage Device Access (DLP)**:
  * *Policy Path*: `Computer Configuration > Administrative Templates > System > Removable Storage Access`
  * *Removable Disks: Deny write access*: `Enabled`.

---

### Policy 3: Departmental Drive Mapping via Group Policy Preferences (GPP)
Applied to departmental OUs with Item-Level Targeting (ILT) based on Security Group membership:

| Drive Letter | Share Path | Target OU / Group | Option |
| :--- | :--- | :--- | :--- |
| `H:` | `\\DC01\Home$\%USERNAME%` | Domain Users | `Update` (Auto-creates personal user folder) |
| `S:` | `\\DC01\Shares\HR-Data` | `OU=HR` (`SG-HR-Staff`) | `Update` |
| `S:` | `\\DC01\Shares\Sales-Data` | `OU=Sales` (`SG-Sales-Staff`) | `Update` |
| `S:` | `\\DC01\Shares\IT-Repository` | `OU=IT Department` (`SG-IT-Staff`) | `Update` |

---

## 3. Client Verification & Policy Refresh

To force and verify Group Policy application on client workstations such as `CLIENT01`:

```powershell
gpupdate /force
```

![CLIENT01 GPUpdate](../screenshots/client01-gpupdate-force.png)
*Figure 2: Group Policy update execution (`gpupdate /force`) on `CLIENT01` verifying policy processing.*

---

## 4. PowerShell GPO Automation Scripts

To automate the creation and linking of baseline policies via PowerShell on `DC01`:

```powershell
# 1. Create IT Security Baseline GPO
$gpoName = "IT Security Baseline"
New-GPO -Name $gpoName -Comment "Enforces screen saver lockout and workstation security baselines"

# 2. Link GPO to Domain Root
$domainDN = "DC=corp,DC=contoso,DC=local"
New-GPLink -Name $gpoName -Target $domainDN -LinkOrder 1

# 3. Configure Screen Saver Timeout (900 seconds / 15 minutes) via Registry Policy
Set-GPRegistryValue -Name $gpoName `
    -Key "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -ValueName "ScreenSaveTimeOut" `
    -Type String `
    -Value "900"

Set-GPRegistryValue -Name $gpoName `
    -Key "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -ValueName "ScreenSaverIsSecure" `
    -Type String `
    -Value "1"

# 4. Force immediate GPO update
gpupdate /force
```
