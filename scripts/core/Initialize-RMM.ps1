<#
.SYNOPSIS
    Bootstrap and setup script for the myTech.Today RMM system.

.DESCRIPTION
    Handles installation, upgrade, repair, and uninstallation of the RMM system.
    Checks dependencies, configures WinRM, initializes the database, and sets up scheduled tasks.

.PARAMETER Mode
    The operation mode: Install, Upgrade, Repair, or Uninstall.

.PARAMETER DatabasePath
    Optional. Custom path for the SQLite database.

.PARAMETER ImportDevices
    Optional. Path to CSV file for initial device import.

.PARAMETER SiteName
    Optional. Site name for multi-site deployments.

.PARAMETER EnableWebDashboard
    Optional. Enable the web dashboard.

.PARAMETER WinRMHttps
    Optional. Configure WinRM to use HTTPS transport.

.PARAMETER SkipDependencies
    Optional. Skip dependency installation (for testing).

.EXAMPLE
    .\Initialize-RMM.ps1 -Mode Install
    Performs a fresh installation of the RMM system.

.EXAMPLE
    .\Initialize-RMM.ps1 -Mode Install -ImportDevices ".\sample-devices.csv" -SiteName "MainOffice"
    Installs RMM and imports devices from CSV.

.EXAMPLE
    .\Initialize-RMM.ps1 -Mode Repair
    Repairs an existing RMM installation.

.NOTES
    Author: Kyle C. Rode (myTech.Today)
    Version: 2.0
    Requires: PowerShell 5.1+, Administrator privileges
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateSet('Install', 'Upgrade', 'Repair', 'Uninstall')]
    [string]$Mode = 'Install',

    [Parameter()]
    [string]$DatabasePath,

    [Parameter()]
    [string]$ImportDevices,

    [Parameter()]
    [string]$SiteName = "Main",

    [Parameter()]
    [switch]$EnableWebDashboard,

    [Parameter()]
    [switch]$WinRMHttps,

    [Parameter()]
    [switch]$SkipDependencies,

    [Parameter()]
    [switch]$Quiet
)

# Script variables
$script:RMMRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ErrorCount = 0
$script:WarningCount = 0

