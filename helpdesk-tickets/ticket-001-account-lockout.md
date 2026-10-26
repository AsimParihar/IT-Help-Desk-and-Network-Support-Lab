# Incident Report: HD-2026-0104 - Frequent Account Lockout on Enterprise User

---

## 1. Ticket Overview

| Field | Value |
| :--- | :--- |
| **Ticket ID** | `HD-2026-0104` |
| **Status** | `Closed / Resolved` |
| **Priority** | `High (P2)` |
| **Category** | Identity & Access Management / Active Directory |
| **Requester** | Amanda Miller (`amiller@corp.contoso.local`) |
| **Department** | Sales (Enterprise Account Executive) |
| **Workstation** | `WS-SALES-02` (IP: `192.168.10.112`) |
| **Assigned Technician** | Alex Mercer (Help Desk Specialist) |
| **Created** | 2026-10-20 09:15 EST |
| **Resolved** | 2026-10-20 09:48 EST |

---

## 2. Issue Description

> **User Statement**:  
> *"Good morning, I have been locked out of my computer three times this morning. Every time I ask a colleague or step away, my Windows login says 'The referenced account is currently locked out and may not be logged on to'. I only changed my password yesterday."*

---

## 3. Initial Assessment & Triage

1. Checked Active Directory account status for `amiller`:
   ```powershell
   Get-ADUser -Identity "amiller" -Properties LockedOut, BadLogonCount, LastBadPasswordAttempt | 
       Select-Object SamAccountName, LockedOut, BadLogonCount, LastBadPasswordAttempt
   ```
   **Output:**
   ```text
   SamAccountName LockedOut BadLogonCount LastBadPasswordAttempt
   -------------- --------- ------------- -----------------------
   amiller             True             5 10/20/2026 9:12:44 AM
   ```
2. User account was confirmed locked due to hitting the 5-attempt threshold enforced by Default Domain GPO.
3. Unlocking the account immediately resulted in another lockout within 3 minutes, indicating an automated background process or device with cached stale credentials.

---

## 4. Root Cause Analysis (RCA)

Technician inspected Security Event Logs on Primary Domain Controller (`DC01`):

```powershell
# Filter for Event ID 4740 (A user account was locked out)
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4740} -MaxEvents 5 | 
    Select-Object TimeCreated, Message | Format-List
```

**Log Details**:
* **Event ID**: `4740`
* **Target Account Name**: `amiller`
* **Caller Computer Name**: `AMILLER-IPHONE`

**Finding**:
The user recently updated her corporate password on workstation `WS-SALES-02` per the 90-day policy. However, her company-issued mobile smartphone (`AMILLER-IPHONE`) connected to corporate Wi-Fi was still running Microsoft Outlook Mobile using the previous expired credentials. The phone repeatedly attempted Exchange ActiveSync authentication every 60 seconds, triggering repeated bad password attempts and triggering the lockout policy.

---

## 5. Remediation & Resolution Steps

1. **Step 1 - Isolate Credential Source**:
   Instructed user to temporarily toggle Airplane Mode ON on her iPhone to halt automated authentication attempts.

2. **Step 2 - Unlock Active Directory Account**:
   Executed PowerShell command on `DC01`:
   ```powershell
   Unlock-ADAccount -Identity "amiller"
   Set-ADUser -Identity "amiller" -PasswordNeverExpires $false
   ```
   Verified account unlock status:
   ```powershell
   (Get-ADUser -Identity "amiller" -Properties LockedOut).LockedOut
   # Returned: False
   ```

3. **Step 3 - Update Mobile Credentials**:
   * Re-enabled mobile connectivity.
   * Navigated to `Settings > Mail > Accounts > Contoso Corporate Exchange` on iOS device.
   * Entered current corporate password and successfully authenticated with Microsoft Entra / Exchange ActiveSync.

4. **Step 4 - Verify Workstation Logon**:
   User successfully authenticated to `WS-SALES-02` without lockout.

---

## 6. Verification & Closure

* Monitored the user's `BadLogonCount` in Active Directory for 20 minutes; value remained at `0`.
* User confirmed full access to workstation, shared drives, and mobile email.
* Follow-up ticket closure notice sent to user.

```
Ticket Status Updated: RESOLVED
Root Cause: Stale cached password on mobile device causing Event 4740 lockout loop.
KB Article Reference: KB-IAM-003: "Resolving Stale Mobile ActiveSync Account Lockouts"
```
