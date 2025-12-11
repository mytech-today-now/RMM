# myTech.Today RMM System - Comprehensive Project Specification

**Project:** myTech.Today Remote Monitoring and Management (RMM)
**Version:** 2.0
**Author:** Kyle C. Rode
**Company:** myTech.Today
**Contact:** sales@mytech.today

---

## Executive Summary

Generate a complete, production-ready repository for an enterprise-capable, open-source Remote Monitoring and Management (RMM) system built entirely using PowerShell scripts. This system is designed for IT professionals managing **150 endpoints initially** but architectured to **scale to 10,000+ endpoints** through partitioning, caching, and async operations. It leverages built-in Windows features like PowerShell Remoting (WinRM), Scheduled Tasks, WinGet for updates, and a tiered storage system (JSON for hot data, SQLite for cold storage, flat files for logs). The focus is on **production reliability at scale**: a hybrid pull/push architecture with central console, distributed collectors, health monitoring, update management, remote actions, alerting, and a web-based dashboard. This achieves approximately **70% of commercial RMM capabilities** (asset inventory, alerting, scripting, patching, remote access, reporting, automation) while remaining maintainable.

---

## Target Environment

| Metric | Initial Target | Maximum Scale |
|--------|----------------|---------------|
| Endpoints | 150 | 10,000+ |
| Concurrent Operations | 25 | 500 |
| Data Retention | 90 days | 2 years |
| Geographic Sites | 1 | 50+ |
| Admin Users | 1-3 | 25+ |

---

## Technical Requirements

### PowerShell Version
- **Minimum:** PowerShell 5.1 (Windows Desktop)
- **Recommended:** PowerShell 7.4+ (for parallel processing, improved performance)
- **Cross-platform:** Optional Linux/macOS collector support via PS7

### Target Operating Systems
- Windows 10 21H2+ (Pro/Enterprise)
- Windows 11 (all versions)
- Windows Server 2016, 2019, 2022, 2025
- Optional: Linux endpoints via SSH remoting

### Dependencies (Auto-bootstrapped)
- PSWindowsUpdate module
- PSSQLite module (for SQLite storage)
- ThreadJob module (PS5.1 parallel)
- ImportExcel module (reporting)
- PSWriteHTML module (dashboard)

---

## Repository Structure

```
RMM/
├── README.md                    # Quick start, feature matrix, screenshots
├── LICENSE                      # Private License
├── .gitignore                   # Exclude data/, logs/, *.log, secrets/
├── config/
│   ├── settings.json            # Global configuration
│   ├── thresholds.json          # Alert thresholds
│   ├── groups.json              # Device groups/tags
│   └── policies/                # Automation policies
│       ├── default.json
│       └── servers.json
├── scripts/
│   ├── core/                    # Core framework
│   │   ├── RMM-Core.psm1        # Main module (import all)
│   │   ├── Initialize-RMM.ps1   # Bootstrap/setup
│   │   ├── Config-Manager.ps1   # Configuration handling
│   │   └── Logging.ps1          # Centralized logging via 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\scripts\logging.ps1', which is located at 'https://raw.githubusercontent.com/mytech-today-now/scripts/refs/heads/main/logging.ps1', update as necessary, but remain backwards compatible, with the rest of the dependent scripts in the './powershellscripts/' repo.
│   ├── collectors/              # Data collection
│   │   ├── Inventory-Collector.ps1
│   │   ├── Hardware-Monitor.ps1
│   │   ├── Software-Auditor.ps1
│   │   ├── Security-Scanner.ps1
│   │   └── Event-Collector.ps1
│   ├── monitors/                # Health monitoring
│   │   ├── Health-Monitor.ps1
│   │   ├── Service-Monitor.ps1
│   │   ├── Performance-Monitor.ps1
│   │   └── Availability-Monitor.ps1
│   ├── actions/                 # Remote actions
│   │   ├── Remote-Actions.ps1
│   │   ├── Script-Executor.ps1
│   │   ├── Update-Manager.ps1
│   │   └── Remediation-Engine.ps1
│   ├── alerts/                  # Alerting system
│   │   ├── Alert-Manager.ps1
│   │   ├── Notification-Engine.ps1
│   │   └── Escalation-Handler.ps1
│   ├── reports/                 # Reporting
│   │   ├── Report-Generator.ps1
│   │   ├── Compliance-Reporter.ps1
│   │   └── Executive-Dashboard.ps1
│   ├── automation/              # Automation
│   │   ├── Policy-Engine.ps1
│   │   ├── Scheduled-Tasks.ps1
│   │   └── Workflow-Orchestrator.ps1
│   └── ui/                      # User interfaces
│       ├── Start-Console.ps1    # CLI dashboard
│       ├── Start-WebDashboard.ps1
│       └── web/                 # HTML/CSS/JS assets
├── data/                        # Runtime data (gitignored)
│   ├── devices.db               # SQLite device database
│   ├── cache/                   # Hot data cache (JSON)
│   ├── queue/                   # Action queue
│   └── archive/                 # Historical data
├── logs/                        # Log files (gitignored)
│   ├── rmm.md                   # Main log
│   └── devices/                 # Per-device logs
├── secrets/                     # Credentials (gitignored)
│   └── credentials.xml          # Encrypted credentials
├── docs/
│   ├── Setup-Guide.md
│   ├── Architecture.md
│   ├── API-Reference.md
│   ├── Scaling-Guide.md
│   └── Troubleshooting.md
└── tests/
    ├── Unit/
    ├── Integration/
    └── Performance/
```

