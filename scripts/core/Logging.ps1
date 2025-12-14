<#
.SYNOPSIS
    RMM-specific logging wrapper for the myTech.Today RMM system.

.DESCRIPTION
    Integrates with the shared logging module from the PowerShellScripts repository.
    Provides RMM-specific logging functions while maintaining backwards compatibility.

.NOTES
    Author: Kyle C. Rode (myTech.Today)
    Version: 2.0
    Requires: PowerShell 5.1+
#>

# Script-scoped variables
$script:SharedLoggingLoaded = $false
$script:RMMLogInitialized = $false

# Load shared logging at module level
try {
    # Try to load shared logging from local path first
    $localLoggingPath = "$PSScriptRoot\..\..\..\scripts\logging.ps1"

    if (Test-Path $localLoggingPath) {
        . $localLoggingPath
        $script:SharedLoggingLoaded = $true
    }
    else {
        # Fallback to remote URL
        $loggingUrl = 'https://raw.githubusercontent.com/mytech-today-now/scripts/refs/heads/main/logging.ps1'
        Invoke-Expression (Invoke-WebRequest -Uri $loggingUrl -UseBasicParsing).Content
        $script:SharedLoggingLoaded = $true
    }
}
catch {
    Write-Warning "Failed to load shared logging: $_"
    $script:SharedLoggingLoaded = $false
}

function Initialize-RMMLogging {
    <#
    .SYNOPSIS
        Initializes the RMM logging system.

    .DESCRIPTION
        Loads the shared logging module and initializes logging for the RMM system.
        Tries to load from local path first, then falls back to remote URL.

    .PARAMETER ScriptName
        Name of the script or component (default: "RMM")

    .PARAMETER ScriptVersion
        Version of the script (default: "2.0")

    .EXAMPLE
        Initialize-RMMLogging
        Initializes logging with default RMM settings.

    .EXAMPLE
        Initialize-RMMLogging -ScriptName "RMM-Collector" -ScriptVersion "2.1"
        Initializes logging for a specific RMM component.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ScriptName = "RMM",

        [Parameter()]
        [string]$ScriptVersion = "2.0"
    )

    try {
        # Initialize logging with RMM-specific settings
        if ($script:SharedLoggingLoaded) {
            Write-Host "[INFO] Initializing RMM logging..." -ForegroundColor Cyan
            Initialize-Log -ScriptName $ScriptName -ScriptVersion $ScriptVersion
            $script:RMMLogInitialized = $true
            Write-Host "[OK] RMM logging initialized" -ForegroundColor Green
        }
        else {
            Write-Warning "Shared logging not loaded. Logging will be limited to console output only"
        }
    }
    catch {
        Write-Warning "Failed to initialize RMM logging: $_"
        Write-Warning "Logging will be limited to console output only"
        $script:RMMLogInitialized = $false
    }
}

function Write-RMMLog {
    <#
    .SYNOPSIS
        Writes a log entry to the main RMM log.

    .DESCRIPTION
        Writes formatted log messages using the shared logging system.
        Falls back to console output if logging is not initialized.

    .PARAMETER Message
        The message to log.

    .PARAMETER Level
        The log level: INFO, SUCCESS, WARNING, or ERROR. Default is INFO.

    .PARAMETER Solution
        Optional. Recommended action or solution for warnings/errors.

    .PARAMETER Context
        Optional. Additional context about what was happening.

    .PARAMETER Component
        Optional. The component or feature affected.

    .EXAMPLE
        Write-RMMLog "RMM system started" -Level INFO

    .EXAMPLE
        Write-RMMLog "Failed to connect to device" -Level ERROR -Solution "Check WinRM configuration" -Component "Device Connection"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO',

        [Parameter()]
        [string]$Solution,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [string]$Component
    )

    if ($script:RMMLogInitialized) {
        # Use shared logging
        $params = @{
            Message = $Message
            Level   = $Level
        }
        if ($Solution) { $params.Solution = $Solution }
        if ($Context) { $params.Context = $Context }
        if ($Component) { $params.Component = $Component }

        Write-Log @params
    }
    else {
        # Fallback to console output
        $color = switch ($Level) {
            'SUCCESS' { 'Green' }
            'WARNING' { 'Yellow' }
            'ERROR'   { 'Red' }
            default   { 'Cyan' }
        }
        $indicator = switch ($Level) {
            'SUCCESS' { '[OK]' }
            'WARNING' { '[WARN]' }
            'ERROR'   { '[ERROR]' }
            default   { '[INFO]' }
        }
        Write-Host "[$([datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $indicator $Message" -ForegroundColor $color
    }
}

