<#
.SYNOPSIS
    Initialize the RMM SQLite database with schema and default data.

.DESCRIPTION
    Creates the SQLite database for the myTech.Today RMM system with all required tables,
    indexes, and default data. This script is idempotent and can be run multiple times safely.

.PARAMETER DatabasePath
    Path to the SQLite database file. Default: .\data\devices.db

.PARAMETER Force
    Force recreation of the database (WARNING: This will delete all existing data)

.PARAMETER SkipDefaultData
    Skip insertion of default site and sample data

.EXAMPLE
    .\Initialize-Database.ps1
    Creates the database with default settings

.EXAMPLE
    .\Initialize-Database.ps1 -DatabasePath "C:\RMM\data\devices.db" -Force
    Recreates the database at the specified path

.NOTES
    Author: Kyle C. Rode (myTech.Today)
    Version: 2.0
    Requires: PSSQLite module
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$DatabasePath = "$PSScriptRoot\..\..\data\devices.db",

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$SkipDefaultData,

    [Parameter()]
    [switch]$Quiet
)

# Ensure PSSQLite module is available
if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
    Write-Host "Installing PSSQLite module..." -ForegroundColor Yellow
    try {
        Install-Module -Name PSSQLite -Force -Scope CurrentUser -ErrorAction Stop
        Write-Host "PSSQLite module installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install PSSQLite module: $_"
        exit 1
    }
}

Import-Module PSSQLite -ErrorAction Stop

# Resolve full path
$DatabasePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DatabasePath)
$DatabaseDir = Split-Path -Parent $DatabasePath

# Create directory if it doesn't exist
if (-not (Test-Path $DatabaseDir)) {
    Write-Host "Creating database directory: $DatabaseDir" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $DatabaseDir -Force | Out-Null
}

# Check if database exists
if ((Test-Path $DatabasePath) -and -not $Force) {
    if (-not $Quiet) {
        Write-Host "Database already exists at: $DatabasePath" -ForegroundColor Yellow
        Write-Host "Use -Force to recreate the database (WARNING: This will delete all data)" -ForegroundColor Yellow

        $response = Read-Host "Do you want to continue and verify the schema? (Y/N)"
        if ($response -ne 'Y') {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            exit 0
        }
    }
    # In Quiet mode, just continue and verify schema
}
elseif ((Test-Path $DatabasePath) -and $Force) {
    Write-Host "Removing existing database..." -ForegroundColor Yellow
    Remove-Item -Path $DatabasePath -Force
}

Write-Host "Initializing RMM database at: $DatabasePath" -ForegroundColor Cyan
Write-Host ""

# SQL Schema
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
    ContactName TEXT,
    ContactEmail TEXT,
    MainPhone TEXT,
    CellPhone TEXT,
    StreetNumber TEXT,
    StreetName TEXT,
    Unit TEXT,
    Building TEXT,
    City TEXT,
    State TEXT,
    Zip TEXT,
    Country TEXT,
    Notes TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS SiteURLs (
    URLId INTEGER PRIMARY KEY AUTOINCREMENT,
    SiteId TEXT NOT NULL,
    URL TEXT NOT NULL,
    Label TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (SiteId) REFERENCES Sites(SiteId) ON DELETE CASCADE
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
    Username TEXT,
    Role TEXT,
    Action TEXT NOT NULL,
    TargetDevices TEXT,
    Result TEXT DEFAULT 'Success',
    IPAddress TEXT,
    Details TEXT
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

Write-Host "Creating database tables..." -ForegroundColor Cyan

try {
    # Execute schema
    Invoke-SqliteQuery -DataSource $DatabasePath -Query $schema -ErrorAction Stop
    Write-Host "[OK] Database tables created successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to create database tables: $_"
    exit 1
}

# Insert default data
if (-not $SkipDefaultData) {
    Write-Host ""
    Write-Host "Inserting default data..." -ForegroundColor Cyan

    # Check if default site exists
    $existingSite = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Sites WHERE SiteId = 'main'" -ErrorAction Stop

    if ($existingSite.Count -eq 0) {
        $defaultSite = @"
INSERT INTO Sites (SiteId, Name, Location, Timezone, ContactEmail)
VALUES ('main', 'Main Site', 'Primary Location', 'UTC', 'admin@mytech.today');
"@
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $defaultSite -ErrorAction Stop
        Write-Host "[OK] Default site created" -ForegroundColor Green
    }
    else {
        Write-Host "[SKIP] Default site already exists" -ForegroundColor Yellow
    }
}

# Verify database
Write-Host ""
Write-Host "Verifying database..." -ForegroundColor Cyan

$tables = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;" -ErrorAction Stop
$indexes = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%' ORDER BY name;" -ErrorAction Stop

Write-Host "[OK] Tables created: $($tables.Count)" -ForegroundColor Green
foreach ($table in $tables) {
    Write-Host "  - $($table.name)" -ForegroundColor Gray
}

Write-Host "[OK] Indexes created: $($indexes.Count)" -ForegroundColor Green
foreach ($index in $indexes) {
    Write-Host "  - $($index.name)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Database initialization complete!" -ForegroundColor Green
Write-Host "Database location: $DatabasePath" -ForegroundColor Cyan
Write-Host ""

