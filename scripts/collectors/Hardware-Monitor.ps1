<#
.SYNOPSIS
    Real-time hardware performance metrics collection.

.DESCRIPTION
    Collects CPU, Memory, Disk, Network, and GPU performance metrics from managed devices
    and stores them in the RMM database. Compares against thresholds and triggers alerts.

.PARAMETER Devices
    Array of device hostnames, a group name, or "All" to monitor all devices.

.PARAMETER Interval
    Collection interval in seconds (default: 300 = 5 minutes).

.PARAMETER Duration
    Total duration to collect metrics in minutes (default: 0 = single collection).

.PARAMETER DatabasePath
    Path to the RMM database. If not specified, uses the default from RMM-Core.

.EXAMPLE
    .\Hardware-Monitor.ps1 -Devices "localhost"

.EXAMPLE
    .\Hardware-Monitor.ps1 -Devices "All" -Interval 60 -Duration 60

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+, PSSQLite module
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Devices = @("All"),

    [Parameter()]
    [int]$Interval = 300,

    [Parameter()]
    [int]$Duration = 0,

    [Parameter()]
    [string]$DatabasePath
)

# Import required modules
$ErrorActionPreference = 'Stop'

try {
    # Import RMM Core
    $rmmCorePath = Join-Path $PSScriptRoot "..\core\RMM-Core.psm1"
    if (-not (Get-Module -Name RMM-Core)) {
        Import-Module $rmmCorePath -Force
    }

    # Import logging module
    $loggingPath = Join-Path $PSScriptRoot "..\core\Logging.ps1"
    . $loggingPath

    # Import PSSQLite
    if (-not (Get-Module -Name PSSQLite)) {
        Import-Module PSSQLite -ErrorAction Stop
    }
}
catch {
    Write-Error "Failed to import required modules: $_"
    exit 1
}

# Initialize RMM
try {
    Initialize-RMM -ErrorAction Stop
    Write-Host "[INFO] RMM initialized successfully" -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to initialize RMM: $_"
    exit 1
}

# Initialize logging for this collector
Initialize-RMMLogging -ScriptName "Hardware-Monitor" -ScriptVersion "2.0"
Write-RMMLog "Hardware Monitor started (Interval: ${Interval}s, Duration: ${Duration}m)" -Level INFO -Component "Hardware-Monitor"

# Get database path
if (-not $DatabasePath) {
    $DatabasePath = Get-RMMDatabase
}

# Load thresholds
$thresholdsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "..\config\thresholds.json"
$thresholds = Get-Content $thresholdsPath -Raw | ConvertFrom-Json

# Resolve devices
$targetDevices = @()
if ($Devices -contains "All") {
    $targetDevices = Get-RMMDevice
    Write-RMMLog "Monitoring all devices ($($targetDevices.Count) total)" -Level INFO -Component "Hardware-Monitor"
}
else {
    foreach ($device in $Devices) {
        $dev = Get-RMMDevice -Hostname $device -ErrorAction SilentlyContinue
        if ($dev) {
            $targetDevices += $dev
        }
        else {
            Write-Warning "Device not found: $device"
            Write-RMMLog "Device not found: $device" -Level WARNING -Component "Hardware-Monitor"
        }
    }
    Write-RMMLog "Monitoring $($targetDevices.Count) device(s): $($Devices -join ', ')" -Level INFO -Component "Hardware-Monitor"
}

if ($targetDevices.Count -eq 0) {
    Write-Warning "No devices found to monitor"
    Write-RMMLog "No devices found to monitor - exiting" -Level WARNING -Component "Hardware-Monitor"
    exit 0
}

Write-Host "[INFO] Monitoring $($targetDevices.Count) device(s)" -ForegroundColor Cyan
Write-Host ""