---

## Core Architecture

### Hybrid Pull/Push Model

```
                                    ┌─────────────────────────────────────┐
                                    │         CENTRAL CONSOLE             │
                                    │  (Primary Management Server)        │
                                    │                                     │
                                    │  ┌─────────────┐ ┌──────────────┐  │
                                    │  │ Web Dashboard│ │ CLI Console  │  │
                                    │  └──────┬──────┘ └──────┬───────┘  │
                                    │         │               │          │
                                    │  ┌──────┴───────────────┴───────┐  │
                                    │  │      RMM-Core.psm1           │  │
                                    │  │  (Orchestration Engine)      │  │
                                    │  └──────────────┬───────────────┘  │
                                    │                 │                   │
                                    │  ┌──────────────┴───────────────┐  │
                                    │  │     SQLite Database          │  │
                                    │  │  (devices.db + cache/)       │  │
                                    │  └──────────────────────────────┘  │
                                    └─────────────────┬───────────────────┘
                                                      │
                    ┌─────────────────────────────────┼─────────────────────────────────┐
                    │                                 │                                 │
           ┌────────┴────────┐               ┌────────┴────────┐               ┌────────┴────────┐
           │   Site Alpha    │               │   Site Beta     │               │   Site Gamma    │
           │  (50 devices)   │               │  (50 devices)   │               │  (50 devices)   │
           │                 │               │                 │               │                 │
           │ ┌─────────────┐ │               │ ┌─────────────┐ │               │ ┌─────────────┐ │
           │ │ Relay Agent │ │               │ │ Relay Agent │ │               │ │ Relay Agent │ │
           │ │  (Optional) │ │               │ │  (Optional) │ │               │ │  (Optional) │ │
           │ └──────┬──────┘ │               │ └──────┬──────┘ │               │ └──────┬──────┘ │
           │        │        │               │        │        │               │        │        │
           │   WinRM/SSH     │               │   WinRM/SSH     │               │   WinRM/SSH     │
           │        │        │               │        │        │               │        │        │
           │ ┌──┬──┬┴┬──┬──┐ │               │ ┌──┬──┬┴┬──┬──┐ │               │ ┌──┬──┬┴┬──┬──┐ │
           │ │EP│EP│EP│EP│EP│ │               │ │EP│EP│EP│EP│EP│ │               │ │EP│EP│EP│EP│EP│ │
           │ └──┴──┴──┴──┴──┘ │               │ └──┴──┴──┴──┴──┘ │               │ └──┴──┴──┴──┴──┘ │
           └──────────────────┘               └──────────────────┘               └──────────────────┘
```

### Communication Methods

| Method | Use Case | Port | Scalability |
|--------|----------|------|-------------|
| WinRM (HTTP) | Internal Windows | 5985 | Up to 500/batch |
| WinRM (HTTPS) | Secure/External | 5986 | Up to 500/batch |
| SSH | Linux/macOS/Cross-platform | 22 | Up to 200/batch |
| SMB Fallback | Firewalled devices | 445 | File-based queue |
| Relay Agent | Remote sites | Custom | Unlimited (queued) |

### Data Storage Architecture

**Tiered Storage Model:**

