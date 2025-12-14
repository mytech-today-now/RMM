<#
.SYNOPSIS
    Generate various RMM reports in multiple formats

.DESCRIPTION
    Generates executive summaries, device inventory, alert summaries, compliance reports,
    and other management reports in HTML, PDF, Excel, or CSV formats.

.PARAMETER ReportType
    Type of report to generate

.PARAMETER OutputPath
    Path where the report will be saved

.PARAMETER Format
    Output format (HTML, PDF, Excel, CSV)

.PARAMETER StartDate
    Start date for report data (default: 7 days ago)

.PARAMETER EndDate
    End date for report data (default: now)

.PARAMETER Devices
    Devices to include in report (default: All)

.PARAMETER EmailTo
    Email addresses to send report to

.EXAMPLE
    .\Report-Generator.ps1 -ReportType "ExecutiveSummary" -OutputPath ".\reports\executive.html"

.EXAMPLE
    .\Report-Generator.ps1 -ReportType "DeviceInventory" -Format "Excel" -OutputPath ".\reports\inventory.xlsx"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("ExecutiveSummary", "DeviceInventory", "AlertSummary", "UpdateCompliance", 
                 "SecurityPosture", "PerformanceTrends", "UptimeReport", "AuditLog")]
    [string]$ReportType = "ExecutiveSummary",

    [Parameter()]
    [string]$OutputPath = ".\reports\report.html",

    [Parameter()]
    [ValidateSet("HTML", "PDF", "Excel", "CSV")]
    [string]$Format = "HTML",

    [Parameter()]
    [datetime]$StartDate = (Get-Date).AddDays(-7),

    [Parameter()]
    [datetime]$EndDate = (Get-Date),

    [Parameter()]
    [string[]]$Devices = @("All"),

    [Parameter()]
    [string[]]$EmailTo
)

# Import required modules
Import-Module "$PSScriptRoot\..\core\RMM-Core.psm1" -Force
Import-Module PSSQLite

# Initialize RMM
Initialize-RMM | Out-Null

# Get database path
$DatabasePath = Get-RMMDatabase

# Ensure reports directory exists
$reportsDir = Split-Path -Path $OutputPath -Parent
if ($reportsDir -and -not (Test-Path $reportsDir)) {
    New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
}

Write-Host "[INFO] Generating $ReportType report..." -ForegroundColor Cyan
Write-Host "[INFO] Date Range: $($StartDate.ToString('yyyy-MM-dd')) to $($EndDate.ToString('yyyy-MM-dd'))" -ForegroundColor Gray

#region Helper Functions

