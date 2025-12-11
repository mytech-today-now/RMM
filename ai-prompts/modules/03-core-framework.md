# Core Framework (scripts/core/)

*Previous: [../02-architecture-schema.md](../02-architecture-schema.md)*

---

## RMM-Core.psm1 - Main Module

```powershell
# Central module that imports all sub-modules and provides unified API
# Exports: Initialize-RMM, Get-RMMConfig, Set-RMMConfig, Get-RMMDevice, etc.

# Key Functions:
# - Initialize-RMM: Bootstrap environment, check dependencies, connect to database
# - Get-RMMDevice: Query devices with filtering (by site, group, status, tag)
# - Invoke-RMMAction: Execute actions with queuing, retry, and logging
# - Get-RMMHealth: System health summary across all endpoints
```

---

## Initialize-RMM.ps1 - Bootstrap & Setup

- **Runs as:** Administrator (first-time setup)
- **Parameters:**
  - `-Mode [Install|Upgrade|Repair|Uninstall]`
  - `-DatabasePath` (default: `$PSScriptRoot/../data/devices.db`)
  - `-ImportDevices` (CSV path for initial import)
  - `-SiteName` (for multi-site)
  - `-EnableWebDashboard` (switch)
  - `-WinRMHttps` (switch for HTTPS transport)
- **Actions:**
  1. Check/install PowerShell module dependencies
  2. Create folder structure and .gitignore
  3. Initialize SQLite database with schema
  4. Create encrypted credential store
  5. Register scheduled tasks (configurable intervals)
  6. Configure Windows Firewall rules
  7. Enable WinRM on local machine
  8. Optional: Generate self-signed certificate for HTTPS
  9. Add localhost as first managed device
  10. Run initial health check

---

## Config-Manager.ps1 - Configuration Handling

```powershell
# Manages settings.json with validation and hot-reload
# Supports environment-specific overrides
# Configuration sections:
@{
    General = @{
        OrganizationName = "myTech.Today"
        DefaultSite = "Main"
        DataRetentionDays = 90
        LogLevel = "Info"  # Debug, Info, Warning, Error
    }
    Connections = @{
        WinRMTimeout = 30
        WinRMMaxConcurrent = 25
        SSHEnabled = $false
        RelayEnabled = $false
    }
    Monitoring = @{
        InventoryInterval = "Daily"
        HealthCheckInterval = 300  # seconds
        MetricsRetention = 7  # days for high-resolution
    }
    Notifications = @{
        EmailEnabled = $false
        SmtpServer = ""
        SlackWebhook = ""
        TeamsWebhook = ""
        PagerDutyKey = ""
    }
    Security = @{
        RequireHttps = $false
        CredentialCacheTTL = 3600
        AuditAllActions = $true
    }
}
```

---

## Logging.ps1 - Centralized Logging

Uses the shared logging module from:
- Local: `Q:\_kyle\temp_documents\GitHub\PowerShellScripts\scripts\logging.ps1`
- Remote: `https://raw.githubusercontent.com/mytech-today-now/scripts/refs/heads/main/logging.ps1`

Update as necessary but remain backwards compatible with dependent scripts in the PowerShellScripts repo.

---

*Next: [04-collectors.md](04-collectors.md)*