```
┌─────────────────────────────────────────────────────────────────┐
│                        HOT TIER (In-Memory)                     │
│  - Active sessions                                              │
│  - Real-time metrics (last 5 minutes)                          │
│  - Currently executing actions                                  │
│  TTL: Session duration                                          │
├─────────────────────────────────────────────────────────────────┤
│                      WARM TIER (JSON Cache)                     │
│  - Recent device states (last 24 hours)                        │
│  - Pending alerts                                               │
│  - Action queue                                                 │
│  Location: /data/cache/*.json                                   │
│  TTL: 24 hours, then migrate to cold                           │
├─────────────────────────────────────────────────────────────────┤
│                      COLD TIER (SQLite)                         │
│  - Device inventory (all devices)                               │
│  - Historical metrics                                           │
│  - Alert history                                                │
│  - Audit logs                                                   │
│  Location: /data/devices.db                                     │
│  Retention: Configurable (default 90 days)                     │
├─────────────────────────────────────────────────────────────────┤
│                    ARCHIVE TIER (Compressed)                    │
│  - Historical reports                                           │
│  - Compliance snapshots                                         │
│  - Old logs                                                     │
│  Location: /data/archive/*.zip                                  │
│  Retention: 2 years                                             │
└─────────────────────────────────────────────────────────────────┘
```

### Database Schema (SQLite)

```sql
-- Core Tables
CREATE TABLE Devices (
    DeviceId TEXT PRIMARY KEY,
    Hostname TEXT NOT NULL,
    FQDN TEXT,
    IPAddress TEXT,
    MACAddress TEXT,
    SiteId TEXT,
    GroupIds TEXT,  -- JSON array
    OSName TEXT,
    OSVersion TEXT,
    OSBuild TEXT,
    LastSeen DATETIME,
    LastInventory DATETIME,
    Status TEXT DEFAULT 'Unknown',
    AgentVersion TEXT,
    Tags TEXT,  -- JSON array
    CustomFields TEXT,  -- JSON object
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Sites (
    SiteId TEXT PRIMARY KEY,
    Name TEXT NOT NULL,
    Location TEXT,
    Timezone TEXT,
    RelayAgent TEXT,
    ContactEmail TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE DeviceGroups (
    GroupId TEXT PRIMARY KEY,
    Name TEXT NOT NULL,
    Description TEXT,
    ParentGroupId TEXT,
    PolicyId TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Inventory (
    InventoryId INTEGER PRIMARY KEY AUTOINCREMENT,
    DeviceId TEXT NOT NULL,
    Category TEXT NOT NULL,  -- Hardware, Software, Security, Network
    Data TEXT NOT NULL,  -- JSON blob
    CollectedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

CREATE TABLE Alerts (
    AlertId TEXT PRIMARY KEY,
    DeviceId TEXT NOT NULL,
    AlertType TEXT NOT NULL,
    Severity TEXT NOT NULL,  -- Critical, High, Medium, Low, Info
    Title TEXT NOT NULL,
    Message TEXT,
    Source TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    AcknowledgedAt DATETIME,
    AcknowledgedBy TEXT,
    ResolvedAt DATETIME,
    ResolvedBy TEXT,
    AutoResolved INTEGER DEFAULT 0,
    NotificationsSent TEXT,  -- JSON array
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

CREATE TABLE Actions (
    ActionId TEXT PRIMARY KEY,
    DeviceId TEXT,
    ActionType TEXT NOT NULL,
    Status TEXT DEFAULT 'Pending',  -- Pending, Running, Completed, Failed, Cancelled
    Priority INTEGER DEFAULT 5,
    Payload TEXT,  -- JSON
    Result TEXT,  -- JSON
    ScheduledAt DATETIME,
    StartedAt DATETIME,
    CompletedAt DATETIME,
    CreatedBy TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Metrics (
    MetricId INTEGER PRIMARY KEY AUTOINCREMENT,
    DeviceId TEXT NOT NULL,
    MetricType TEXT NOT NULL,  -- CPU, Memory, Disk, Network
    Value REAL NOT NULL,
    Unit TEXT,
    Timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

CREATE TABLE AuditLog (
    LogId INTEGER PRIMARY KEY AUTOINCREMENT,
    Timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    User TEXT,
    Action TEXT NOT NULL,
    Target TEXT,
    Details TEXT,
    IPAddress TEXT,
    Success INTEGER DEFAULT 1
);

-- Indexes for performance
CREATE INDEX idx_devices_status ON Devices(Status);
CREATE INDEX idx_devices_site ON Devices(SiteId);
CREATE INDEX idx_inventory_device ON Inventory(DeviceId);
CREATE INDEX idx_inventory_date ON Inventory(CollectedAt);
CREATE INDEX idx_alerts_device ON Alerts(DeviceId);
CREATE INDEX idx_alerts_severity ON Alerts(Severity);
CREATE INDEX idx_alerts_created ON Alerts(CreatedAt);
CREATE INDEX idx_actions_status ON Actions(Status);
CREATE INDEX idx_actions_device ON Actions(DeviceId);
CREATE INDEX idx_metrics_device_type ON Metrics(DeviceId, MetricType);
CREATE INDEX idx_metrics_timestamp ON Metrics(Timestamp);
```

