<#
.SYNOPSIS
    Automated installer for myTech.Today RMM.

.DESCRIPTION
    Fully automated installation following Microsoft best practices:

    Program Files (read-only binaries):
        C:\Program Files (x86)\myTech.Today\RMM\

    Application Data (writable data, config, logs):
        C:\ProgramData\myTech.Today\RMM\data\
        C:\ProgramData\myTech.Today\RMM\config\
        C:\ProgramData\myTech.Today\RMM\logs\

    PowerShell Module (system-wide):
        C:\Program Files\WindowsPowerShell\Modules\RMM\

    The installer:
    1. Copies production RMM files to Program Files
    2. Installs dependencies (PSSQLite, ImportExcel, PSWriteHTML)
    3. Initializes the database in ProgramData
    4. Creates configuration files
    5. Registers the RMM PowerShell module system-wide
    6. Creates Desktop and Start Menu shortcuts

    After installation, use: Import-Module RMM

.PARAMETER Force
    Overwrite existing installation without prompting.

.PARAMETER Uninstall
    Remove the RMM installation.

.EXAMPLE
    .\Install.ps1
    Performs full automated installation.

.EXAMPLE
    .\Install.ps1 -Force
    Reinstalls, overwriting existing files.

.EXAMPLE
    .\Install.ps1 -Uninstall
    Removes the RMM installation.

.NOTES
    Author: myTech.Today
    Version: 2.1.0
    Requires: Administrator privileges for standard installation paths
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Uninstall
)

# PowerShell 7+ Version Check - myTech.Today standard
$script:PS7ContinueOnPS51 = $true  # Allow running on PS 5.1 with warning
$script:PS7Silent = $false
$script:_RepoRoot = $PSScriptRoot
while ($script:_RepoRoot -and -not (Test-Path (Join-Path $script:_RepoRoot 'scripts\Require-PowerShell7.ps1'))) {
    $script:_RepoRoot = Split-Path $script:_RepoRoot -Parent
}
if ($script:_RepoRoot -and (Test-Path (Join-Path $script:_RepoRoot 'scripts\Require-PowerShell7.ps1'))) {
    . (Join-Path $script:_RepoRoot 'scripts\Require-PowerShell7.ps1')
}

$ErrorActionPreference = 'Stop'

#region Path Configuration
# Source directory (where the installer is run from)
$SourceRoot = $PSScriptRoot

# Program Files - read-only application binaries
$ProgramFilesRoot = "${env:ProgramFiles(x86)}\myTech.Today"
$RMMInstallPath = "$ProgramFilesRoot\RMM"

# ProgramData - writable application data (works for SYSTEM and all users)
$ProgramDataRoot = "$env:ProgramData\myTech.Today\RMM"
$DataPath = "$ProgramDataRoot\data"
$ConfigPath = "$ProgramDataRoot\config"
$LogPath = "$ProgramDataRoot\logs"

# PowerShell module - system-wide location
$ModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules\RMM"

# Shortcuts
$PublicDesktop = "$env:PUBLIC\Desktop"
$StartMenuFolder = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\myTech.Today"

# Folders to EXCLUDE from deployment (dev/test artifacts)
$ExcludedItems = @(
    '.augment',
    'ai-prompts',
    'tests',
    'secrets',
    'sample-devices.csv',
    '.git',
    '.gitignore',
    '.vscode',
    'node_modules',
    '*.md',       # README, etc.
    'LICENSE'
)
#endregion

#region Helper Functions
function Show-Banner {
    param([string]$Title, [string]$Color = "Cyan")
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor $Color
    Write-Host "  $Title" -ForegroundColor White
    Write-Host ("=" * 60) -ForegroundColor $Color
    Write-Host ""
}

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "[$Step] $Message" -ForegroundColor Yellow
}

