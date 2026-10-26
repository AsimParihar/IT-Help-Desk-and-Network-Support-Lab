# Incident Report: HD-2026-0118 - Shared Folder Permission Denied (NTFS / Security Group)

---

## 1. Ticket Overview

| Field | Value |
| :--- | :--- |
| **Ticket ID** | `HD-2026-0118` |
| **Status** | `Closed / Resolved` |
| **Priority** | `Medium (P3)` |
| **Category** | File Services / NTFS Permissions & Active Directory Groups |
| **Requester** | Carlos Gomez (`cgomez@corp.contoso.local`) |
| **Department** | HR (Compensation & Benefits Analyst) |
| **Workstation** | `WS-HR-04` (IP: `192.168.10.104`) |
| **Assigned Technician** | Alex Mercer (Help Desk Specialist) |
| **Created** | 2026-10-22 11:05 EST |
| **Resolved** | 2026-10-22 11:35 EST |

---

## 2. Issue Description

> **User Statement**:  
> *"Hello IT Support, I recently transferred to the Compensation & Benefits team under HR. I need to review this quarter's payroll spreadsheets, but when I navigate to `\\DC01\HR-Shares\Confidential-Payroll`, Windows displays 'Network Error: Windows cannot access \\DC01\HR-Shares\Confidential-Payroll. You do not have permission to access'."*

---

## 3. Initial Assessment & Triage

1. Verified network connectivity between workstation and `DC01`:
   ```powershell
   Test-NetConnection -ComputerName "192.168.10.10" -Port 445
   # Result: TcpTestSucceeded : True (SMB port 445 is open and responsive)
   ```
2. Checked user's current Active Directory Security Group memberships:
   ```powershell
   Get-ADPrincipalGroupMembership -Identity "cgomez" | Select-Object Name
   ```
   **Output:**
   ```text
   Name
   ----
   Domain Users
   SG-HR-General
   ```
3. Reviewed share and NTFS Access Control Lists (ACLs) on `DC01`:
   * **Share Permission (`HR-Shares`)**: `Authenticated Users` -> Change & Read.
   * **Folder NTFS Permission (`C:\Shares\HR-Shares\Confidential-Payroll`)**:
     * `SYSTEM` -> Full Control
     * `Domain Admins` -> Full Control
     * `SG-HR-Payroll-RW` -> Modify, Read & Execute, List, Read, Write
     * `Inheritance` -> Disabled

---

## 4. Root Cause Analysis (RCA)

* **Access Model**: Contoso Corporation adheres to the **AGDLP** (Accounts -> Global Groups -> Domain Local Groups -> Permissions) model for role-based access control.
* **Finding**: During the onboarding and transfer process, user `cgomez` was assigned only the broad `SG-HR-General` group. Access to the subfolder `Confidential-Payroll` requires membership in the specialized security group `SG-HR-Payroll-RW`.
* Because NTFS permissions take precedence when more restrictive than share permissions, lack of membership in `SG-HR-Payroll-RW` resulted in an explicit `Access Denied` error.

---

## 5. Remediation & Resolution Steps

1. **Step 1 - Obtain Manager Approval**:
   Verified departmental authorization with Elena Rodriguez (HR Director) via internal ticketing approval workflow.

2. **Step 2 - Assign Security Group Membership**:
   Added user `cgomez` to `SG-HR-Payroll-RW` via PowerShell:
   ```powershell
   Add-ADGroupMember -Identity "SG-HR-Payroll-RW" -Members "cgomez"
   
   # Verification
   Get-ADGroupMember -Identity "SG-HR-Payroll-RW" | Select-Object SamAccountName
   ```

3. **Step 3 - Refresh Kerberos Ticket (Token Update)**:
   Active Directory group changes are encoded into the user's Kerberos Ticket Granting Service (TGS) token during logon. To avoid forcing a full system reboot or logoff:
   On client workstation `WS-HR-04`, ran the following command in Command Prompt:
   ```cmd
   klist purge
   ```
   *Purging cached Kerberos tickets forced Windows to request a fresh token containing the new `SG-HR-Payroll-RW` SID from `DC01`.*

4. **Step 4 - Validate Effective Access**:
   Tested access directly by browsing to `\\DC01\HR-Shares\Confidential-Payroll`.

---

## 6. Verification & Closure

* Confirmed `cgomez` can read, open, and modify files within the payroll folder.
* Attempted a test file write (`test_access.tmp`) which succeeded and was cleanly removed.
* No unauthorized access granted outside prescribed role.

```
Ticket Status: CLOSED
Resolution Category: Access Management / Security Group Assignment
KB Reference: KB-FS-012: "Granting Departmental Folder Access via AGDLP Groups"
```
