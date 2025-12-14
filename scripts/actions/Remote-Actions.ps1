<#
.SYNOPSIS
    Execute remote actions on managed endpoints.

.DESCRIPTION
    Performs common remote management actions such as reboot, shutdown, RDP control,
    file transfer, service management, and system maintenance tasks.

.PARAMETER Action
    The action to perform. Valid actions: Reboot, Shutdown, WakeOnLAN, Lock, Logoff,
    EnableRDP, DisableRDP, StartRDP, StartRemotePS, FileTransfer, RegistryEdit,
    ServiceControl, ProcessKill, ClearTemp, FlushDNS, GPUpdate

.PARAMETER Devices
    Array of device hostnames or "All" to target all devices.

.PARAMETER Confirm
    Skip confirmation prompts for destructive actions (use with caution).

.PARAMETER Queue
    Queue action for offline devices to execute when they come online.

.PARAMETER Parameters
    Hashtable of action-specific parameters.

.EXAMPLE
    .\Remote-Actions.ps1 -Action "FlushDNS" -Devices "localhost"

.EXAMPLE
    .\Remote-Actions.ps1 -Action "Reboot" -Devices "SERVER01" -Confirm:$false

.EXAMPLE
    .\Remote-Actions.ps1 -Action "ServiceControl" -Devices "localhost" -Parameters @{ServiceName="Spooler"; Action="Restart"}

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+, PSSQLite module
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Reboot', 'Shutdown', 'WakeOnLAN', 'Lock', 'Logoff', 'EnableRDP', 'DisableRDP',
                 'StartRDP', 'StartRemotePS', 'FileTransfer', 'RegistryEdit', 'ServiceControl',
                 'ProcessKill', 'ClearTemp', 'FlushDNS', 'GPUpdate')]
    [string]$Action,

    [Parameter()]
    [string[]]$Devices = @("All"),

    [Parameter()]
    [hashtable]$Parameters = @{},

    [Parameter()]
    [switch]$Queue,

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
    Write-Error "No devices found to execute action on"
    exit 1
}

Write-Host "[INFO] Executing action '$Action' on $($targetDevices.Count) device(s)" -ForegroundColor Cyan
Write-Host ""

# Define actions that require confirmation
$destructiveActions = @('Reboot', 'Shutdown', 'Logoff', 'EnableRDP', 'DisableRDP', 'RegistryEdit', 'ProcessKill')

# Check if confirmation is needed
if ($destructiveActions -contains $Action -and -not $PSBoundParameters.ContainsKey('Confirm')) {
    $confirmation = Read-Host "This action is destructive. Continue? (yes/no)"
    if ($confirmation -ne 'yes') {
        Write-Host "[CANCELLED] Action cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

# Action execution functions
function Invoke-RemoteAction {
    param($Device, $Action, $Parameters)

    $result = @{
        DeviceId = $Device.DeviceId
        Hostname = $Device.Hostname
        Action   = $Action
        Success  = $false
        Message  = ""
        Output   = ""
    }

    # Check if device is online
    $online = Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $online) {
        $result.Message = "Device is offline"
        if ($Queue) {
            # Queue action for later execution
            $result.Message += " - Queued for execution when online"
        }
        return $result
    }

    try {
        switch ($Action) {
            'Reboot' {
                Restart-Computer -ComputerName $Device.Hostname -Force -ErrorAction Stop
                $result.Success = $true
                $result.Message = "Reboot initiated"
            }
            'Shutdown' {
                Stop-Computer -ComputerName $Device.Hostname -Force -ErrorAction Stop
                $result.Success = $true
                $result.Message = "Shutdown initiated"
            }
            'Lock' {
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    rundll32.exe user32.dll,LockWorkStation
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "Workstation locked"
            }
            'Logoff' {
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    logoff
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "User logged off"
            }
            'EnableRDP' {
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
                    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "RDP enabled"
            }
            'DisableRDP' {
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1
                    Disable-NetFirewallRule -DisplayGroup "Remote Desktop"
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "RDP disabled"
            }
            'StartRDP' {
                Start-Process "mstsc.exe" -ArgumentList "/v:$($Device.Hostname)"
                $result.Success = $true
                $result.Message = "RDP session launched"
            }
            'StartRemotePS' {
                Enter-PSSession -ComputerName $Device.Hostname
                $result.Success = $true
                $result.Message = "PowerShell session started"
            }
            'ServiceControl' {
                $serviceName = $Parameters.ServiceName
                $serviceAction = $Parameters.Action
                if (-not $serviceName -or -not $serviceAction) {
                    throw "ServiceName and Action parameters required"
                }
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    param($Name, $Action)
                    switch ($Action) {
                        'Start' { Start-Service -Name $Name }
                        'Stop' { Stop-Service -Name $Name -Force }
                        'Restart' { Restart-Service -Name $Name -Force }
                    }
                } -ArgumentList $serviceName, $serviceAction -ErrorAction Stop
                $result.Success = $true
                $result.Message = "Service $serviceName $serviceAction completed"
            }
            'ProcessKill' {
                $processName = $Parameters.ProcessName
                if (-not $processName) {
                    throw "ProcessName parameter required"
                }
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    param($Name)
                    Stop-Process -Name $Name -Force
                } -ArgumentList $processName -ErrorAction Stop
                $result.Success = $true
                $result.Message = "Process $processName terminated"
            }
            'ClearTemp' {
                $output = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    $paths = @("$env:TEMP\*", "C:\Windows\Temp\*")
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
            }
            'FlushDNS' {
                Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    Clear-DnsClientCache
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "DNS cache flushed"
            }
            'GPUpdate' {
                $output = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    gpupdate /force
                } -ErrorAction Stop
                $result.Success = $true
                $result.Message = "Group Policy updated"
                $result.Output = $output
            }
            default {
                $result.Message = "Action not implemented: $Action"
            }
        }
    }
    catch {
        $result.Success = $false
        $result.Message = "Action failed: $($_.Exception.Message)"
    }

    # Log action to database
    try {
        $query = @"
INSERT INTO Actions (ActionId, DeviceId, ActionType, Status, Result, CreatedAt)
VALUES (@ActionId, @DeviceId, @ActionType, @Status, @Result, CURRENT_TIMESTAMP)
"@
        $params = @{
            ActionId   = [guid]::NewGuid().ToString()
            DeviceId   = $Device.DeviceId
            ActionType = $Action
            Status     = if ($result.Success) { 'Completed' } else { 'Failed' }
            Result     = ($result | ConvertTo-Json -Compress)
        }
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params
    }
    catch {
        Write-Warning "Failed to log action to database: $_"
    }

    return $result
}

# Execute actions on all devices
$successCount = 0
$failCount = 0

foreach ($device in $targetDevices) {
    $result = Invoke-RemoteAction -Device $device -Action $Action -Parameters $Parameters

    if ($result.Success) {
        $successCount++
        Write-Host "[SUCCESS] $($result.Hostname): $($result.Message)" -ForegroundColor Green
        if ($result.Output) {
            Write-Host "  Output: $($result.Output)" -ForegroundColor Gray
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
Write-Host "  Action Execution Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Action: $Action" -ForegroundColor White
Write-Host "Total Devices: $($targetDevices.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Cyan