function Write-OK {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Set-DirectoryAcl {
    param(
        [string]$Path,
        [string]$Access = "Modify"  # FullControl, Modify, ReadAndExecute
    )
    try {
        $acl = Get-Acl $Path
        # Grant SYSTEM full control
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($systemRule)

        # Grant Administrators full control
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($adminRule)

        # Grant Users specified access
        $usersRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Users", $Access, "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($usersRule)

        Set-Acl -Path $Path -AclObject $acl
    } catch {
        Write-Warn "Could not set ACL on $Path : $_"
    }
}
#endregion

#region Uninstall
if ($Uninstall) {
    Show-Banner "myTech.Today RMM - Uninstall" "Red"

    Write-Step "1/5" "Stopping RMM services..."
    Get-Process -Name pwsh, powershell -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*Start-WebDashboard*" -or $_.CommandLine -like "*RMM*" } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Write-OK "Services stopped"

    Write-Step "2/5" "Removing shortcuts..."

    # Remove Public Desktop shortcut
    $dashboardShortcut = Join-Path $PublicDesktop "mTT RMM Dashboard.lnk"
    $clientShortcut = Join-Path $PublicDesktop "mTT RMM Client.lnk"
    @($dashboardShortcut, $clientShortcut) | ForEach-Object {
        if (Test-Path $_) {
            Remove-Item -Path $_ -Force
            Write-OK "Removed: $_"
        }
    }

    # Remove Start Menu folder
    if (Test-Path $StartMenuFolder) {
        Remove-Item -Path $StartMenuFolder -Recurse -Force
        Write-OK "Start Menu folder removed: $StartMenuFolder"
    }

    Write-Step "3/5" "Removing PowerShell module..."
    if (Test-Path $ModulePath) {
        Remove-Item -Path $ModulePath -Recurse -Force
        Write-OK "Module removed: $ModulePath"
    } else {
        Write-Info "Module not found (already removed)"
    }

    Write-Step "4/5" "Removing program files..."
    if (Test-Path $RMMInstallPath) {
        Remove-Item -Path $RMMInstallPath -Recurse -Force
        Write-OK "Program files removed: $RMMInstallPath"
    }
    # Clean up parent folder if empty
    if ((Test-Path $ProgramFilesRoot) -and (Get-ChildItem $ProgramFilesRoot -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item -Path $ProgramFilesRoot -Force
    }

    Write-Step "5/5" "User data..."
    Write-Info "Data preserved at: $ProgramDataRoot"
    Write-Host ""
    Write-Host "To completely remove all data, run:" -ForegroundColor Yellow
    Write-Host "  Remove-Item -Path '$ProgramDataRoot' -Recurse -Force" -ForegroundColor White
    Write-Host ""

    Show-Banner "Uninstall Complete" "Green"
    exit 0
}
#endregion

#region Main Installation
Show-Banner "myTech.Today RMM - Enterprise Installation"

Write-Host "Installation Paths:" -ForegroundColor Cyan
Write-Host "  Program Files: $RMMInstallPath" -ForegroundColor Gray
Write-Host "  Data/Config:   $ProgramDataRoot" -ForegroundColor Gray
Write-Host "  PS Module:     $ModulePath" -ForegroundColor Gray
Write-Host ""

# Clear any cached RMM module from current session to prevent stale module issues
if (Get-Module -Name RMM -ErrorAction SilentlyContinue) {
    Remove-Module -Name RMM -Force -ErrorAction SilentlyContinue
    Write-Info "Cleared cached RMM module from session"
}

# Clear PowerShell module analysis cache to ensure fresh module loading after install
$moduleAnalysisCache = "$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\ModuleAnalysisCache"
if (Test-Path $moduleAnalysisCache) {
    Remove-Item -Path $moduleAnalysisCache -Force -ErrorAction SilentlyContinue
    Write-Info "Cleared module analysis cache"
}

# Check for existing installation
if ((Test-Path $RMMInstallPath) -and -not $Force) {
    Write-Host "RMM is already installed at: $RMMInstallPath" -ForegroundColor Yellow
    $response = Read-Host "Overwrite existing installation? (Y/N)"
    if ($response -notmatch '^[Yy]') {
        Write-Host "Installation cancelled." -ForegroundColor Red
        exit 1
    }
}

#region Step 1: Install Dependencies
Write-Step "1/7" "Installing PowerShell dependencies..."

$requiredModules = @('PSSQLite', 'ImportExcel', 'PSWriteHTML')
foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Info "Installing $mod..."
        try {
            # Install system-wide when running as admin
            Install-Module -Name $mod -Force -Scope AllUsers -AllowClobber -ErrorAction Stop
            Write-OK "$mod installed (AllUsers)"
        } catch {
            try {
                Install-Module -Name $mod -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
                Write-OK "$mod installed (CurrentUser)"
            } catch {
                Write-Warn "Failed to install $mod - some features may not work"
            }
        }
    } else {
        Write-Info "$mod already installed"
    }
}
Write-OK "Dependencies ready"
#endregion

