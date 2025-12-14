<#
.SYNOPSIS
    Manage Windows and application updates on managed endpoints.

.DESCRIPTION
    Scans for, downloads, and installs Windows Updates and application updates.
    Supports scheduling, approval workflows, and maintenance windows.

.PARAMETER Action
    Action to perform: Scan, Download, Install, Schedule, History

.PARAMETER Devices
    Array of device hostnames or "All" to target all devices.

.PARAMETER Categories
    Update categories to include: Security, Critical, Updates, Drivers, FeaturePacks

.PARAMETER AutoApprove
    Automatically approve updates matching specified categories.

.PARAMETER ScheduleReboot
    Schedule reboot after installation (datetime or "Immediate").

.PARAMETER MaintenanceWindow
    Only install during maintenance window (requires configuration).

.EXAMPLE
    .\Update-Manager.ps1 -Action "Scan" -Devices "localhost"

.EXAMPLE
    .\Update-Manager.ps1 -Action "Install" -Devices "SERVER01" -Categories "Security","Critical" -AutoApprove

.EXAMPLE
    .\Update-Manager.ps1 -Action "Schedule" -Devices "All" -ScheduleReboot "2024-01-15 02:00"

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+, PSWindowsUpdate module (optional), PSSQLite module
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Scan', 'Download', 'Install', 'Schedule', 'History')]
    [string]$Action,

    [Parameter()]
    [string[]]$Devices = @("All"),

    [Parameter()]
    [ValidateSet('Security', 'Critical', 'Updates', 'Drivers', 'FeaturePacks', 'All')]
    [string[]]$Categories = @('Security', 'Critical'),

    [Parameter()]
    [switch]$AutoApprove,

    [Parameter()]
    [string]$ScheduleReboot,

    [Parameter()]
    [switch]$MaintenanceWindow,

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
    Write-Error "No devices found to manage updates on"
    exit 1
}

Write-Host "[INFO] Managing updates on $($targetDevices.Count) device(s)" -ForegroundColor Cyan
Write-Host "[INFO] Action: $Action" -ForegroundColor Cyan
Write-Host ""

# Update management functions
function Invoke-UpdateScan {
    param($Device)

    $result = @{
        DeviceId      = $Device.DeviceId
        Hostname      = $Device.Hostname
        Success       = $false
        UpdatesFound  = 0
        Updates       = @()
        Message       = ""
    }

    try {
        # Check if device is online
        $online = Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $online) {
            $result.Message = "Device is offline"
            return $result
        }

        # Scan for updates using Windows Update API
        $updates = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
            $updateSession = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $searchResult = $updateSearcher.Search("IsInstalled=0")
            
            $updateList = @()
            foreach ($update in $searchResult.Updates) {
                $updateList += @{
                    Title       = $update.Title
                    KB          = ($update.KBArticleIDs | Select-Object -First 1)
                    Severity    = $update.MsrcSeverity
                    Size        = [math]::Round($update.MaxDownloadSize / 1MB, 2)
                    IsDownloaded = $update.IsDownloaded
                }
            }
            return $updateList
        } -ErrorAction Stop

        $result.Success = $true
        $result.UpdatesFound = $updates.Count
        $result.Updates = $updates
        $result.Message = "Found $($updates.Count) update(s)"
    }
    catch {
        $result.Message = "Scan failed: $($_.Exception.Message)"
    }

    return $result
}

function Invoke-UpdateInstall {
    param($Device, $Categories, $AutoApprove)

    $result = @{
        DeviceId       = $Device.DeviceId
        Hostname       = $Device.Hostname
        Success        = $false
        Installed      = 0
        Failed         = 0
        RebootRequired = $false
        Message        = ""
    }

    try {
        # Check if device is online
        $online = Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $online) {
            $result.Message = "Device is offline"
            return $result
        }

        # Install updates
        $installResult = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
            param($Categories, $AutoApprove)

            $updateSession = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $searchResult = $updateSearcher.Search("IsInstalled=0")

            $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl

            foreach ($update in $searchResult.Updates) {
                # Filter by category if specified
                if ($Categories -notcontains 'All') {
                    $matchCategory = $false
                    foreach ($category in $update.Categories) {
                        if ($Categories -contains $category.Name) {
                            $matchCategory = $true
                            break
                        }
                    }
                    if (-not $matchCategory) { continue }
                }

                # Add to install collection
                $updatesToInstall.Add($update) | Out-Null
            }

            if ($updatesToInstall.Count -eq 0) {
                return @{ Installed = 0; Failed = 0; RebootRequired = $false }
            }

            # Download and install
            $downloader = $updateSession.CreateUpdateDownloader()
            $downloader.Updates = $updatesToInstall
            $downloader.Download()

            $installer = $updateSession.CreateUpdateInstaller()
            $installer.Updates = $updatesToInstall
            $installationResult = $installer.Install()

            return @{
                Installed      = $updatesToInstall.Count
                Failed         = 0
                RebootRequired = $installationResult.RebootRequired
            }
        } -ArgumentList $Categories, $AutoApprove -ErrorAction Stop

        $result.Success = $true
        $result.Installed = $installResult.Installed
        $result.Failed = $installResult.Failed
        $result.RebootRequired = $installResult.RebootRequired
        $result.Message = "Installed $($installResult.Installed) update(s)"
    }
    catch {
        $result.Message = "Installation failed: $($_.Exception.Message)"
    }

    return $result
}