---

## Feature Modules

### 1. Core Framework (scripts/core/)

#### RMM-Core.psm1 - Main Module
```powershell
# Central module that imports all sub-modules and provides unified API
# Exports: Initialize-RMM, Get-RMMConfig, Set-RMMConfig, Get-RMMDevice, etc.

# Key Functions:
# - Initialize-RMM: Bootstrap environment, check dependencies, connect to database
# - Get-RMMDevice: Query devices with filtering (by site, group, status, tag)
# - Invoke-RMMAction: Execute actions with queuing, retry, and logging
# - Get-RMMHealth: System health summary across all endpoints
```

#### Initialize-RMM.ps1 - Bootstrap & Setup
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

#### Config-Manager.ps1 - Configuration Handling
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

### 2. Data Collection (scripts/collectors/)

#### Inventory-Collector.ps1
- **Purpose:** Complete hardware/software inventory
- **Scheduling:** Daily (configurable)
- **Parameters:**
  - `-Devices` (array, group name, or "All")
  - `-Categories [All|Hardware|Software|Security|Network]`
  - `-Parallel` (switch, default: $true for PS7+)
  - `-ThrottleLimit` (default: 25)
  - `-Force` (skip cache, fresh collection)
- **Data Collected:**
  ```powershell
  @{
      Hardware = @{
          System = Get-CimInstance Win32_ComputerSystem
          BIOS = Get-CimInstance Win32_BIOS
          Motherboard = Get-CimInstance Win32_BaseBoard
          Processor = Get-CimInstance Win32_Processor
          Memory = Get-CimInstance Win32_PhysicalMemory
          Disks = Get-CimInstance Win32_DiskDrive
          Volumes = Get-CimInstance Win32_LogicalDisk
          GPU = Get-CimInstance Win32_VideoController
          Network = Get-NetAdapter | Get-NetIPConfiguration
          USB = Get-CimInstance Win32_USBController
          Monitor = Get-CimInstance WmiMonitorID -Namespace root/wmi
          Battery = Get-CimInstance Win32_Battery
      }
      Software = @{
          OS = Get-CimInstance Win32_OperatingSystem
          Hotfixes = Get-HotFix
          InstalledApps = Get-Package
          WinGetApps = winget list --source winget
          Services = Get-Service
          StartupPrograms = Get-CimInstance Win32_StartupCommand
          ScheduledTasks = Get-ScheduledTask
      }
      Security = @{
          Defender = Get-MpComputerStatus
          Firewall = Get-NetFirewallProfile
          BitLocker = Get-BitLockerVolume
          TPM = Get-Tpm
          LocalAdmins = Get-LocalGroupMember -Group "Administrators"
          PasswordPolicy = net accounts
          AuditPolicy = auditpol /get /category:*
      }
      Network = @{
          Adapters = Get-NetAdapter
          IPConfig = Get-NetIPConfiguration
          Routes = Get-NetRoute
          DNSServers = Get-DnsClientServerAddress
          Shares = Get-SmbShare
          Connections = Get-NetTCPConnection -State Established
          FirewallRules = Get-NetFirewallRule | Where Enabled -eq True
      }
  }
  ```

#### Hardware-Monitor.ps1
- **Purpose:** Real-time hardware metrics
- **Scheduling:** Every 5 minutes (configurable)
- **Metrics:**
  - CPU: Usage %, temperature, frequency, per-core stats
  - Memory: Used/Available, page file, cache
  - Disk: IOPS, queue length, latency, space
  - Network: Throughput, errors, dropped packets
  - GPU: Usage, memory, temperature (NVIDIA/AMD if available)

#### Software-Auditor.ps1
- **Purpose:** Software inventory and compliance
- **Features:**
  - Detect unauthorized software (blacklist)
  - Find missing required software (whitelist)
  - License tracking (registry-based)
  - Version compliance checking
  - Browser extension inventory