#region Step 2: Create Directory Structure
Write-Step "2/7" "Creating directory structure..."

# Program Files directories (read-only)
$programDirs = @(
    $ProgramFilesRoot,
    $RMMInstallPath,
    "$RMMInstallPath\scripts",
    "$RMMInstallPath\scripts\core",
    "$RMMInstallPath\scripts\ui",
    "$RMMInstallPath\scripts\collectors",
    "$RMMInstallPath\scripts\monitors",
    "$RMMInstallPath\scripts\actions",
    "$RMMInstallPath\scripts\automation",
    "$RMMInstallPath\scripts\alerts",
    "$RMMInstallPath\scripts\reports",
    "$RMMInstallPath\docs"
)

# ProgramData directories (writable)
$dataDirs = @(
    $ProgramDataRoot,
    $DataPath,
    "$DataPath\cache",
    "$DataPath\queue",
    "$DataPath\archive",
    "$DataPath\backups",
    $LogPath,
    "$LogPath\devices",
    "$LogPath\web",
    $ConfigPath,
    "$ConfigPath\policies"
)

foreach ($dir in $programDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}
Write-OK "Program directories created"

foreach ($dir in $dataDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Set appropriate ACLs on ProgramData directories
Set-DirectoryAcl -Path $ProgramDataRoot -Access "Modify"
Write-OK "Data directories created with proper ACLs"
#endregion

#region Step 3: Copy RMM Files (Production Only)
Write-Step "3/7" "Copying production files..."

# Copy scripts folder (the core application)
$scriptsSource = Join-Path $SourceRoot "scripts"
$scriptsDest = Join-Path $RMMInstallPath "scripts"

if (Test-Path $scriptsSource) {
    if (Test-Path $scriptsDest) {
        Remove-Item -Path $scriptsDest -Recurse -Force
    }
    Copy-Item -Path $scriptsSource -Destination $scriptsDest -Recurse -Force
    Write-OK "Scripts copied"
}

# Copy docs folder (user documentation only)
$docsSource = Join-Path $SourceRoot "docs"
$docsDest = Join-Path $RMMInstallPath "docs"

if (Test-Path $docsSource) {
    if (Test-Path $docsDest) {
        Remove-Item -Path $docsDest -Recurse -Force
    }
    Copy-Item -Path $docsSource -Destination $docsDest -Recurse -Force
    Write-OK "Documentation copied"
}

# Copy config templates to ProgramData (if not already present)
$configSource = Join-Path $SourceRoot "config"
if (Test-Path $configSource) {
    # Copy policy templates
    $policiesSource = Join-Path $configSource "policies"
    $policiesDest = Join-Path $ConfigPath "policies"
    if (Test-Path $policiesSource) {
        Copy-Item -Path "$policiesSource\*" -Destination $policiesDest -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Copy thresholds.json if not exists
    $thresholdsSource = Join-Path $configSource "thresholds.json"
    $thresholdsDest = Join-Path $ConfigPath "thresholds.json"
    if ((Test-Path $thresholdsSource) -and -not (Test-Path $thresholdsDest)) {
        Copy-Item -Path $thresholdsSource -Destination $thresholdsDest -Force
    }

    # Copy groups.json if not exists
    $groupsSource = Join-Path $configSource "groups.json"
    $groupsDest = Join-Path $ConfigPath "groups.json"
    if ((Test-Path $groupsSource) -and -not (Test-Path $groupsDest)) {
        Copy-Item -Path $groupsSource -Destination $groupsDest -Force
    }

    Write-OK "Configuration templates copied"
}

Write-Info "Excluded from deployment: ai-prompts, tests, secrets, sample-devices.csv, .augment"
Write-OK "Production files installed to: $RMMInstallPath"
#endregion

#region Step 4: Initialize Database
Write-Step "4/7" "Initializing database..."

$dbPath = "$DataPath\devices.db"
Import-Module PSSQLite -Force

$schema = @"
-- Core device management
CREATE TABLE IF NOT EXISTS Devices (
    DeviceId TEXT PRIMARY KEY,
    Hostname TEXT NOT NULL UNIQUE,
    FQDN TEXT,
    IPAddress TEXT,
    MACAddress TEXT,
    Status TEXT DEFAULT 'Unknown',
    LastSeen TEXT,
    SiteId TEXT DEFAULT 'default',
    DeviceType TEXT DEFAULT 'Workstation',
    OSName TEXT,
    OSVersion TEXT,
    OSBuild TEXT,
    Manufacturer TEXT,
    Model TEXT,
    SerialNumber TEXT,
    AgentVersion TEXT,
    Tags TEXT,
    Description TEXT,
    Notes TEXT,
    CredentialName TEXT,
    AdminUsername TEXT,
    AdminPasswordEncrypted TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Alerts and notifications
CREATE TABLE IF NOT EXISTS Alerts (
    AlertId TEXT PRIMARY KEY,
    DeviceId TEXT,
    AlertType TEXT,
    Severity TEXT DEFAULT 'Medium',
    Title TEXT,
    Message TEXT,
    Source TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    AcknowledgedAt TEXT,
    AcknowledgedBy TEXT,
    ResolvedAt TEXT,
    ResolvedBy TEXT,
    AutoResolved INTEGER DEFAULT 0,
    NotificationsSent TEXT,
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

-- Remote actions
CREATE TABLE IF NOT EXISTS Actions (
    ActionId TEXT PRIMARY KEY,
    DeviceId TEXT,
    ActionType TEXT,
    Parameters TEXT,
    Status TEXT DEFAULT 'Pending',
    Priority INTEGER DEFAULT 5,
    Result TEXT,
    ErrorMessage TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    StartedAt TEXT,
    CompletedAt TEXT,
    CreatedBy TEXT,
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

-- Performance metrics
CREATE TABLE IF NOT EXISTS Metrics (
    MetricId INTEGER PRIMARY KEY AUTOINCREMENT,
    DeviceId TEXT,
    MetricType TEXT,
    Value REAL,
    Unit TEXT,
    Timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

-- Hardware/software inventory
CREATE TABLE IF NOT EXISTS Inventory (
    InventoryId INTEGER PRIMARY KEY AUTOINCREMENT,
    DeviceId TEXT,
    Category TEXT,
    ItemName TEXT,
    ItemValue TEXT,
    Data TEXT,
    CollectedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

-- Audit logging
CREATE TABLE IF NOT EXISTS AuditLog (
    LogId INTEGER PRIMARY KEY AUTOINCREMENT,
    Timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    User TEXT,
    Role TEXT,
    Action TEXT,
    Target TEXT,
    Details TEXT,
    Result TEXT,
    IPAddress TEXT
);

-- Sites/locations
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
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Site URLs (one-to-many)
CREATE TABLE IF NOT EXISTS SiteURLs (
    URLId INTEGER PRIMARY KEY AUTOINCREMENT,
    SiteId TEXT NOT NULL,
    URL TEXT NOT NULL,
    Label TEXT,
    Username TEXT,
    EncryptedPassword TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (SiteId) REFERENCES Sites(SiteId) ON DELETE CASCADE
);

-- Device URLs (one-to-many)
CREATE TABLE IF NOT EXISTS DeviceURLs (
    URLId INTEGER PRIMARY KEY AUTOINCREMENT,
    DeviceId TEXT NOT NULL,
    URL TEXT NOT NULL,
    Label TEXT,
    Username TEXT,
    EncryptedPassword TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId) ON DELETE CASCADE
);

-- Device groups
CREATE TABLE IF NOT EXISTS DeviceGroups (
    GroupId TEXT PRIMARY KEY,
    Name TEXT NOT NULL,
    Description TEXT,
    Query TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Default site
INSERT OR IGNORE INTO Sites (SiteId, Name, Location) VALUES ('default', 'Default Site', 'Primary Location');

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_devices_status ON Devices(Status);
CREATE INDEX IF NOT EXISTS idx_devices_site ON Devices(SiteId);
CREATE INDEX IF NOT EXISTS idx_alerts_device ON Alerts(DeviceId);
CREATE INDEX IF NOT EXISTS idx_alerts_severity ON Alerts(Severity);
CREATE INDEX IF NOT EXISTS idx_actions_device ON Actions(DeviceId);
CREATE INDEX IF NOT EXISTS idx_actions_status ON Actions(Status);
CREATE INDEX IF NOT EXISTS idx_metrics_device ON Metrics(DeviceId);
CREATE INDEX IF NOT EXISTS idx_metrics_type ON Metrics(MetricType);
"@

Invoke-SqliteQuery -DataSource $dbPath -Query $schema

# Migration: Add new columns to existing databases
$migrations = @(
    "ALTER TABLE Devices ADD COLUMN FQDN TEXT",
    "ALTER TABLE Devices ADD COLUMN Description TEXT",
    "ALTER TABLE Devices ADD COLUMN CredentialName TEXT",
    "ALTER TABLE Alerts ADD COLUMN AutoResolved INTEGER DEFAULT 0",
    "ALTER TABLE Alerts ADD COLUMN NotificationsSent TEXT"
)
foreach ($migration in $migrations) {
    try {
        Invoke-SqliteQuery -DataSource $dbPath -Query $migration -ErrorAction SilentlyContinue
    } catch {
        # Column already exists, ignore
    }
}

Write-OK "Database initialized: $dbPath"

# Auto-register the local computer as a device in the default site with full system info
Write-Info "Registering local computer in default site..."
try {
    $deviceId = [guid]::NewGuid().ToString()
    $hostname = $env:COMPUTERNAME
    $ipAddress = $null
    $macAddress = $null
    $fqdn = $null
    $deviceType = "Workstation"
    $osName = $null
    $osVersion = $null
    $osBuild = $null
    $manufacturer = $null
    $model = $null
    $serialNumber = $null

    # Get FQDN
    try {
        $fqdn = [System.Net.Dns]::GetHostEntry($hostname).HostName
    } catch { $fqdn = $hostname }

    # Get primary IP and MAC address
    try {
        $adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
                   Where-Object { $_.Status -eq 'Up' } |
                   Select-Object -First 1
        if ($adapter) {
            $macAddress = $adapter.MacAddress
            $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
                        Select-Object -First 1
            if ($ipConfig) { $ipAddress = $ipConfig.IPAddress }
        }
    } catch { }

    # Fallback IP detection
    if (-not $ipAddress) {
        try {
            $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -ne 'WellKnown' } |
                  Select-Object -First 1
            if ($ip) { $ipAddress = $ip.IPAddress }
        } catch { }
    }

    # Get OS information
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $osName = $os.Caption
            $osVersion = $os.Version
            $osBuild = $os.BuildNumber
            if ($os.ProductType -eq 2 -or $os.ProductType -eq 3) {
                $deviceType = "Server"
            }
        }
    } catch { }

    # Get hardware information
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs) {
            $manufacturer = $cs.Manufacturer
            $model = $cs.Model
            # Refine device type
            switch ($cs.PCSystemType) {
                1 { if ($deviceType -ne "Server") { $deviceType = "Desktop" } }
                2 { $deviceType = "Laptop" }
                3 { if ($deviceType -ne "Server") { $deviceType = "Workstation" } }
                4 { $deviceType = "Server" }
                5 { $deviceType = "Server" }
            }
            # Check for virtual machine
            if ($model -match 'Virtual|VMware|Hyper-V|VirtualBox|QEMU|KVM') {
                $deviceType = "Virtual"
            }
        }
    } catch { }

    # Get serial number from BIOS
    try {
        $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
        if ($bios) { $serialNumber = $bios.SerialNumber }
    } catch { }

    # Check if device with this hostname already exists
    $existingDevice = Invoke-SqliteQuery -DataSource $dbPath -Query "SELECT DeviceId FROM Devices WHERE Hostname = @Hostname" -SqlParameters @{ Hostname = $hostname }

    if ($existingDevice) {
        # Update existing device with current system info
        $updateQuery = @"
UPDATE Devices SET
    FQDN = @FQDN,
    IPAddress = @IPAddress,
    MACAddress = @MACAddress,
    DeviceType = @DeviceType,
    OSName = @OSName,
    OSVersion = @OSVersion,
    OSBuild = @OSBuild,
    Manufacturer = @Manufacturer,
    Model = @Model,
    SerialNumber = @SerialNumber,
    Status = 'Online',
    LastSeen = CURRENT_TIMESTAMP,
    UpdatedAt = CURRENT_TIMESTAMP
WHERE Hostname = @Hostname
"@
        Invoke-SqliteQuery -DataSource $dbPath -Query $updateQuery -SqlParameters @{
            Hostname = $hostname
            FQDN = $fqdn
            IPAddress = $ipAddress
            MACAddress = $macAddress
            DeviceType = $deviceType
            OSName = $osName
            OSVersion = $osVersion
            OSBuild = $osBuild
            Manufacturer = $manufacturer
            Model = $model
            SerialNumber = $serialNumber
        }
        Write-OK "Local device updated: $hostname ($osName, $manufacturer $model)"
    } else {
        # Insert new device
        $insertDeviceQuery = @"
INSERT INTO Devices (DeviceId, Hostname, FQDN, IPAddress, MACAddress, SiteId, DeviceType, OSName, OSVersion, OSBuild, Manufacturer, Model, SerialNumber, Status, CreatedAt, UpdatedAt)
VALUES (@DeviceId, @Hostname, @FQDN, @IPAddress, @MACAddress, 'default', @DeviceType, @OSName, @OSVersion, @OSBuild, @Manufacturer, @Model, @SerialNumber, 'Online', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
"@
        Invoke-SqliteQuery -DataSource $dbPath -Query $insertDeviceQuery -SqlParameters @{
            DeviceId = $deviceId
            Hostname = $hostname
            FQDN = $fqdn
            IPAddress = $ipAddress
            MACAddress = $macAddress
            DeviceType = $deviceType
            OSName = $osName
            OSVersion = $osVersion
            OSBuild = $osBuild
            Manufacturer = $manufacturer
            Model = $model
            SerialNumber = $serialNumber
        }
        Write-OK "Local device registered: $hostname ($osName, $manufacturer $model)"
    }
} catch {
    Write-Host "  [WARN] Could not auto-register local device: $_" -ForegroundColor Yellow
}
#endregion

#region Step 5: Create Configuration
Write-Step "5/7" "Creating configuration..."

$settingsPath = "$ConfigPath\settings.json"

# Only create settings if not exists (preserve existing config on reinstall)
if (-not (Test-Path $settingsPath)) {
    $settings = @{
        General = @{
            SiteName = "Default"
            Version = "2.1.0"
            DefaultSite = "default"
            DataRetentionDays = 90
        }
        Paths = @{
            InstallPath = $RMMInstallPath
            DataPath = $DataPath
            ConfigPath = $ConfigPath
            LogPath = $LogPath
        }
        Database = @{
            Path = $dbPath
            BackupEnabled = $true
            BackupRetentionDays = 30
        }
        Logging = @{
            Path = $LogPath
            Level = "Info"
            MaxFileSizeMB = 10
            RetentionDays = 30
        }
        Connections = @{
            WinRMTimeout = 30
            MaxConcurrent = 10
            RetryCount = 3
        }
        Monitoring = @{
            HealthCheckInterval = 300
            MetricsRetentionDays = 30
        }
        Notifications = @{
            Enabled = $false
            EmailServer = ""
            EmailFrom = ""
        }
        Security = @{
            RequireEncryption = $true
            SessionTimeout = 3600
            MaxLoginAttempts = 5
        }
        Performance = @{
            CacheEnabled = $true
            CacheTTL = 300
            MaxCacheItems = 1000
        }
        UI = @{
            Theme = "Default"
            RefreshInterval = 30
            WebPort = 8080
        }
    }
    $settings | ConvertTo-Json -Depth 4 | Out-File $settingsPath -Encoding UTF8
    Write-OK "Configuration created: $settingsPath"
} else {
    Write-Info "Existing configuration preserved: $settingsPath"
}
#endregion

#region Step 6: Register PowerShell Module
Write-Step "6/7" "Registering PowerShell module..."

# Create module directory
if (-not (Test-Path $ModulePath)) {
    New-Item -ItemType Directory -Path $ModulePath -Force | Out-Null
}

# Copy core module files from installed location
$coreSourcePath = Join-Path $RMMInstallPath "scripts\core"
Copy-Item -Path "$coreSourcePath\*" -Destination $ModulePath -Force -Recurse

# Force-load the new module to replace any cached version
# This ensures Get-RMMDevice works immediately after installation
try {
    Import-Module RMM -Force -ErrorAction Stop
    Write-OK "Module registered and loaded: $ModulePath"
}
catch {
    Write-OK "Module registered: $ModulePath"
    Write-Info "Note: Module will be available in new PowerShell sessions"
}
#endregion

#region Step 7: Create Shortcuts
Write-Step "7/7" "Creating shortcuts..."

$dashboardScript = "$RMMInstallPath\scripts\ui\Start-WebDashboard.ps1"

# Helper function to create shortcuts
function New-Shortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$IconLocation,
        [string]$Description
    )

    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $TargetPath
    if ($Arguments) { $Shortcut.Arguments = $Arguments }
    if ($WorkingDirectory) { $Shortcut.WorkingDirectory = $WorkingDirectory }
    if ($IconLocation) { $Shortcut.IconLocation = $IconLocation }
    if ($Description) { $Shortcut.Description = $Description }
    $Shortcut.Save()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WshShell) | Out-Null
}

