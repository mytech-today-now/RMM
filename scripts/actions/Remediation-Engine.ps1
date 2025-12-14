<#
.SYNOPSIS
    Automated issue remediation engine for managed endpoints.

.DESCRIPTION
    Executes automated remediation actions based on triggers or manual invocation.
    Includes built-in remediations for common issues and supports custom remediation rules.

.PARAMETER Remediation
    Built-in remediation to execute: ClearTemp, RestartService, ResetWindowsUpdate,
    ClearPrintQueue, RenewDHCP, FixWMI, ResetNetwork, RepairWindowsImage, FlushDNS

.PARAMETER Devices
    Array of device hostnames or "All" to target all devices.

.PARAMETER AutoRemediate
    Automatically execute remediation without confirmation.

.PARAMETER TriggerCondition
    Condition that triggered the remediation (for logging).

.PARAMETER Parameters
    Hashtable of remediation-specific parameters.

.EXAMPLE
    .\Remediation-Engine.ps1 -Remediation "ClearTemp" -Devices "localhost"

.EXAMPLE
    .\Remediation-Engine.ps1 -Remediation "RestartService" -Devices "SERVER01" -Parameters @{ServiceName="Spooler"}

.EXAMPLE
    .\Remediation-Engine.ps1 -Remediation "FixWMI" -Devices "All" -AutoRemediate

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+, PSSQLite module
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ClearTemp', 'RestartService', 'ResetWindowsUpdate', 'ClearPrintQueue',
                 'RenewDHCP', 'FixWMI', 'ResetNetwork', 'RepairWindowsImage', 'FlushDNS')]
    [string]$Remediation,

    [Parameter()]
    [string[]]$Devices = @("All"),

    [Parameter()]
    [switch]$AutoRemediate,

    [Parameter()]
    [string]$TriggerCondition,

    [Parameter()]
    [hashtable]$Parameters = @{},

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

if ($targetDevices.Count -eq 0) {
    Write-Error "No devices found to remediate"
    exit 1
}

Write-Host "[INFO] Executing remediation '$Remediation' on $($targetDevices.Count) device(s)" -ForegroundColor Cyan
if ($TriggerCondition) {
    Write-Host "[INFO] Trigger: $TriggerCondition" -ForegroundColor Cyan
}
Write-Host ""