#### Security-Scanner.ps1
- **Purpose:** Security posture assessment
- **Checks:**
  - Windows Update status
  - Antivirus status and definitions age
  - Firewall configuration
  - BitLocker encryption status
  - Local admin accounts audit
  - Weak password detection
  - Open ports scan
  - SSL/TLS certificate expiry
  - Pending reboots
  - Security event log analysis

#### Event-Collector.ps1
- **Purpose:** Centralized event log collection
- **Event Sources:**
  - System (Errors, Warnings)
  - Application (Errors, Warnings)
  - Security (Logon failures, privilege use)
  - PowerShell (Script execution)
  - Custom event filters (configurable)
- **Features:**
  - Forward to central collector
  - Parse and normalize events
  - Correlation with alerts

### 3. Health Monitoring (scripts/monitors/)

#### Health-Monitor.ps1
- **Purpose:** Comprehensive health assessment
- **Health Score Calculation:**
  ```powershell
  # 0-100 score based on weighted factors
  $healthScore = @{
      Availability = 25    # Is device reachable?
      Performance = 25     # CPU/Memory/Disk within thresholds?
      Security = 25        # AV current, firewall on, updates installed?
      Compliance = 25      # Matches policy requirements?
  }
  ```
- **Status Levels:** Healthy, Warning, Critical, Offline, Unknown

#### Service-Monitor.ps1
- **Purpose:** Critical service monitoring
- **Features:**
  - Monitor list of critical services per device/group
  - Auto-restart failed services (configurable)
  - Service dependency tracking
  - Startup type compliance

#### Performance-Monitor.ps1
- **Purpose:** Performance threshold monitoring
- **Default Thresholds (configurable in thresholds.json):**
  ```json
  {
      "CPU": { "Warning": 80, "Critical": 95 },
      "Memory": { "Warning": 85, "Critical": 95 },
      "DiskSpace": { "Warning": 20, "Critical": 10 },
      "DiskLatency": { "Warning": 20, "Critical": 50 },
      "NetworkErrors": { "Warning": 100, "Critical": 1000 }
  }
  ```

#### Availability-Monitor.ps1
- **Purpose:** Uptime and connectivity monitoring
- **Methods:**
  - ICMP Ping (basic)
  - WinRM Test (service availability)
  - Port checks (custom services)
  - HTTP/HTTPS checks (web services)
- **Features:**
  - Latency tracking
  - Packet loss detection
  - Automatic offline/online transitions
  - Maintenance windows support

### 4. Remote Actions (scripts/actions/)

#### Remote-Actions.ps1
- **Actions Available:**
  | Action | Description | Confirmation |
  |--------|-------------|--------------|
  | Reboot | Restart computer | Yes |
  | Shutdown | Power off | Yes |
  | WakeOnLAN | Send magic packet | No |
  | Lock | Lock workstation | No |
  | Logoff | Log off current user | Yes |
  | EnableRDP | Enable Remote Desktop | Yes |
  | DisableRDP | Disable Remote Desktop | Yes |
  | StartRDP | Launch RDP session | No |
  | StartRemotePS | Interactive PS session | No |
  | FileTransfer | Copy files to/from | No |
  | RegistryEdit | Modify registry | Yes |
  | ServiceControl | Start/Stop/Restart service | Depends |
  | ProcessKill | Terminate process | Yes |
  | ClearTemp | Clear temp files | No |
  | FlushDNS | Clear DNS cache | No |
  | GPUpdate | Force Group Policy update | No |

#### Script-Executor.ps1
- **Purpose:** Run custom scripts on endpoints
- **Features:**
  - Script library management
  - Parameter passing
  - Output capture and logging
  - Timeout handling
  - Credential injection (secure)
  - Pre/post execution hooks
  - Rollback scripts

#### Update-Manager.ps1
- **Purpose:** Windows and application updates
- **Capabilities:**
  - Scan for Windows Updates
  - Install Windows Updates (with scheduling)
  - Reboot scheduling (maintenance windows)
  - WinGet package updates
  - Driver updates (optional)
  - Feature update management
  - Update history tracking
  - Rollback support
- **Approval Workflow:**
  - Auto-approve by classification
  - Manual approval queue
  - Staged rollout (pilot → production)

#### Remediation-Engine.ps1
- **Purpose:** Automated issue remediation
- **Built-in Remediations:**
  - Clear temp files when disk low
  - Restart hung services
  - Reset Windows Update components
  - Clear print queue
  - Renew DHCP lease
  - Re-register DLLs
  - Fix WMI repository
  - Reset network stack
