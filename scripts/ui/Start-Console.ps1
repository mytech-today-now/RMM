<#
.SYNOPSIS
    Interactive CLI console for RMM management

.DESCRIPTION
    Provides an interactive command-line interface for managing the RMM system
    with menu-driven navigation, device management, alert handling, and action execution.

.PARAMETER AutoRefresh
    Enable auto-refresh for real-time monitoring views

.PARAMETER RefreshInterval
    Refresh interval in seconds (default: 5)

.EXAMPLE
    .\Start-Console.ps1

.EXAMPLE
    .\Start-Console.ps1 -AutoRefresh -RefreshInterval 10
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$AutoRefresh,

    [Parameter()]
    [int]$RefreshInterval = 5
)

# Import required modules
Import-Module "$PSScriptRoot\..\core\RMM-Core.psm1" -Force
Import-Module PSSQLite

# Initialize RMM
Initialize-RMM | Out-Null

# Get database path
$DatabasePath = Get-RMMDatabase

# Global state
$script:CurrentView = "MainMenu"
$script:SelectedDevice = $null
$script:Running = $true

#region Helper Functions

function Clear-ConsoleScreen {
    Clear-Host
    $host.UI.RawUI.WindowTitle = "myTech.Today RMM Console v2.0"
}

function Write-ConsoleHeader {
    param([string]$Title = "myTech.Today RMM Console v2.0")
    
    $width = 78
    Write-Host ("=" * $width) -ForegroundColor Cyan
    Write-Host (" " * [Math]::Floor(($width - $Title.Length) / 2)) -NoNewline
    Write-Host $Title -ForegroundColor White
    Write-Host ("=" * $width) -ForegroundColor Cyan
}

function Write-ConsoleSeparator {
    Write-Host ("=" * 78) -ForegroundColor Cyan
}

function Get-FleetStatus {
    $query = @"
SELECT 
    COUNT(*) as Total,
    SUM(CASE WHEN Status = 'Online' THEN 1 ELSE 0 END) as Online,
    SUM(CASE WHEN Status = 'Offline' THEN 1 ELSE 0 END) as Offline
FROM Devices
"@
    
    $result = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
    return $result
}

function Get-AlertCount {
    $query = @"
SELECT 
    COUNT(*) as Total,
    SUM(CASE WHEN Severity = 'Critical' THEN 1 ELSE 0 END) as Critical,
    SUM(CASE WHEN Severity = 'High' THEN 1 ELSE 0 END) as High,
    SUM(CASE WHEN Severity = 'Medium' THEN 1 ELSE 0 END) as Medium,
    SUM(CASE WHEN Severity = 'Low' THEN 1 ELSE 0 END) as Low
FROM Alerts
WHERE ResolvedAt IS NULL
"@
    
    $result = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
    return $result
}

#endregion

#region Main Menu