# Create Start Menu folder
if (-not (Test-Path $StartMenuFolder)) {
    New-Item -ItemType Directory -Path $StartMenuFolder -Force | Out-Null
}

# Dashboard shortcut - Public Desktop (visible to all users)
$dashboardDesktopShortcut = Join-Path $PublicDesktop "mTT RMM Dashboard.lnk"
try {
    New-Shortcut -ShortcutPath $dashboardDesktopShortcut `
                 -TargetPath "powershell.exe" `
                 -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dashboardScript`" -OpenBrowser" `
                 -WorkingDirectory $RMMInstallPath `
                 -Description "Launch myTech.Today RMM Web Dashboard"
    Write-OK "Dashboard Desktop: $dashboardDesktopShortcut"
} catch {
    Write-Warn "Could not create dashboard desktop shortcut: $_"
}

# Dashboard shortcut - Start Menu
$dashboardStartMenuShortcut = Join-Path $StartMenuFolder "mTT RMM Dashboard.lnk"
try {
    New-Shortcut -ShortcutPath $dashboardStartMenuShortcut `
                 -TargetPath "powershell.exe" `
                 -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dashboardScript`" -OpenBrowser" `
                 -WorkingDirectory $RMMInstallPath `
                 -Description "Launch myTech.Today RMM Web Dashboard"
    Write-OK "Dashboard Start Menu: $dashboardStartMenuShortcut"
} catch {
    Write-Warn "Could not create dashboard Start Menu shortcut: $_"
}

