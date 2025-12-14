# PROMPT 02: Database Schema & Architecture Setup

**Previous:** [01-repository-structure.md](01-repository-structure.md) - Complete that first

---

## Your Task

Create the SQLite database schema and architecture documentation. This establishes the data model that all modules will use.

---

## Step 1: Understand the Architecture

The RMM system uses a **Hybrid Pull/Push Model**:

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

---

## Communication Methods

| Method | Use Case | Port | Scalability |
|--------|----------|------|-------------|
| WinRM (HTTP) | Internal Windows | 5985 | Up to 500/batch |
| WinRM (HTTPS) | Secure/External | 5986 | Up to 500/batch |
| SSH | Linux/macOS/Cross-platform | 22 | Up to 200/batch |
| SMB Fallback | Firewalled devices | 445 | File-based queue |
| Relay Agent | Remote sites | Custom | Unlimited (queued) |

---

## Data Storage Architecture

### Tiered Storage Model

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

---

## Step 2: Create Database Schema Script

Create `RMM/scripts/core/Initialize-Database.ps1` with the complete SQLite schema:

```powershell
<#
.SYNOPSIS
    Initialize the RMM SQLite database with schema.

.DESCRIPTION
    Creates the SQLite database and all required tables, indexes, and initial data.

.PARAMETER DatabasePath
    Path to the SQLite database file. Default: ../data/devices.db

.EXAMPLE
    .\Initialize-Database.ps1

.NOTES
    Author: Kyle C. Rode
    Company: myTech.Today
#>
[CmdletBinding()]
param (
    [Parameter()]
    [string]$DatabasePath = "$PSScriptRoot/../../data/devices.db"
)

# Ensure PSSQLite module is available
if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
    Write-Host "Installing PSSQLite module..." -ForegroundColor Yellow
    Install-Module -Name PSSQLite -Force -Scope CurrentUser
}

Import-Module PSSQLite

# Create data directory if it doesn't exist
$dataDir = Split-Path -Parent $DatabasePath
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

Write-Host "Initializing database at: $DatabasePath" -ForegroundColor Cyan

# Database schema
$schema = @"
-- Core Tables
CREATE TABLE IF NOT EXISTS Devices (
    DeviceId TEXT PRIMARY KEY,
    Hostname TEXT NOT NULL,
    FQDN TEXT,
    IPAddress TEXT,
    MACAddress TEXT,
    SiteId TEXT,
    GroupIds TEXT,
    OSName TEXT,
    OSVersion TEXT,
    OSBuild TEXT,
    LastSeen DATETIME,
    LastInventory DATETIME,
    Status TEXT DEFAULT 'Unknown',
    AgentVersion TEXT,
    Tags TEXT,
    CustomFields TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS Sites (
    SiteId TEXT PRIMARY KEY,
    Name TEXT NOT NULL,
    Location TEXT,
    Timezone TEXT,
    RelayAgent TEXT,
    ContactEmail TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS DeviceGroups (
    GroupId TEXT PRIMARY KEY,
    Name TEXT NOT NULL,
    Description TEXT,
    ParentGroupId TEXT,
    PolicyId TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS Inventory (
    InventoryId INTEGER PRIMARY KEY AUTOINCREMENT,
    DeviceId TEXT NOT NULL,
    Category TEXT NOT NULL,
    Data TEXT NOT NULL,
    CollectedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

CREATE TABLE IF NOT EXISTS Alerts (
    AlertId TEXT PRIMARY KEY,
    DeviceId TEXT NOT NULL,
    AlertType TEXT NOT NULL,
    Severity TEXT NOT NULL,
    Title TEXT NOT NULL,
    Message TEXT,
    Source TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    AcknowledgedAt DATETIME,
    AcknowledgedBy TEXT,
    ResolvedAt DATETIME,
    ResolvedBy TEXT,
    AutoResolved INTEGER DEFAULT 0,
    NotificationsSent TEXT,
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

CREATE TABLE IF NOT EXISTS Actions (
    ActionId TEXT PRIMARY KEY,
    DeviceId TEXT,
    ActionType TEXT NOT NULL,
    Status TEXT DEFAULT 'Pending',
    Priority INTEGER DEFAULT 5,
    Payload TEXT,
    Result TEXT,
    ScheduledAt DATETIME,
    StartedAt DATETIME,
    CompletedAt DATETIME,
    CreatedBy TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS Metrics (
    MetricId INTEGER PRIMARY KEY AUTOINCREMENT,
    DeviceId TEXT NOT NULL,
    MetricType TEXT NOT NULL,
    Value REAL NOT NULL,
    Unit TEXT,
    Timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

CREATE TABLE IF NOT EXISTS AuditLog (
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
CREATE INDEX IF NOT EXISTS idx_devices_status ON Devices(Status);
CREATE INDEX IF NOT EXISTS idx_devices_site ON Devices(SiteId);
CREATE INDEX IF NOT EXISTS idx_inventory_device ON Inventory(DeviceId);
CREATE INDEX IF NOT EXISTS idx_inventory_date ON Inventory(CollectedAt);
CREATE INDEX IF NOT EXISTS idx_alerts_device ON Alerts(DeviceId);
CREATE INDEX IF NOT EXISTS idx_alerts_severity ON Alerts(Severity);
CREATE INDEX IF NOT EXISTS idx_alerts_created ON Alerts(CreatedAt);
CREATE INDEX IF NOT EXISTS idx_actions_status ON Actions(Status);
CREATE INDEX IF NOT EXISTS idx_actions_device ON Actions(DeviceId);
CREATE INDEX IF NOT EXISTS idx_metrics_device_type ON Metrics(DeviceId, MetricType);
CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON Metrics(Timestamp);
"@

try {
    # Execute schema
    Invoke-SqliteQuery -DataSource $DatabasePath -Query $schema

    # Insert default site
    $insertSite = @"
INSERT OR IGNORE INTO Sites (SiteId, Name, Location, Timezone)
VALUES ('main', 'Main Site', 'Default', 'UTC');
"@
    Invoke-SqliteQuery -DataSource $DatabasePath -Query $insertSite

    Write-Host "Database initialized successfully!" -ForegroundColor Green
    Write-Host "Location: $DatabasePath" -ForegroundColor Gray
}
catch {
    Write-Error "Failed to initialize database: $_"
    throw
}
```

---

## Step 3: Create Architecture Documentation

Create `RMM/docs/Architecture.md` documenting the system architecture (reference the diagrams from the original 02-architecture.md for content).

---

## Validation

After completing this prompt, verify:

- [ ] `Initialize-Database.ps1` script is created
- [ ] Script runs without errors
- [ ] `data/devices.db` file is created
- [ ] Database contains all 8 tables
- [ ] All indexes are created
- [ ] Default site is inserted
- [ ] `docs/Architecture.md` is created

Test the database:

```powershell
# Run the initialization
.\scripts\core\Initialize-Database.ps1

# Verify tables exist
Import-Module PSSQLite
$tables = Invoke-SqliteQuery -DataSource ".\data\devices.db" -Query "SELECT name FROM sqlite_master WHERE type='table';"
$tables
```

---

**NEXT PROMPT:** [modules/03-core-framework.md](modules/03-core-framework.md) - Build the core framework

---

*This is prompt 3 of 13 in the RMM build sequence*

