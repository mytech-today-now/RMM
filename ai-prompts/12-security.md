# Security Model

*Previous: [11-scalability.md](11-scalability.md)*

---

## Authentication & Authorization

- Windows Authentication (Kerberos/NTLM)
- Credential encryption using DPAPI
- Per-device credential override support
- Role-based access control (Admin, Operator, Viewer)

### Role Definitions

| Role | Permissions |
|------|-------------|
| Admin | Full access, configuration, user management |
| Operator | Device management, actions, alerts |
| Viewer | Read-only access to dashboards and reports |

---

## Credential Management

```powershell
# Secure credential storage
$credential = Get-Credential
$credential | Export-Clixml -Path "$PSScriptRoot/../secrets/credentials.xml"

# Retrieval with scope protection
$credential = Import-Clixml -Path "$PSScriptRoot/../secrets/credentials.xml"
```

### Credential Best Practices
- Store credentials in `secrets/` folder (gitignored)
- Use DPAPI encryption (Windows-native)
- Per-device credential support for non-domain devices
- Credential rotation reminders
- Never log credential values

---

## Audit Logging

- All actions logged with user, timestamp, target
- Immutable audit trail (append-only)
- Export capability for compliance
- Retention configurable (default: 2 years)

### Audit Log Fields
- Timestamp (UTC)
- User/Service account
- Action performed
- Target device(s)
- Result (success/failure)
- IP address of console
- Details/parameters

---

## Network Security

- WinRM over HTTPS recommended
- Firewall rules documentation
- Network segmentation support
- No inbound connections required (pull model)

### Required Ports

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 5985 | TCP | Outbound | WinRM HTTP |
| 5986 | TCP | Outbound | WinRM HTTPS |
| 445 | TCP | Outbound | SMB fallback |
| 22 | TCP | Outbound | SSH (optional) |
| 8080 | TCP | Inbound | Web dashboard (configurable) |

### Firewall Configuration

```powershell
# Enable WinRM HTTPS on endpoints
Enable-PSRemoting -Force
winrm quickconfig -transport:https

# Configure firewall for console
New-NetFirewallRule -Name "RMM-WinRM" -Direction Outbound -Protocol TCP -RemotePort 5985,5986 -Action Allow
```

---

*Next: [13-implementation.md](13-implementation.md)*