function Get-RMMReportData {
    param(
        [string]$ReportType,
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string[]]$Devices
    )

    $data = @{}

    switch ($ReportType) {
        "ExecutiveSummary" {
            # Get fleet health metrics
            $deviceCount = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Devices").Count
            $onlineDevices = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Devices WHERE Status = 'Online'").Count
            $alerts = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT Severity, COUNT(*) as Count FROM Alerts WHERE ResolvedAt IS NULL GROUP BY Severity"
            $recentActions = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT ActionType, COUNT(*) as Count FROM Actions WHERE datetime(CreatedAt) >= datetime('$($StartDate.ToString('yyyy-MM-dd'))') GROUP BY ActionType"
            
            $data.DeviceCount = $deviceCount
            $data.OnlineDevices = $onlineDevices
            $data.OfflineDevices = $deviceCount - $onlineDevices
            $data.HealthScore = if ($deviceCount -gt 0) { [math]::Round(($onlineDevices / $deviceCount) * 100, 2) } else { 0 }
            $data.Alerts = $alerts
            $data.RecentActions = $recentActions
        }
        "DeviceInventory" {
            $query = "SELECT * FROM Devices ORDER BY Hostname"
            $data.Devices = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
        }
        "AlertSummary" {
            $query = @"
SELECT AlertId, DeviceId, AlertType, Severity, Title, Message, CreatedAt, ResolvedAt
FROM Alerts
WHERE datetime(CreatedAt) >= datetime('$($StartDate.ToString('yyyy-MM-dd'))')
  AND datetime(CreatedAt) <= datetime('$($EndDate.ToString('yyyy-MM-dd'))')
ORDER BY CreatedAt DESC
"@
            $data.Alerts = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
        }
        "UpdateCompliance" {
            # Get update status from inventory
            $query = "SELECT DeviceId, Data FROM Inventory WHERE Category = 'Software' ORDER BY CollectedAt DESC"
            $data.Updates = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
        }
        "SecurityPosture" {
            # Get security metrics from inventory
            $query = "SELECT DeviceId, Data FROM Inventory WHERE Category = 'Security' ORDER BY CollectedAt DESC"
            $data.Security = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
        }
        "PerformanceTrends" {
            $query = @"
SELECT DeviceId, MetricType, Value, Timestamp
FROM Metrics
WHERE datetime(Timestamp) >= datetime('$($StartDate.ToString('yyyy-MM-dd'))')
  AND datetime(Timestamp) <= datetime('$($EndDate.ToString('yyyy-MM-dd'))')
ORDER BY Timestamp
"@
            $data.Metrics = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
        }
        "UptimeReport" {
            $query = @"
SELECT DeviceId, Status, LastSeen
FROM Devices
ORDER BY Hostname
"@
            $data.Devices = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
        }
        "AuditLog" {
            $query = @"
SELECT ActionId, DeviceId, ActionType, Status, Result, CreatedAt
FROM Actions
WHERE datetime(CreatedAt) >= datetime('$($StartDate.ToString('yyyy-MM-dd'))')
  AND datetime(CreatedAt) <= datetime('$($EndDate.ToString('yyyy-MM-dd'))')
ORDER BY CreatedAt DESC
"@
            $data.Actions = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
        }
    }

    return $data
}