- **Custom Remediation:** Define in JSON with trigger conditions

### 5. Alerting System (scripts/alerts/)

#### Alert-Manager.ps1
- **Purpose:** Central alert processing
- **Alert Lifecycle:**
  ```
  Triggered → Active → [Acknowledged] → Resolved → Archived
  ```
- **Alert Deduplication:** Same alert type + device within 5 minutes = increment count
- **Alert Correlation:** Group related alerts (e.g., disk + performance = "Resource Exhaustion")
- **Auto-Resolution:** Automatically resolve when condition clears

#### Notification-Engine.ps1
- **Channels Supported:**
  | Channel | Configuration | Features |
  |---------|---------------|----------|
  | Email (SMTP) | Server, port, credentials | HTML templates, attachments |
  | Microsoft Teams | Webhook URL | Adaptive cards, action buttons |
  | Slack | Webhook URL | Rich formatting, threads |
  | PagerDuty | Integration key | Escalation, on-call routing |
  | SMS (Twilio) | Account SID, Auth token | Critical alerts only |
  | Webhook (Generic) | URL, headers | JSON payload, custom format |
  | Windows Event Log | Local/remote | For SIEM integration |
- **Notification Rules:**
  ```json
  {
      "rules": [
          {
              "name": "Critical to On-Call",
              "condition": { "severity": "Critical" },
              "channels": ["PagerDuty", "SMS"],
              "delay": 0
          },
          {
              "name": "High to Team",
              "condition": { "severity": "High" },
              "channels": ["Teams", "Email"],
              "delay": 300,
              "suppressDuplicates": true
          }
      ]
  }
  ```

#### Escalation-Handler.ps1
- **Purpose:** Time-based alert escalation
- **Features:**
  - Multi-tier escalation paths
  - Business hours awareness
  - On-call schedule integration
  - Escalation timeout (no response)
  - Manager override notifications

### 6. Reporting (scripts/reports/)

#### Report-Generator.ps1
- **Report Types:**
  | Report | Frequency | Format | Content |
  |--------|-----------|--------|---------|
  | Executive Summary | Weekly | HTML/PDF | Health scores, trends, top issues |
  | Device Inventory | Monthly | Excel | Complete asset list with details |
  | Alert Summary | Daily | HTML | Alert counts by severity/device |
  | Update Compliance | Weekly | HTML | Patch status across fleet |
  | Security Posture | Weekly | HTML/PDF | Security scores, vulnerabilities |
  | Performance Trends | Weekly | HTML | Resource utilization graphs |
  | Uptime Report | Monthly | HTML | Availability percentages |
  | Audit Log | On-demand | CSV | All actions with timestamps |

#### Compliance-Reporter.ps1
- **Purpose:** Compliance and baseline checking
- **Compliance Frameworks:**
  - CIS Benchmarks (Windows 10/11, Server)
  - NIST guidelines
  - Custom organizational policies
- **Output:** Compliance score, deviations list, remediation recommendations

#### Executive-Dashboard.ps1
- **Purpose:** Management-friendly overview
- **Metrics:**
  - Fleet health score (aggregate)
  - Active alerts by severity
  - Patch compliance percentage
  - Top 10 problematic devices
  - Trend charts (7/30/90 days)

### 7. Automation (scripts/automation/)

#### Policy-Engine.ps1
- **Purpose:** Apply configuration policies to device groups
- **Policy Types:**
  ```json
  {
      "policies": {
          "SecurityBaseline": {
              "targets": ["All Workstations"],
              "settings": {
                  "WindowsFirewall": "Enabled",
                  "BitLocker": "Required",
                  "ScreenLockTimeout": 300,
                  "PasswordMinLength": 12
              },
              "remediate": true,
              "schedule": "Daily"
          },
          "MaintenanceWindow": {
              "targets": ["Production Servers"],
              "settings": {
                  "AllowUpdates": false,
                  "AllowReboots": false
              },
              "activeHours": "06:00-22:00",
              "timezone": "America/New_York"
          }
      }
  }
  ```

#### Scheduled-Tasks.ps1
- **Purpose:** Manage RMM scheduled operations
- **Default Schedules:**
  | Task | Interval | Description |
  |------|----------|-------------|
  | Availability Check | 5 min | Ping all devices |
  | Health Metrics | 5 min | Collect performance data |
  | Full Inventory | Daily 2AM | Complete inventory scan |
  | Update Scan | Daily 3AM | Check for available updates |
  | Security Scan | Daily 4AM | Security posture check |
  | Report Generation | Weekly Sun 6AM | Generate weekly reports |
  | Data Cleanup | Daily 5AM | Prune old data per retention |
  | Database Maintenance | Weekly Sun 3AM | Vacuum SQLite, optimize |

