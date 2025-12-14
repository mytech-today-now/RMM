# PROMPT 03: Core Framework Implementation

**Previous:** [../02-architecture.md](../02-architecture.md) - Complete that first

---

## Your Task

Implement the core framework that provides the foundation for all RMM functionality. This includes the main module, initialization script, configuration manager, and logging integration.

---

## Step 1: Create RMM-Core.psm1 - Main Module

Create `RMM/scripts/core/RMM-Core.psm1`:

This is the central module that provides the unified API for the RMM system. It should:

- Import all configuration and database functions
- Provide device query functions
- Provide action execution functions
- Provide health check functions
- Export all public functions

**Key Functions to Implement:**

1. `Initialize-RMM` - Bootstrap environment, check dependencies, connect to database
2. `Get-RMMConfig` - Retrieve configuration settings
3. `Set-RMMConfig` - Update configuration settings
4. `Get-RMMDevice` - Query devices with filtering (by site, group, status, tag)
5. `Add-RMMDevice` - Register a new device
6. `Update-RMMDevice` - Update device information
7. `Remove-RMMDevice` - Unregister a device
8. `Invoke-RMMAction` - Execute actions with queuing, retry, and logging
9. `Get-RMMHealth` - System health summary across all endpoints
10. `Get-RMMDatabase` - Get database connection

Include comprehensive comment-based help for each function.

---

## Step 2: Create Initialize-RMM.ps1 - Bootstrap & Setup

Create `RMM/scripts/core/Initialize-RMM.ps1`:

**Requirements:**

- **Runs as:** Administrator (first-time setup)
- **Parameters:**
  - `-Mode [Install|Upgrade|Repair|Uninstall]`
  - `-DatabasePath` (default: `$PSScriptRoot/../../data/devices.db`)
  - `-ImportDevices` (CSV path for initial import)
  - `-SiteName` (for multi-site)
  - `-EnableWebDashboard` (switch)
  - `-WinRMHttps` (switch for HTTPS transport)

**Actions the script must perform:**

1. Check/install PowerShell module dependencies (PSWindowsUpdate, PSSQLite, ThreadJob, ImportExcel, PSWriteHTML)
2. Verify folder structure exists (or create it)
3. Initialize SQLite database by calling `Initialize-Database.ps1`
4. Create encrypted credential store in `secrets/` folder
5. Register scheduled tasks for monitoring (configurable intervals)
6. Configure Windows Firewall rules for WinRM
7. Enable WinRM on local machine
8. Optional: Generate self-signed certificate for HTTPS
9. Add localhost as first managed device
10. Run initial health check
11. Display summary of installation

Include comprehensive error handling and progress indicators.

---

## Step 3: Create Config-Manager.ps1 - Configuration Handling

Create `RMM/scripts/core/Config-Manager.ps1`:

This script manages `settings.json` with validation and hot-reload capabilities.

**Key Functions to Implement:**

1. `Get-RMMConfiguration` - Load and parse settings.json
2. `Set-RMMConfiguration` - Update specific configuration values
3. `Test-RMMConfiguration` - Validate configuration structure
4. `Reset-RMMConfiguration` - Reset to defaults
5. `Export-RMMConfiguration` - Export current config
6. `Import-RMMConfiguration` - Import config from file

**Configuration Structure:**

The configuration should match the structure already created in `config/settings.json`:

- General (OrganizationName, DefaultSite, DataRetentionDays, LogLevel)
- Connections (WinRMTimeout, WinRMMaxConcurrent, SSHEnabled, RelayEnabled)
- Monitoring (InventoryInterval, HealthCheckInterval, MetricsRetention)
- Notifications (EmailEnabled, SmtpServer, SlackWebhook, TeamsWebhook, PagerDutyKey)
- Security (RequireHttps, CredentialCacheTTL, AuditAllActions)

Include validation for each setting type and range.

---

## Step 4: Integrate Logging System

Create `RMM/scripts/core/Logging.ps1`:

This script integrates with the shared logging module from the PowerShellScripts repository.

**Requirements:**

- Source the logging functions from: `Q:\_kyle\temp_documents\GitHub\PowerShellScripts\scripts\logging.ps1`
- Fallback to remote: `https://raw.githubusercontent.com/mytech-today-now/scripts/refs/heads/main/logging.ps1`
- Remain backwards compatible with other scripts in the PowerShellScripts repo
- Configure log path to: `%USERPROFILE%\myTech.Today\logs\rmm.md`
- Support log levels: Debug, Info, Warning, Error
- Include device-specific logging to `logs/devices/{DeviceId}.md`

**Key Functions:**

1. `Write-RMMLog` - Write to main RMM log
2. `Write-RMMDeviceLog` - Write to device-specific log
3. `Get-RMMLog` - Retrieve log entries with filtering
4. `Clear-RMMLog` - Archive and clear old logs

---

## Validation

After completing this prompt, verify:

- [ ] `RMM-Core.psm1` is created with all 10 key functions
- [ ] `Initialize-RMM.ps1` is created and runs without errors
- [ ] `Config-Manager.ps1` is created with configuration functions
- [ ] `Logging.ps1` is created and integrates with shared logging
- [ ] All functions have comment-based help
- [ ] Module can be imported: `Import-Module .\scripts\core\RMM-Core.psm1`
- [ ] Initialization completes successfully
- [ ] Configuration can be read and updated
- [ ] Logging works to both main and device logs

Test the core framework:

```powershell
# Import the module
Import-Module .\scripts\core\RMM-Core.psm1 -Force

# Run initialization
.\scripts\core\Initialize-RMM.ps1 -Mode Install

# Test configuration
$config = Get-RMMConfiguration
$config.General

# Test device functions
Get-RMMDevice
```

---

**NEXT PROMPT:** [04-collectors.md](04-collectors.md) - Implement data collection system

---

*This is prompt 4 of 13 in the RMM build sequence*