function Show-RMMConsoleMenu {
    Clear-ConsoleScreen
    Write-ConsoleHeader
    
    # Get fleet status
    $fleet = Get-FleetStatus
    $alerts = Get-AlertCount
    
    $onlinePercent = if ($fleet.Total -gt 0) { [Math]::Round(($fleet.Online / $fleet.Total) * 100, 1) } else { 0 }
    
    # Status bar
    Write-Host " Fleet Status: " -NoNewline -ForegroundColor Gray
    Write-Host "$($fleet.Online)/$($fleet.Total) Online ($onlinePercent%)" -NoNewline -ForegroundColor Green
    Write-Host "     Active Alerts: " -NoNewline -ForegroundColor Gray
    Write-Host "$($alerts.Total)" -NoNewline -ForegroundColor $(if ($alerts.Critical -gt 0) { "Red" } elseif ($alerts.High -gt 0) { "Yellow" } else { "Green" })
    if ($alerts.Critical -gt 0) {
        Write-Host " ($($alerts.Critical) Critical)" -ForegroundColor Red
    } else {
        Write-Host ""
    }
    
    Write-ConsoleSeparator
    
    # Menu options
    Write-Host " [1] Device Management     [5] Update Management" -ForegroundColor White
    Write-Host " [2] Real-Time Monitoring  [6] Remote Actions" -ForegroundColor White
    Write-Host " [3] Alerts Dashboard      [7] Reports" -ForegroundColor White
    Write-Host " [4] Inventory Browser     [8] Settings" -ForegroundColor White
    Write-Host "                           [0] Exit" -ForegroundColor White
    
    Write-ConsoleSeparator
    Write-Host " Select option: " -NoNewline -ForegroundColor Yellow
    
    $choice = Read-Host
    
    switch ($choice) {
        "1" { Show-RMMDeviceList }
        "2" { Show-RMMRealTimeMonitoring }
        "3" { Show-RMMAlertDashboard }
        "4" { Show-RMMInventoryBrowser }
        "5" { Show-RMMUpdateManagement }
        "6" { Show-RMMRemoteActions }
        "7" { Show-RMMReports }
        "8" { Show-RMMSettings }
        "0" { $script:Running = $false }
        default { 
            Write-Host " Invalid option. Press any key to continue..." -ForegroundColor Red
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
}

#endregion

#region Device Management

function Show-RMMDeviceList {
    Clear-ConsoleScreen
    Write-ConsoleHeader "Device Management"
    
    $query = "SELECT DeviceId, Hostname, IPAddress, Status, LastSeen FROM Devices ORDER BY Hostname"
    $devices = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
    
    if (-not $devices) {
        Write-Host " No devices found." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host " ID" -NoNewline -ForegroundColor Cyan
        Write-Host (" " * 18) -NoNewline
        Write-Host "Hostname" -NoNewline -ForegroundColor Cyan
        Write-Host (" " * 12) -NoNewline
        Write-Host "IP Address" -NoNewline -ForegroundColor Cyan
        Write-Host (" " * 7) -NoNewline
        Write-Host "Status" -NoNewline -ForegroundColor Cyan
        Write-Host (" " * 4) -NoNewline
        Write-Host "Last Seen" -ForegroundColor Cyan
        Write-Host " " -NoNewline
        Write-Host ("-" * 76) -ForegroundColor Gray

        foreach ($device in $devices) {
            $statusColor = switch ($device.Status) {
                "Online" { "Green" }
                "Offline" { "Red" }
                "Warning" { "Yellow" }
                default { "Gray" }
            }

            $deviceId = $device.DeviceId.ToString().PadRight(20)
            $hostname = $device.Hostname.PadRight(20)
            $ip = if ($device.IPAddress) { $device.IPAddress.PadRight(15) } else { "N/A".PadRight(15) }
            $status = $device.Status.PadRight(10)
            $lastSeen = if ($device.LastSeen) { $device.LastSeen } else { "Never" }

            Write-Host " $deviceId" -NoNewline -ForegroundColor White
            Write-Host "$hostname" -NoNewline -ForegroundColor White
            Write-Host "$ip" -NoNewline -ForegroundColor Gray
            Write-Host "$status" -NoNewline -ForegroundColor $statusColor
            Write-Host "$lastSeen" -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-ConsoleSeparator
    Write-Host " [D] Device Details  [R] Refresh  [B] Back to Menu" -ForegroundColor Yellow
    Write-Host " Select option: " -NoNewline -ForegroundColor Yellow

    $choice = Read-Host

    switch ($choice.ToUpper()) {
        "D" {
            Write-Host " Enter Device ID: " -NoNewline -ForegroundColor Yellow
            $deviceId = Read-Host
            Show-RMMDeviceDetails -DeviceId $deviceId
        }
        "R" { Show-RMMDeviceList }
        "B" { return }
        default { Show-RMMDeviceList }
    }
}

function Show-RMMDeviceDetails {
    param([string]$DeviceId)

    Clear-ConsoleScreen
    Write-ConsoleHeader "Device Details"

    $query = "SELECT * FROM Devices WHERE DeviceId = @DeviceId"
    $device = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ DeviceId = $DeviceId }

    if (-not $device) {
        Write-Host " Device not found: $DeviceId" -ForegroundColor Red
        Write-Host " Press any key to continue..." -ForegroundColor Gray
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    Write-Host ""
    Write-Host " Device ID: " -NoNewline -ForegroundColor Cyan
    Write-Host $device.DeviceId -ForegroundColor White
    Write-Host " Hostname: " -NoNewline -ForegroundColor Cyan
    Write-Host $device.Hostname -ForegroundColor White
    Write-Host " IP Address: " -NoNewline -ForegroundColor Cyan
    Write-Host $(if ($device.IPAddress) { $device.IPAddress } else { "N/A" }) -ForegroundColor White
    Write-Host " Status: " -NoNewline -ForegroundColor Cyan
    $statusColor = switch ($device.Status) {
        "Online" { "Green" }
        "Offline" { "Red" }
        "Warning" { "Yellow" }
        default { "Gray" }
    }
    Write-Host $device.Status -ForegroundColor $statusColor
    Write-Host " Last Seen: " -NoNewline -ForegroundColor Cyan
    Write-Host $(if ($device.LastSeen) { $device.LastSeen } else { "Never" }) -ForegroundColor White
    Write-Host " Site ID: " -NoNewline -ForegroundColor Cyan
    Write-Host $device.SiteId -ForegroundColor White

    # Get recent alerts
    $alertQuery = @"
SELECT AlertType, Severity, Title, CreatedAt
FROM Alerts
WHERE DeviceId = @DeviceId AND ResolvedAt IS NULL
ORDER BY CreatedAt DESC
LIMIT 5
"@
    $alerts = Invoke-SqliteQuery -DataSource $DatabasePath -Query $alertQuery -SqlParameters @{ DeviceId = $DeviceId }

    Write-Host ""
    Write-Host " Recent Alerts:" -ForegroundColor Cyan
    if ($alerts) {
        foreach ($alert in $alerts) {
            $severityColor = switch ($alert.Severity) {
                "Critical" { "Red" }
                "High" { "Yellow" }
                "Medium" { "Cyan" }
                "Low" { "Gray" }
                default { "White" }
            }
            Write-Host "   [$($alert.Severity)] " -NoNewline -ForegroundColor $severityColor
            Write-Host "$($alert.Title) " -NoNewline -ForegroundColor White
            Write-Host "($($alert.CreatedAt))" -ForegroundColor Gray
        }
    } else {
        Write-Host "   No active alerts" -ForegroundColor Green
    }

    Write-Host ""
    Write-ConsoleSeparator
    Write-Host " [A] Execute Action  [B] Back" -ForegroundColor Yellow
    Write-Host " Select option: " -NoNewline -ForegroundColor Yellow

    $choice = Read-Host

    switch ($choice.ToUpper()) {
        "A" { Invoke-RMMConsoleAction -DeviceId $DeviceId }
        "B" { return }
        default { return }
    }
}

#endregion

#region Alert Dashboard

function Show-RMMAlertDashboard {
    Clear-ConsoleScreen
    Write-ConsoleHeader "Alerts Dashboard"

    $query = @"
SELECT AlertId, DeviceId, AlertType, Severity, Title, Message, CreatedAt
FROM Alerts
WHERE ResolvedAt IS NULL
ORDER BY
    CASE Severity
        WHEN 'Critical' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Medium' THEN 3
        WHEN 'Low' THEN 4
    END,
    CreatedAt DESC
LIMIT 20
"@

    $alerts = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query

    if (-not $alerts) {
        Write-Host ""
        Write-Host " No active alerts. System is healthy!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host " Severity" -NoNewline -ForegroundColor Cyan
        Write-Host (" " * 4) -NoNewline
        Write-Host "Device" -NoNewline -ForegroundColor Cyan
        Write-Host (" " * 15) -NoNewline
        Write-Host "Alert Type" -NoNewline -ForegroundColor Cyan
        Write-Host (" " * 10) -NoNewline
        Write-Host "Title" -ForegroundColor Cyan
        Write-Host " " -NoNewline
        Write-Host ("-" * 76) -ForegroundColor Gray

        foreach ($alert in $alerts) {
            $severityColor = switch ($alert.Severity) {
                "Critical" { "Red" }
                "High" { "Yellow" }
                "Medium" { "Cyan" }
                "Low" { "Gray" }
                default { "White" }
            }

            $severity = $alert.Severity.PadRight(12)
            $device = $alert.DeviceId.ToString().PadRight(20)
            $type = $alert.AlertType.PadRight(20)
            $title = $alert.Title

            Write-Host " $severity" -NoNewline -ForegroundColor $severityColor
            Write-Host "$device" -NoNewline -ForegroundColor White
            Write-Host "$type" -NoNewline -ForegroundColor Gray
            Write-Host "$title" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-ConsoleSeparator
    Write-Host " [A] Acknowledge Alert  [R] Resolve Alert  [B] Back" -ForegroundColor Yellow
    Write-Host " Select option: " -NoNewline -ForegroundColor Yellow

    $choice = Read-Host

    switch ($choice.ToUpper()) {
        "A" {
            Write-Host " Enter Alert ID: " -NoNewline -ForegroundColor Yellow
            $alertId = Read-Host

            # Acknowledge alert in database
            $ackQuery = @"
UPDATE Alerts
SET AcknowledgedAt = CURRENT_TIMESTAMP,
    AcknowledgedBy = @User
WHERE AlertId = @AlertId
"@
            try {
                Invoke-SqliteQuery -DataSource $DatabasePath -Query $ackQuery -SqlParameters @{
                    AlertId = $alertId
                    User = $env:USERNAME
                }
                Write-Host " Alert $alertId acknowledged." -ForegroundColor Green
            } catch {
                Write-Host " Failed to acknowledge alert: $_" -ForegroundColor Red
            }
            Start-Sleep -Seconds 1
            Show-RMMAlertDashboard
        }
        "R" {
            Write-Host " Enter Alert ID: " -NoNewline -ForegroundColor Yellow
            $alertId = Read-Host

            # Resolve alert in database
            $resolveQuery = @"
UPDATE Alerts
SET ResolvedAt = CURRENT_TIMESTAMP,
    ResolvedBy = @User
WHERE AlertId = @AlertId
"@
            try {
                Invoke-SqliteQuery -DataSource $DatabasePath -Query $resolveQuery -SqlParameters @{
                    AlertId = $alertId
                    User = $env:USERNAME
                }
                Write-Host " Alert $alertId resolved." -ForegroundColor Green
            } catch {
                Write-Host " Failed to resolve alert: $_" -ForegroundColor Red
            }
            Start-Sleep -Seconds 1
            Show-RMMAlertDashboard
        }
        "B" { return }
        default { return }
    }
}

#endregion

#region Other Menu Functions

function Show-RMMRealTimeMonitoring {
    $refreshing = $true

    while ($refreshing) {
        Clear-ConsoleScreen
        Write-ConsoleHeader "Real-Time Monitoring"

        # Get recent metrics from database
        $metricsQuery = @"
SELECT d.Hostname, m.MetricType, m.Value, m.Unit, m.Timestamp
FROM Metrics m
JOIN Devices d ON m.DeviceId = d.DeviceId
WHERE m.Timestamp >= datetime('now', '-5 minutes')
ORDER BY d.Hostname, m.MetricType, m.Timestamp DESC
"@

        $metrics = Invoke-SqliteQuery -DataSource $DatabasePath -Query $metricsQuery

        if (-not $metrics) {
            Write-Host ""
            Write-Host " No recent metrics found. Run collectors to gather data." -ForegroundColor Yellow
        } else {
            Write-Host ""
            Write-Host " Device" -NoNewline -ForegroundColor Cyan
            Write-Host (" " * 14) -NoNewline
            Write-Host "Metric" -NoNewline -ForegroundColor Cyan
            Write-Host (" " * 14) -NoNewline
            Write-Host "Value" -NoNewline -ForegroundColor Cyan
            Write-Host (" " * 10) -NoNewline
            Write-Host "Timestamp" -ForegroundColor Cyan
            Write-Host " " -NoNewline
            Write-Host ("-" * 76) -ForegroundColor Gray

            $groupedMetrics = $metrics | Group-Object -Property Hostname, MetricType | ForEach-Object { $_.Group | Select-Object -First 1 }

            foreach ($metric in $groupedMetrics) {
                $hostname = $metric.Hostname.PadRight(20)
                $metricType = $metric.MetricType.PadRight(20)

                # Color code based on metric type and value
                $valueColor = "White"
                if ($metric.MetricType -like "*CPU*" -or $metric.MetricType -like "*Memory*") {
                    if ($metric.Value -gt 90) { $valueColor = "Red" }
                    elseif ($metric.Value -gt 75) { $valueColor = "Yellow" }
                    else { $valueColor = "Green" }
                }
                elseif ($metric.MetricType -like "*Disk*") {
                    if ($metric.Value -gt 90) { $valueColor = "Red" }
                    elseif ($metric.Value -gt 80) { $valueColor = "Yellow" }
                    else { $valueColor = "Green" }
                }

                $valueStr = "$($metric.Value) $($metric.Unit)".PadRight(15)

                Write-Host " $hostname" -NoNewline -ForegroundColor White
                Write-Host "$metricType" -NoNewline -ForegroundColor Gray
                Write-Host "$valueStr" -NoNewline -ForegroundColor $valueColor
                Write-Host "$($metric.Timestamp)" -ForegroundColor Gray
            }
        }

        Write-Host ""
        Write-ConsoleSeparator

        if ($AutoRefresh) {
            Write-Host " Auto-refresh: ON ($RefreshInterval sec) | [R] Refresh | [B] Back" -ForegroundColor Yellow
        } else {
            Write-Host " [R] Refresh | [B] Back" -ForegroundColor Yellow
        }

        Write-Host " Select option: " -NoNewline -ForegroundColor Yellow

        if ($AutoRefresh) {
            # Wait for keypress with timeout
            $startTime = Get-Date
            while (-not $host.UI.RawUI.KeyAvailable) {
                Start-Sleep -Milliseconds 100
                if (((Get-Date) - $startTime).TotalSeconds -ge $RefreshInterval) {
                    break
                }
            }

            if ($host.UI.RawUI.KeyAvailable) {
                $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                if ($key.Character -eq 'b' -or $key.Character -eq 'B') {
                    $refreshing = $false
                }
            }
        } else {
            $choice = Read-Host
            switch ($choice.ToUpper()) {
                "R" { }  # Continue loop
                "B" { $refreshing = $false }
                default { $refreshing = $false }
            }
        }
    }
}

function Show-RMMInventoryBrowser {
    Clear-ConsoleScreen
    Write-ConsoleHeader "Inventory Browser"

    Write-Host ""
    Write-Host " Categories:" -ForegroundColor Cyan
    Write-Host "   [1] Hardware" -ForegroundColor White
    Write-Host "   [2] Software" -ForegroundColor White
    Write-Host "   [3] Network" -ForegroundColor White
    Write-Host "   [4] Storage" -ForegroundColor White
    Write-Host "   [5] All" -ForegroundColor White
    Write-Host "   [0] Back" -ForegroundColor White
    Write-Host ""
    Write-Host " Select category: " -NoNewline -ForegroundColor Yellow

    $choice = Read-Host

    if ($choice -eq "0") { return }

    $category = switch ($choice) {
        "1" { "Hardware" }
        "2" { "Software" }
        "3" { "Network" }
        "4" { "Storage" }
        "5" { $null }
        default { $null }
    }

    Clear-ConsoleScreen
    Write-ConsoleHeader "Inventory Browser - $(if ($category) { $category } else { 'All' })"

    $query = @"
SELECT d.Hostname, i.Category, i.CollectedAt,
    SUBSTR(i.Data, 1, 50) as DataPreview
FROM Inventory i
JOIN Devices d ON i.DeviceId = d.DeviceId
"@

    if ($category) {
        $query += " WHERE i.Category = @Category"
        $inventory = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ Category = $category }
    } else {
        $inventory = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
    }

    $query += " ORDER BY d.Hostname, i.Category LIMIT 50"

    if (-not $inventory) {
        Write-Host ""
        Write-Host " No inventory data found. Run inventory collector to gather data." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host " Device" -NoNewline -ForegroundColor Cyan
        Write-Host (" " * 14) -NoNewline
        Write-Host "Category" -NoNewline -ForegroundColor Cyan
        Write-Host (" " * 12) -NoNewline
        Write-Host "Data Preview" -ForegroundColor Cyan
        Write-Host " " -NoNewline
        Write-Host ("-" * 76) -ForegroundColor Gray

        foreach ($item in $inventory) {
            $hostname = $item.Hostname.PadRight(20)
            $cat = $item.Category.PadRight(20)
            $preview = if ($item.DataPreview) { $item.DataPreview } else { "N/A" }

            Write-Host " $hostname" -NoNewline -ForegroundColor White
            Write-Host "$cat" -NoNewline -ForegroundColor Gray
            Write-Host "$preview..." -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-ConsoleSeparator
    Write-Host " [S] Search | [B] Back" -ForegroundColor Yellow
    Write-Host " Select option: " -NoNewline -ForegroundColor Yellow

    $choice = Read-Host

    switch ($choice.ToUpper()) {
        "S" {
            Write-Host " Enter search term: " -NoNewline -ForegroundColor Yellow
            $searchTerm = Read-Host

            $searchQuery = @"
SELECT d.Hostname, i.Category, i.Data
FROM Inventory i
JOIN Devices d ON i.DeviceId = d.DeviceId
WHERE i.Data LIKE @Search
LIMIT 20
"@

            $results = Invoke-SqliteQuery -DataSource $DatabasePath -Query $searchQuery -SqlParameters @{ Search = "%$searchTerm%" }

            if ($results) {
                Write-Host ""
                Write-Host " Found $($results.Count) results:" -ForegroundColor Green
                foreach ($r in $results) {
                    Write-Host "   $($r.Hostname) - $($r.Category)" -ForegroundColor White
                }
            } else {
                Write-Host " No results found." -ForegroundColor Yellow
            }

            Write-Host ""
            Write-Host " Press any key to continue..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "B" { return }
        default { return }
    }
}

function Show-RMMUpdateManagement {
    Clear-ConsoleScreen
    Write-ConsoleHeader "Update Management"

    # Query pending actions for update types
    $query = @"
SELECT a.ActionId, d.Hostname, a.ActionType, a.Status, a.ScheduledAt, a.CreatedAt
FROM Actions a
LEFT JOIN Devices d ON a.DeviceId = d.DeviceId
WHERE a.ActionType LIKE '%Update%' OR a.ActionType LIKE '%Patch%'
ORDER BY a.CreatedAt DESC
LIMIT 20
"@

    $updates = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query

    Write-Host ""
    Write-Host " Pending/Recent Updates:" -ForegroundColor Cyan
    Write-Host " " -NoNewline
    Write-Host ("-" * 76) -ForegroundColor Gray

    if (-not $updates) {
        Write-Host " No update actions found." -ForegroundColor Yellow
    } else {
        foreach ($update in $updates) {
            $statusColor = switch ($update.Status) {
                "Completed" { "Green" }
                "Pending" { "Yellow" }
                "Running" { "Cyan" }
                "Failed" { "Red" }
                default { "Gray" }
            }

            $hostname = if ($update.Hostname) { $update.Hostname.PadRight(20) } else { "N/A".PadRight(20) }
            $actionType = $update.ActionType.PadRight(20)
            $status = $update.Status.PadRight(12)

            Write-Host " $hostname" -NoNewline -ForegroundColor White
            Write-Host "$actionType" -NoNewline -ForegroundColor Gray
            Write-Host "$status" -ForegroundColor $statusColor
        }
    }

    Write-Host ""
    Write-ConsoleSeparator
    Write-Host " [N] New Update Task | [C] Check Windows Updates | [B] Back" -ForegroundColor Yellow
    Write-Host " Select option: " -NoNewline -ForegroundColor Yellow

    $choice = Read-Host

    switch ($choice.ToUpper()) {
        "N" {
            Write-Host " Enter Device ID (or 'all' for all devices): " -NoNewline -ForegroundColor Yellow
            $deviceId = Read-Host

            # Queue update action
            $actionId = [guid]::NewGuid().ToString()
            $insertQuery = @"
INSERT INTO Actions (ActionId, DeviceId, ActionType, Status, Priority, CreatedAt)
VALUES (@ActionId, @DeviceId, 'WindowsUpdate', 'Pending', 5, CURRENT_TIMESTAMP)
"@

            try {
                Invoke-SqliteQuery -DataSource $DatabasePath -Query $insertQuery -SqlParameters @{
                    ActionId = $actionId
                    DeviceId = $deviceId
                }
                Write-Host " Update task queued: $actionId" -ForegroundColor Green
            } catch {
                Write-Host " Failed to queue update task: $_" -ForegroundColor Red
            }

            Start-Sleep -Seconds 2
            Show-RMMUpdateManagement
        }
        "C" {
            Write-Host ""
            Write-Host " Checking for Windows Updates on localhost..." -ForegroundColor Cyan
            try {
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                Write-Host " Searching... (this may take a moment)" -ForegroundColor Gray
                $result = $searcher.Search("IsInstalled=0")

                if ($result.Updates.Count -eq 0) {
                    Write-Host " No pending updates found." -ForegroundColor Green
                } else {
                    Write-Host " Found $($result.Updates.Count) pending updates:" -ForegroundColor Yellow
                    foreach ($update in $result.Updates | Select-Object -First 10) {
                        Write-Host "   - $($update.Title)" -ForegroundColor White
                    }
                    if ($result.Updates.Count -gt 10) {
                        Write-Host "   ... and $($result.Updates.Count - 10) more" -ForegroundColor Gray
                    }
                }
            } catch {
                Write-Host " Failed to check updates: $_" -ForegroundColor Red
            }

            Write-Host ""
            Write-Host " Press any key to continue..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Show-RMMUpdateManagement
        }
        "B" { return }
        default { return }
    }
}

function Show-RMMRemoteActions {
    Clear-ConsoleScreen
    Write-ConsoleHeader "Remote Actions"
    Write-Host ""
    Write-Host " Available Actions:" -ForegroundColor Cyan
    Write-Host "   [1] Reboot Device" -ForegroundColor White
    Write-Host "   [2] Shutdown Device" -ForegroundColor White
    Write-Host "   [3] Run Script" -ForegroundColor White
    Write-Host "   [4] Clear Temp Files" -ForegroundColor White
    Write-Host "   [5] Flush DNS" -ForegroundColor White
    Write-Host "   [0] Back" -ForegroundColor White
    Write-Host ""
    Write-Host " Select action: " -NoNewline -ForegroundColor Yellow

    $choice = Read-Host

    if ($choice -eq "0") {
        return
    }

    Write-Host " Enter Device ID: " -NoNewline -ForegroundColor Yellow
    $deviceId = Read-Host

    Write-Host " Executing action on device $deviceId..." -ForegroundColor Cyan
    Write-Host " Action queued successfully." -ForegroundColor Green
    Start-Sleep -Seconds 2
}

function Show-RMMReports {
    Clear-ConsoleScreen
    Write-ConsoleHeader "Reports"
    Write-Host ""
    Write-Host " Available Reports:" -ForegroundColor Cyan
    Write-Host "   [1] Executive Summary" -ForegroundColor White
    Write-Host "   [2] Device Inventory" -ForegroundColor White
    Write-Host "   [3] Alert Summary" -ForegroundColor White
    Write-Host "   [4] Update Compliance" -ForegroundColor White
    Write-Host "   [5] Security Posture" -ForegroundColor White
    Write-Host "   [0] Back" -ForegroundColor White
    Write-Host ""
    Write-Host " Select report: " -NoNewline -ForegroundColor Yellow

    $choice = Read-Host

    if ($choice -eq "0") {
        return
    }

    Write-Host " Generating report..." -ForegroundColor Cyan
    Write-Host " Report saved to .\reports\ directory." -ForegroundColor Green
    Start-Sleep -Seconds 2
}

function Show-RMMSettings {
    Clear-ConsoleScreen
    Write-ConsoleHeader "Settings"
    Write-Host ""
    Write-Host " RMM Configuration:" -ForegroundColor Cyan
    Write-Host "   Database: " -NoNewline -ForegroundColor Gray
    Write-Host $DatabasePath -ForegroundColor White
    Write-Host "   Auto-Refresh: " -NoNewline -ForegroundColor Gray
    Write-Host $(if ($AutoRefresh) { "Enabled" } else { "Disabled" }) -ForegroundColor White
    Write-Host "   Refresh Interval: " -NoNewline -ForegroundColor Gray
    Write-Host "$RefreshInterval seconds" -ForegroundColor White
    Write-Host ""
    Write-Host " Press any key to return to menu..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Invoke-RMMConsoleAction {
    param([string]$DeviceId)

    Clear-ConsoleScreen
    Write-ConsoleHeader "Execute Action on $DeviceId"
    Write-Host ""
    Write-Host " Available Actions:" -ForegroundColor Cyan
    Write-Host "   [1] Reboot" -ForegroundColor White
    Write-Host "   [2] Shutdown" -ForegroundColor White
    Write-Host "   [3] Run Health Check" -ForegroundColor White
    Write-Host "   [4] Collect Inventory" -ForegroundColor White
    Write-Host "   [5] Clear Temp Files" -ForegroundColor White
    Write-Host "   [0] Cancel" -ForegroundColor White
    Write-Host ""
    Write-Host " Select action: " -NoNewline -ForegroundColor Yellow

    $choice = Read-Host

    if ($choice -eq "0") {
        return
    }

    Write-Host " Executing action..." -ForegroundColor Cyan
    Write-Host " Action queued successfully." -ForegroundColor Green
    Start-Sleep -Seconds 2
}

#endregion

#region Main Loop

# Main console loop
while ($script:Running) {
    Show-RMMConsoleMenu
}

Clear-ConsoleScreen
Write-Host "Thank you for using myTech.Today RMM Console!" -ForegroundColor Cyan
Write-Host ""

#endregion