#### Workflow-Orchestrator.ps1
- **Purpose:** Multi-step automated workflows
- **Example Workflows:**
  ```yaml
  OnboardNewDevice:
    trigger: "Device added to group 'New Devices'"
    steps:
      - name: "Verify Connectivity"
        action: "Test-WinRMConnection"
        onFailure: "notify-admin"
      - name: "Collect Initial Inventory"
        action: "Invoke-Inventory -Full"
      - name: "Apply Security Baseline"
        action: "Apply-Policy -Name SecurityBaseline"
      - name: "Install Required Software"
        action: "Install-RequiredApps"
      - name: "Move to Production Group"
        action: "Set-DeviceGroup -Group 'Production'"
      - name: "Notify IT"
        action: "Send-Notification -Channel Teams"

  PatchTuesday:
    trigger: "Schedule: Second Tuesday 10PM"
    steps:
      - name: "Scan All Devices"
        action: "Invoke-UpdateScan -All"
        parallel: true
      - name: "Install Updates - Pilot"
        action: "Install-Updates -Group Pilot"
        waitForReboot: true
      - name: "Verify Pilot Health"
        action: "Test-GroupHealth -Group Pilot"
        onFailure: "rollback-and-notify"
      - name: "Install Updates - Production"
        action: "Install-Updates -Group Production"
        delay: "24h"
  ```

### 8. User Interfaces (scripts/ui/)

#### Start-Console.ps1 - CLI Dashboard
```
╔══════════════════════════════════════════════════════════════════════╗
║                    myTech.Today RMM Console v2.0                     ║
╠══════════════════════════════════════════════════════════════════════╣
║  Fleet Status: 147/150 Online (98%)     Active Alerts: 3 (1 Critical)║
╠══════════════════════════════════════════════════════════════════════╣
║  [1] Device Management     [5] Update Management                     ║
║  [2] Real-Time Monitoring  [6] Remote Actions                        ║
║  [3] Alerts Dashboard      [7] Reports                               ║
║  [4] Inventory Browser     [8] Settings                              ║
║                            [0] Exit                                  ║
╚══════════════════════════════════════════════════════════════════════╝
Select option: _
```

#### Start-WebDashboard.ps1 - Web Interface
- **Technology:** Self-hosted HTTP listener (no IIS required)
- **Port:** 8080 (configurable)
- **Features:**
  - Responsive HTML5 dashboard
  - Real-time updates via polling/SSE
  - Device drill-down views
  - Alert management
  - Action execution
  - Report viewing
  - Mobile-friendly

---

## Scalability Architecture

### Performance Optimizations for 1000+ Endpoints

#### Parallel Processing
```powershell
# PS7+ parallel with throttling
$devices | ForEach-Object -Parallel {
    Invoke-Command -ComputerName $_.ComputerName -ScriptBlock $using:scriptBlock
} -ThrottleLimit 50

# PS5.1 fallback with runspace pools
$runspacePool = [RunspaceFactory]::CreateRunspacePool(1, 50)
$runspacePool.Open()
```

#### Connection Pooling
- Reuse WinRM sessions across multiple operations
- Session cache with TTL (configurable)
- Graceful session cleanup

#### Batch Operations
```powershell
# Group devices by site for network efficiency
$devicesBySite = $devices | Group-Object SiteId
foreach ($site in $devicesBySite) {
    Invoke-ParallelOperation -Devices $site.Group -ThrottleLimit 25
}
```

#### Caching Strategy
- Device status: 5-minute cache
- Inventory: 24-hour cache
- Configuration: Hot-reload on change
- Metrics: Write-through with batch commits

#### Database Optimization
- Indexed queries for common patterns
- Batch inserts for metrics (100 rows/commit)
- Automatic archival of old data
- Weekly VACUUM for SQLite maintenance

### Multi-Site Support

#### Relay Agent Architecture
```
Central Console ←── HTTPS ──→ Site Relay Agent ←── WinRM ──→ Local Endpoints
                                      ↓
                               Local Cache DB
                               (sync on schedule)
```