#endregion

#region Complete
Show-Banner "Installation Complete!" "Green"

Write-Host "Installation Summary:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Program Files (binaries):" -ForegroundColor White
Write-Host "    $RMMInstallPath" -ForegroundColor Gray
Write-Host ""
Write-Host "  Application Data (writable):" -ForegroundColor White
Write-Host "    Database:  $dbPath" -ForegroundColor Gray
Write-Host "    Config:    $ConfigPath" -ForegroundColor Gray
Write-Host "    Logs:      $LogPath" -ForegroundColor Gray
Write-Host ""
Write-Host "  PowerShell Module:" -ForegroundColor White
Write-Host "    $ModulePath" -ForegroundColor Gray
Write-Host ""
Write-Host "  Shortcuts:" -ForegroundColor White
Write-Host "    Desktop:    $dashboardDesktopShortcut" -ForegroundColor Gray
Write-Host "    Start Menu: $StartMenuFolder" -ForegroundColor Gray
Write-Host ""

Write-Host "Quick Start (module is already loaded in this session):" -ForegroundColor Cyan
Write-Host "  Get-RMMDevice" -ForegroundColor Yellow
Write-Host "  Get-RMMSite" -ForegroundColor Yellow
Write-Host ""
Write-Host "In new PowerShell sessions:" -ForegroundColor Cyan
Write-Host "  Import-Module RMM   # Auto-initializes" -ForegroundColor Yellow
Write-Host "  Get-RMMDevice       # Works immediately" -ForegroundColor Yellow
Write-Host ""

Write-Host "Web Dashboard:" -ForegroundColor Cyan
Write-Host "  Double-click 'mTT RMM Dashboard' on your Desktop, or run:" -ForegroundColor White
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$RMMInstallPath\scripts\ui\Start-WebDashboard.ps1`" -OpenBrowser" -ForegroundColor Yellow
Write-Host ""

Write-Host "To uninstall:" -ForegroundColor Cyan
Write-Host "  .\uninstall-server-windows.ps1" -ForegroundColor Yellow
Write-Host "  # Or with data removal: .\uninstall-server-windows.ps1 -RemoveData -Force" -ForegroundColor Gray
Write-Host ""
#endregion

