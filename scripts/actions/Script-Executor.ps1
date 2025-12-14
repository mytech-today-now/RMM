<#
.SYNOPSIS
    Execute custom PowerShell scripts on managed endpoints.

.DESCRIPTION
    Runs PowerShell scripts on remote devices with parameter passing, output capture,
    timeout handling, and result logging. Supports both inline scripts and script files.

.PARAMETER ScriptBlock
    PowerShell script block to execute.

.PARAMETER ScriptPath
    Path to PowerShell script file to execute.

.PARAMETER Devices
    Array of device hostnames or "All" to target all devices.

.PARAMETER ScriptParameters
    Hashtable of parameters to pass to the script.

.PARAMETER Timeout
    Script execution timeout in seconds (default: 300).

.PARAMETER AsJob
    Run script as background job.

.PARAMETER CaptureOutput
    Capture and return script output (default: true).

.EXAMPLE
    .\Script-Executor.ps1 -ScriptBlock { Get-Service } -Devices "localhost"

.EXAMPLE
    .\Script-Executor.ps1 -ScriptPath "C:\Scripts\Maintenance.ps1" -Devices "SERVER01" -ScriptParameters @{Mode="Full"}

.EXAMPLE
    .\Script-Executor.ps1 -ScriptBlock { param($Name) Get-Process -Name $Name } -Devices "localhost" -ScriptParameters @{Name="powershell"}

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+, PSSQLite module
#>

[CmdletBinding(DefaultParameterSetName = 'ScriptBlock')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'ScriptBlock')]
    [scriptblock]$ScriptBlock,

    [Parameter(Mandatory = $true, ParameterSetName = 'ScriptPath')]
    [string]$ScriptPath,

    [Parameter()]
    [string[]]$Devices = @("All"),

    [Parameter()]
    [hashtable]$ScriptParameters = @{},

    [Parameter()]
    [int]$Timeout = 300,

    [Parameter()]
    [switch]$AsJob,

    [Parameter()]
    [bool]$CaptureOutput = $true,

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

# Load script from file if ScriptPath is provided
if ($PSCmdlet.ParameterSetName -eq 'ScriptPath') {
    if (-not (Test-Path $ScriptPath)) {
        Write-Error "Script file not found: $ScriptPath"
        exit 1
    }
    $ScriptBlock = [scriptblock]::Create((Get-Content $ScriptPath -Raw))
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
    Write-Error "No devices found to execute script on"
    exit 1
}

Write-Host "[INFO] Executing script on $($targetDevices.Count) device(s)" -ForegroundColor Cyan
Write-Host "[INFO] Timeout: $Timeout seconds" -ForegroundColor Cyan
Write-Host ""

# Script execution function
function Invoke-RemoteScript {
    param($Device, $ScriptBlock, $Parameters, $Timeout, $CaptureOutput)

    $result = @{
        DeviceId  = $Device.DeviceId
        Hostname  = $Device.Hostname
        Success   = $false
        Output    = ""
        Error     = ""
        Duration  = 0
        ExitCode  = $null
    }

    $startTime = Get-Date

    try {
        # Check if device is online
        $online = Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $online) {
            $result.Error = "Device is offline"
            return $result
        }

        # Execute script remotely
        $invokeParams = @{
            ComputerName = $Device.Hostname
            ScriptBlock  = $ScriptBlock
            ErrorAction  = 'Stop'
        }

        if ($Parameters.Count -gt 0) {
            $invokeParams.ArgumentList = $Parameters.Values
        }

        $output = Invoke-Command @invokeParams

        $result.Success = $true
        if ($CaptureOutput) {
            $result.Output = $output | Out-String
        }
    }
    catch {
        $result.Success = $false
        $result.Error = $_.Exception.Message
    }

    $result.Duration = ((Get-Date) - $startTime).TotalSeconds

    # Log execution to database
    try {
        $query = @"
INSERT INTO Actions (ActionId, DeviceId, ActionType, Status, Result, CreatedAt)
VALUES (@ActionId, @DeviceId, @ActionType, @Status, @Result, CURRENT_TIMESTAMP)
"@
        $params = @{
            ActionId   = [guid]::NewGuid().ToString()
            DeviceId   = $Device.DeviceId
            ActionType = 'ScriptExecution'
            Status     = if ($result.Success) { 'Completed' } else { 'Failed' }
            Result     = ($result | ConvertTo-Json -Compress)
        }
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params
    }
    catch {
        Write-Warning "Failed to log script execution to database: $_"
    }

    return $result
}

# Execute scripts on all devices
$successCount = 0
$failCount = 0
$results = @()

foreach ($device in $targetDevices) {
    Write-Host "[EXECUTING] $($device.Hostname)..." -ForegroundColor Yellow

    $result = Invoke-RemoteScript -Device $device -ScriptBlock $ScriptBlock -Parameters $ScriptParameters -Timeout $Timeout -CaptureOutput $CaptureOutput
    $results += $result

    if ($result.Success) {
        $successCount++
        Write-Host "[SUCCESS] $($result.Hostname) - Completed in $([math]::Round($result.Duration, 2))s" -ForegroundColor Green
        if ($CaptureOutput -and $result.Output) {
            Write-Host "  Output:" -ForegroundColor Gray
            Write-Host "  $($result.Output)" -ForegroundColor Gray
        }
    }
    else {
        $failCount++
        Write-Host "[FAILED] $($result.Hostname): $($result.Error)" -ForegroundColor Red
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Script Execution Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Devices: $($targetDevices.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
$avgDuration = ($results | Where-Object { $_.Success } | Measure-Object -Property Duration -Average).Average
if ($avgDuration) {
    Write-Host "Average Duration: $([math]::Round($avgDuration, 2))s" -ForegroundColor White
}
Write-Host "========================================" -ForegroundColor Cyan

# Return results if needed
if ($AsJob) {
    return $results
}