# Metrics collection function
function Collect-HardwareMetrics {
    param(
        [Parameter(Mandatory)]
        $Device,
        
        [Parameter(Mandatory)]
        $Thresholds,
        
        [Parameter(Mandatory)]
        [string]$DatabasePath
    )

    $metrics = @()
    $alerts = @()

    try {
        # Test connectivity
        $testConnection = Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $testConnection) {
            Write-Warning "$($Device.Hostname): Device is offline"
            return @{ Metrics = @(); Alerts = @() }
        }

        # CPU Metrics
        try {
            $cpuCounter = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -ComputerName $Device.Hostname -ErrorAction Stop | Where-Object { $_.Name -eq "_Total" }
            $cpuUsage = $cpuCounter.PercentProcessorTime
            
            $metrics += @{
                DeviceId   = $Device.DeviceId
                MetricType = "CPU_Usage"
                Value      = $cpuUsage
                Unit       = "Percent"
            }

            # Check thresholds
            if ($cpuUsage -ge $Thresholds.performance.cpu.critical) {
                $alerts += @{
                    DeviceId = $Device.DeviceId
                    Severity = "Critical"
                    Message  = "CPU usage is critical: $cpuUsage%"
                }
            }
            elseif ($cpuUsage -ge $Thresholds.performance.cpu.warning) {
                $alerts += @{
                    DeviceId = $Device.DeviceId
                    Severity = "Warning"
                    Message  = "CPU usage is high: $cpuUsage%"
                }
            }
        }
        catch {
            Write-Warning "$($Device.Hostname): Failed to collect CPU metrics: $_"
        }

        # Memory Metrics
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Device.Hostname -ErrorAction Stop
            $totalMemory = $os.TotalVisibleMemorySize
            $freeMemory = $os.FreePhysicalMemory
            $usedMemory = $totalMemory - $freeMemory
            $memoryUsagePercent = [math]::Round(($usedMemory / $totalMemory) * 100, 2)

            $metrics += @{
                DeviceId   = $Device.DeviceId
                MetricType = "Memory_Usage"
                Value      = $memoryUsagePercent
                Unit       = "Percent"
            }

            $metrics += @{
                DeviceId   = $Device.DeviceId
                MetricType = "Memory_Available"
                Value      = [math]::Round($freeMemory / 1MB, 2)
                Unit       = "MB"
            }

            # Check thresholds
            if ($memoryUsagePercent -ge $Thresholds.performance.memory.critical) {
                $alerts += @{
                    DeviceId = $Device.DeviceId
                    Severity = "Critical"
                    Message  = "Memory usage is critical: $memoryUsagePercent%"
                }
            }
            elseif ($memoryUsagePercent -ge $Thresholds.performance.memory.warning) {
                $alerts += @{
                    DeviceId = $Device.DeviceId
                    Severity = "Warning"
                    Message  = "Memory usage is high: $memoryUsagePercent%"
                }
            }
        }
        catch {
            Write-Warning "$($Device.Hostname): Failed to collect Memory metrics: $_"
        }

        # Disk Metrics
        try {
            $disks = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $Device.Hostname -ErrorAction Stop | Where-Object { $_.DriveType -eq 3 }

            foreach ($disk in $disks) {
                $freeSpacePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)

                $metrics += @{
                    DeviceId   = $Device.DeviceId
                    MetricType = "Disk_FreeSpace_$($disk.DeviceID)"
                    Value      = $freeSpacePercent
                    Unit       = "Percent"
                }

                # Check thresholds (inverted - low free space is bad)
                if ($freeSpacePercent -le $Thresholds.performance.diskSpace.critical) {
                    $alerts += @{
                        DeviceId = $Device.DeviceId
                        Severity = "Critical"
                        Message  = "Disk $($disk.DeviceID) space is critical: $freeSpacePercent% free"
                    }
                }
                elseif ($freeSpacePercent -le $Thresholds.performance.diskSpace.warning) {
                    $alerts += @{
                        DeviceId = $Device.DeviceId
                        Severity = "Warning"
                        Message  = "Disk $($disk.DeviceID) space is low: $freeSpacePercent% free"
                    }
                }
            }
        }
        catch {
            Write-Warning "$($Device.Hostname): Failed to collect Disk metrics: $_"
        }

        # Network Metrics
        try {
            $adapters = Get-CimInstance -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface -ComputerName $Device.Hostname -ErrorAction Stop

            foreach ($adapter in $adapters) {
                $metrics += @{
                    DeviceId   = $Device.DeviceId
                    MetricType = "Network_BytesSent_$($adapter.Name)"
                    Value      = $adapter.BytesSentPerSec
                    Unit       = "BytesPerSec"
                }

                $metrics += @{
                    DeviceId   = $Device.DeviceId
                    MetricType = "Network_BytesReceived_$($adapter.Name)"
                    Value      = $adapter.BytesReceivedPerSec
                    Unit       = "BytesPerSec"
                }
            }
        }
        catch {
            Write-Warning "$($Device.Hostname): Failed to collect Network metrics: $_"
        }
    }
    catch {
        Write-Warning "$($Device.Hostname): General metrics collection error: $_"
    }

    return @{
        Metrics = $metrics
        Alerts  = $alerts
    }
}