function Write-RMMDeviceLog {
    <#
    .SYNOPSIS
        Writes a log entry to a device-specific log file.

    .DESCRIPTION
        Creates and writes to device-specific log files in logs/devices/{DeviceId}.md
        This allows tracking of all activities related to a specific device.

    .PARAMETER DeviceId
        The unique identifier of the device.

    .PARAMETER Message
        The message to log.

    .PARAMETER Level
        The log level: INFO, SUCCESS, WARNING, or ERROR. Default is INFO.

    .EXAMPLE
        Write-RMMDeviceLog -DeviceId "SERVER01" -Message "Health check completed" -Level SUCCESS

    .EXAMPLE
        Write-RMMDeviceLog -DeviceId "WS-001" -Message "Failed to connect" -Level ERROR
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceId,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    try {
        # Create device log directory if it doesn't exist
        $deviceLogDir = "$PSScriptRoot\..\..\logs\devices"
        if (-not (Test-Path $deviceLogDir)) {
            New-Item -ItemType Directory -Path $deviceLogDir -Force | Out-Null
        }

        # Device log file path
        $deviceLogPath = Join-Path $deviceLogDir "$DeviceId.md"

        # Create log file with header if it doesn't exist
        if (-not (Test-Path $deviceLogPath)) {
            $header = @"
# Device Log: $DeviceId

**Created:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

---

## Activity Log

| Timestamp | Level | Message |
|-----------|-------|---------|
"@
            Set-Content -Path $deviceLogPath -Value $header -Force
        }

        # Format log entry
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $indicator = switch ($Level) {
            'SUCCESS' { '[OK]' }
            'WARNING' { '[WARN]' }
            'ERROR'   { '[ERROR]' }
            default   { '[INFO]' }
        }

        $logEntry = "| $timestamp | $indicator | $Message |"
        Add-Content -Path $deviceLogPath -Value $logEntry

        # Also write to main log
        Write-RMMLog -Message "[$DeviceId] $Message" -Level $Level -Component "Device: $DeviceId"
    }
    catch {
        Write-Warning "Failed to write device log for ${DeviceId}: $($_.Exception.Message)"
    }
}

function Get-RMMLog {
    <#
    .SYNOPSIS
        Retrieves log entries with optional filtering.

    .DESCRIPTION
        Reads and filters log entries from the main RMM log or device-specific logs.

    .PARAMETER DeviceId
        Optional. Retrieve logs for a specific device.

    .PARAMETER Level
        Optional. Filter by log level.

    .PARAMETER Last
        Optional. Return only the last N entries.

    .EXAMPLE
        Get-RMMLog -Last 50
        Returns the last 50 log entries from the main log.

    .EXAMPLE
        Get-RMMLog -DeviceId "SERVER01" -Level ERROR
        Returns all ERROR entries for SERVER01.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$DeviceId,

        [Parameter()]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level,

        [Parameter()]
        [int]$Last
    )

    try {
        if ($DeviceId) {
            $logPath = "$PSScriptRoot\..\..\logs\devices\$DeviceId.md"
        }
        else {
            if ($script:RMMLogInitialized) {
                $logPath = Get-LogPath
            }
            else {
                Write-Warning "Logging not initialized"
                return
            }
        }

        if (-not (Test-Path $logPath)) {
            Write-Warning "Log file not found: $logPath"
            return
        }

        # Read log file
        $content = Get-Content -Path $logPath

        # Filter markdown table rows
        $logEntries = $content | Where-Object { $_ -match '^\|.*\|.*\|.*\|$' -and $_ -notmatch '^[\|\s-]+$' -and $_ -notmatch 'Timestamp.*Level.*Message' }

        # Apply level filter if specified
        if ($Level) {
            $indicator = switch ($Level) {
                'SUCCESS' { '\[OK\]' }
                'WARNING' { '\[WARN\]' }
                'ERROR'   { '\[ERROR\]' }
                default   { '\[INFO\]' }
            }
            $logEntries = $logEntries | Where-Object { $_ -match $indicator }
        }

        # Apply last N filter if specified
        if ($Last -and $Last -gt 0) {
            $logEntries = $logEntries | Select-Object -Last $Last
        }

        return $logEntries
    }
    catch {
        Write-Error "Failed to retrieve log entries: $_"
    }
}

function Clear-RMMLog {
    <#
    .SYNOPSIS
        Archives and clears old log files.

    .DESCRIPTION
        Archives log files older than the specified retention period.

    .PARAMETER RetentionDays
        Number of days to retain logs. Default is 90.

    .PARAMETER DeviceId
        Optional. Clear logs for a specific device only.

    .EXAMPLE
        Clear-RMMLog -RetentionDays 30
        Archives logs older than 30 days.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [int]$RetentionDays = 90,

        [Parameter()]
        [string]$DeviceId
    )

    try {
        $archiveDir = "$PSScriptRoot\..\..\data\archive"
        if (-not (Test-Path $archiveDir)) {
            New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
        }

        if ($DeviceId) {
            # Clear specific device log
            $deviceLogPath = "$PSScriptRoot\..\..\logs\devices\$DeviceId.md"
            if (Test-Path $deviceLogPath) {
                if ($PSCmdlet.ShouldProcess($DeviceId, "Archive device log")) {
                    $archivePath = Join-Path $archiveDir "$DeviceId-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
                    Move-Item -Path $deviceLogPath -Destination $archivePath -Force
                    Write-Host "[OK] Device log archived: $archivePath" -ForegroundColor Green
                }
            }
        }
        else {
            # Clear old device logs
            $deviceLogDir = "$PSScriptRoot\..\..\logs\devices"
            if (Test-Path $deviceLogDir) {
                $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
                $oldLogs = Get-ChildItem -Path $deviceLogDir -Filter "*.md" | Where-Object { $_.LastWriteTime -lt $cutoffDate }

                foreach ($log in $oldLogs) {
                    if ($PSCmdlet.ShouldProcess($log.Name, "Archive old log")) {
                        $archivePath = Join-Path $archiveDir "$($log.BaseName)-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
                        Move-Item -Path $log.FullName -Destination $archivePath -Force
                        Write-Host "[OK] Archived: $($log.Name)" -ForegroundColor Green
                    }
                }
            }
        }
    }
    catch {
        Write-Error "Failed to clear logs: $_"
    }
}

# Export functions (only if running as a module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function Initialize-RMMLogging, Write-RMMLog, Write-RMMDeviceLog, Get-RMMLog, Clear-RMMLog
}

