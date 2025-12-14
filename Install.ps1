<#
.SYNOPSIS
    Automated installer for myTech.Today RMM.

.DESCRIPTION
    Fully automated installation that:
    1. Copies the RMM project to %USERPROFILE%\myTech.Today\RMM\
    2. Installs all dependencies (PSSQLite, ImportExcel, PSWriteHTML)
    3. Initializes the database
    4. Creates configuration files
    5. Registers the RMM PowerShell module

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
    Version: 2.0.0
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# Paths
$SourceRoot = $PSScriptRoot
$InstallRoot = "$env:USERPROFILE\myTech.Today"
$RMMInstallPath = "$InstallRoot\RMM"
$DataPath = "$InstallRoot\data"
$LogPath = "$InstallRoot\logs"
$ConfigPath = "$InstallRoot\config"
$SecretsPath = "$InstallRoot\secrets"

# Module path (for Import-Module RMM)
$docsFolder = [Environment]::GetFolderPath('MyDocuments')
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $ModulePath = Join-Path $docsFolder "PowerShell\Modules\RMM"
} else {
    $ModulePath = Join-Path $docsFolder "WindowsPowerShell\Modules\RMM"
}

#region Banner
function Show-Banner {
    param([string]$Title, [string]$Color = "Cyan")
    Write-Host ""
    Write-Host ("=" * 50) -ForegroundColor $Color
    Write-Host "  $Title" -ForegroundColor White
    Write-Host ("=" * 50) -ForegroundColor $Color
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
#endregion

#region Uninstall
if ($Uninstall) {
    Show-Banner "myTech.Today RMM - Uninstall" "Red"

    Write-Step "1/4" "Removing shortcuts..."

    # Remove Desktop shortcut
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $desktopShortcut = Join-Path $desktopPath "myTech.Today RMM Dashboard.lnk"
    if (Test-Path $desktopShortcut) {
        Remove-Item -Path $desktopShortcut -Force
        Write-OK "Desktop shortcut removed"
    } else {
        Write-Info "Desktop shortcut not found"
    }

    # Remove Start Menu shortcuts (All Users)
    $startMenuAllUsers = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\myTech.Today"
    if (Test-Path $startMenuAllUsers) {
        Remove-Item -Path $startMenuAllUsers -Recurse -Force
        Write-OK "Start Menu folder removed (All Users)"
    }

    # Remove Start Menu shortcuts (Current User)
    $startMenuCurrentUser = Join-Path ([Environment]::GetFolderPath('StartMenu')) "Programs\myTech.Today"
    if (Test-Path $startMenuCurrentUser) {
        Remove-Item -Path $startMenuCurrentUser -Recurse -Force
        Write-OK "Start Menu folder removed (Current User)"
    }

    Write-Step "2/4" "Removing module registration..."
    if (Test-Path $ModulePath) {
        Remove-Item -Path $ModulePath -Recurse -Force
        Write-OK "Module removed from: $ModulePath"
    } else {
        Write-Info "Module not found (already removed)"
    }

    Write-Step "3/4" "Removing RMM installation..."
    if (Test-Path $RMMInstallPath) {
        Remove-Item -Path $RMMInstallPath -Recurse -Force
        Write-OK "RMM removed from: $RMMInstallPath"
    } else {
        Write-Info "RMM folder not found (already removed)"
    }

    Write-Step "4/4" "Preserving user data..."
    Write-Info "Data preserved at: $DataPath"
    Write-Info "Logs preserved at: $LogPath"
    Write-Info "Config preserved at: $ConfigPath"
    Write-Host ""
    Write-Host "To completely remove all data, manually delete:" -ForegroundColor Yellow
    Write-Host "  $InstallRoot" -ForegroundColor White
    Write-Host ""

    Show-Banner "Uninstall Complete" "Green"
    exit 0
}
#endregion

#region Main Installation
Show-Banner "myTech.Today RMM - Automated Install"

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
Write-Step "1/6" "Installing PowerShell dependencies..."

$requiredModules = @('PSSQLite', 'ImportExcel', 'PSWriteHTML')
foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Info "Installing $mod..."
        try {
            Install-Module -Name $mod -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
            Write-OK "$mod installed"
        } catch {
            Write-Host "  [WARN] Failed to install $mod - some features may not work" -ForegroundColor Yellow
        }
    } else {
        Write-Info "$mod already installed"
    }
}
Write-OK "Dependencies ready"
#endregion