# Main collection loop
$startTime = Get-Date
$endTime = if ($Duration -gt 0) { $startTime.AddMinutes($Duration) } else { $startTime }
$iteration = 0

do {
    $iteration++
    Write-Host "[INFO] Collection iteration $iteration at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan

    $totalMetrics = 0
    $totalAlerts = 0

    foreach ($device in $targetDevices) {
        $result = Collect-HardwareMetrics -Device $device -Thresholds $thresholds -DatabasePath $DatabasePath

        # Store metrics in database
        foreach ($metric in $result.Metrics) {
            try {
                $query = @"
INSERT INTO Metrics (DeviceId, MetricType, Value, Unit, Timestamp)
VALUES (@DeviceId, @MetricType, @Value, @Unit, CURRENT_TIMESTAMP)
"@

                Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $metric
                $totalMetrics++
            }
            catch {
                Write-Warning "Failed to store metric: $_"
                Write-RMMLog "Failed to store metric for $($device.Hostname): $_" -Level ERROR -Component "Hardware-Monitor"
            }
        }

        # Log alerts
        foreach ($alert in $result.Alerts) {
            Write-Host "[$($alert.Severity.ToUpper())] $($device.Hostname): $($alert.Message)" -ForegroundColor $(if ($alert.Severity -eq 'Critical') { 'Red' } else { 'Yellow' })
            $logLevel = if ($alert.Severity -eq 'Critical') { 'ERROR' } else { 'WARNING' }
            Write-RMMLog "$($device.Hostname): $($alert.Message)" -Level $logLevel -Component "Hardware-Monitor"
            Write-RMMDeviceLog -DeviceId $device.DeviceId -Message "Hardware alert: $($alert.Message)" -Level $logLevel
            $totalAlerts++
        }

        if ($result.Metrics.Count -gt 0) {
            Write-Host "[OK] $($device.Hostname): Collected $($result.Metrics.Count) metrics" -ForegroundColor Green
        }
    }

    Write-Host "[INFO] Stored $totalMetrics metrics, generated $totalAlerts alerts" -ForegroundColor Cyan
    Write-Host ""
    Write-RMMLog "Collection iteration $iteration complete: $totalMetrics metrics stored, $totalAlerts alerts generated" -Level INFO -Component "Hardware-Monitor"

    # Wait for next interval if duration is set
    if ($Duration -gt 0 -and (Get-Date) -lt $endTime) {
        Write-Host "[INFO] Waiting $Interval seconds until next collection..." -ForegroundColor Gray
        Start-Sleep -Seconds $Interval
    }

} while ($Duration -gt 0 -and (Get-Date) -lt $endTime)

Write-Host "[OK] Hardware monitoring completed" -ForegroundColor Green
Write-RMMLog "Hardware Monitor completed after $iteration iteration(s)" -Level SUCCESS -Component "Hardware-Monitor"

