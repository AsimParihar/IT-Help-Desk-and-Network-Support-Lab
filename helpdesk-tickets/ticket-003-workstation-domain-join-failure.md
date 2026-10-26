# Incident Report: HD-2026-0129 - Workstation Domain Join Failure (DNS SRV Record Lookup)

---

## 1. Ticket Overview

| Field | Value |
| :--- | :--- |
| **Ticket ID** | `HD-2026-0129` |
| **Status** | `Closed / Resolved` |
| **Priority** | `Medium (P3)` |
| **Category** | Workstation Provisioning / DNS & Active Directory Domain Join |
| **Requester** | IT Staging Lab / Staged Workstation Client |
| **Department** | IT Support / Staging |
| **Workstation** | `CLIENT01` (Staged Windows 11 Enterprise Client) |
| **Assigned Technician** | Alex Mercer (Help Desk Specialist) |
| **Created** | 2026-10-24 14:10 EST |
| **Resolved** | 2026-10-24 14:42 EST |

---

## 2. Issue Description

> **Technician Statement**:  
> *"Attempted to join newly imaged Windows 11 client `CLIENT01` to domain `corp.contoso.local`. The join attempt failed with the standard Windows error dialog: 'An Active Directory Domain Controller (AD DC) for the domain corp.contoso.local could not be contacted. Ensure that the domain name is typed correctly.' Ping to the server IP 192.168.10.10 works, but domain joining fails."*

---

## 3. Initial Assessment & Diagnostic Steps

1. **ICMP Ping Test**:
   ```cmd
   ping 192.168.10.10
   # Reply from 192.168.10.10: bytes=32 time<1ms TTL=128 (Network layer connectivity verified)
   ```

2. **Network Adapter IP Configuration Audit (`ipconfig /all`)**:
   ```text
   Ethernet adapter Ethernet:
      Connection-specific DNS Suffix  . : 
      Description . . . . . . . . . . . : Intel(R) PRO/1000 MT Desktop Adapter
      DHCP Enabled. . . . . . . . . . . : No
      IPv4 Address. . . . . . . . . . . : 192.168.10.114(Preferred)
      Subnet Mask . . . . . . . . . . . : 255.255.255.0
      Default Gateway . . . . . . . . . : 192.168.10.1
      DNS Servers . . . . . . . . . . . : 8.8.8.8
                                          1.1.1.1
   ```

3. **DNS Service Record (SRV) Query**:
   To join an Active Directory domain, the client must resolve the LDAP SRV resource record (`_ldap._tcp.dc._msdcs.<Domain>`).
   ```cmd
   nslookup -type=SRV _ldap._tcp.dc._msdcs.corp.contoso.local
   ```
   **Output:**
   ```text
   Server:  dns.google
   Address:  8.8.8.8

   *** dns.google can't find _ldap._tcp.dc._msdcs.corp.contoso.local: Non-existent domain
   ```

---

## 4. Root Cause Analysis (RCA)

* **DNS Resolver Misconfiguration**:
  The staging technician previously configured static public DNS servers (`8.8.8.8` and `1.1.1.1`) during base OS imaging.
* In an Active Directory environment, Windows domain clients **must** point their primary DNS resolver to the internal Active Directory DNS Server (`192.168.10.10` / `DC01`). Public resolvers cannot resolve internal Active Directory Service Records (`_msdcs`), causing domain discovery to fail with error `0x0000232B (NAME_COLLISION / Non-existent domain)`.

---

## 5. Remediation & Resolution Steps

1. **Step 1 - Switch Network Configuration to DHCP**:
   Reconfigured the network interface to obtain IP and DNS settings dynamically from the authorized corporate DHCP server on `DC01`:
   ```powershell
   # Enable DHCP on the primary network interface
   Set-NetIPInterface -InterfaceAlias "Ethernet" -Dhcp Enabled
   Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ResetServerAddresses
   
   # Release and renew lease
   ipconfig /release
   ipconfig /renew
   ```

2. **Step 2 - Verify DHCP Lease & DNS Assignment**:
   Verified that DHCP Scope `192.168.10.50 - 192.168.10.150` provided dynamic IP `192.168.10.50`, Default Gateway `192.168.10.1`, Option 006 DNS `192.168.10.10`, and Option 015 domain suffix `corp.contoso.local`:
   
   ![CLIENT01 IPConfig](../screenshots/client01-ipconfig-dhcp-lease.png)
   *Figure 1: `ipconfig /all` on `CLIENT01` verifying dynamic IP `192.168.10.50` and DNS `192.168.10.10`.*

3. **Step 3 - Re-Query AD SRV Record & Domain Controller**:
   Verified successful resolution of `dc01.corp.contoso.local` pointing to `192.168.10.10`:
   
   ```powershell
   nslookup dc01.corp.contoso.local
   ```

   ![DNS NSLookup](../screenshots/client01-dns-nslookup.png)
   *Figure 2: `nslookup dc01.corp.contoso.local` confirming internal name resolution via `192.168.10.10`.*

4. **Step 4 - Perform Domain Join**:
   Joined `CLIENT01` to `corp.contoso.local` with administrative credentials:
   ```powershell
   Add-Computer -DomainName "corp.contoso.local" -Restart
   ```

   ![Domain Join Properties](../screenshots/client01-domain-join-properties.png)
   *Figure 3: System Properties confirming `CLIENT01` joined to `corp.contoso.local`.*

---

## 6. Verification & Closure

* Machine rebooted and verified computer account presence on `DC01` in Active Directory Users and Computers:

  ![ADUC Computers CLIENT01](../screenshots/dc01-aduc-computers-client01.png)
  *Figure 4: ADUC console on `DC01` confirming `CLIENT01` domain computer object.*

* User successfully logged in with domain credentials.
* Baseline GPO update verified:

  ![CLIENT01 GPUpdate](../screenshots/client01-gpupdate-force.png)
  *Figure 5: `gpupdate /force` on `CLIENT01` confirming Group Policy application.*

```
Ticket Status: CLOSED
Root Cause: Client NIC configured with public DNS instead of internal AD DNS (192.168.10.10).
KB Reference: KB-NET-005: "Standard Operating Procedure for Domain Joining and DNS Validation"
```