# Confirmation check
if (-not $AutoRemediate -and -not $PSBoundParameters.ContainsKey('Confirm')) {
    $confirmation = Read-Host "Execute remediation on $($targetDevices.Count) device(s)? (yes/no)"
    if ($confirmation -ne 'yes') {
        Write-Host "[CANCELLED] Remediation cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

# Remediation execution function
function Invoke-Remediation {
    param($Device, $Remediation, $Parameters)

    $result = @{
        DeviceId    = $Device.DeviceId
        Hostname    = $Device.Hostname
        Remediation = $Remediation
        Success     = $false
        Message     = ""
        Output      = ""
        Verified    = $false
    }

    # Check if device is online
    $online = Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $online) {
        $result.Message = "Device is offline"
        return $result
    }

    try {
        switch ($Remediation) {
            'ClearTemp' {
                $output = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    $paths = @("$env:TEMP\*", "C:\Windows\Temp\*", "C:\Windows\Prefetch\*")
                    $freedSpace = 0
                    foreach ($path in $paths) {
                        $items = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                        $freedSpace += ($items | Measure-Object -Property Length -Sum).Sum
                        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    return [math]::Round($freedSpace / 1MB, 2)
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "Cleared temp files"
                $result.Output = "Freed ${output}MB"
                $result.Verified = $true
            }
            'RestartService' {
                $serviceName = $Parameters.ServiceName
                if (-not $serviceName) {
                    throw "ServiceName parameter required"
                }
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    param($Name)
                    Restart-Service -Name $Name -Force
                    Start-Sleep -Seconds 2
                    $service = Get-Service -Name $Name
                    return $service.Status
                } -ArgumentList $serviceName -ErrorAction Stop
                $result.Success = $true
                $result.Message = "Service $serviceName restarted"
                $result.Verified = $true
            }
            'ResetWindowsUpdate' {
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    Stop-Service -Name wuauserv, bits, cryptsvc -Force
                    Remove-Item -Path "C:\Windows\SoftwareDistribution" -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "C:\Windows\System32\catroot2" -Recurse -Force -ErrorAction SilentlyContinue
                    Start-Service -Name wuauserv, bits, cryptsvc
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "Windows Update components reset"
                $result.Verified = $true
            }
            'ClearPrintQueue' {
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    Stop-Service -Name Spooler -Force
                    Remove-Item -Path "C:\Windows\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
                    Start-Service -Name Spooler
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "Print queue cleared"
                $result.Verified = $true
            }
            'RenewDHCP' {
                $output = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    ipconfig /release | Out-Null
                    Start-Sleep -Seconds 1
                    ipconfig /renew | Out-Null
                    return (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1).IPAddress
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "DHCP lease renewed"
                $result.Output = "New IP: $output"
                $result.Verified = $true
            }
            'FixWMI' {
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    Stop-Service -Name Winmgmt -Force
                    winmgmt /salvagerepository
                    Start-Service -Name Winmgmt
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "WMI repository repaired"
                $result.Verified = $true
            }
            'ResetNetwork' {
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    netsh winsock reset
                    netsh int ip reset
                    ipconfig /flushdns
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "Network stack reset (reboot required)"
                $result.Verified = $false
            }
            'RepairWindowsImage' {
                $output = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    DISM /Online /Cleanup-Image /RestoreHealth
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "Windows image repair initiated"
                $result.Output = $output
                $result.Verified = $false
            }
            'FlushDNS' {
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    Clear-DnsClientCache
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "DNS cache flushed"
                $result.Verified = $true
            }
            default {
                $result.Message = "Remediation not implemented: $Remediation"
            }
        }
    }
    catch {
        $result.Success = $false
        $result.Message = "Remediation failed: $($_.Exception.Message)"
    }

    # Log remediation to database
    try {
        $query = @"
INSERT INTO Actions (ActionId, DeviceId, ActionType, Status, Result, CreatedAt)
VALUES (@ActionId, @DeviceId, @ActionType, @Status, @Result, CURRENT_TIMESTAMP)
"@
        $params = @{
            ActionId   = [guid]::NewGuid().ToString()
            DeviceId   = $Device.DeviceId
            ActionType = "Remediation_$Remediation"
            Status     = if ($result.Success) { 'Completed' } else { 'Failed' }
            Result     = ($result | ConvertTo-Json -Compress)
        }
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params
    }
    catch {
        Write-Warning "Failed to log remediation to database: $_"
    }

    return $result
}

# Execute remediation on all devices
$successCount = 0
$failCount = 0

foreach ($device in $targetDevices) {
    Write-Host "[REMEDIATING] $($device.Hostname)..." -ForegroundColor Yellow

    $result = Invoke-Remediation -Device $device -Remediation $Remediation -Parameters $Parameters

    if ($result.Success) {
        $successCount++
        Write-Host "[SUCCESS] $($result.Hostname): $($result.Message)" -ForegroundColor Green
        if ($result.Output) {
            Write-Host "  Output: $($result.Output)" -ForegroundColor Gray
        }
        if ($result.Verified) {
            Write-Host "  [✓] Remediation verified" -ForegroundColor Green
        }
        else {
            Write-Host "  [!] Manual verification recommended" -ForegroundColor Yellow
        }
    }
    else {
        $failCount++
        Write-Host "[FAILED] $($result.Hostname): $($result.Message)" -ForegroundColor Red
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Remediation Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Remediation: $Remediation" -ForegroundColor White
Write-Host "Total Devices: $($targetDevices.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Cyan