#region Step 2: Create Directory Structure
Write-Step "2/6" "Creating directory structure..."

$directories = @(
    $InstallRoot,
    $RMMInstallPath,
    $DataPath,
    "$DataPath\cache",
    "$DataPath\queue",
    "$DataPath\archive",
    $LogPath,
    "$LogPath\devices",
    $ConfigPath,
    "$ConfigPath\policies",
    $SecretsPath
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}
Write-OK "Directories created at: $InstallRoot"
#endregion

#region Step 3: Copy RMM Files
Write-Step "3/6" "Copying RMM files..."

# Items to copy (excluding git, temp files, etc.)
$itemsToCopy = @(
    'scripts',
    'docs',
    'tests',
    'ai-prompts',
    'sample-devices.csv',
    'README.md',
    'LICENSE'
)

foreach ($item in $itemsToCopy) {
    $sourcePath = Join-Path $SourceRoot $item
    $destPath = Join-Path $RMMInstallPath $item

    if (Test-Path $sourcePath) {
        if (Test-Path $destPath) {
            Remove-Item -Path $destPath -Recurse -Force
        }
        Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
        Write-Info "Copied: $item"
    }
}
Write-OK "RMM files installed to: $RMMInstallPath"
#endregion

#region Step 4: Initialize Database
Write-Step "4/6" "Initializing database..."

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
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (SiteId) REFERENCES Sites(SiteId) ON DELETE CASCADE
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
    "ALTER TABLE Devices ADD COLUMN CredentialName TEXT"
)
foreach ($migration in $migrations) {
    try {
        Invoke-SqliteQuery -DataSource $dbPath -Query $migration -ErrorAction SilentlyContinue
    } catch {
        # Column already exists, ignore
    }
}

Write-OK "Database initialized: $dbPath"

# Note: No devices are auto-registered during installation.
# Use the Web Dashboard or Add-RMMDevice cmdlet to add devices manually.
Write-Info "Database ready. Add devices via Web Dashboard or Add-RMMDevice cmdlet."
#endregion

#region Step 5: Create Configuration
Write-Step "5/6" "Creating configuration..."

