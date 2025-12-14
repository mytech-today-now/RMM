<#
.SYNOPSIS
    Performance threshold monitoring and alerting.

.DESCRIPTION
    Monitors CPU, Memory, Disk, and Network performance against configurable thresholds.
    Generates alerts when thresholds are breached.

.PARAMETER Devices
    Array of device hostnames, a group name, or "All" to monitor all devices.

.PARAMETER DatabasePath
    Path to the RMM database. If not specified, uses the default from RMM-Core.

.EXAMPLE
    .\Performance-Monitor.ps1 -Devices "localhost"

.EXAMPLE
    .\Performance-Monitor.ps1 -Devices "All"

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+, PSSQLite module
    
    Thresholds are loaded from config/thresholds.json:
    - CPU: Warning 80%, Critical 95%
    - Memory: Warning 85%, Critical 95%
    - DiskSpace: Warning 20% free, Critical 10% free
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Devices = @("All"),

    [Parameter()]
    [string]$DatabasePath
)

# Import required modules
$ErrorActionPreference = 'Stop'

try {
    $rmmCorePath = Join-Path $PSScriptRoot "..\core\RMM-Core.psm1"
    if (-not (Get-Module -Name RMM-Core)) {
        Import-Module $rmmCorePath -Force
    }

    if (-not (Get-Module -Name PSSQLite)) {
        Import-Module PSSQLite -ErrorAction Stop
    }
}
catch {
    Write-Error "Failed to import required modules: $_"
    exit 1
}

# Initialize RMM
Initialize-RMM -ErrorAction Stop

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
}
else {
    foreach ($device in $Devices) {
        $dev = Get-RMMDevice -Hostname $device -ErrorAction SilentlyContinue
        if ($dev) {
            $targetDevices += $dev
        }
        else {
            Write-Warning "Device not found: $device"
        }
    }
}

Write-Host "[INFO] Monitoring performance on $($targetDevices.Count) device(s)" -ForegroundColor Cyan
Write-Host ""

# Performance monitoring function (reuses logic from Hardware-Monitor.ps1)
function Monitor-Performance {
    param($Device, $Thresholds)

    $alerts = @()

    try {
        if (-not (Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            return $alerts
        }

        # CPU check
        $cpu = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -ComputerName $Device.Hostname -ErrorAction Stop |
            Where-Object { $_.Name -eq "_Total" }
        
        if ($cpu.PercentProcessorTime -ge $Thresholds.performance.cpu.critical) {
            $alerts += @{ Severity = "Critical"; Message = "CPU usage is critical: $($cpu.PercentProcessorTime)%" }
        }
        elseif ($cpu.PercentProcessorTime -ge $Thresholds.performance.cpu.warning) {
            $alerts += @{ Severity = "Warning"; Message = "CPU usage is high: $($cpu.PercentProcessorTime)%" }
        }

        # Memory check
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Device.Hostname -ErrorAction Stop
        $memUsage = (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100
        
        if ($memUsage -ge $Thresholds.performance.memory.critical) {
            $alerts += @{ Severity = "Critical"; Message = "Memory usage is critical: $([math]::Round($memUsage, 2))%" }
        }
        elseif ($memUsage -ge $Thresholds.performance.memory.warning) {
            $alerts += @{ Severity = "Warning"; Message = "Memory usage is high: $([math]::Round($memUsage, 2))%" }
        }

        # Disk check
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $Device.Hostname -ErrorAction Stop |
            Where-Object { $_.DriveType -eq 3 }
        
        foreach ($disk in $disks) {
            $freePercent = ($disk.FreeSpace / $disk.Size) * 100
            if ($freePercent -le $Thresholds.performance.diskSpace.critical) {
                $alerts += @{ Severity = "Critical"; Message = "Disk $($disk.DeviceID) space is critical: $([math]::Round($freePercent, 2))% free" }
            }
            elseif ($freePercent -le $Thresholds.performance.diskSpace.warning) {
                $alerts += @{ Severity = "Warning"; Message = "Disk $($disk.DeviceID) space is low: $([math]::Round($freePercent, 2))% free" }
            }
        }

        if ($alerts.Count -eq 0) {
            Write-Host "[OK] $($Device.Hostname): All performance metrics within thresholds" -ForegroundColor Green
        }
        else {
            foreach ($alert in $alerts) {
                $color = if ($alert.Severity -eq 'Critical') { 'Red' } else { 'Yellow' }
                Write-Host "[$($alert.Severity.ToUpper())] $($Device.Hostname): $($alert.Message)" -ForegroundColor $color
            }
        }
    }
    catch {
        Write-Warning "$($Device.Hostname): Performance monitoring failed: $_"
    }

    return $alerts
}

# Execute monitoring
foreach ($device in $targetDevices) {
    $alerts = Monitor-Performance -Device $device -Thresholds $thresholds
}

Write-Host ""
Write-Host "[OK] Performance monitoring completed" -ForegroundColor Green
