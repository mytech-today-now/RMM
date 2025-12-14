<#
.SYNOPSIS
    Centralized event log collection from managed devices.

.DESCRIPTION
    Collects events from System, Application, Security, and PowerShell logs.
    Filters and normalizes event data for centralized storage and analysis.

.PARAMETER Devices
    Array of device hostnames, a group name, or "All" to collect from all devices.

.PARAMETER LogNames
    Event log names to collect from (default: System, Application, Security).

.PARAMETER Hours
    Number of hours of events to collect (default: 24).

.PARAMETER MinimumLevel
    Minimum event level: Error, Warning, Information (default: Warning).

.PARAMETER DatabasePath
    Path to the RMM database. If not specified, uses the default from RMM-Core.

.EXAMPLE
    .\Event-Collector.ps1 -Devices "localhost" -Hours 24

.EXAMPLE
    .\Event-Collector.ps1 -Devices "All" -LogNames "System","Application" -MinimumLevel Error

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
    [string[]]$LogNames = @('System', 'Application', 'Security'),

    [Parameter()]
    [int]$Hours = 24,

    [Parameter()]
    [ValidateSet('Error', 'Warning', 'Information')]
    [string]$MinimumLevel = 'Warning',

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

Write-Host "[INFO] Collecting events from $($targetDevices.Count) device(s)" -ForegroundColor Cyan
Write-Host "[INFO] Time range: Last $Hours hours" -ForegroundColor Cyan
Write-Host "[INFO] Minimum level: $MinimumLevel" -ForegroundColor Cyan
Write-Host ""

# Event collection function
function Collect-Events {
    param($Device, $LogNames, $Hours, $MinimumLevel)

    $events = @()
    $startTime = (Get-Date).AddHours(-$Hours)

    try {
        # Test connectivity
        if (-not (Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Write-Warning "$($Device.Hostname): Device is offline"
            return $events
        }

        # Determine level filter
        $levelFilter = switch ($MinimumLevel) {
            'Error' { 1, 2 }
            'Warning' { 1, 2, 3 }
            'Information' { 1, 2, 3, 4 }
        }

        foreach ($logName in $LogNames) {
            try {
                $logEvents = Get-WinEvent -ComputerName $Device.Hostname -FilterHashtable @{
                    LogName   = $logName
                    StartTime = $startTime
                    Level     = $levelFilter
                } -MaxEvents 100 -ErrorAction SilentlyContinue

                foreach ($event in $logEvents) {
                    $events += @{
                        DeviceId    = $Device.DeviceId
                        LogName     = $event.LogName
                        EventId     = $event.Id
                        Level       = $event.LevelDisplayName
                        Message     = $event.Message
                        TimeCreated = $event.TimeCreated
                        Source      = $event.ProviderName
                    }
                }
            }
            catch {
                Write-Warning "$($Device.Hostname): Failed to collect from $logName : $_"
            }
        }

        Write-Host "[OK] $($Device.Hostname): Collected $($events.Count) events" -ForegroundColor Green
    }
    catch {
        Write-Warning "$($Device.Hostname): Event collection failed: $_"
    }

    return $events
}

# Execute collection
$totalEvents = 0

foreach ($device in $targetDevices) {
    $events = Collect-Events -Device $device -LogNames $LogNames -Hours $Hours -MinimumLevel $MinimumLevel
    $totalEvents += $events.Count
}

Write-Host ""
Write-Host "[OK] Event collection completed. Total events: $totalEvents" -ForegroundColor Green