$settingsPath = "$ConfigPath\settings.json"
$settings = @{
    General = @{
        SiteName = "Default"
        Version = "2.0.0"
        DefaultSite = "default"
        DataRetentionDays = 90
        InstallPath = $RMMInstallPath
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

# Copy policy templates if they exist
$sourcePolicies = Join-Path $SourceRoot "config\policies"
if (Test-Path $sourcePolicies) {
    Copy-Item -Path "$sourcePolicies\*" -Destination "$ConfigPath\policies\" -Recurse -Force -ErrorAction SilentlyContinue
}
#endregion

#region Step 6: Register PowerShell Module
Write-Step "6/7" "Registering PowerShell module..."

# Create module directory
if (-not (Test-Path $ModulePath)) {
    New-Item -ItemType Directory -Path $ModulePath -Force | Out-Null
}

# Copy core module files
$coreSourcePath = Join-Path $RMMInstallPath "scripts\core"
Copy-Item -Path "$coreSourcePath\*" -Destination $ModulePath -Force -Recurse

Write-OK "Module registered at: $ModulePath"
#endregion

#region Step 7: Create Shortcuts
Write-Step "7/7" "Creating shortcuts..."

$dashboardScript = "$RMMInstallPath\scripts\ui\Start-WebDashboard.ps1"
$shortcutName = "myTech.Today RMM Dashboard"

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

# Desktop shortcut (current user)
$desktopPath = [Environment]::GetFolderPath('Desktop')
$desktopShortcut = Join-Path $desktopPath "$shortcutName.lnk"

try {
    New-Shortcut -ShortcutPath $desktopShortcut `
                 -TargetPath "powershell.exe" `
                 -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$dashboardScript`" -OpenBrowser" `
                 -WorkingDirectory $RMMInstallPath `
                 -Description "Launch myTech.Today RMM Web Dashboard"
    Write-OK "Desktop shortcut: $desktopShortcut"
} catch {
    Write-Host "  [WARN] Could not create desktop shortcut: $_" -ForegroundColor Yellow
}

# Start Menu shortcut (All Users - requires elevation)
$startMenuAllUsers = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\myTech.Today"
$startMenuShortcut = Join-Path $startMenuAllUsers "$shortcutName.lnk"

try {
    # Create the myTech.Today folder in Start Menu
    if (-not (Test-Path $startMenuAllUsers)) {
        New-Item -ItemType Directory -Path $startMenuAllUsers -Force | Out-Null
    }

    New-Shortcut -ShortcutPath $startMenuShortcut `
                 -TargetPath "powershell.exe" `
                 -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$dashboardScript`" -OpenBrowser" `
                 -WorkingDirectory $RMMInstallPath `
                 -Description "Launch myTech.Today RMM Web Dashboard"
    Write-OK "Start Menu shortcut: $startMenuShortcut"
} catch {
    # Fall back to current user Start Menu if All Users fails (no admin rights)
    Write-Info "Could not create All Users shortcut (requires admin). Trying current user..."

    $startMenuCurrentUser = Join-Path ([Environment]::GetFolderPath('StartMenu')) "Programs\myTech.Today"
    $startMenuShortcut = Join-Path $startMenuCurrentUser "$shortcutName.lnk"

    try {
        if (-not (Test-Path $startMenuCurrentUser)) {
            New-Item -ItemType Directory -Path $startMenuCurrentUser -Force | Out-Null
        }

        New-Shortcut -ShortcutPath $startMenuShortcut `
                     -TargetPath "powershell.exe" `
                     -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$dashboardScript`" -OpenBrowser" `
                     -WorkingDirectory $RMMInstallPath `
                     -Description "Launch myTech.Today RMM Web Dashboard"
        Write-OK "Start Menu shortcut (user): $startMenuShortcut"
    } catch {
        Write-Host "  [WARN] Could not create Start Menu shortcut: $_" -ForegroundColor Yellow
    }
}
#endregion

#region Complete
Show-Banner "Installation Complete!" "Green"

Write-Host "Installation Summary:" -ForegroundColor Cyan
Write-Host "  RMM Location:     $RMMInstallPath" -ForegroundColor White
Write-Host "  Data Location:    $DataPath" -ForegroundColor White
Write-Host "  Logs Location:    $LogPath" -ForegroundColor White
Write-Host "  Config Location:  $ConfigPath" -ForegroundColor White
Write-Host "  Module Location:  $ModulePath" -ForegroundColor White
Write-Host "  Desktop Shortcut: $desktopShortcut" -ForegroundColor White
Write-Host "  Start Menu:       $startMenuShortcut" -ForegroundColor White
Write-Host ""

Write-Host "Quick Start:" -ForegroundColor Cyan
Write-Host "  Import-Module RMM" -ForegroundColor Yellow
Write-Host "  Initialize-RMM" -ForegroundColor Yellow
Write-Host "  Get-RMMDevice" -ForegroundColor Yellow
Write-Host ""

Write-Host "Web Dashboard:" -ForegroundColor Cyan
Write-Host "  Double-click the Desktop shortcut, or:" -ForegroundColor White
Write-Host "  & `"$RMMInstallPath\scripts\ui\Start-WebDashboard.ps1`" -OpenBrowser" -ForegroundColor Yellow
Write-Host ""

Write-Host "To uninstall:" -ForegroundColor Cyan
Write-Host "  & `"$SourceRoot\Install.ps1`" -Uninstall" -ForegroundColor Yellow
Write-Host ""
#endregion

