<#
.SYNOPSIS
    Critical service monitoring and auto-remediation.

.DESCRIPTION
    Monitors critical services on managed devices and optionally auto-restarts failed services.
    Tracks service uptime and generates alerts for service failures.

.PARAMETER Devices
    Array of device hostnames, a group name, or "All" to monitor all devices.

.PARAMETER Services
    Array of service names to monitor. If not specified, monitors common critical services.

.PARAMETER AutoRestart
    Automatically restart stopped critical services.

.PARAMETER DatabasePath
    Path to the RMM database. If not specified, uses the default from RMM-Core.

.EXAMPLE
    .\Service-Monitor.ps1 -Devices "localhost" -Services "Spooler","W32Time"

.EXAMPLE
    .\Service-Monitor.ps1 -Devices "All" -AutoRestart

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
    [string[]]$Services = @('Spooler', 'W32Time', 'Winmgmt', 'WinRM'),

    [Parameter()]
    [switch]$AutoRestart,

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

Write-Host "[INFO] Monitoring services on $($targetDevices.Count) device(s)" -ForegroundColor Cyan
Write-Host "[INFO] Services: $($Services -join ', ')" -ForegroundColor Cyan
if ($AutoRestart) {
    Write-Host "[INFO] Auto-restart is ENABLED" -ForegroundColor Yellow
}
Write-Host ""

# Service monitoring function
function Monitor-Services {
    param($Device, $ServiceNames, $AutoRestart)

    $results = @{
        DeviceId       = $Device.DeviceId
        Hostname       = $Device.Hostname
        ServicesOK     = 0
        ServicesFailed = 0
        ServicesRestarted = 0
        Issues         = @()
    }

    try {
        # Test connectivity
        if (-not (Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            $results.Issues += "Device is offline"
            return $results
        }

        foreach ($serviceName in $ServiceNames) {
            try {
                $service = Get-Service -Name $serviceName -ComputerName $Device.Hostname -ErrorAction Stop
                
                if ($service.Status -eq 'Running') {
                    $results.ServicesOK++
                }
                else {
                    $results.ServicesFailed++
                    $results.Issues += "$serviceName is $($service.Status)"
                    
                    if ($AutoRestart -and $service.StartType -ne 'Disabled') {
                        try {
                            Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                                param($svcName)
                                Start-Service -Name $svcName -ErrorAction Stop
                            } -ArgumentList $serviceName -ErrorAction Stop
                            
                            $results.ServicesRestarted++
                            Write-Host "[RESTART] $($Device.Hostname): Restarted service $serviceName" -ForegroundColor Yellow
                        }
                        catch {
                            Write-Warning "$($Device.Hostname): Failed to restart $serviceName : $_"
                        }
                    }
                }
            }
            catch {
                $results.Issues += "Failed to check $serviceName : $_"
            }
        }

        $status = if ($results.ServicesFailed -eq 0) { "OK" } else { "WARN" }
        $color = if ($results.ServicesFailed -eq 0) { "Green" } else { "Yellow" }
        
        Write-Host "[$status] $($Device.Hostname): $($results.ServicesOK)/$($ServiceNames.Count) services running" -ForegroundColor $color
    }
    catch {
        $results.Issues += "Service monitoring failed: $_"
    }

    return $results
}

# Execute monitoring
foreach ($device in $targetDevices) {
    $result = Monitor-Services -Device $device -ServiceNames $Services -AutoRestart $AutoRestart
}

Write-Host ""
Write-Host "[OK] Service monitoring completed" -ForegroundColor Green
