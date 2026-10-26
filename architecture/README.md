# Architecture & Network Design

This directory documents the infrastructure specifications, network addressing scheme, directory hierarchy, and logical design for the **Contoso Corporation Active Directory Enterprise Lab**.

---

## 1. Physical & Virtual Network Topology

The lab simulates an on-premises enterprise environment deployed using hypervisors such as **Oracle VirtualBox**, **Hyper-V**, or **VMware Workstation/ESXi** operating on an isolated internal/host-only virtual network (`192.168.10.0/24`).

```
                  +-------------------------------------------------+
                  |          Enterprise Edge Gateway / NAT          |
                  |                   192.168.10.1                  |
                  +-----------------------+-------------------------+
                                          |
                                          | Corporate Internal LAN
                                          | (Subnet: 192.168.10.0/24)
                  +-----------------------+-------------------------+
                  |                                                 |
+-----------------+-------------------+           +-----------------+-------------------+
|     Primary Domain Controller       |           |           Managed Switch            |
|               DC01                  |           |           Virtual Switch            |
|          192.168.10.10              |           +-----------------+-------------------+
|  Roles: AD DS, DNS, DHCP, File Svc  |                             |
+-------------------------------------+          +------------------+------------------+
                                                 |                                     |
                                         +-------+-------+                     +-------+-------+
                                         |    Client 1   |                     |    Client 2   |
                                         |   CLIENT01    |                     |   WS-SALES-01 |
                                         | 192.168.10.50 |                     | 192.168.10.51 |
                                         | (DHCP Leased) |                     | (DHCP Leased) |
                                         +---------------+                     +---------------+
```

---

## 2. IP Addressing Scheme

| Device Hostname | Role / Description | IP Address | Subnet Mask | Default Gateway | Primary DNS |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Edge-Router** | Gateway / NAT Router | `192.168.10.1` | `255.255.255.0` | N/A | External / ISP |
| **DC01** | Primary Domain Controller (AD DS / DNS / DHCP / GPO) | `192.168.10.10` | `255.255.255.0` | `192.168.10.1` | `127.0.0.1` / `192.168.10.10` |
| **DHCP Scope** | Dynamic Client Pool (`Corporate-LAN`) | `192.168.10.50 - 192.168.10.150` | `255.255.255.0` | `192.168.10.1` | `192.168.10.10` |
| **CLIENT01** | Windows 11 Enterprise Domain Client (Verified Lease) | `192.168.10.50` (Dynamic) | `255.255.255.0` | `192.168.10.1` | `192.168.10.10` |
| **Static / Reserved** | Network Printers, Secondary Servers, Management | `192.168.10.151 - 192.168.10.254` | `255.255.255.0` | `192.168.10.1` | `192.168.10.10` |

### DHCP Scope Options Configured

* **Option 003 (Router / Default Gateway)**: `192.168.10.1`
* **Option 006 (DNS Servers)**: `192.168.10.10` (`DC01.corp.contoso.local`)
* **Option 015 (Domain Name)**: `corp.contoso.local`

![DHCP Address Pool](../screenshots/dc01-dhcp-scope-address-pool.png)
*Figure 1: DHCP Console on DC01 displaying active scope `192.168.10.0` with address pool `192.168.10.50` - `192.168.10.150`.*

---

## 3. Active Directory Logical Hierarchy

### Domain Identity
- **Fully Qualified Domain Name (FQDN)**: `corp.contoso.local`
- **NetBIOS Domain Name**: `CORP`
- **Forest & Domain Functional Level**: Windows Server 2022 / 2025 Standard

### Organizational Unit (OU) Architecture

```
corp.contoso.local
│
├── OU=IT Department
│   ├── User Accounts (e.g., Asim Parihar [asimp], Systems Administrators)
│   └── Security Groups (SG-IT-Support, SG-Server-Admins)
│
├── OU=HR (Human Resources)
│   ├── User Accounts (Directors, Generalists, Analysts)
│   └── Security Groups (SG-HR-General, SG-HR-Payroll-RW)
│
├── OU=IT (Information Technology)
│   ├── User Accounts (Systems Admins, Help Desk, SecOps)
│   └── Security Groups (SG-IT-HelpDesk, SG-Server-Admins)
│
├── OU=Sales (Sales & Business Development)
│   ├── User Accounts (Account Execs, SDRs, CSMs)
│   └── Security Groups (SG-Sales-Staff, SG-Sales-Leads)
│
├── OU=Workstations (Managed Domain Workstations)
│   ├── Staged client computers
│   └── WS-SALES-01 ... WS-SALES-05
│
└── CN=Computers (Default Computer Container)
    └── CLIENT01 (Verified domain client workstation)
```

![ADUC Computers Container](../screenshots/dc01-aduc-computers-client01.png)
*Figure 2: Active Directory Users and Computers confirming `CLIENT01` domain computer object.*

---

## 4. Key Services & Port Matrix

| Protocol / Service | Port(s) | Direction / Purpose |
| :--- | :--- | :--- |
| **DNS** | 53 (TCP/UDP) | Name resolution for domain resources & SRV records (`_ldap._tcp.dc._msdcs`) |
| **DHCP** | 67 (Server UDP), 68 (Client UDP) | Automatic IP lease allocation and option distribution |
| **Kerberos** | 88 (TCP/UDP) | User & computer authentication and ticket granting |
| **LDAP / LDAPS** | 389 (TCP) / 636 (SSL) | Active Directory directory queries & identity validation |
| **SMB** | 445 (TCP) | File shares, SYSVOL & Netlogon replication, GPO downloads |
| **RPC Endpoint Mapper** | 135 (TCP) | AD replication and remote server management |

---

## 5. Client Verification & Name Resolution

The workstation `CLIENT01` is confirmed connected to `corp.contoso.local`, dynamically acquiring its IP configuration from `DC01` and querying `dc01.corp.contoso.local`:

![CLIENT01 IPConfig](../screenshots/client01-ipconfig-dhcp-lease.png)
*Figure 3: `ipconfig /all` on `CLIENT01` demonstrating leased IP `192.168.10.50` and DNS `192.168.10.10`.*

![CLIENT01 DNS NSLookup](../screenshots/client01-dns-nslookup.png)
*Figure 4: Forward DNS resolution on `CLIENT01` verifying `dc01.corp.contoso.local` resolving to `192.168.10.10`.*