#### Site Configuration
```json
{
    "sites": [
        {
            "siteId": "site-alpha",
            "name": "Headquarters",
            "relayAgent": null,
            "directConnect": true
        },
        {
            "siteId": "site-beta",
            "name": "Remote Office",
            "relayAgent": "relay-beta.domain.com",
            "syncInterval": 300,
            "queuedActions": true
        }
    ]
}
```

---

## Security Model

### Authentication & Authorization
- Windows Authentication (Kerberos/NTLM)
- Credential encryption using DPAPI
- Per-device credential override support
- Role-based access control (Admin, Operator, Viewer)

### Credential Management
```powershell
# Secure credential storage
$credential = Get-Credential
$credential | Export-Clixml -Path "$PSScriptRoot/../secrets/credentials.xml"

# Retrieval with scope protection
$credential = Import-Clixml -Path "$PSScriptRoot/../secrets/credentials.xml"
```

### Audit Logging
- All actions logged with user, timestamp, target
- Immutable audit trail (append-only)
- Export capability for compliance

### Network Security
- WinRM over HTTPS recommended
- Firewall rules documentation
- Network segmentation support
- No inbound connections required (pull model)

---

## Implementation Guidelines

### Coding Standards
- Follow myTech.Today PowerShell guidelines (see .augment/core-guidelines.md)
- Verb-Noun naming convention
- Comprehensive comment-based help
- Parameter validation on all functions
- ASCII-only output (no emoji)
- Centralized logging to `%USERPROFILE%\myTech.Today\logs\`

### Error Handling
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

### Testing Requirements
- Unit tests for all core functions (Pester 5.x)
- Integration tests with mock devices
- Performance tests for scale validation
- Target: 80% code coverage

### Documentation
- README.md: Quick start, feature matrix, screenshots
- docs/Setup-Guide.md: Detailed installation
- docs/Architecture.md: System design
- docs/API-Reference.md: Function documentation
- docs/Scaling-Guide.md: Performance tuning
- docs/Troubleshooting.md: Common issues

---

## Feature Comparison

| Feature | myTech.Today RMM | Commercial RMM |
|---------|------------------|----------------|
| Device Inventory | ✓ Full | ✓ Full |
| Real-Time Monitoring | ✓ 5-min intervals | ✓ Real-time |
| Alerting | ✓ Multi-channel | ✓ Multi-channel |
| Remote Actions | ✓ Core actions | ✓ Extensive |
| Patch Management | ✓ Windows + WinGet | ✓ Full |
| Remote Desktop | ✓ RDP launch | ✓ Integrated |
| Scripting | ✓ PowerShell | ✓ Multi-language |
| Reporting | ✓ HTML/Excel | ✓ Full suite |
| Web Dashboard | ✓ Basic | ✓ Full-featured |
| Mobile App | ✗ | ✓ |
| Multi-tenant | ✗ | ✓ |
| EDR/Security | ✓ Basic | ✓ Advanced |
| Backup Integration | ✗ | ✓ |
| Billing/PSA | ✗ | ✓ |
| **Cost** | **Free** | **$2-5/endpoint/mo** |
| **Coverage** | **~70%** | **100%** |

---

## Quick Start

```powershell
# 1. Clone repository
git clone https://github.com/mytech-today-now/RMM.git
cd RMM

# 2. Run initialization (as Administrator)
.\scripts\core\Initialize-RMM.ps1 -Mode Install

# 3. Import devices from CSV
.\scripts\core\Initialize-RMM.ps1 -ImportDevices .\sample-devices.csv

# 4. Start the console
.\scripts\ui\Start-Console.ps1

# 5. Or start web dashboard
.\scripts\ui\Start-WebDashboard.ps1 -Port 8080
```

---

## Generation Instructions

Generate the entire repository with the following structure and complete, production-ready code:

1. Create folder structure as defined above
2. Generate each script with:
   - Full comment-based help (.SYNOPSIS, .DESCRIPTION, .PARAMETER, .EXAMPLE)
   - Parameter validation
   - Error handling (try/catch)
   - Logging integration
   - Progress indicators for long operations
3. Create sample configuration files
4. Create sample device CSV with 10 test devices
5. Generate comprehensive README.md
6. Generate .gitignore (exclude data/, logs/, secrets/)
7. Generate Pester tests for core functions
8. Ensure zero-config ready: `Initialize-RMM.ps1` handles all setup

**Target Metrics:**
- Initial deployment: < 15 minutes
- First inventory collection: < 5 minutes for 150 devices
- Alert response time: < 60 seconds
- Web dashboard load: < 3 seconds