function Write-Progress-Step {
    param(
        [string]$Message,
        [string]$Status = "Running",
        [int]$PercentComplete = 0
    )
    Write-Progress -Activity "RMM $Mode" -Status $Status -CurrentOperation $Message -PercentComplete $PercentComplete
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Failure {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    $script:ErrorCount++
}

function Write-WarningMessage {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
    $script:WarningCount++
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-RequiredModules {
    Write-Progress-Step "Checking PowerShell module dependencies..." -PercentComplete 10

    $requiredModules = @(
        @{ Name = 'PSSQLite'; MinVersion = '1.1.0' }
        @{ Name = 'PSWindowsUpdate'; MinVersion = '2.0.0' }
        @{ Name = 'ThreadJob'; MinVersion = '2.0.0' }
        @{ Name = 'ImportExcel'; MinVersion = '7.0.0' }
        @{ Name = 'PSWriteHTML'; MinVersion = '0.0.170' }
    )

    foreach ($module in $requiredModules) {
        # Special handling for ThreadJob - check if Start-ThreadJob command exists (built into PS 7+)
        if ($module.Name -eq 'ThreadJob') {
            $cmdExists = Get-Command -Name 'Start-ThreadJob' -ErrorAction SilentlyContinue
            if ($cmdExists) {
                Write-Host "  [OK] Start-ThreadJob command available (PowerShell $($PSVersionTable.PSVersion.Major)+)" -ForegroundColor Gray
                continue
            }
        }

        $installed = Get-Module -ListAvailable -Name $module.Name | Where-Object { $_.Version -ge $module.MinVersion }

        if (-not $installed) {
            Write-Host "  Installing $($module.Name)..." -ForegroundColor Yellow
            try {
                # Use -AllowClobber for ThreadJob to handle PS7+ scenarios where command exists but module doesn't
                $installParams = @{
                    Name = $module.Name
                    MinimumVersion = $module.MinVersion
                    Force = $true
                    Scope = 'CurrentUser'
                    ErrorAction = 'Stop'
                }
                if ($module.Name -eq 'ThreadJob') {
                    $installParams.AllowClobber = $true
                }
                Install-Module @installParams
                Write-Success "$($module.Name) installed successfully"
            }
            catch {
                Write-Failure "Failed to install $($module.Name): $_"
            }
        }
        else {
            Write-Host "  [OK] $($module.Name) already installed (v$($installed[0].Version))" -ForegroundColor Gray
        }
    }
}

function Initialize-FolderStructure {
    Write-Progress-Step "Verifying folder structure..." -PercentComplete 20

    $folders = @(
        'config\policies',
        'scripts\core', 'scripts\collectors', 'scripts\monitors', 'scripts\actions',
        'scripts\alerts', 'scripts\reports', 'scripts\automation', 'scripts\ui\web',
        'data\cache', 'data\queue', 'data\archive',
        'logs\devices',
        'secrets',
        'docs'
    )

    foreach ($folder in $folders) {
        $fullPath = Join-Path $script:RMMRoot $folder
        if (-not (Test-Path $fullPath)) {
            New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
            Write-Host "  Created: $folder" -ForegroundColor Gray
        }
    }

    Write-Success "Folder structure verified"
}

function Initialize-Database {
    Write-Progress-Step "Initializing database..." -PercentComplete 30

    $dbScript = Join-Path $PSScriptRoot "Initialize-Database.ps1"

    if (-not (Test-Path $dbScript)) {
        Write-Failure "Database initialization script not found: $dbScript"
        return $false
    }

    try {
        $dbParams = @{ Quiet = $true; ErrorAction = 'Stop' }
        if ($DatabasePath) { $dbParams.DatabasePath = $DatabasePath }

        & $dbScript @dbParams
        Write-Success "Database initialized successfully"
        return $true
    }
    catch {
        Write-Failure "Database initialization failed: $_"
        return $false
    }
}

function Enable-WinRMConfiguration {
    Write-Progress-Step "Configuring WinRM..." -PercentComplete 40

    try {
        # Check if WinRM is already running
        $winrmService = Get-Service -Name WinRM -ErrorAction SilentlyContinue

        if ($winrmService.Status -ne 'Running') {
            Write-Host "  Starting WinRM service..." -ForegroundColor Yellow
            Start-Service -Name WinRM -ErrorAction Stop
        }

        # Enable WinRM
        Write-Host "  Enabling WinRM..." -ForegroundColor Yellow
        Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop

        # Configure firewall rules
        Write-Host "  Configuring firewall rules..." -ForegroundColor Yellow
        Enable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue

        # Configure HTTPS if requested
        if ($WinRMHttps) {
            Write-Host "  Configuring HTTPS transport..." -ForegroundColor Yellow

            # Check for existing certificate
            $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {
                $_.Subject -match $env:COMPUTERNAME -and
                $_.EnhancedKeyUsageList.FriendlyName -contains 'Server Authentication'
            } | Select-Object -First 1

            if (-not $cert) {
                Write-Host "  Generating self-signed certificate..." -ForegroundColor Yellow
                $cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My -ErrorAction Stop
            }

            # Create HTTPS listener
            $httpsListener = Get-WSManInstance -ResourceURI winrm/config/listener -SelectorSet @{Address="*";Transport="HTTPS"} -ErrorAction SilentlyContinue

            if (-not $httpsListener) {
                New-WSManInstance -ResourceURI winrm/config/listener -SelectorSet @{Address="*";Transport="HTTPS"} -ValueSet @{CertificateThumbprint=$cert.Thumbprint} -ErrorAction Stop
                Write-Success "HTTPS listener created"
            }
        }

        Write-Success "WinRM configured successfully"
        return $true
    }
    catch {
        Write-Failure "WinRM configuration failed: $_"
        return $false
    }
}

function Register-ScheduledTasks {
    Write-Progress-Step "Registering scheduled tasks..." -PercentComplete 50

    try {
        # Get configuration
        $configPath = Join-Path $script:RMMRoot "config\settings.json"
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

        # Health check task
        $healthCheckInterval = $config.Monitoring.HealthCheckInterval
        # Use indefinite repetition by not specifying RepetitionDuration
        $healthCheckTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Seconds $healthCheckInterval)
        $healthCheckAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script:RMMRoot\scripts\monitors\Health-Monitor.ps1`""
        $healthCheckSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        Register-ScheduledTask -TaskName "RMM-HealthCheck" -Trigger $healthCheckTrigger -Action $healthCheckAction -Settings $healthCheckSettings -Description "RMM Health Check Monitor" -Force -ErrorAction Stop

        Write-Success "Scheduled tasks registered"
        return $true
    }
    catch {
        Write-WarningMessage "Failed to register scheduled tasks: $_"
        return $false
    }
}

function Add-LocalDevice {
    Write-Progress-Step "Adding localhost as managed device..." -PercentComplete 60

    try {
        # Import the RMM module
        Import-Module "$PSScriptRoot\RMM-Core.psm1" -Force -ErrorAction Stop

        # Initialize RMM
        Initialize-RMM -ErrorAction Stop

        # Check if localhost already exists
        $existing = Get-RMMDevice -Hostname $env:COMPUTERNAME

        if (-not $existing) {
            # Add localhost
            $ipAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } | Select-Object -First 1).IPAddress

            Add-RMMDevice -Hostname $env:COMPUTERNAME -IPAddress $ipAddress -SiteId $SiteName -Tags "localhost,managed" -ErrorAction Stop
            Write-Success "Localhost added as managed device"
        }
        else {
            Write-Host "  [OK] Localhost already registered" -ForegroundColor Gray
        }

        return $true
    }
    catch {
        Write-Failure "Failed to add localhost: $_"
        return $false
    }
}

function Import-DevicesFromCSV {
    param([string]$CsvPath)

    Write-Progress-Step "Importing devices from CSV..." -PercentComplete 70

    try {
        if (-not (Test-Path $CsvPath)) {
            Write-Failure "CSV file not found: $CsvPath"
            return $false
        }

        $devices = Import-Csv -Path $CsvPath -ErrorAction Stop

        # Import the RMM module
        Import-Module "$PSScriptRoot\RMM-Core.psm1" -Force -ErrorAction Stop
        Initialize-RMM -ErrorAction Stop

        $imported = 0
        foreach ($device in $devices) {
            try {
                Add-RMMDevice -Hostname $device.Hostname -IPAddress $device.IPAddress -SiteId $device.SiteId -Tags $device.Tags -ErrorAction Stop
                $imported++
            }
            catch {
                Write-WarningMessage "Failed to import device $($device.Hostname): $_"
            }
        }

        Write-Success "Imported $imported of $($devices.Count) devices"
        return $true
    }
    catch {
        Write-Failure "Failed to import devices: $_"
        return $false
    }
}

function Invoke-InitialHealthCheck {
    Write-Progress-Step "Running initial health check..." -PercentComplete 80

    try {
        Import-Module "$PSScriptRoot\RMM-Core.psm1" -Force -ErrorAction Stop
        Initialize-RMM -ErrorAction Stop

        $health = Get-RMMHealth -ErrorAction Stop

        Write-Host ""
        Write-Host "=== RMM Health Summary ===" -ForegroundColor Cyan
        Write-Host "Total Devices: $($health.TotalDevices)" -ForegroundColor White
        Write-Host ""

        if ($health.DevicesByStatus) {
            Write-Host "Devices by Status:" -ForegroundColor Cyan
            foreach ($status in $health.DevicesByStatus) {
                Write-Host "  $($status.Status): $($status.Count)" -ForegroundColor Gray
            }
        }

        Write-Success "Initial health check completed"
        return $true
    }
    catch {
        Write-WarningMessage "Health check failed: $_"
        return $false
    }
}

function Show-Summary {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  RMM $Mode Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor White
    Write-Host "  Errors:   $script:ErrorCount" -ForegroundColor $(if ($script:ErrorCount -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  Warnings: $script:WarningCount" -ForegroundColor $(if ($script:WarningCount -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Review configuration: config\settings.json" -ForegroundColor Gray
    Write-Host "  2. Import the RMM module: Import-Module .\scripts\core\RMM-Core.psm1" -ForegroundColor Gray
    Write-Host "  3. View devices: Get-RMMDevice" -ForegroundColor Gray
    Write-Host "  4. Check health: Get-RMMHealth" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Documentation: README.md" -ForegroundColor Gray
    Write-Host ""
}

# Main execution
try {
    Clear-Host
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  myTech.Today RMM - $Mode" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check administrator privileges
    if (-not (Test-Administrator)) {
        Write-Failure "This script requires Administrator privileges"
        Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
        exit 1
    }

    switch ($Mode) {
        'Install' {
            Write-Host "Starting fresh installation..." -ForegroundColor Cyan
            Write-Host ""

            # Install dependencies
            if (-not $SkipDependencies) {
                Install-RequiredModules
            }

            # Initialize folder structure
            Initialize-FolderStructure

            # Initialize database
            $dbSuccess = Initialize-Database
            if (-not $dbSuccess) {
                Write-Failure "Database initialization failed. Installation aborted."
                exit 1
            }

            # Configure WinRM
            Enable-WinRMConfiguration

            # Register scheduled tasks
            Register-ScheduledTasks

            # Add localhost
            Add-LocalDevice

            # Import devices if CSV provided
            if ($ImportDevices) {
                Import-DevicesFromCSV -CsvPath $ImportDevices
            }

            # Run initial health check
            Invoke-InitialHealthCheck

            # Show summary
            Show-Summary
        }

        'Upgrade' {
            Write-Host "Starting upgrade..." -ForegroundColor Cyan
            Write-Host ""

            # Install/update dependencies
            if (-not $SkipDependencies) {
                Install-RequiredModules
            }

            # Verify folder structure
            Initialize-FolderStructure

            # Update scheduled tasks
            Register-ScheduledTasks

            Write-Success "Upgrade completed successfully"
            Show-Summary
        }

        'Repair' {
            Write-Host "Starting repair..." -ForegroundColor Cyan
            Write-Host ""

            # Verify dependencies
            if (-not $SkipDependencies) {
                Install-RequiredModules
            }

            # Repair folder structure
            Initialize-FolderStructure

            # Verify database
            $dbPath = if ($DatabasePath) { $DatabasePath } else { "$script:RMMRoot\data\devices.db" }
            if (-not (Test-Path $dbPath)) {
                Write-WarningMessage "Database not found. Reinitializing..."
                Initialize-Database
            }

            # Reconfigure WinRM
            Enable-WinRMConfiguration

            # Re-register scheduled tasks
            Register-ScheduledTasks

            Write-Success "Repair completed successfully"
            Show-Summary
        }

        'Uninstall' {
            Write-Host "Starting uninstallation..." -ForegroundColor Yellow
            Write-Host ""

            $confirm = Read-Host "Are you sure you want to uninstall RMM? This will remove scheduled tasks. (Y/N)"
            if ($confirm -ne 'Y') {
                Write-Host "Uninstallation cancelled" -ForegroundColor Yellow
                exit 0
            }

            # Remove scheduled tasks
            Write-Progress-Step "Removing scheduled tasks..." -PercentComplete 50
            Unregister-ScheduledTask -TaskName "RMM-HealthCheck" -Confirm:$false -ErrorAction SilentlyContinue

            Write-Host ""
            Write-Host "Uninstallation complete!" -ForegroundColor Green
            Write-Host "Note: Database and configuration files were preserved in case you want to reinstall." -ForegroundColor Yellow
            Write-Host ""
        }
    }

    Write-Progress -Activity "RMM $Mode" -Completed
}
catch {
    Write-Host ""
    Write-Failure "An unexpected error occurred: $_"
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}

