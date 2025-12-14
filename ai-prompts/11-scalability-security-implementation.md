# PROMPT 11: Scalability, Security & Implementation

**Previous:** [modules/10-ui.md](modules/10-ui.md) - Complete that first

---

## Your Task

Add scalability features, security hardening, and ensure all code follows implementation standards.

---

## Part 1: Scalability Features

### Parallel Processing

Implement parallel processing for operations on multiple devices:

**PowerShell 7+ (Preferred):**
```powershell
$devices | ForEach-Object -Parallel {
    Invoke-Command -ComputerName $_.ComputerName -ScriptBlock $using:scriptBlock
} -ThrottleLimit 50
```

**PowerShell 5.1 Fallback:**
```powershell
$runspacePool = [RunspaceFactory]::CreateRunspacePool(1, 50)
$runspacePool.Open()
# Implement runspace pool logic
```

### Connection Pooling

- Reuse WinRM sessions across multiple operations
- Session cache with TTL (configurable, default 5 minutes)
- Graceful session cleanup on timeout

### Batch Operations

- Group devices by site for network efficiency
- Batch database inserts (100 rows per commit)
- Batch metric writes with write-through caching

### Caching Strategy

- Device status: 5-minute cache
- Inventory: 24-hour cache
- Configuration: Hot-reload on change
- Metrics: Write-through with batch commits

### Database Optimization

- Use indexed queries (already defined in schema)
- Batch inserts for metrics
- Automatic archival of old data (per retention policy)
- Weekly VACUUM for SQLite maintenance

### Multi-Site Support (Optional)

For deployments with remote sites, implement relay agent architecture:

```text
Central Console <-- HTTPS --> Site Relay Agent <-- WinRM --> Local Endpoints
                                      |
                               Local Cache DB
                               (sync on schedule)
```

---

## Part 2: Security Hardening

### Authentication & Authorization

- Use Windows Authentication (Kerberos/NTLM)
- Encrypt credentials using DPAPI
- Support per-device credential override
- Implement role-based access control (Admin, Operator, Viewer)

**Role Definitions:**

| Role | Permissions |
|------|-------------|
| Admin | Full access, configuration, user management |
| Operator | Device management, actions, alerts |
| Viewer | Read-only access to dashboards and reports |

### Credential Management

```powershell
# Secure credential storage
$credential = Get-Credential
$credential | Export-Clixml -Path "$PSScriptRoot/../secrets/credentials.xml"

# Retrieval with scope protection
$credential = Import-Clixml -Path "$PSScriptRoot/../secrets/credentials.xml"
```

**Best Practices:**
- Store credentials in `secrets/` folder (gitignored)
- Use DPAPI encryption (Windows-native)
- Support per-device credentials for non-domain devices
- Never log credential values
- Implement credential rotation reminders

### Audit Logging

All actions must be logged to the AuditLog table with:
- Timestamp (UTC)
- User/Service account
- Action performed
- Target device(s)
- Result (success/failure)
- IP address of console
- Details/parameters

### Network Security

- Recommend WinRM over HTTPS (port 5986)
- Document firewall rules
- Support network segmentation
- No inbound connections required (pull model)

**Required Ports:**

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 5985 | TCP | Outbound | WinRM HTTP |
| 5986 | TCP | Outbound | WinRM HTTPS |
| 445 | TCP | Outbound | SMB fallback |
| 8080 | TCP | Inbound | Web dashboard (configurable) |

---

## Part 3: Implementation Standards

### Coding Standards

All code must follow myTech.Today PowerShell guidelines:
- Verb-Noun naming convention
- Comprehensive comment-based help (.SYNOPSIS, .DESCRIPTION, .PARAMETER, .EXAMPLE)
- Parameter validation on all functions
- ASCII-only output (no emoji)
- Centralized logging to `%USERPROFILE%\myTech.Today\logs\`
- Integration with shared logging module: `Q:\_kyle\temp_documents\GitHub\PowerShellScripts\scripts\logging.ps1`

### Error Handling

Implement proper error handling with categorization:

```powershell
try {
    $result = Invoke-Command -ComputerName $target -ScriptBlock $sb -ErrorAction Stop
}
catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
    Write-LogWarning "Device unreachable: $target"
    Set-DeviceStatus -DeviceId $deviceId -Status "Offline"
    Add-OfflineQueue -DeviceId $deviceId -Action $pendingAction
}
catch {
    Write-LogError "Unexpected error on $target : $_"
    throw
}
```

**Error Categories:**
- **Transient:** Network issues, timeouts - retry with backoff
- **Device:** Device offline, WinRM disabled - queue for later
- **Configuration:** Invalid settings - log and alert admin
- **Fatal:** Database corruption, critical failure - stop and notify

---

## Validation

After completing this prompt, verify:

- [ ] Parallel processing is implemented
- [ ] Connection pooling is working
- [ ] Caching is implemented
- [ ] Database operations are optimized
- [ ] Credentials are encrypted with DPAPI
- [ ] All actions are audit logged
- [ ] All code has comment-based help
- [ ] Error handling is comprehensive
- [ ] Logging uses centralized module

---

**NEXT PROMPT:** [12-testing-validation.md](12-testing-validation.md) - Final testing and validation

---

*This is prompt 12 of 13 in the RMM build sequence*