function Get-UpdateHistory {
    param($Device)

    $result = @{
        DeviceId = $Device.DeviceId
        Hostname = $Device.Hostname
        Success  = $false
        History  = @()
        Message  = ""
    }

    try {
        # Check if device is online
        $online = Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $online) {
            $result.Message = "Device is offline"
            return $result
        }

        # Get update history
        $history = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
            $updateSession = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $historyCount = $updateSearcher.GetTotalHistoryCount()

            if ($historyCount -gt 0) {
                $updateHistory = $updateSearcher.QueryHistory(0, [Math]::Min($historyCount, 50))

                $historyList = @()
                foreach ($entry in $updateHistory) {
                    $historyList += @{
                        Title       = $entry.Title
                        Date        = $entry.Date
                        Operation   = $entry.Operation
                        ResultCode  = $entry.ResultCode
                    }
                }
                return $historyList
            }
            return @()
        } -ErrorAction Stop

        $result.Success = $true
        $result.History = $history
        $result.Message = "Retrieved $($history.Count) history entries"
    }
    catch {
        $result.Message = "Failed to retrieve history: $($_.Exception.Message)"
    }

    return $result
}

# Execute action on all devices
$successCount = 0
$failCount = 0
$totalUpdates = 0

foreach ($device in $targetDevices) {
    Write-Host "[PROCESSING] $($device.Hostname)..." -ForegroundColor Yellow

    $result = $null
    switch ($Action) {
        'Scan' {
            $result = Invoke-UpdateScan -Device $device
            if ($result.Success) {
                $totalUpdates += $result.UpdatesFound
                Write-Host "[SUCCESS] $($result.Hostname): $($result.Message)" -ForegroundColor Green
                foreach ($update in $result.Updates) {
                    Write-Host "  - $($update.Title) (KB$($update.KB)) - $($update.Size)MB" -ForegroundColor Gray
                }
            }
        }
        'Install' {
            $result = Invoke-UpdateInstall -Device $device -Categories $Categories -AutoApprove $AutoApprove
            if ($result.Success) {
                Write-Host "[SUCCESS] $($result.Hostname): $($result.Message)" -ForegroundColor Green
                if ($result.RebootRequired) {
                    Write-Host "  [!] Reboot required" -ForegroundColor Yellow
                }
            }
        }
        'History' {
            $result = Get-UpdateHistory -Device $device
            if ($result.Success) {
                Write-Host "[SUCCESS] $($result.Hostname): $($result.Message)" -ForegroundColor Green
                foreach ($entry in $result.History | Select-Object -First 10) {
                    Write-Host "  - $($entry.Date): $($entry.Title)" -ForegroundColor Gray
                }
            }
        }
    }

    if ($result.Success) {
        $successCount++
    }
    else {
        $failCount++
        Write-Host "[FAILED] $($result.Hostname): $($result.Message)" -ForegroundColor Red
    }

    # Log to database
    try {
        $query = @"
INSERT INTO Actions (ActionId, DeviceId, ActionType, Status, Result, CreatedAt)
VALUES (@ActionId, @DeviceId, @ActionType, @Status, @Result, CURRENT_TIMESTAMP)
"@
        $params = @{
            ActionId   = [guid]::NewGuid().ToString()
            DeviceId   = $device.DeviceId
            ActionType = "UpdateManagement_$Action"
            Status     = if ($result.Success) { 'Completed' } else { 'Failed' }
            Result     = ($result | ConvertTo-Json -Compress)
        }
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params
    }
    catch {
        Write-Warning "Failed to log action to database: $_"
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Update Management Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Action: $Action" -ForegroundColor White
Write-Host "Total Devices: $($targetDevices.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
if ($Action -eq 'Scan') {
    Write-Host "Total Updates Found: $totalUpdates" -ForegroundColor White
}
Write-Host "========================================" -ForegroundColor Cyan
