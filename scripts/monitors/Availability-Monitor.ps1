<#
.SYNOPSIS
    Uptime and connectivity monitoring.

.DESCRIPTION
    Monitors device availability using multiple methods: ICMP ping, WinRM test, and port checks.
    Updates device status and LastSeen timestamp in the database.

.PARAMETER Devices
    Array of device hostnames, a group name, or "All" to monitor all devices.

.PARAMETER Methods
    Monitoring methods to use: ICMP, WinRM, Port, HTTP (default: ICMP, WinRM).

.PARAMETER DatabasePath
    Path to the RMM database. If not specified, uses the default from RMM-Core.

.EXAMPLE
    .\Availability-Monitor.ps1 -Devices "localhost"

.EXAMPLE
    .\Availability-Monitor.ps1 -Devices "All" -Methods "ICMP","WinRM","Port"

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
    [ValidateSet('ICMP', 'WinRM', 'Port', 'HTTP')]
    [string[]]$Methods = @('ICMP', 'WinRM'),

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

Write-Host "[INFO] Monitoring availability of $($targetDevices.Count) device(s)" -ForegroundColor Cyan
Write-Host "[INFO] Methods: $($Methods -join ', ')" -ForegroundColor Cyan
Write-Host ""

# Availability check function
function Test-Availability {
    param($Device, $Methods)

    $results = @{
        DeviceId   = $Device.DeviceId
        Hostname   = $Device.Hostname
        Online     = $false
        Latency    = $null
        Methods    = @{}
    }

    # ICMP Ping
    if ($Methods -contains 'ICMP') {
        try {
            $ping = Test-Connection -ComputerName $Device.Hostname -Count 2 -ErrorAction SilentlyContinue
            if ($ping) {
                $results.Methods.ICMP = $true
                $results.Online = $true
                $results.Latency = ($ping | Measure-Object -Property ResponseTime -Average).Average
            }
            else {
                $results.Methods.ICMP = $false
            }
        }
        catch {
            $results.Methods.ICMP = $false
        }
    }

    # WinRM Test (checks both HTTP and HTTPS)
    if ($Methods -contains 'WinRM') {
        try {
            $winrm = Test-WSMan -ComputerName $Device.Hostname -ErrorAction SilentlyContinue
            $results.Methods.WinRM = ($null -ne $winrm)
            if ($results.Methods.WinRM) {
                $results.Online = $true
            }

            # Also check HTTPS availability for workgroup support
            $httpsAvailable = Test-RMMRemoteHTTPS -ComputerName $Device.Hostname
            $results.Methods.WinRMHTTPS = $httpsAvailable
        }
        catch {
            $results.Methods.WinRM = $false
            $results.Methods.WinRMHTTPS = $false
        }
    }

    # Port Check (checks both 5985 HTTP and 5986 HTTPS for WinRM)
    if ($Methods -contains 'Port') {
        try {
            # Check HTTP port 5985
            $portHttp = Test-NetConnection -ComputerName $Device.Hostname -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $results.Methods.Port = $portHttp.TcpTestSucceeded
            $results.Methods.PortHTTP = $portHttp.TcpTestSucceeded

            # Check HTTPS port 5986
            $portHttps = Test-NetConnection -ComputerName $Device.Hostname -Port 5986 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $results.Methods.PortHTTPS = $portHttps.TcpTestSucceeded

            if ($results.Methods.Port -or $results.Methods.PortHTTPS) {
                $results.Online = $true
            }
        }
        catch {
            $results.Methods.Port = $false
            $results.Methods.PortHTTP = $false
            $results.Methods.PortHTTPS = $false
        }
    }

    return $results
}

# Execute availability monitoring
$onlineCount = 0
$offlineCount = 0

foreach ($device in $targetDevices) {
    $result = Test-Availability -Device $device -Methods $Methods
    
    if ($result.Online) {
        $onlineCount++
        $latencyInfo = if ($result.Latency) { " (Latency: $([math]::Round($result.Latency, 2))ms)" } else { "" }
        Write-Host "[ONLINE] $($result.Hostname)$latencyInfo" -ForegroundColor Green
        
        # Update database
        try {
            $query = "UPDATE Devices SET Status = 'Online', LastSeen = CURRENT_TIMESTAMP WHERE DeviceId = @DeviceId"
            Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ DeviceId = $result.DeviceId }
        }
        catch {
            Write-Warning "Failed to update device status: $_"
        }
    }
    else {
        $offlineCount++
        Write-Host "[OFFLINE] $($result.Hostname)" -ForegroundColor Red
        
        # Update database
        try {
            $query = "UPDATE Devices SET Status = 'Offline' WHERE DeviceId = @DeviceId"
            Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ DeviceId = $result.DeviceId }
        }
        catch {
            Write-Warning "Failed to update device status: $_"
        }
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Availability Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Online: $onlineCount" -ForegroundColor Green
Write-Host "Offline: $offlineCount" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Cyan