function Export-RMMReportHTML {
    param(
        [string]$ReportType,
        [hashtable]$Data,
        [string]$OutputPath
    )

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>$ReportType - $(Get-Date -Format 'yyyy-MM-dd')</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #333; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #0078d4; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f1f1f1; }
        .metric { display: inline-block; margin: 10px 20px; padding: 20px; background-color: white; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); min-width: 150px; }
        .metric-value { font-size: 32px; font-weight: bold; color: #0078d4; }
        .metric-label { font-size: 14px; color: #666; margin-top: 5px; }
        .critical { color: #d13438; font-weight: bold; }
        .high { color: #ff8c00; font-weight: bold; }
        .medium { color: #ffd700; font-weight: bold; }
        .low { color: #107c10; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>$ReportType</h1>
    <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
"@

    switch ($ReportType) {
        "ExecutiveSummary" {
            $html += @"
    <h2>Fleet Overview</h2>
    <div class="metric">
        <div class="metric-value">$($Data.DeviceCount)</div>
        <div class="metric-label">Total Devices</div>
    </div>
    <div class="metric">
        <div class="metric-value">$($Data.OnlineDevices)</div>
        <div class="metric-label">Online</div>
    </div>
    <div class="metric">
        <div class="metric-value">$($Data.OfflineDevices)</div>
        <div class="metric-label">Offline</div>
    </div>
    <div class="metric">
        <div class="metric-value">$($Data.HealthScore)%</div>
        <div class="metric-label">Health Score</div>
    </div>

    <h2>Active Alerts</h2>
    <table>
        <tr><th>Severity</th><th>Count</th></tr>
"@
            if ($Data.Alerts) {
                foreach ($alert in $Data.Alerts) {
                    $severityClass = $alert.Severity.ToLower()
                    $html += "        <tr><td class='$severityClass'>$($alert.Severity)</td><td>$($alert.Count)</td></tr>`n"
                }
            } else {
                $html += "        <tr><td colspan='2'>No active alerts</td></tr>`n"
            }
            $html += "    </table>`n"

            $html += @"
    <h2>Recent Actions</h2>
    <table>
        <tr><th>Action Type</th><th>Count</th></tr>
"@
            if ($Data.RecentActions) {
                foreach ($action in $Data.RecentActions) {
                    $html += "        <tr><td>$($action.ActionType)</td><td>$($action.Count)</td></tr>`n"
                }
            } else {
                $html += "        <tr><td colspan='2'>No recent actions</td></tr>`n"
            }
            $html += "    </table>`n"
        }
        "DeviceInventory" {
            $html += @"
    <h2>Device List</h2>
    <table>
        <tr><th>Hostname</th><th>IP Address</th><th>Status</th><th>Last Seen</th><th>Site ID</th></tr>
"@
            if ($Data.Devices) {
                foreach ($device in $Data.Devices) {
                    $statusClass = if ($device.Status -eq 'Online') { 'low' } else { 'high' }
                    $html += "        <tr><td>$($device.Hostname)</td><td>$($device.IPAddress)</td><td class='$statusClass'>$($device.Status)</td><td>$($device.LastSeen)</td><td>$($device.SiteId)</td></tr>`n"
                }
            } else {
                $html += "        <tr><td colspan='5'>No devices found</td></tr>`n"
            }
            $html += "    </table>`n"
        }
        "AlertSummary" {
            $html += @"
    <h2>Alert History</h2>
    <table>
        <tr><th>Severity</th><th>Type</th><th>Title</th><th>Device</th><th>Created</th><th>Status</th></tr>
"@
            if ($Data.Alerts) {
                foreach ($alert in $Data.Alerts) {
                    $severityClass = $alert.Severity.ToLower()
                    $status = if ($alert.ResolvedAt) { "Resolved" } else { "Active" }
                    $html += "        <tr><td class='$severityClass'>$($alert.Severity)</td><td>$($alert.AlertType)</td><td>$($alert.Title)</td><td>$($alert.DeviceId)</td><td>$($alert.CreatedAt)</td><td>$status</td></tr>`n"
                }
            } else {
                $html += "        <tr><td colspan='6'>No alerts found</td></tr>`n"
            }
            $html += "    </table>`n"
        }
        "AuditLog" {
            $html += @"
    <h2>Action History</h2>
    <table>
        <tr><th>Action ID</th><th>Device</th><th>Action Type</th><th>Status</th><th>Created</th></tr>
"@
            if ($Data.Actions) {
                foreach ($action in $Data.Actions) {
                    $html += "        <tr><td>$($action.ActionId)</td><td>$($action.DeviceId)</td><td>$($action.ActionType)</td><td>$($action.Status)</td><td>$($action.CreatedAt)</td></tr>`n"
                }
            } else {
                $html += "        <tr><td colspan='5'>No actions found</td></tr>`n"
            }
            $html += "    </table>`n"
        }
        default {
            $html += "    <p>Report type '$ReportType' is not yet fully implemented.</p>`n"
        }
    }

    $html += @"
    <div class="footer">
        <p>myTech.Today RMM System | Report Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "[SUCCESS] HTML report saved to: $OutputPath" -ForegroundColor Green
}

function Export-RMMReportCSV {
    param(
        [string]$ReportType,
        [hashtable]$Data,
        [string]$OutputPath
    )

    switch ($ReportType) {
        "DeviceInventory" {
            if ($Data.Devices) {
                $Data.Devices | Export-Csv -Path $OutputPath -NoTypeInformation
            }
        }
        "AlertSummary" {
            if ($Data.Alerts) {
                $Data.Alerts | Export-Csv -Path $OutputPath -NoTypeInformation
            }
        }
        "AuditLog" {
            if ($Data.Actions) {
                $Data.Actions | Export-Csv -Path $OutputPath -NoTypeInformation
            }
        }
        default {
            Write-Host "[WARN] CSV export not supported for $ReportType" -ForegroundColor Yellow
            return
        }
    }

    Write-Host "[SUCCESS] CSV report saved to: $OutputPath" -ForegroundColor Green
}

function Send-RMMReport {
    param(
        [string]$ReportPath,
        [string[]]$EmailTo,
        [string]$Subject = "RMM Report"
    )

    # Load notification configuration
    $configPath = ".\config\notifications.json"
    if (-not (Test-Path $configPath)) {
        Write-Host "[ERROR] Notification configuration not found: $configPath" -ForegroundColor Red
        return
    }

    $config = Get-Content $configPath | ConvertFrom-Json
    $emailConfig = $config.channels | Where-Object { $_.type -eq "Email" } | Select-Object -First 1

    if (-not $emailConfig -or -not $emailConfig.enabled) {
        Write-Host "[ERROR] Email notifications not configured or disabled" -ForegroundColor Red
        return
    }

    try {
        $mailParams = @{
            From       = $emailConfig.from
            To         = $EmailTo
            Subject    = $Subject
            Body       = "Please find the attached RMM report."
            SmtpServer = $emailConfig.smtp_server
            Port       = $emailConfig.smtp_port
            Attachments = $ReportPath
        }

        if ($emailConfig.use_ssl) {
            $mailParams.UseSsl = $true
        }

        if ($emailConfig.username -and $emailConfig.password) {
            $securePassword = ConvertTo-SecureString $emailConfig.password -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($emailConfig.username, $securePassword)
            $mailParams.Credential = $credential
        }

        Send-MailMessage @mailParams
        Write-Host "[SUCCESS] Report emailed to: $($EmailTo -join ', ')" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to send email: $_" -ForegroundColor Red
    }
}

#endregion

#region Main Execution

# Get report data
$reportData = Get-RMMReportData -ReportType $ReportType -StartDate $StartDate -EndDate $EndDate -Devices $Devices

# Generate report based on format
switch ($Format) {
    "HTML" {
        Export-RMMReportHTML -ReportType $ReportType -Data $reportData -OutputPath $OutputPath
    }
    "CSV" {
        Export-RMMReportCSV -ReportType $ReportType -Data $reportData -OutputPath $OutputPath
    }
    "Excel" {
        # Check if ImportExcel module is available
        if (Get-Module -ListAvailable -Name ImportExcel) {
            Import-Module ImportExcel
            # Convert to CSV first, then to Excel
            $csvPath = $OutputPath -replace '\.xlsx$', '.csv'
            Export-RMMReportCSV -ReportType $ReportType -Data $reportData -OutputPath $csvPath
            if (Test-Path $csvPath) {
                Import-Csv $csvPath | Export-Excel -Path $OutputPath -AutoSize -TableName "RMMReport"
                Remove-Item $csvPath
                Write-Host "[SUCCESS] Excel report saved to: $OutputPath" -ForegroundColor Green
            }
        }
        else {
            Write-Host "[WARN] ImportExcel module not installed. Falling back to CSV format." -ForegroundColor Yellow
            $csvPath = $OutputPath -replace '\.xlsx$', '.csv'
            Export-RMMReportCSV -ReportType $ReportType -Data $reportData -OutputPath $csvPath
        }
    }
    "PDF" {
        Write-Host "[WARN] PDF export requires additional tools. Generating HTML instead." -ForegroundColor Yellow
        $htmlPath = $OutputPath -replace '\.pdf$', '.html'
        Export-RMMReportHTML -ReportType $ReportType -Data $reportData -OutputPath $htmlPath
        Write-Host "[INFO] To convert to PDF, use a tool like wkhtmltopdf or print from browser" -ForegroundColor Gray
    }
}

# Email report if requested
if ($EmailTo) {
    $subject = "$ReportType Report - $(Get-Date -Format 'yyyy-MM-dd')"
    Send-RMMReport -ReportPath $OutputPath -EmailTo $EmailTo -Subject $subject
}

Write-Host ""
Write-Host "[OK] Report generation complete!" -ForegroundColor Green

#endregion

