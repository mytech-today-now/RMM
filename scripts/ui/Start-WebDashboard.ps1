<#
.SYNOPSIS
    Self-hosted web dashboard for RMM management

.DESCRIPTION
    Starts a self-hosted HTTP server providing a web-based dashboard for RMM management.
    No IIS required - uses PowerShell HttpListener class.

.PARAMETER Port
    Port to listen on (default: 8080)

.PARAMETER OpenBrowser
    Automatically open browser after starting

.EXAMPLE
    .\Start-WebDashboard.ps1

.EXAMPLE
    .\Start-WebDashboard.ps1 -Port 8080 -OpenBrowser
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$Port = 8080,

    [Parameter()]
    [switch]$OpenBrowser
)

# Import required modules
Import-Module "$PSScriptRoot\..\core\RMM-Core.psm1" -Force
Import-Module PSSQLite

# Import logging module
$loggingPath = Join-Path $PSScriptRoot "..\core\Logging.ps1"
. $loggingPath

# Initialize RMM
Initialize-RMM | Out-Null

# Initialize logging for this component
Initialize-RMMLogging -ScriptName "Web-Dashboard" -ScriptVersion "2.0"
Write-RMMLog "Web Dashboard starting on port $Port" -Level INFO -Component "Web-Dashboard"

# Get database path
$DatabasePath = Get-RMMDatabase

# Web assets directory
$WebRoot = Join-Path $PSScriptRoot "web"

#region Helper Functions

function Get-StatusDescription {
    param(
        [string]$Status,
        [string]$LastSeen
    )

    switch ($Status) {
        "Offline" {
            if ($LastSeen) {
                try {
                    $lastSeenDate = [DateTime]::Parse($LastSeen)
                    $diff = (Get-Date) - $lastSeenDate
                    if ($diff.TotalDays -gt 7) { return "- Not seen for $([int]$diff.TotalDays) days" }
                    elseif ($diff.TotalHours -gt 24) { return "- Last seen $([int]$diff.TotalDays) day(s) ago" }
                    elseif ($diff.TotalMinutes -gt 60) { return "- Last seen $([int]$diff.TotalHours) hour(s) ago" }
                    else { return "- Last seen $([int]$diff.TotalMinutes) min ago" }
                } catch { return "- Device not responding" }
            }
            return "- Device not responding"
        }
        "Warning" { return "- Performance issues detected" }
        "Critical" { return "- Critical alerts pending" }
        "Pending" { return "- Awaiting first check-in" }
        "Maintenance" { return "- In maintenance mode" }
        default { return "" }
    }
}

#endregion

#region Data Retrieval Functions

function Get-FleetStatusData {
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

function Get-AlertsData {
    param(
        [switch]$CriticalOnly,  # For main dashboard - only show Critical alerts
        [string]$DeviceId       # For device detail page - only show alerts for this device
    )

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

    $counts = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query

    # Build the alerts query based on filters
    $whereClause = "WHERE ResolvedAt IS NULL"
    if ($CriticalOnly) {
        $whereClause += " AND Severity = 'Critical'"
    }
    if ($DeviceId) {
        $whereClause += " AND DeviceId = '$DeviceId'"
    }

    $alertsQuery = @"
SELECT AlertId, DeviceId, AlertType, Severity, Title, Message, CreatedAt
FROM Alerts
$whereClause
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

    $alerts = Invoke-SqliteQuery -DataSource $DatabasePath -Query $alertsQuery

    return @{
        Total = $counts.Total
        Critical = $counts.Critical
        High = $counts.High
        Medium = $counts.Medium
        Low = $counts.Low
        Alerts = $alerts
    }
}

function Get-RecentActionsData {
    $query = @"
SELECT a.ActionId, a.DeviceId, a.ActionType, a.Status, a.CreatedAt,
       COALESCE(s.Name, 'Unknown') AS Site, COALESCE(d.Hostname, 'Unknown') AS Hostname
FROM Actions a
LEFT JOIN Devices d ON a.DeviceId = d.DeviceId
LEFT JOIN Sites s ON d.SiteId = s.SiteId
ORDER BY a.CreatedAt DESC
LIMIT 50
"@

    $actions = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
    return $actions
}

function Clear-ActionsHistory {
    $query = "DELETE FROM Actions"
    Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
    return @{ success = $true; message = "Actions history cleared" }
}

#endregion

#region Default Assets

function Get-DefaultCSS {
    return @"
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
    color: #333;
}

header {
    background: rgba(255, 255, 255, 0.95);
    padding: 1rem 2rem;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
}

header h1 {
    color: #667eea;
    font-size: 1.8rem;
    margin-bottom: 0.5rem;
}

nav {
    display: flex;
    gap: 1.5rem;
}

nav a {
    color: #666;
    text-decoration: none;
    padding: 0.5rem 1rem;
    border-radius: 5px;
    transition: all 0.3s;
}

nav a:hover, nav a.active {
    background: #667eea;
    color: white;
}

main {
    padding: 2rem;
    max-width: 1400px;
    margin: 0 auto;
}

.metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 1.5rem;
    margin-bottom: 2rem;
}

.metric-card {
    background: white;
    padding: 1.5rem;
    border-radius: 10px;
    box-shadow: 0 4px 15px rgba(0,0,0,0.1);
    text-align: center;
}

.metric-card h3 {
    color: #666;
    font-size: 0.9rem;
    text-transform: uppercase;
    margin-bottom: 1rem;
}

.metric-value {
    font-size: 2.5rem;
    font-weight: bold;
    color: #667eea;
    margin-bottom: 0.5rem;
}

.metric-value.alert-critical {
    color: #e74c3c;
}

.metric-value.alert-warning {
    color: #f39c12;
}

.metric-label {
    color: #999;
    font-size: 0.9rem;
}

.content-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(500px, 1fr));
    gap: 1.5rem;
}

.panel {
    background: white;
    padding: 1.5rem;
    border-radius: 10px;
    box-shadow: 0 4px 15px rgba(0,0,0,0.1);
}

.panel h2 {
    color: #667eea;
    margin-bottom: 1rem;
    padding-bottom: 0.5rem;
    border-bottom: 2px solid #f0f0f0;
}

table {
    width: 100%;
    border-collapse: collapse;
}

thead {
    background: #f8f9fa;
}

th {
    padding: 0.75rem;
    text-align: left;
    font-weight: 600;
    color: #666;
    border-bottom: 2px solid #e0e0e0;
}

td {
    padding: 0.75rem;
    border-bottom: 1px solid #f0f0f0;
}

.badge {
    padding: 0.25rem 0.75rem;
    border-radius: 20px;
    font-size: 0.85rem;
    font-weight: 600;
    display: inline-block;
}

.badge-critical {
    background: #fee;
    color: #e74c3c;
}

.badge-high {
    background: #fef5e7;
    color: #f39c12;
}

.badge-medium {
    background: #e8f4f8;
    color: #3498db;
}

.badge-low {
    background: #f0f0f0;
    color: #95a5a6;
}

.badge-success {
    background: #d4edda;
    color: #28a745;
}

.badge-warning {
    background: #fff3cd;
    color: #ffc107;
}

footer {
    text-align: center;
    padding: 2rem;
    color: white;
    font-size: 0.9rem;
}

@media (max-width: 768px) {
    .metrics-grid {
        grid-template-columns: 1fr;
    }

    .content-grid {
        grid-template-columns: 1fr;
    }
}
"@
}

function Get-DefaultJS {
    return @"
// Auto-refresh functionality
let refreshInterval = 30000; // 30 seconds

function loadDevices() {
    fetch('/api/devices')
        .then(response => response.json())
        .then(data => {
            const container = document.getElementById('devices-list');
            if (container) {
                let html = '<table><thead><tr><th>Hostname</th><th>IP Address</th><th>Status</th><th>Last Seen</th></tr></thead><tbody>';
                data.devices.forEach(device => {
                    const statusClass = device.Status === 'Online' ? 'success' : 'warning';
                    html += \`<tr>
                        <td><a href="/devices/\${device.DeviceId}">\${device.Hostname}</a></td>
                        <td>\${device.IPAddress || 'N/A'}</td>
                        <td><span class="badge badge-\${statusClass}">\${device.Status}</span></td>
                        <td>\${device.LastSeen || 'Never'}</td>
                    </tr>\`;
                });
                html += '</tbody></table>';
                container.innerHTML = html;
            }
        })
        .catch(error => console.error('Error loading devices:', error));
}

function loadAlerts() {
    fetch('/api/alerts')
        .then(response => response.json())
        .then(data => {
            const container = document.getElementById('alerts-list');
            if (container) {
                if (data.Alerts && data.Alerts.length > 0) {
                    let html = '<div class="stats" style="margin-bottom:20px;">';
                    html += '<div class="stat-card" style="background:#dc3545;color:white;"><div class="stat-number">' + (data.Critical || 0) + '</div><div class="stat-label">Critical</div></div>';
                    html += '<div class="stat-card" style="background:#fd7e14;color:white;"><div class="stat-number">' + (data.High || 0) + '</div><div class="stat-label">High</div></div>';
                    html += '<div class="stat-card" style="background:#ffc107;"><div class="stat-number">' + (data.Medium || 0) + '</div><div class="stat-label">Medium</div></div>';
                    html += '<div class="stat-card" style="background:#17a2b8;color:white;"><div class="stat-number">' + (data.Low || 0) + '</div><div class="stat-label">Low</div></div>';
                    html += '</div>';
                    html += '<table><thead><tr><th>Severity</th><th>Type</th><th>Alert</th><th>Time</th><th>Actions</th></tr></thead><tbody>';
                    data.Alerts.forEach(alert => {
                        const severityClass = alert.Severity.toLowerCase();
                        const severityColor = alert.Severity === 'Critical' ? '#dc3545' : alert.Severity === 'High' ? '#fd7e14' : alert.Severity === 'Medium' ? '#ffc107' : '#17a2b8';
                        html += '<tr>';
                        html += '<td><span class="badge" style="background:' + severityColor + ';color:' + (alert.Severity === 'Medium' ? '#333' : 'white') + ';">' + alert.Severity + '</span></td>';
                        html += '<td>' + alert.AlertType + '</td>';
                        html += '<td>' + alert.Title + '</td>';
                        html += '<td>' + alert.CreatedAt + '</td>';
                        html += '<td><button onclick="acknowledgeAlert(\\'' + alert.AlertId + '\\')" style="padding:5px 10px;margin-right:5px;cursor:pointer;">Ack</button>';
                        html += '<button onclick="resolveAlert(\\'' + alert.AlertId + '\\')" style="padding:5px 10px;cursor:pointer;">Resolve</button></td>';
                        html += '</tr>';
                    });
                    html += '</tbody></table>';
                    container.innerHTML = html;
                } else {
                    container.innerHTML = '<p style="color:#28a745;font-size:1.2em;">✓ No active alerts!</p>';
                }
            }
        })
        .catch(error => console.error('Error loading alerts:', error));
}

function acknowledgeAlert(alertId) {
    fetch('/api/alerts/acknowledge', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ alertId: alertId, acknowledgedBy: 'Admin' })
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            // Reload page if on device detail, otherwise reload alerts list
            if (window.location.pathname.startsWith('/devices/')) {
                window.location.reload();
            } else if (typeof loadAlerts === 'function') {
                loadAlerts();
            }
        } else {
            alert('Error: ' + data.error);
        }
    });
}

// Alias for ackAlert to match button onclick
function ackAlert(alertId) {
    acknowledgeAlert(alertId);
}

function resolveAlert(alertId) {
    fetch('/api/alerts/resolve', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ alertId: alertId, resolvedBy: 'Admin' })
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            // Reload page if on device detail, otherwise reload alerts list
            if (window.location.pathname.startsWith('/devices/')) {
                window.location.reload();
            } else if (typeof loadAlerts === 'function') {
                loadAlerts();
            }
        } else {
            alert('Error: ' + data.error);
        }
    });
}

function loadActions() {
    fetch('/api/actions')
        .then(response => response.json())
        .then(data => {
            const container = document.getElementById('actions-list');
            if (container) {
                let html = '<table><thead><tr><th>Device</th><th>Action</th><th>Status</th><th>Time</th></tr></thead><tbody>';
                if (data.actions) {
                    data.actions.forEach(action => {
                        const statusClass = action.Status === 'Completed' ? 'success' : 'warning';
                        html += \`<tr>
                            <td>\${action.DeviceId}</td>
                            <td>\${action.ActionType}</td>
                            <td><span class="badge badge-\${statusClass}">\${action.Status}</span></td>
                            <td>\${action.CreatedAt}</td>
                        </tr>\`;
                    });
                }
                html += '</tbody></table>';
                container.innerHTML = html;
            }
        })
        .catch(error => console.error('Error loading actions:', error));
}

function executeAction(e) {
    e.preventDefault();
    const deviceId = document.getElementById('deviceId').value;
    const actionType = document.getElementById('actionType').value;

    fetch('/api/actions/execute', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ deviceId, actionType })
    })
    .then(response => response.json())
    .then(data => {
        const resultDiv = document.getElementById('action-result');
        if (data.success) {
            resultDiv.innerHTML = '<p class="success-text">Action queued: ' + data.message + '</p>';
            loadActions();
        } else {
            resultDiv.innerHTML = '<p class="error-text">Error: ' + data.error + '</p>';
        }
    })
    .catch(error => {
        document.getElementById('action-result').innerHTML = '<p class="error-text">Error: ' + error + '</p>';
    });
}

function executeDeviceAction(deviceId, actionType) {
    fetch('/api/actions/execute', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ deviceId, actionType })
    })
    .then(response => response.json())
    .then(data => {
        const resultDiv = document.getElementById('action-result');
        if (data.success) {
            resultDiv.innerHTML = '<p class="success-text">Action queued: ' + data.message + '</p>';
        } else {
            resultDiv.innerHTML = '<p class="error-text">Error: ' + data.error + '</p>';
        }
    })
    .catch(error => {
        document.getElementById('action-result').innerHTML = '<p class="error-text">Error: ' + error + '</p>';
    });
}

// Auto-refresh on dashboard
if (window.location.pathname === '/') {
    setInterval(() => {
        location.reload();
    }, refreshInterval);
}

console.log('myTech.Today RMM Dashboard loaded');
"@
}

#endregion

#region HTML Generation Functions

function Get-DashboardHTML {
    $fleet = Get-FleetStatusData
    $alerts = Get-AlertsData  # All alerts for counts
    $criticalAlerts = Get-AlertsData -CriticalOnly  # Only Critical for display on dashboard
    $recentActions = Get-RecentActionsData

    $onlinePercent = if ($fleet.Total -gt 0) { [Math]::Round(($fleet.Online / $fleet.Total) * 100, 1) } else { 0 }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>myTech.Today RMM Dashboard</title>
    <link rel="stylesheet" href="/styles.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>ðŸ–¥ï¸</text></svg>">
</head>
<body>
    <header>
        <h1>myTech.Today RMM Dashboard</h1>
        <nav>
            <a href="/" class="active">Dashboard</a>
            <a href="/devices">Devices</a>
            <a href="/alerts">Alerts</a>
            <a href="/actions">Actions</a>
            <a href="/sites">Sites</a>
            <a href="/reports">Reports</a>
            <a href="/settings">Settings</a>
        </nav>
    </header>

    <main>
        <div class="metrics-grid">
            <div class="metric-card">
                <h3>Fleet Status</h3>
                <div class="metric-value">$($fleet.Online)/$($fleet.Total)</div>
                <div class="metric-label">$onlinePercent% Online</div>
            </div>

            <div class="metric-card">
                <h3>Active Alerts</h3>
                <div class="metric-value alert-critical">$($alerts.Total)</div>
                <div class="metric-label">$($alerts.Critical) Critical</div>
            </div>

            <div class="metric-card">
                <h3>Offline Devices</h3>
                <div class="metric-value alert-warning">$($fleet.Offline)</div>
                <div class="metric-label">Requires Attention</div>
            </div>

            <div class="metric-card">
                <h3>Recent Actions</h3>
                <div class="metric-value">$(if ($recentActions) { @($recentActions).Count } else { 0 })</div>
                <div class="metric-label">Last 24 Hours</div>
            </div>
        </div>

        <div class="content-grid">
            <div class="panel">
                <h2>Critical Alerts <a href="/alerts" style="font-size:12px;font-weight:normal;margin-left:10px;">View All ($($alerts.Total))</a></h2>
                <div id="alerts-list">
                    <table>
                        <thead>
                            <tr>
                                <th>Severity</th>
                                <th>Device</th>
                                <th>Alert</th>
                                <th>Time</th>
                            </tr>
                        </thead>
                        <tbody>
"@

    if ($criticalAlerts.Alerts) {
        foreach ($alert in $criticalAlerts.Alerts) {
            $severityClass = if ($alert.Severity) { $alert.Severity.ToLower() } else { "low" }
            $html += @"
                            <tr>
                                <td><span class="badge badge-$severityClass">$($alert.Severity)</span></td>
                                <td>$($alert.DeviceId)</td>
                                <td>$($alert.Title)</td>
                                <td>$($alert.CreatedAt)</td>
                            </tr>
"@
        }
    } else {
        $html += "<tr><td colspan='4' style='text-align:center;color:#28a745;'>No critical alerts - all systems nominal</td></tr>"
    }

    $html += @"
                        </tbody>
                    </table>
                </div>
            </div>

            <div class="panel">
                <h2>Recent Actions</h2>
                <div id="actions-list">
                    <table>
                        <thead>
                            <tr>
                                <th>Device</th>
                                <th>Action</th>
                                <th>Status</th>
                                <th>Time</th>
                            </tr>
                        </thead>
                        <tbody>
"@

    if ($recentActions) {
        foreach ($action in $recentActions) {
            $statusClass = if ($action.Status -eq "Completed") { "success" } else { "warning" }
            $html += @"
                            <tr>
                                <td>$($action.DeviceId)</td>
                                <td>$($action.ActionType)</td>
                                <td><span class="badge badge-$statusClass">$($action.Status)</span></td>
                                <td>$($action.CreatedAt)</td>
                            </tr>
"@
        }
    } else {
        $html += "<tr><td colspan='4' style='text-align:center;color:#999;'>No recent actions</td></tr>"
    }

    $html += @"
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </main>

    <footer>
        <p>&copy; 2025 myTech.Today RMM - Powered by PowerShell</p>
    </footer>

    <script src="/app.js"></script>
</body>
</html>
"@

    return $html
}

function Get-DevicesPageHTML {
    # Get sites for dropdown
    $sitesQuery = "SELECT SiteId, Name FROM Sites ORDER BY Name"
    $sites = Invoke-SqliteQuery -DataSource $DatabasePath -Query $sitesQuery
    $siteOptions = ""
    foreach ($site in $sites) {
        $siteOptions += "<option value='$($site.SiteId)'>$($site.Name)</option>`n"
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Devices - myTech.Today RMM</title>
    <link rel="stylesheet" href="/styles.css">
    <style>
        .device-actions { display: flex; gap: 10px; margin-bottom: 20px; flex-wrap: wrap; }
        .device-actions button { padding: 10px 20px; background: #667eea; color: white; border: none; border-radius: 5px; cursor: pointer; }
        .device-actions button:hover { background: #5a6fd6; }
        .device-actions button.secondary { background: #6c757d; }
        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 1000; }
        .modal.active { display: flex; justify-content: center; align-items: center; }
        .modal-content { background: white; padding: 30px; border-radius: 10px; max-width: 600px; width: 90%; max-height: 85vh; overflow-y: auto; }
        .modal-content h3 { margin-top: 0; }
        .form-group { margin-bottom: 15px; }
        .form-group label { display: block; margin-bottom: 5px; font-weight: bold; }
        .form-group input, .form-group select, .form-group textarea { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; }
        .form-row { display: flex; gap: 15px; }
        .form-row .form-group { flex: 1; }
        .btn-row { display: flex; gap: 10px; margin-top: 20px; }
        .btn-primary { background: #667eea; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; }
        .btn-cancel { background: #6c757d; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; }
        .btn-small { padding: 5px 10px; font-size: 12px; }
        .btn-success { background: #28a745; color: white; border: none; border-radius: 5px; cursor: pointer; }
        .result-message { padding: 10px; border-radius: 5px; margin-top: 10px; }
        .result-message.success { background: #d4edda; color: #155724; }
        .result-message.error { background: #f8d7da; color: #721c24; }
        .result-message.info { background: #cce5ff; color: #004085; }
        .export-links { display: flex; gap: 10px; }
        .export-links a { text-decoration: none; padding: 5px 15px; background: #28a745; color: white; border-radius: 4px; }
        .input-with-status { position: relative; }
        .input-with-status input { padding-right: 30px; }
        .input-with-status .status-indicator { position: absolute; right: 10px; top: 50%; transform: translateY(-50%); font-size: 16px; }
        .input-validated { text-align: right; text-transform: uppercase; font-weight: bold; background: #d4edda !important; }
        .input-error { background: #f8d7da !important; }
        .site-row { display: flex; gap: 10px; align-items: flex-end; }
        .site-row .form-group { flex: 1; margin-bottom: 0; }
        .pairing-section { background: #f8f9fa; padding: 15px; border-radius: 8px; margin-bottom: 15px; border: 2px dashed #667eea; }
        .pairing-code { font-size: 32px; font-family: monospace; letter-spacing: 5px; text-align: center; color: #667eea; font-weight: bold; }
        .pairing-timer { text-align: center; font-size: 14px; color: #666; margin-top: 5px; }
        .pairing-timer.expired { color: #dc3545; font-weight: bold; }
        .new-site-input { display: none; margin-top: 10px; }
        .new-site-input.active { display: block; }
    </style>
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>ðŸ–¥ï¸</text></svg>">
</head>
<body>
    <header>
        <h1>myTech.Today RMM Dashboard</h1>
        <nav>
            <a href="/">Dashboard</a>
            <a href="/devices" class="active">Devices</a>
            <a href="/alerts">Alerts</a>
            <a href="/actions">Actions</a>
            <a href="/sites">Sites</a>
            <a href="/reports">Reports</a>
            <a href="/settings">Settings</a>
        </nav>
    </header>

    <main>
        <div class="panel">
            <h2>Device Management</h2>
            <div class="device-actions">
                <button onclick="openAddDeviceModal()">+ Add Device</button>
                <button class="secondary" onclick="openImportModal()">Import Devices</button>
                <div class="export-links">
                    <a href="/api/devices/export?format=csv">Export CSV</a>
                    <a href="/api/devices/export?format=json">Export JSON</a>
                </div>
            </div>
            <div id="devices-list">Loading...</div>
        </div>
    </main>

    <!-- Add Device Modal -->
    <div id="addDeviceModal" class="modal">
        <div class="modal-content">
            <h3>Add New Device</h3>

            <!-- Pairing Code Section -->
            <div class="pairing-section">
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;">
                    <strong>Client Pairing Code</strong>
                    <button type="button" class="btn-primary btn-small" onclick="generatePairingCode()">Generate Code</button>
                </div>
                <div class="pairing-code" id="pairingCode">------</div>
                <div class="pairing-timer" id="pairingTimer">Click Generate to create a 10-minute code</div>
            </div>

            <form id="addDeviceForm" onsubmit="submitAddDevice(event)">
                <div class="form-row">
                    <div class="form-group input-with-status">
                        <label for="hostname">Hostname *</label>
                        <input type="text" id="hostname" name="hostname" required placeholder="e.g., SERVER01" onblur="resolveHostname(this)">
                        <span class="status-indicator" id="hostnameStatus"></span>
                    </div>
                    <div class="form-group input-with-status">
                        <label for="ipAddress">IP Address</label>
                        <input type="text" id="ipAddress" name="ipAddress" placeholder="e.g., 192.168.1.10" onblur="pingIPAddress(this)">
                        <span class="status-indicator" id="ipStatus"></span>
                    </div>
                </div>
                <div class="form-group">
                    <div class="site-row">
                        <div class="form-group">
                            <label for="siteId">Site</label>
                            <select id="siteId" name="siteId" onchange="toggleNewSite(this)">
                                $siteOptions
                                <option value="__new__">+ Add New Site...</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label for="deviceType">Device Type</label>
                            <select id="deviceType" name="deviceType">
                                <option value="Workstation">Workstation</option>
                                <option value="Server">Server</option>
                                <option value="Laptop">Laptop</option>
                                <option value="Virtual">Virtual</option>
                                <option value="Container">Container</option>
                                <option value="Other">Other</option>
                            </select>
                        </div>
                    </div>
                    <div class="new-site-input" id="newSiteContainer">
                        <div class="form-row" style="margin-top:10px;">
                            <div class="form-group">
                                <input type="text" id="newSiteName" placeholder="New site name...">
                            </div>
                            <button type="button" class="btn-success btn-small" onclick="createNewSite()" style="height:38px;">Create Site</button>
                        </div>
                    </div>
                </div>
                <div class="form-group">
                    <label for="description">Description</label>
                    <textarea id="description" name="description" rows="2" placeholder="Device description..."></textarea>
                </div>
                <div class="form-group">
                    <label for="tags">Tags (comma-separated)</label>
                    <input type="text" id="tags" name="tags" placeholder="e.g., production, critical">
                </div>
                <div id="addDeviceResult"></div>
                <div class="btn-row">
                    <button type="submit" class="btn-primary">Add Device</button>
                    <button type="button" class="btn-cancel" onclick="closeModal('addDeviceModal')">Cancel</button>
                </div>
            </form>
        </div>
    </div>

    <!-- Import Modal -->
    <div id="importModal" class="modal">
        <div class="modal-content">
            <h3>Import Devices</h3>
            <p>Use PowerShell to import devices:</p>
            <pre style="background:#f5f5f5;padding:15px;border-radius:5px;">Import-RMMDevices -Path "devices.csv"
Import-RMMDevices -Path "devices.xlsx"
Import-RMMDevices -Path "devices.json"</pre>
            <p><strong>Required:</strong> Hostname</p>
            <p><strong>Optional:</strong> FQDN, IPAddress, MACAddress, SiteId, DeviceType, Description, Tags</p>
            <div class="btn-row">
                <button type="button" class="btn-cancel" onclick="closeModal('importModal')">Close</button>
            </div>
        </div>
    </div>

    <footer>
        <p>&copy; 2025 myTech.Today RMM - Powered by PowerShell</p>
    </footer>

    <script src="/app.js"></script>
    <script>
        loadDevices();
        let pairingInterval = null;
        let pairingExpiry = null;

        function openAddDeviceModal() { document.getElementById('addDeviceModal').classList.add('active'); }
        function openImportModal() { document.getElementById('importModal').classList.add('active'); }
        function closeModal(id) {
            document.getElementById(id).classList.remove('active');
            document.getElementById('addDeviceResult').innerHTML = '';
            if (pairingInterval) { clearInterval(pairingInterval); pairingInterval = null; }
        }

        function generatePairingCode() {
            const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
            let code = '';
            for (let i = 0; i < 6; i++) code += chars.charAt(Math.floor(Math.random() * chars.length));
            document.getElementById('pairingCode').textContent = code;
            pairingExpiry = Date.now() + (10 * 60 * 1000);
            fetch('/api/pairing/create', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: code, expiresAt: pairingExpiry }) });
            if (pairingInterval) clearInterval(pairingInterval);
            pairingInterval = setInterval(updatePairingTimer, 1000);
            updatePairingTimer();
        }

        function updatePairingTimer() {
            const timerEl = document.getElementById('pairingTimer');
            if (!pairingExpiry) return;
            const remaining = Math.max(0, pairingExpiry - Date.now());
            if (remaining <= 0) {
                timerEl.textContent = 'Code expired - generate a new one';
                timerEl.classList.add('expired');
                document.getElementById('pairingCode').textContent = '------';
                clearInterval(pairingInterval);
                pairingInterval = null; pairingExpiry = null;
            } else {
                const mins = Math.floor(remaining / 60000);
                const secs = Math.floor((remaining % 60000) / 1000);
                timerEl.textContent = 'Valid for ' + mins + ':' + secs.toString().padStart(2, '0');
                timerEl.classList.remove('expired');
            }
        }

        function resolveHostname(input) {
            const hostname = input.value.trim();
            if (!hostname) return;
            const status = document.getElementById('hostnameStatus');
            status.textContent = '...';
            fetch('/api/network/resolve?hostname=' + encodeURIComponent(hostname))
                .then(r => r.json())
                .then(result => {
                    if (result.success) {
                        input.value = result.hostname.toUpperCase();
                        input.classList.add('input-validated');
                        input.classList.remove('input-error');
                        status.textContent = '\u2705';
                        if (result.ipAddress && !document.getElementById('ipAddress').value) {
                            document.getElementById('ipAddress').value = result.ipAddress;
                        }
                        if (result.deviceType) { document.getElementById('deviceType').value = result.deviceType; }
                    } else {
                        input.classList.remove('input-validated');
                        status.textContent = '\u26A0';
                    }
                })
                .catch(() => { status.textContent = '?'; });
        }

        function pingIPAddress(input) {
            const ip = input.value.trim();
            if (!ip) return;
            const status = document.getElementById('ipStatus');
            status.textContent = '...';
            fetch('/api/network/ping?ip=' + encodeURIComponent(ip))
                .then(r => r.json())
                .then(result => {
                    if (result.success && result.reachable) {
                        input.classList.add('input-validated');
                        input.classList.remove('input-error');
                        status.textContent = '\u2705';
                    } else {
                        input.classList.remove('input-validated');
                        input.classList.add('input-error');
                        status.textContent = '\u274C';
                    }
                })
                .catch(() => { status.textContent = '?'; });
        }

        function toggleNewSite(select) {
            const container = document.getElementById('newSiteContainer');
            if (select.value === '__new__') {
                container.classList.add('active');
                document.getElementById('newSiteName').focus();
            } else {
                container.classList.remove('active');
            }
        }

        function createNewSite() {
            const name = document.getElementById('newSiteName').value.trim();
            if (!name) { alert('Please enter a site name'); return; }
            fetch('/api/sites/add', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: name }) })
            .then(r => r.json())
            .then(result => {
                if (result.success) {
                    const select = document.getElementById('siteId');
                    const option = document.createElement('option');
                    option.value = result.siteId;
                    option.textContent = name;
                    select.insertBefore(option, select.querySelector('option[value="__new__"]'));
                    select.value = result.siteId;
                    document.getElementById('newSiteContainer').classList.remove('active');
                    document.getElementById('newSiteName').value = '';
                } else { alert('Error: ' + result.error); }
            });
        }

        function submitAddDevice(e) {
            e.preventDefault();
            const f = e.target;
            const siteId = f.siteId.value === '__new__' ? 'default' : f.siteId.value;
            fetch('/api/devices/add', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ hostname: f.hostname.value, ipAddress: f.ipAddress.value, siteId: siteId, deviceType: f.deviceType.value, description: f.description.value, tags: f.tags.value })
            })
            .then(r => r.json())
            .then(result => {
                const div = document.getElementById('addDeviceResult');
                if (result.success) {
                    div.innerHTML = '<div class="result-message success">Device added: ' + result.deviceId + '</div>';
                    f.reset();
                    setTimeout(() => { closeModal('addDeviceModal'); loadDevices(); }, 1500);
                } else {
                    div.innerHTML = '<div class="result-message error">Error: ' + result.error + '</div>';
                }
            });
        }
    </script>
</body>
</html>
"@
    return $html
}

function Get-AlertsPageHTML {
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Alerts - myTech.Today RMM</title>
    <link rel="stylesheet" href="/styles.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>ðŸ–¥ï¸</text></svg>">
</head>
<body>
    <header>
        <h1>myTech.Today RMM Dashboard</h1>
        <nav>
            <a href="/">Dashboard</a>
            <a href="/devices">Devices</a>
            <a href="/alerts" class="active">Alerts</a>
            <a href="/actions">Actions</a>
            <a href="/sites">Sites</a>
            <a href="/reports">Reports</a>
            <a href="/settings">Settings</a>
        </nav>
    </header>

    <main>
        <div class="panel">
            <h2>Alert Management</h2>
            <div id="alerts-list">Loading...</div>
        </div>
    </main>

    <footer>
        <p>&copy; 2025 myTech.Today RMM - Powered by PowerShell</p>
    </footer>

    <script src="/app.js"></script>
    <script>loadAlerts();</script>
</body>
</html>
"@
    return $html
}

function Get-ActionsPageHTML {
    # Get devices for dropdown
    $devicesQuery = "SELECT DeviceId, Hostname, Status FROM Devices ORDER BY Hostname"
    $devices = Invoke-SqliteQuery -DataSource $DatabasePath -Query $devicesQuery
    $deviceOptions = "<option value='all'>All Devices</option>`n"
    foreach ($device in $devices) {
        $statusIcon = if ($device.Status -eq 'Online') { '[OK]' } elseif ($device.Status -eq 'Offline') { '[OFF]' } else { '[!]' }
        $deviceOptions += "<option value='$($device.DeviceId)'>$statusIcon $($device.Hostname)</option>`n"
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Actions - myTech.Today RMM</title>
    <link rel="stylesheet" href="/styles.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>ðŸ–¥ï¸</text></svg>">
</head>
<body>
    <header>
        <h1>myTech.Today RMM Dashboard</h1>
        <nav>
            <a href="/">Dashboard</a>
            <a href="/devices">Devices</a>
            <a href="/alerts">Alerts</a>
            <a href="/actions" class="active">Actions</a>
            <a href="/sites">Sites</a>
            <a href="/reports">Reports</a>
            <a href="/settings">Settings</a>
        </nav>
    </header>

    <main>
        <div class="panel">
            <h2>Execute Action</h2>
            <form id="action-form">
                <div style="display:flex;gap:20px;flex-wrap:wrap;align-items:flex-end;">
                    <div class="form-group" style="flex:1;min-width:200px;">
                        <label for="deviceId" style="display:block;margin-bottom:5px;font-weight:bold;">Target Device:</label>
                        <select id="deviceId" name="deviceId" style="width:100%;padding:10px;border:1px solid #ddd;border-radius:5px;">
                            $deviceOptions
                        </select>
                    </div>
                    <div class="form-group" style="flex:1;min-width:200px;">
                        <label for="actionType" style="display:block;margin-bottom:5px;font-weight:bold;">Action Type:</label>
                        <select id="actionType" name="actionType" style="width:100%;padding:10px;border:1px solid #ddd;border-radius:5px;">
                            <optgroup label="Diagnostics">
                                <option value="HealthCheck">Health Check</option>
                                <option value="InventoryCollection">Collect Inventory</option>
                                <option value="GetSystemInfo">Get System Info</option>
                            </optgroup>
                            <optgroup label="Maintenance">
                                <option value="ClearTempFiles">Clear Temp Files</option>
                                <option value="FlushDNS">Flush DNS</option>
                                <option value="ClearEventLogs">Clear Event Logs</option>
                                <option value="DiskCleanup">Disk Cleanup</option>
                            </optgroup>
                            <optgroup label="Updates">
                                <option value="WindowsUpdate">Windows Update</option>
                                <option value="CheckUpdates">Check for Updates</option>
                            </optgroup>
                            <optgroup label="Power">
                                <option value="Reboot">Reboot</option>
                                <option value="Shutdown">Shutdown</option>
                            </optgroup>
                            <optgroup label="Network">
                                <option value="RenewIP">Renew IP Address</option>
                                <option value="ResetNetwork">Reset Network Stack</option>
                            </optgroup>
                        </select>
                    </div>
                </div>
                <button type="submit" class="btn btn-primary" style="margin-top:15px;padding:10px 20px;background:#667eea;color:white;border:none;border-radius:5px;cursor:pointer;">Execute Action</button>
            </form>
            <div id="action-result" style="margin-top:15px;"></div>
        </div>

        <div class="panel" style="margin-top:20px;">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;">
                <h2 style="margin:0;">Recent Actions</h2>
                <button onclick="clearActionsHistory()" class="btn btn-danger" style="padding:8px 16px;background:#dc3545;color:white;border:none;border-radius:5px;cursor:pointer;">Clear History</button>
            </div>
            <div id="actions-list">Loading...</div>
        </div>
    </main>

    <footer>
        <p>&copy; 2025 myTech.Today RMM - Powered by PowerShell</p>
    </footer>

    <script src="/app.js"></script>
    <script>
        loadActions();
        document.getElementById('action-form').addEventListener('submit', executeAction);
    </script>
</body>
</html>
"@
    return $html
}

function Get-ReportsPageHTML {
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reports - myTech.Today RMM</title>
    <link rel="stylesheet" href="/styles.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>ðŸ–¥ï¸</text></svg>">
</head>
<body>
    <header>
        <h1>myTech.Today RMM Dashboard</h1>
        <nav>
            <a href="/">Dashboard</a>
            <a href="/devices">Devices</a>
            <a href="/alerts">Alerts</a>
            <a href="/actions">Actions</a>
            <a href="/sites">Sites</a>
            <a href="/reports" class="active">Reports</a>
            <a href="/settings">Settings</a>
        </nav>
    </header>

    <main>
        <div class="panel">
            <h2>Reports</h2>
            <p>Report generation interface coming soon...</p>
        </div>
    </main>

    <footer>
        <p>&copy; 2025 myTech.Today RMM - Powered by PowerShell</p>
    </footer>

    <script src="/app.js"></script>
</body>
</html>
"@
    return $html
}

function Get-SettingsPageHTML {
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Settings - myTech.Today RMM</title>
    <link rel="stylesheet" href="/styles.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>ðŸ–¥ï¸</text></svg>">
</head>
<body>
    <header>
        <h1>myTech.Today RMM Dashboard</h1>
        <nav>
            <a href="/">Dashboard</a>
            <a href="/devices">Devices</a>
            <a href="/alerts">Alerts</a>
            <a href="/actions">Actions</a>
            <a href="/sites">Sites</a>
            <a href="/reports">Reports</a>
            <a href="/settings" class="active">Settings</a>
        </nav>
    </header>

    <main>
        <div class="panel">
            <h2>RMM Configuration</h2>
            <table class="settings-table">
                <tr><th>Setting</th><th>Value</th></tr>
                <tr><td>Database Path</td><td>$DatabasePath</td></tr>
                <tr><td>Web Port</td><td>$Port</td></tr>
                <tr><td>Auto Refresh</td><td>30 seconds</td></tr>
            </table>
        </div>

        <div class="panel" style="margin-top:20px;">
            <h2>System Information</h2>
            <table class="settings-table">
                <tr><td>RMM Version</td><td>2.0.0</td></tr>
                <tr><td>PowerShell Version</td><td>$($PSVersionTable.PSVersion)</td></tr>
                <tr><td>Server</td><td>$($env:COMPUTERNAME)</td></tr>
                <tr><td>Started</td><td>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</td></tr>
            </table>
        </div>

        <div class="panel" style="margin-top:20px;">
            <h2>Dashboard Controls</h2>
            <p style="color:#666;margin-bottom:15px;">Restart the dashboard to apply configuration changes or updates.</p>
            <button onclick="if(confirm('Restart the dashboard? The page will reload automatically.')) { fetch('/api/restart').then(() => setTimeout(() => location.reload(), 3000)); }" style="padding:10px 20px;background:#667eea;color:white;border:none;border-radius:5px;cursor:pointer;margin-right:10px;">Restart Dashboard</button>
            <button onclick="location.reload(true);" style="padding:10px 20px;background:#17a2b8;color:white;border:none;border-radius:5px;cursor:pointer;">Refresh Page (Clear Cache)</button>
        </div>

        <div class="panel" style="margin-top:20px;border:2px solid #dc3545;">
            <h2 style="color:#dc3545;">Uninstall RMM</h2>
            <p style="color:#666;margin-bottom:10px;">Remove myTech.Today RMM from this computer. Choose your uninstall method:</p>

            <div style="background:#f8f9fa;padding:15px;border-radius:5px;margin-bottom:15px;">
                <h4 style="margin:0 0 10px 0;">PowerShell (Recommended)</h4>
                <code style="display:block;background:#333;color:#0f0;padding:10px;border-radius:4px;font-family:monospace;">.\Uninstall.ps1</code>
                <p style="color:#666;font-size:12px;margin:8px 0 0 0;">Or with data removal: <code>.\Uninstall.ps1 -RemoveData</code></p>
            </div>

            <div style="background:#f8f9fa;padding:15px;border-radius:5px;margin-bottom:15px;">
                <h4 style="margin:0 0 10px 0;">Alternative Method</h4>
                <code style="display:block;background:#333;color:#0f0;padding:10px;border-radius:4px;font-family:monospace;">.\Install.ps1 -Uninstall</code>
            </div>

            <div style="background:#f8f9fa;padding:15px;border-radius:5px;">
                <h4 style="margin:0 0 10px 0;">PowerShell Module Command</h4>
                <code style="display:block;background:#333;color:#0f0;padding:10px;border-radius:4px;font-family:monospace;">Initialize-RMM -Mode Uninstall</code>
            </div>
        </div>
    </main>

    <footer>
        <p>&copy; 2025 myTech.Today RMM - Powered by PowerShell</p>
    </footer>

    <script src="/app.js"></script>
</body>
</html>
"@
    return $html
}

function Get-SitesPageHTML {
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sites - myTech.Today RMM</title>
    <link rel="stylesheet" href="/styles.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>ðŸ–¥ï¸</text></svg>">
    <style>
        .site-form { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; }
        .site-form .full-width { grid-column: 1 / -1; }
        .site-form label { display: block; margin-bottom: 5px; font-weight: bold; color: #555; font-size: 12px; }
        .site-form input, .site-form textarea { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; }
        .site-form textarea { min-height: 60px; }
        .site-card { background: white; border-radius: 8px; padding: 15px; margin-bottom: 15px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .site-card h3 { margin: 0 0 10px 0; color: #333; }
        .site-card .address { color: #666; font-size: 14px; }
        .site-card .contact { margin-top: 10px; font-size: 13px; }
        .site-card .urls { margin-top: 10px; }
        .site-card .urls a { display: block; color: #667eea; text-decoration: none; font-size: 13px; }
        .btn-sm { padding: 5px 10px; font-size: 12px; border: none; border-radius: 4px; cursor: pointer; margin-right: 5px; }
        .btn-edit { background: #17a2b8; color: white; }
        .btn-delete { background: #dc3545; color: white; }
        .btn-primary { background: #667eea; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; }
        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 1000; }
        .modal-content { background: white; margin: 5% auto; padding: 20px; border-radius: 8px; max-width: 800px; max-height: 80vh; overflow-y: auto; }
        .modal-header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #eee; padding-bottom: 10px; margin-bottom: 15px; }
        .modal-close { font-size: 24px; cursor: pointer; color: #666; }
    </style>
</head>
<body>
    <header>
        <h1>myTech.Today RMM Dashboard</h1>
        <nav>
            <a href="/">Dashboard</a>
            <a href="/devices">Devices</a>
            <a href="/alerts">Alerts</a>
            <a href="/actions">Actions</a>
            <a href="/sites" class="active">Sites</a>
            <a href="/reports">Reports</a>
            <a href="/settings">Settings</a>
        </nav>
    </header>

    <main>
        <div class="panel">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:15px;">
                <h2 style="margin:0;">Sites</h2>
                <button class="btn-primary" onclick="openAddSiteModal()">+ Add Site</button>
            </div>
            <div id="sites-list">Loading...</div>
        </div>
    </main>

    <div id="siteModal" class="modal">
        <div class="modal-content">
            <div class="modal-header">
                <h3 id="modalTitle">Add New Site</h3>
                <span class="modal-close" onclick="closeSiteModal()">&times;</span>
            </div>
            <form id="siteForm" onsubmit="saveSite(event)">
                <input type="hidden" id="editSiteId" value="">
                <div class="site-form">
                    <div class="full-width">
                        <label>Site Name *</label>
                        <input type="text" id="siteName" required>
                    </div>
                    <div>
                        <label>Contact Name</label>
                        <input type="text" id="contactName">
                    </div>
                    <div>
                        <label>Contact Email</label>
                        <input type="email" id="contactEmail">
                    </div>
                    <div>
                        <label>Main Phone</label>
                        <input type="tel" id="mainPhone">
                    </div>
                    <div>
                        <label>Cell Phone</label>
                        <input type="tel" id="cellPhone">
                    </div>
                    <div>
                        <label>Street Number</label>
                        <input type="text" id="streetNumber">
                    </div>
                    <div>
                        <label>Street Name</label>
                        <input type="text" id="streetName">
                    </div>
                    <div>
                        <label>Unit/Suite</label>
                        <input type="text" id="unit">
                    </div>
                    <div>
                        <label>Building</label>
                        <input type="text" id="building">
                    </div>
                    <div>
                        <label>City</label>
                        <input type="text" id="city">
                    </div>
                    <div>
                        <label>State/Province</label>
                        <select id="state"></select>
                    </div>
                    <div>
                        <label>ZIP/Postal Code</label>
                        <input type="text" id="zip">
                    </div>
                    <div>
                        <label>Country</label>
                        <select id="country" onchange="onCountryChange()"></select>
                    </div>
                    <div>
                        <label>Timezone</label>
                        <select id="timezone"></select>
                    </div>
                    <div class="full-width">
                        <label>Notes</label>
                        <textarea id="notes"></textarea>
                    </div>
                </div>
                <div style="margin-top:20px;text-align:right;">
                    <button type="button" onclick="closeSiteModal()" style="padding:10px 20px;margin-right:10px;">Cancel</button>
                    <button type="submit" class="btn-primary">Save Site</button>
                </div>
            </form>
        </div>
    </div>

    <!-- Delete Options Modal -->
    <div id="deleteOptionsModal" class="modal" style="display:none;">
        <div class="modal-content" style="max-width:500px;">
            <div class="modal-header">
                <h3 id="deleteModalTitle">Delete Site</h3>
                <span class="close-btn" onclick="closeDeleteOptionsModal()">&times;</span>
            </div>
            <div style="padding:20px;">
                <p id="deviceCountInfo" style="background:#fff3cd;padding:15px;border-radius:5px;border-left:4px solid #ffc107;margin-bottom:20px;"></p>

                <p><strong>What would you like to do?</strong></p>

                <div style="margin:15px 0;">
                    <select id="deleteOption" onchange="onDeleteOptionChange()" style="width:100%;padding:10px;font-size:14px;">
                        <option value="">-- Select an option --</option>
                        <option value="deleteall">Delete site AND all devices</option>
                        <option value="reassign">Move devices to another site</option>
                        <option value="newsite">Move devices to a new site</option>
                    </select>
                </div>

                <div id="reassignSection" style="display:none;margin:15px 0;padding:15px;background:#f8f9fa;border-radius:5px;">
                    <label><strong>Select destination site:</strong></label>
                    <select id="reassignSiteId" style="width:100%;padding:10px;margin-top:8px;font-size:14px;">
                        <option value="">-- Select a site --</option>
                    </select>
                </div>

                <div id="newSiteSection" style="display:none;margin:15px 0;padding:15px;background:#f8f9fa;border-radius:5px;">
                    <label><strong>New site name:</strong></label>
                    <input type="text" id="newSiteNameForReassign" placeholder="Enter new site name" style="width:100%;padding:10px;margin-top:8px;font-size:14px;box-sizing:border-box;">
                </div>

                <div style="margin-top:20px;text-align:right;">
                    <button type="button" onclick="closeDeleteOptionsModal()" style="padding:10px 20px;margin-right:10px;">Cancel</button>
                    <button type="button" onclick="confirmDeleteWithOption()" class="btn-delete" style="padding:10px 20px;">Delete Site</button>
                </div>
            </div>
        </div>
    </div>

    <footer>
        <p>&copy; 2025 myTech.Today RMM - Powered by PowerShell</p>
    </footer>

    <script src="/app.js"></script>
    <script>
        loadSites();

        async function loadSites() {
            try {
                const data = await (await fetch('/api/sites')).json();
                const container = document.getElementById('sites-list');
                if (data.sites && data.sites.length > 0) {
                    let html = '';
                    data.sites.forEach(s => {
                        let addr = [s.StreetNumber, s.StreetName].filter(x => x).join(' ');
                        if (s.Unit) addr += ', ' + s.Unit;
                        if (s.Building) addr += ', ' + s.Building;
                        let cityLine = [s.City, s.State, s.Zip].filter(x => x).join(', ');
                        if (s.Country) cityLine += ', ' + s.Country;

                        html += '<div class="site-card">';
                        html += '<div style="display:flex;justify-content:space-between;align-items:start;">';
                        html += '<div><h3>' + s.Name + '</h3>';
                        if (addr || cityLine) {
                            html += '<div class="address">';
                            if (addr) html += addr + '<br>';
                            if (cityLine) html += cityLine;
                            html += '</div>';
                        }
                        if (s.ContactName || s.ContactEmail || s.MainPhone || s.CellPhone) {
                            html += '<div class="contact">';
                            if (s.ContactName) html += '<strong>' + s.ContactName + '</strong><br>';
                            if (s.ContactEmail) html += 'Email: ' + s.ContactEmail + '<br>';
                            if (s.MainPhone) html += 'Phone: ' + s.MainPhone + '<br>';
                            if (s.CellPhone) html += 'Cell: ' + s.CellPhone;
                            html += '</div>';
                        }
                        if (s.URLs && s.URLs.length > 0) {
                            html += '<div class="urls">';
                            s.URLs.forEach(u => {
                                html += '<a href="' + u.URL + '" target="_blank">' + (u.Label || u.URL) + '</a>';
                            });
                            html += '</div>';
                        }
                        html += '</div>';
                        html += '<div>';
                        html += '<button class="btn-sm btn-edit" onclick="editSite(\'' + s.SiteId + '\')">Edit</button>';
                        html += '<button class="btn-sm btn-delete" onclick="deleteSite(\'' + s.SiteId + '\', \'' + s.Name + '\')">Delete</button>';
                        html += '</div></div></div>';
                    });
                    container.innerHTML = html;
                } else {
                    container.innerHTML = '<p>No sites configured. Click "Add Site" to create one.</p>';
                }
            } catch (e) {
                console.error('Error loading sites:', e);
                document.getElementById('sites-list').innerHTML = '<p style="color:red;">Error loading sites</p>';
            }
        }

        function openAddSiteModal() {
            document.getElementById('modalTitle').textContent = 'Add New Site';
            document.getElementById('siteForm').reset();
            document.getElementById('editSiteId').value = '';
            document.getElementById('siteModal').style.display = 'block';
        }

        function closeSiteModal() {
            document.getElementById('siteModal').style.display = 'none';
        }

        async function editSite(siteId) {
            const data = await (await fetch('/api/sites/' + siteId)).json();
            if (data.site) {
                const s = data.site;
                document.getElementById('modalTitle').textContent = 'Edit Site: ' + s.Name;
                document.getElementById('editSiteId').value = siteId;
                document.getElementById('siteName').value = s.Name || '';
                document.getElementById('contactName').value = s.ContactName || '';
                document.getElementById('contactEmail').value = s.ContactEmail || '';
                document.getElementById('mainPhone').value = s.MainPhone || '';
                document.getElementById('cellPhone').value = s.CellPhone || '';
                document.getElementById('streetNumber').value = s.StreetNumber || '';
                document.getElementById('streetName').value = s.StreetName || '';
                document.getElementById('unit').value = s.Unit || '';
                document.getElementById('building').value = s.Building || '';
                document.getElementById('city').value = s.City || '';
                document.getElementById('state').value = s.State || '';
                document.getElementById('zip').value = s.Zip || '';
                document.getElementById('country').value = s.Country || '';
                document.getElementById('timezone').value = s.Timezone || '';
                document.getElementById('notes').value = s.Notes || '';
                document.getElementById('siteModal').style.display = 'block';
            }
        }

        async function saveSite(e) {
            e.preventDefault();
            const siteId = document.getElementById('editSiteId').value;
            const siteData = {
                name: document.getElementById('siteName').value,
                contactName: document.getElementById('contactName').value,
                contactEmail: document.getElementById('contactEmail').value,
                mainPhone: document.getElementById('mainPhone').value,
                cellPhone: document.getElementById('cellPhone').value,
                streetNumber: document.getElementById('streetNumber').value,
                streetName: document.getElementById('streetName').value,
                unit: document.getElementById('unit').value,
                building: document.getElementById('building').value,
                city: document.getElementById('city').value,
                state: document.getElementById('state').value,
                zip: document.getElementById('zip').value,
                country: document.getElementById('country').value,
                timezone: document.getElementById('timezone').value,
                notes: document.getElementById('notes').value
            };

            const url = siteId ? '/api/sites/update' : '/api/sites/add';
            if (siteId) siteData.siteId = siteId;

            const result = await (await fetch(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(siteData)
            })).json();

            if (result.success) {
                closeSiteModal();
                loadSites();
            } else {
                alert('Error: ' + (result.error || 'Unknown error'));
            }
        }

        async function deleteSite(siteId, name) {
            // First check if there are devices assigned to this site
            const checkResult = await (await fetch('/api/sites/' + siteId + '/devices')).json();

            if (checkResult.deviceCount > 0) {
                // Show delete options modal
                showDeleteOptionsModal(siteId, name, checkResult.deviceCount, checkResult.devices);
            } else {
                // No devices - simple delete confirmation
                if (!confirm('Delete site "' + name + '"? This cannot be undone.')) return;
                await executeDeleteSite(siteId, 'delete', null);
            }
        }

        function showDeleteOptionsModal(siteId, siteName, deviceCount, devices) {
            // Store for later use
            window.deletingSiteId = siteId;
            window.deletingSiteName = siteName;

            // Update modal content
            document.getElementById('deleteModalTitle').textContent = 'Delete Site: ' + siteName;
            document.getElementById('deviceCountInfo').textContent =
                'This site has ' + deviceCount + ' device(s) assigned: ' +
                devices.map(d => d.Hostname).join(', ');

            // Load other sites for dropdown
            loadSitesForReassign(siteId);

            // Reset selection
            document.getElementById('deleteOption').value = '';
            document.getElementById('reassignSection').style.display = 'none';
            document.getElementById('newSiteSection').style.display = 'none';

            document.getElementById('deleteOptionsModal').style.display = 'block';
        }

        async function loadSitesForReassign(excludeSiteId) {
            const data = await (await fetch('/api/sites')).json();
            const select = document.getElementById('reassignSiteId');
            select.innerHTML = '<option value="">-- Select a site --</option>';
            if (data.sites) {
                data.sites.forEach(s => {
                    if (s.SiteId !== excludeSiteId) {
                        select.innerHTML += '<option value="' + s.SiteId + '">' + s.Name + '</option>';
                    }
                });
            }
        }

        function onDeleteOptionChange() {
            const option = document.getElementById('deleteOption').value;
            document.getElementById('reassignSection').style.display = (option === 'reassign') ? 'block' : 'none';
            document.getElementById('newSiteSection').style.display = (option === 'newsite') ? 'block' : 'none';
        }

        function closeDeleteOptionsModal() {
            document.getElementById('deleteOptionsModal').style.display = 'none';
        }

        async function confirmDeleteWithOption() {
            const option = document.getElementById('deleteOption').value;
            const siteId = window.deletingSiteId;

            if (!option) {
                alert('Please select an option');
                return;
            }

            let targetSiteId = null;

            if (option === 'reassign') {
                targetSiteId = document.getElementById('reassignSiteId').value;
                if (!targetSiteId) {
                    alert('Please select a site to reassign devices to');
                    return;
                }
            } else if (option === 'newsite') {
                const newSiteName = document.getElementById('newSiteNameForReassign').value.trim();
                if (!newSiteName) {
                    alert('Please enter a name for the new site');
                    return;
                }
                // Create new site first
                const createResult = await (await fetch('/api/sites/add', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name: newSiteName })
                })).json();

                if (!createResult.success) {
                    alert('Error creating new site: ' + (createResult.error || 'Unknown error'));
                    return;
                }
                targetSiteId = createResult.siteId;
            }

            // Execute the delete with the selected option
            await executeDeleteSite(siteId, option === 'deleteall' ? 'cascade' : 'reassign', targetSiteId);
            closeDeleteOptionsModal();
        }

        async function executeDeleteSite(siteId, action, targetSiteId) {
            const result = await (await fetch('/api/sites/delete', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    siteId: siteId,
                    action: action,
                    targetSiteId: targetSiteId
                })
            })).json();

            if (result.success) {
                loadSites();
            } else {
                alert('Error: ' + (result.error || 'Unknown error'));
            }
        }
    </script>
</body>
</html>
"@
    return $html
}

function Get-DeviceDetailPageHTML {
    param([string]$DeviceId)

    $query = "SELECT * FROM Devices WHERE DeviceId = @DeviceId"
    $device = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ DeviceId = $DeviceId }

    if (-not $device) {
        return "<html><body><h1>Device Not Found</h1><p>Device ID: $DeviceId</p><a href='/devices'>Back to Devices</a></body></html>"
    }

    $alertsQuery = "SELECT * FROM Alerts WHERE DeviceId = @DeviceId AND ResolvedAt IS NULL ORDER BY CreatedAt DESC LIMIT 10"
    $alerts = Invoke-SqliteQuery -DataSource $DatabasePath -Query $alertsQuery -SqlParameters @{ DeviceId = $DeviceId }

    # Get sites for dropdown
    $sitesQuery = "SELECT SiteId, Name FROM Sites ORDER BY Name"
    $sites = Invoke-SqliteQuery -DataSource $DatabasePath -Query $sitesQuery

    # Build site options
    $siteOptions = ""
    foreach ($site in $sites) {
        $selected = if ($site.SiteId -eq $device.SiteId) { "selected" } else { "" }
        $siteOptions += "<option value='$($site.SiteId)' $selected>$($site.Name)</option>`n"
    }

    # Build device type options
    $deviceTypes = @("Workstation", "Server", "Laptop", "Virtual Machine", "Network Device", "Mobile Device", "Other")
    $typeOptions = ""
    foreach ($type in $deviceTypes) {
        $selected = if ($type -eq $device.DeviceType) { "selected" } else { "" }
        $typeOptions += "<option value='$type' $selected>$type</option>`n"
    }

    # Get status description for non-OK statuses
    $statusDesc = ""
    if ($device.Status -ne 'Online' -and $device.Status -ne 'OK') {
        $statusDesc = " <span style='color:#666;font-size:12px;'>$(Get-StatusDescription -Status $device.Status -LastSeen $device.LastSeen)</span>"
    }

    # Escape values for HTML
    $escTags = if ($device.Tags) { [System.Web.HttpUtility]::HtmlEncode($device.Tags) } else { '' }
    $escDesc = if ($device.Description) { [System.Web.HttpUtility]::HtmlEncode($device.Description) } else { '' }
    $escCred = if ($device.CredentialName) { [System.Web.HttpUtility]::HtmlEncode($device.CredentialName) } else { '' }
    $escNotes = if ($device.Notes) { [System.Web.HttpUtility]::HtmlEncode($device.Notes) } else { '' }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$($device.Hostname) - myTech.Today RMM</title>
    <link rel="stylesheet" href="/styles.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>ðŸ–¥ï¸</text></svg>">
    <style>
        .field-row { display: flex; border-bottom: 1px solid #eee; padding: 8px 0; align-items: flex-start; }
        .field-label { width: 180px; font-weight: bold; color: #555; padding-top: 6px; }
        .field-value { flex: 1; }
        .field-value.readonly { color: #666; background: #f9f9f9; padding: 6px 10px; border-radius: 4px; }
        .field-value input, .field-value select, .field-value textarea {
            width: 100%; padding: 6px 10px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; box-sizing: border-box;
        }
        .field-value textarea { min-height: 80px; resize: vertical; font-family: inherit; }
        .section-header { background: #f5f5f5; padding: 10px 15px; margin: 20px 0 10px 0; border-radius: 4px; font-weight: bold; color: #333; }
        .save-btn { background: #28a745; color: white; padding: 12px 30px; border: none; border-radius: 5px; cursor: pointer; font-size: 14px; margin-top: 20px; }
        .save-btn:hover { background: #218838; }
        .save-result { margin-top: 10px; padding: 10px; border-radius: 4px; display: none; }
        .save-result.success { background: #d4edda; color: #155724; display: block; }
        .save-result.error { background: #f8d7da; color: #721c24; display: block; }
        .not-collected { font-style: italic; color: #999; }
    </style>
</head>
<body>
    <header>
        <h1>myTech.Today RMM Dashboard</h1>
        <nav>
            <a href="/">Dashboard</a>
            <a href="/devices" class="active">Devices</a>
            <a href="/alerts">Alerts</a>
            <a href="/actions">Actions</a>
            <a href="/sites">Sites</a>
            <a href="/reports">Reports</a>
            <a href="/settings">Settings</a>
        </nav>
    </header>

    <main>
        <div class="panel">
            <h2>Device: $($device.Hostname)</h2>
            <form id="deviceForm">
                <input type="hidden" name="deviceId" value="$($device.DeviceId)">

                <div class="section-header">Read-Only Information</div>

                <div class="field-row">
                    <div class="field-label">Device ID</div>
                    <div class="field-value readonly">$($device.DeviceId)</div>
                </div>
                <div class="field-row">
                    <div class="field-label">Hostname</div>
                    <div class="field-value readonly">$($device.Hostname)</div>
                </div>
                <div class="field-row">
                    <div class="field-label">FQDN</div>
                    <div class="field-value readonly">$(if ($device.FQDN) { $device.FQDN } else { "<span class='not-collected'>Not collected</span>" })</div>
                </div>
                <div class="field-row">
                    <div class="field-label">IP Address</div>
                    <div class="field-value readonly">$(if ($device.IPAddress) { $device.IPAddress } else { "<span class='not-collected'>Not collected</span>" })</div>
                </div>
                <div class="field-row">
                    <div class="field-label">MAC Address</div>
                    <div class="field-value readonly">$(if ($device.MACAddress) { $device.MACAddress } else { "<span class='not-collected'>Not collected</span>" })</div>
                </div>
                <div class="field-row">
                    <div class="field-label">Status</div>
                    <div class="field-value readonly"><span class="badge badge-$(if ($device.Status -eq 'Online') { 'success' } elseif ($device.Status -eq 'Offline') { 'danger' } else { 'warning' })">$($device.Status)</span>$statusDesc</div>
                </div>
                <div class="field-row">
                    <div class="field-label">Last Seen</div>
                    <div class="field-value readonly">$(if ($device.LastSeen) { $device.LastSeen } else { "<span class='not-collected'>Never</span>" })</div>
                </div>

                <div class="section-header">System Information</div>

                <div class="field-row">
                    <div class="field-label">Operating System</div>
                    <div class="field-value readonly">$(if ($device.OSName) { "$($device.OSName) $($device.OSVersion)" } else { "<span class='not-collected'>Not collected</span>" })</div>
                </div>
                <div class="field-row">
                    <div class="field-label">OS Build</div>
                    <div class="field-value readonly">$(if ($device.OSBuild) { $device.OSBuild } else { "<span class='not-collected'>Not collected</span>" })</div>
                </div>
                <div class="field-row">
                    <div class="field-label">Manufacturer</div>
                    <div class="field-value readonly">$(if ($device.Manufacturer) { $device.Manufacturer } else { "<span class='not-collected'>Not collected</span>" })</div>
                </div>
                <div class="field-row">
                    <div class="field-label">Model</div>
                    <div class="field-value readonly">$(if ($device.Model) { $device.Model } else { "<span class='not-collected'>Not collected</span>" })</div>
                </div>
                <div class="field-row">
                    <div class="field-label">Serial Number</div>
                    <div class="field-value readonly">$(if ($device.SerialNumber) { $device.SerialNumber } else { "<span class='not-collected'>Not collected</span>" })</div>
                </div>
                <div class="field-row">
                    <div class="field-label">Agent Version</div>
                    <div class="field-value readonly">$(if ($device.AgentVersion) { $device.AgentVersion } else { "<span class='not-collected'>Not installed</span>" })</div>
                </div>

                <div class="section-header">Editable Fields</div>

                <div class="field-row">
                    <div class="field-label">Site</div>
                    <div class="field-value"><select name="siteId">$siteOptions</select></div>
                </div>
                <div class="field-row">
                    <div class="field-label">Device Type</div>
                    <div class="field-value"><select name="deviceType">$typeOptions</select></div>
                </div>
                <div class="field-row">
                    <div class="field-label">Tags</div>
                    <div class="field-value"><input type="text" name="tags" value="$escTags" placeholder="Comma-separated tags"></div>
                </div>
                <div class="field-row">
                    <div class="field-label">Description</div>
                    <div class="field-value"><input type="text" name="description" value="$escDesc" placeholder="Short description"></div>
                </div>
                <div class="field-row">
                    <div class="field-label">Credential Name</div>
                    <div class="field-value"><input type="text" name="credentialName" value="$escCred" placeholder="Stored credential name for remote access"></div>
                </div>
                <div class="field-row">
                    <div class="field-label">Notes</div>
                    <div class="field-value"><textarea name="notes" placeholder="Additional notes about this device...">$escNotes</textarea></div>
                </div>

                <button type="submit" class="save-btn">Save Changes</button>
                <div id="saveResult" class="save-result"></div>

                <div class="section-header">Timestamps</div>

                <div class="field-row">
                    <div class="field-label">Created At</div>
                    <div class="field-value readonly">$(if ($device.CreatedAt) { $device.CreatedAt } else { "<span class='not-collected'>Unknown</span>" })</div>
                </div>
                <div class="field-row">
                    <div class="field-label">Updated At</div>
                    <div class="field-value readonly">$(if ($device.UpdatedAt) { $device.UpdatedAt } else { "<span class='not-collected'>Unknown</span>" })</div>
                </div>
            </form>
        </div>

        <div class="panel" style="margin-top:20px;">
            <h2>Device Alerts <span id="alertCount" style="font-size:14px;font-weight:normal;color:#666;"></span></h2>
            <div id="device-alerts-list">
"@

    if ($alerts) {
        $alertCount = @($alerts).Count
        $html += "<p style='margin-bottom:10px;color:#666;'>$alertCount active alert$(if ($alertCount -ne 1) { 's' })</p>"
        $html += "<table><thead><tr><th>Severity</th><th>Type</th><th>Title</th><th>Created</th><th>Actions</th></tr></thead><tbody>"
        foreach ($alert in $alerts) {
            $severityClass = if ($alert.Severity) { $alert.Severity.ToLower() } else { "low" }
            $alertType = if ($alert.AlertType) { $alert.AlertType } else { "Unknown" }
            $html += @"
                <tr>
                    <td><span class='badge badge-$severityClass'>$($alert.Severity)</span></td>
                    <td>$alertType</td>
                    <td>$($alert.Title)</td>
                    <td>$($alert.CreatedAt)</td>
                    <td>
                        <button onclick="ackAlert('$($alert.AlertId)')" style="padding:4px 8px;margin:2px;background:#17a2b8;color:white;border:none;border-radius:3px;cursor:pointer;font-size:12px;">Ack</button>
                        <button onclick="resolveAlert('$($alert.AlertId)')" style="padding:4px 8px;margin:2px;background:#28a745;color:white;border:none;border-radius:3px;cursor:pointer;font-size:12px;">Resolve</button>
                    </td>
                </tr>
"@
        }
        $html += "</tbody></table>"
    } else {
        $html += "<p class='success-text' style='color:#28a745;padding:20px;text-align:center;'>&#10003; No active alerts for this device.</p>"
    }

    $html += @"
            </div>
        </div>

        <div class="panel" style="margin-top:20px;">
            <h2>Quick Actions</h2>
            <div class="action-buttons">
                <button class="btn" onclick="executeDeviceAction('$DeviceId', 'HealthCheck')" style="padding:10px 15px;margin:5px;background:#667eea;color:white;border:none;border-radius:5px;cursor:pointer;">Health Check</button>
                <button class="btn" onclick="executeDeviceAction('$DeviceId', 'InventoryCollection')" style="padding:10px 15px;margin:5px;background:#667eea;color:white;border:none;border-radius:5px;cursor:pointer;">Collect Inventory</button>
                <button class="btn" onclick="executeDeviceAction('$DeviceId', 'Reboot')" style="padding:10px 15px;margin:5px;background:#e74c3c;color:white;border:none;border-radius:5px;cursor:pointer;">Reboot</button>
            </div>
            <div id="action-result" style="margin-top:15px;"></div>
        </div>

        <div class="panel" style="margin-top:20px;border:2px solid #dc3545;">
            <h2 style="color:#dc3545;">Danger Zone</h2>
            <p style="color:#666;margin-bottom:15px;">Removing this device will delete all associated data. This action cannot be undone.</p>
            <button class="btn" onclick="forgetDevice('$DeviceId', '$($device.Hostname)')" style="padding:10px 20px;background:#dc3545;color:white;border:none;border-radius:5px;cursor:pointer;">Forget Device</button>
        </div>
    </main>

    <footer>
        <p>&copy; 2025 myTech.Today RMM - Powered by PowerShell</p>
    </footer>

    <script src="/app.js"></script>
    <script>
        document.getElementById('deviceForm').addEventListener('submit', function(e) {
            e.preventDefault();
            const form = e.target;
            const resultDiv = document.getElementById('saveResult');
            resultDiv.className = 'save-result';
            resultDiv.textContent = 'Saving...';
            resultDiv.style.display = 'block';

            const data = {
                deviceId: form.deviceId.value,
                siteId: form.siteId.value,
                deviceType: form.deviceType.value,
                tags: form.tags.value,
                description: form.description.value,
                credentialName: form.credentialName.value,
                notes: form.notes.value
            };

            fetch('/api/devices/update', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data)
            })
            .then(r => r.json())
            .then(result => {
                if (result.success) {
                    resultDiv.className = 'save-result success';
                    resultDiv.textContent = 'Changes saved successfully!';
                    setTimeout(() => { resultDiv.style.display = 'none'; }, 3000);
                } else {
                    resultDiv.className = 'save-result error';
                    resultDiv.textContent = 'Error: ' + result.error;
                }
            })
            .catch(err => {
                resultDiv.className = 'save-result error';
                resultDiv.textContent = 'Error: ' + err.message;
            });
        });

        function forgetDevice(deviceId, hostname) {
            if (!confirm('Are you sure you want to forget device "' + hostname + '"? This action cannot be undone.')) return;
            fetch('/api/devices/delete', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ deviceId: deviceId })
            })
            .then(r => r.json())
            .then(result => {
                if (result.success) {
                    alert('Device removed successfully.');
                    window.location.href = '/devices';
                } else {
                    alert('Error: ' + result.error);
                }
            });
        }
    </script>
</body>
</html>
"@
    return $html
}

#endregion

#region JSON API Functions

function Get-FleetStatusJSON {
    $data = Get-FleetStatusData
    return $data | ConvertTo-Json -Depth 3
}

function Get-DevicesJSON {
    $query = "SELECT DeviceId, Hostname, IPAddress, Status, LastSeen FROM Devices ORDER BY Hostname"
    $devices = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
    return @{ devices = @($devices) } | ConvertTo-Json -Depth 3
}

function Get-DeviceDetailsJSON {
    param([string]$DeviceId)

    $query = "SELECT * FROM Devices WHERE DeviceId = @DeviceId"
    $device = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ DeviceId = $DeviceId }

    if ($device) {
        return $device | ConvertTo-Json -Depth 3
    } else {
        return @{ error = "Device not found" } | ConvertTo-Json
    }
}

function Get-AlertsJSON {
    $data = Get-AlertsData
    return $data | ConvertTo-Json -Depth 3
}

function Get-ActionsJSON {
    $data = Get-RecentActionsData
    return @{ actions = @($data) } | ConvertTo-Json -Depth 3
}

function Get-MetricsJSON {
    $query = @"
SELECT d.Hostname, m.MetricType, m.Value, m.Unit, m.Timestamp
FROM Metrics m
JOIN Devices d ON m.DeviceId = d.DeviceId
WHERE m.Timestamp >= datetime('now', '-1 hour')
ORDER BY m.Timestamp DESC
LIMIT 100
"@

    $metrics = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
    return @{ metrics = @($metrics) } | ConvertTo-Json -Depth 3
}

function Invoke-ActionExecution {
    param([string]$Body)

    try {
        $data = $Body | ConvertFrom-Json
        $deviceId = $data.deviceId
        $actionType = $data.actionType

        if (-not $deviceId -or -not $actionType) {
            Write-RMMLog "Action execution failed: Device ID and Action Type are required" -Level WARNING -Component "Web-Dashboard"
            return @{ success = $false; error = "Device ID and Action Type are required" } | ConvertTo-Json
        }

        $actionId = [guid]::NewGuid().ToString()

        # Insert action with 'Running' status
        $query = @"
INSERT INTO Actions (ActionId, DeviceId, ActionType, Status, Priority, CreatedAt)
VALUES (@ActionId, @DeviceId, @ActionType, 'Running', 5, CURRENT_TIMESTAMP)
"@
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{
            ActionId = $actionId
            DeviceId = $deviceId
            ActionType = $actionType
        }

        Write-Host "[ACTION] Starting: $actionType on $deviceId ($actionId)" -ForegroundColor Yellow

        # Execute the action immediately
        $result = Execute-ActionNow -ActionId $actionId -DeviceId $deviceId -ActionType $actionType

        # Update action status based on result
        $status = if ($result.Success) { 'Completed' } else { 'Failed' }
        $updateQuery = @"
UPDATE Actions
SET Status = @Status,
    Result = @Result,
    CompletedAt = CURRENT_TIMESTAMP
WHERE ActionId = @ActionId
"@
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $updateQuery -SqlParameters @{
            ActionId = $actionId
            Status = $status
            Result = ($result | ConvertTo-Json -Compress -Depth 3)
        }

        $logLevel = if ($result.Success) { 'SUCCESS' } else { 'WARNING' }
        Write-Host "[ACTION] $status`: $actionType on $deviceId" -ForegroundColor $(if ($result.Success) { 'Green' } else { 'Red' })
        Write-RMMLog "Action $status`: $actionType on device $deviceId (ActionId: $actionId)" -Level $logLevel -Component "Web-Dashboard"
        Write-RMMDeviceLog -DeviceId $deviceId -Message "Action $status`: $actionType" -Level INFO

        return @{
            success = $result.Success
            actionId = $actionId
            status = $status
            message = $result.Message
            output = $result.Output
        } | ConvertTo-Json -Depth 3
    }
    catch {
        Write-RMMLog "Action execution failed: $($_.Exception.Message)" -Level ERROR -Component "Web-Dashboard"
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Execute-ActionNow {
    param(
        [string]$ActionId,
        [string]$DeviceId,
        [string]$ActionType
    )

    $result = @{
        Success = $false
        Message = ""
        Output = ""
    }

    try {
        # Get device information
        $device = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT * FROM Devices WHERE DeviceId = @DeviceId" -SqlParameters @{ DeviceId = $DeviceId }

        if (-not $device) {
            $result.Message = "Device not found"
            return $result
        }

        $hostname = $device.Hostname
        $isLocal = ($hostname -eq $env:COMPUTERNAME) -or ($hostname -eq 'localhost')

        switch ($ActionType) {
            'HealthCheck' {
                # Run health monitor for this device
                $scriptPath = Join-Path $PSScriptRoot "..\monitors\Health-Monitor.ps1"
                if (Test-Path $scriptPath) {
                    try {
                        $output = & $scriptPath -Devices $hostname 2>&1 | Out-String
                        $result.Success = $true
                        $result.Message = "Health check completed for $hostname"
                        $result.Output = $output
                    } catch {
                        $result.Message = "Health check failed: $($_.Exception.Message)"
                    }
                } else {
                    $result.Message = "Health monitor script not found"
                }
            }
            'InventoryCollection' {
                # Run inventory collector for this device
                $scriptPath = Join-Path $PSScriptRoot "..\collectors\Inventory-Collector.ps1"
                if (Test-Path $scriptPath) {
                    try {
                        $output = & $scriptPath -Devices $hostname 2>&1 | Out-String
                        $result.Success = $true
                        $result.Message = "Inventory collection completed for $hostname"
                        $result.Output = $output
                    } catch {
                        $result.Message = "Inventory collection failed: $($_.Exception.Message)"
                    }
                } else {
                    $result.Message = "Inventory collector script not found"
                }
            }
            'GetSystemInfo' {
                if ($isLocal) {
                    $sysInfo = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, LastBootUpTime
                    $result.Success = $true
                    $result.Message = "System info retrieved"
                    $result.Output = $sysInfo | ConvertTo-Json
                } else {
                    $sysInfo = Invoke-Command -ComputerName $hostname -ScriptBlock {
                        Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, LastBootUpTime
                    } -ErrorAction Stop
                    $result.Success = $true
                    $result.Message = "System info retrieved from $hostname"
                    $result.Output = $sysInfo | ConvertTo-Json
                }
            }
            'FlushDNS' {
                if ($isLocal) {
                    Clear-DnsClientCache
                    $result.Success = $true
                    $result.Message = "DNS cache flushed"
                } else {
                    Invoke-Command -ComputerName $hostname -ScriptBlock { Clear-DnsClientCache } -ErrorAction Stop
                    $result.Success = $true
                    $result.Message = "DNS cache flushed on $hostname"
                }
            }
            'ClearTemp' {
                $tempPaths = @("$env:TEMP\*", "$env:WINDIR\Temp\*")
                $cleared = 0
                foreach ($path in $tempPaths) {
                    $cleared += (Get-ChildItem $path -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue).Count
                }
                $result.Success = $true
                $result.Message = "Temporary files cleared"
            }
            'Reboot' {
                # Don't actually reboot from web UI - just queue for confirmation
                $result.Success = $false
                $result.Message = "Reboot requires manual confirmation. Use PowerShell: Restart-Computer -ComputerName $hostname"
            }
            default {
                $result.Message = "Action type '$ActionType' is not implemented for immediate execution"
            }
        }
    }
    catch {
        $result.Success = $false
        $result.Message = "Error: $($_.Exception.Message)"
    }

    return $result
}

function Set-AlertAcknowledgedAPI {
    param([string]$Body)

    try {
        $data = $Body | ConvertFrom-Json
        $alertId = $data.alertId

        if (-not $alertId) {
            return @{ success = $false; error = "Alert ID is required" } | ConvertTo-Json
        }

        $query = @"
UPDATE Alerts
SET AcknowledgedAt = CURRENT_TIMESTAMP,
    AcknowledgedBy = @User
WHERE AlertId = @AlertId
"@

        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{
            AlertId = $alertId
            User = "WebUI"
        }

        return @{ success = $true; message = "Alert acknowledged" } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Set-AlertResolvedAPI {
    param([string]$Body)

    try {
        $data = $Body | ConvertFrom-Json
        $alertId = $data.alertId

        if (-not $alertId) {
            return @{ success = $false; error = "Alert ID is required" } | ConvertTo-Json
        }

        $query = @"
UPDATE Alerts
SET ResolvedAt = CURRENT_TIMESTAMP,
    ResolvedBy = @User
WHERE AlertId = @AlertId
"@

        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{
            AlertId = $alertId
            User = "WebUI"
        }

        return @{ success = $true; message = "Alert resolved" } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Add-DeviceAPI {
    param([string]$Body)

    try {
        $data = $Body | ConvertFrom-Json

        if (-not $data.hostname) {
            Write-RMMLog "Add device failed: Hostname is required" -Level WARNING -Component "Web-Dashboard"
            return @{ success = $false; error = "Hostname is required" } | ConvertTo-Json
        }

        # Check if device already exists
        $existingQuery = "SELECT DeviceId FROM Devices WHERE Hostname = @Hostname"
        $existing = Invoke-SqliteQuery -DataSource $DatabasePath -Query $existingQuery -SqlParameters @{ Hostname = $data.hostname }
        if ($existing) {
            Write-RMMLog "Add device failed: Device '$($data.hostname)' already exists" -Level WARNING -Component "Web-Dashboard"
            return @{ success = $false; error = "Device with hostname '$($data.hostname)' already exists" } | ConvertTo-Json
        }

        $deviceId = [guid]::NewGuid().ToString()
        $siteId = if ($data.siteId) { $data.siteId } else { "default" }
        $deviceType = if ($data.deviceType) { $data.deviceType } else { "Workstation" }

        $query = @"
INSERT INTO Devices (DeviceId, Hostname, IPAddress, SiteId, DeviceType, Description, Tags, Status, CreatedAt, UpdatedAt)
VALUES (@DeviceId, @Hostname, @IPAddress, @SiteId, @DeviceType, @Description, @Tags, 'Unknown', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
"@

        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{
            DeviceId    = $deviceId
            Hostname    = $data.hostname
            IPAddress   = $data.ipAddress
            SiteId      = $siteId
            DeviceType  = $deviceType
            Description = $data.description
            Tags        = $data.tags
        }

        Write-RMMLog "Device added: $($data.hostname) ($deviceId) - Type: $deviceType, Site: $siteId" -Level SUCCESS -Component "Web-Dashboard"
        Write-RMMDeviceLog -DeviceId $deviceId -Message "Device registered via Web Dashboard" -Level SUCCESS

        return @{ success = $true; deviceId = $deviceId; message = "Device added successfully" } | ConvertTo-Json
    }
    catch {
        Write-RMMLog "Add device failed: $($_.Exception.Message)" -Level ERROR -Component "Web-Dashboard"
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Export-DevicesAPI {
    param([string]$Format = "json")

    try {
        $query = "SELECT DeviceId, Hostname, FQDN, IPAddress, MACAddress, Status, SiteId, DeviceType, OSName, OSVersion, Description, Tags, LastSeen, CreatedAt FROM Devices ORDER BY Hostname"
        $devices = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query

        switch ($Format.ToLower()) {
            "csv" {
                if (-not $devices -or $devices.Count -eq 0) {
                    return "DeviceId,Hostname,FQDN,IPAddress,MACAddress,Status,SiteId,DeviceType,OSName,OSVersion,Description,Tags,LastSeen,CreatedAt"
                }
                $csv = $devices | ConvertTo-Csv -NoTypeInformation
                return ($csv -join "`n")
            }
            default {
                if (-not $devices -or $devices.Count -eq 0) {
                    return "[]"
                }
                return ($devices | ConvertTo-Json -Depth 5)
            }
        }
    }
    catch {
        return @{ error = $_.Exception.Message } | ConvertTo-Json
    }
}

# In-memory pairing codes storage
$script:PairingCodes = @{}

function Add-PairingCodeAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        $code = $data.code
        $expiresAt = $data.expiresAt
        $script:PairingCodes[$code] = @{ ExpiresAt = $expiresAt; CreatedAt = [DateTime]::Now; Used = $false }
        Write-Host "[PAIRING] Code generated: $code (expires in 10 minutes)" -ForegroundColor Green
        return @{ success = $true; code = $code } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Update-DeviceAPI {
    <#
    .SYNOPSIS
        Updates editable fields of a device
    #>
    param([string]$Body)

    try {
        $data = $Body | ConvertFrom-Json
        $deviceId = $data.deviceId

        if (-not $deviceId) {
            return @{ success = $false; error = "Device ID is required" } | ConvertTo-Json
        }

        # Check if device exists
        $existingQuery = "SELECT DeviceId FROM Devices WHERE DeviceId = @DeviceId"
        $existing = Invoke-SqliteQuery -DataSource $DatabasePath -Query $existingQuery -SqlParameters @{ DeviceId = $deviceId }
        if (-not $existing) {
            return @{ success = $false; error = "Device not found" } | ConvertTo-Json
        }

        # Build update query for editable fields only
        $updates = @()
        $params = @{ DeviceId = $deviceId }

        # Editable fields: SiteId, DeviceType, Tags, Description, Notes, CredentialName
        if ($null -ne $data.siteId) {
            $updates += "SiteId = @SiteId"
            $params.SiteId = $data.siteId
        }
        if ($null -ne $data.deviceType) {
            $updates += "DeviceType = @DeviceType"
            $params.DeviceType = $data.deviceType
        }
        if ($null -ne $data.tags) {
            $updates += "Tags = @Tags"
            $params.Tags = $data.tags
        }
        if ($null -ne $data.description) {
            $updates += "Description = @Description"
            $params.Description = $data.description
        }
        if ($null -ne $data.notes) {
            $updates += "Notes = @Notes"
            $params.Notes = $data.notes
        }
        if ($null -ne $data.credentialName) {
            $updates += "CredentialName = @CredentialName"
            $params.CredentialName = $data.credentialName
        }

        if ($updates.Count -eq 0) {
            return @{ success = $false; error = "No editable fields provided" } | ConvertTo-Json
        }

        $updates += "UpdatedAt = CURRENT_TIMESTAMP"
        $query = "UPDATE Devices SET $($updates -join ', ') WHERE DeviceId = @DeviceId"
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params

        Write-RMMLog "Device updated: $deviceId - fields: $($updates -join ', ')" -Level SUCCESS -Component "Web-Dashboard"
        Write-RMMDeviceLog -DeviceId $deviceId -Message "Device information updated via Web Dashboard" -Level INFO

        return @{ success = $true; message = "Device updated successfully" } | ConvertTo-Json
    }
    catch {
        Write-RMMLog "Update device failed: $($_.Exception.Message)" -Level ERROR -Component "Web-Dashboard"
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Register-DeviceWithPairingCodeAPI {
    <#
    .SYNOPSIS
        Registers a device using a pairing code from the client agent
    #>
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        $code = $data.pairingCode

        if (-not $code) {
            return @{ success = $false; error = "Pairing code is required" } | ConvertTo-Json
        }

        $code = $code.ToUpper()

        # Check if code exists and is valid
        if (-not $script:PairingCodes.ContainsKey($code)) {
            Write-Host "[PAIRING] Invalid code attempted: $code" -ForegroundColor Yellow
            Write-RMMLog "Pairing failed: Invalid code '$code' attempted" -Level WARNING -Component "Web-Dashboard"
            return @{ success = $false; error = "Invalid pairing code" } | ConvertTo-Json
        }

        $codeData = $script:PairingCodes[$code]

        # Check if code has expired
        $currentTime = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        if ($currentTime -gt $codeData.ExpiresAt) {
            $script:PairingCodes.Remove($code)
            Write-Host "[PAIRING] Expired code attempted: $code" -ForegroundColor Yellow
            Write-RMMLog "Pairing failed: Expired code '$code' attempted" -Level WARNING -Component "Web-Dashboard"
            return @{ success = $false; error = "Pairing code has expired" } | ConvertTo-Json
        }

        # Check if code has already been used
        if ($codeData.Used) {
            Write-RMMLog "Pairing failed: Code '$code' already used" -Level WARNING -Component "Web-Dashboard"
            return @{ success = $false; error = "Pairing code has already been used" } | ConvertTo-Json
        }

        # Validate required device info
        if (-not $data.hostname) {
            return @{ success = $false; error = "Hostname is required" } | ConvertTo-Json
        }

        # Check if device already exists
        $existingQuery = "SELECT DeviceId FROM Devices WHERE Hostname = @Hostname"
        $existing = Invoke-SqliteQuery -DataSource $DatabasePath -Query $existingQuery -SqlParameters @{ Hostname = $data.hostname }
        if ($existing) {
            Write-RMMLog "Pairing failed: Device '$($data.hostname)' already exists" -Level WARNING -Component "Web-Dashboard"
            return @{ success = $false; error = "Device with hostname '$($data.hostname)' already registered" } | ConvertTo-Json
        }

        # Create the device
        $deviceId = [guid]::NewGuid().ToString()
        $deviceType = if ($data.deviceType) { $data.deviceType } else { "Workstation" }

        $query = @"
INSERT INTO Devices (DeviceId, Hostname, IPAddress, SiteId, DeviceType, OSName, OSVersion, Manufacturer, Model, SerialNumber, Status, LastSeen, CreatedAt, UpdatedAt)
VALUES (@DeviceId, @Hostname, @IPAddress, 'default', @DeviceType, @OSName, @OSVersion, @Manufacturer, @Model, @SerialNumber, 'Online', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
"@

        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{
            DeviceId     = $deviceId
            Hostname     = $data.hostname.ToUpper()
            IPAddress    = $data.ipAddress
            DeviceType   = $deviceType
            OSName       = $data.osName
            OSVersion    = $data.osVersion
            Manufacturer = $data.manufacturer
            Model        = $data.model
            SerialNumber = $data.serialNumber
        }

        # Mark code as used
        $script:PairingCodes[$code].Used = $true

        Write-Host "[PAIRING] Device registered: $($data.hostname) via code $code" -ForegroundColor Green
        Write-RMMLog "Device paired successfully: $($data.hostname) ($deviceId) via code $code - Type: $deviceType, OS: $($data.osName)" -Level SUCCESS -Component "Web-Dashboard"
        Write-RMMDeviceLog -DeviceId $deviceId -Message "Device registered via pairing code" -Level SUCCESS

        return @{
            success = $true
            deviceId = $deviceId
            message = "Device registered successfully"
        } | ConvertTo-Json
    }
    catch {
        Write-Host "[PAIRING] Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-RMMLog "Pairing failed: $($_.Exception.Message)" -Level ERROR -Component "Web-Dashboard"
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Get-PairingStatusAPI {
    <#
    .SYNOPSIS
        Returns the status of active pairing codes
    #>
    try {
        $currentTime = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        $activeCodes = @()

        foreach ($code in $script:PairingCodes.Keys) {
            $codeData = $script:PairingCodes[$code]
            if ($currentTime -lt $codeData.ExpiresAt -and -not $codeData.Used) {
                $remainingMs = $codeData.ExpiresAt - $currentTime
                $activeCodes += @{
                    code = $code
                    remainingSeconds = [Math]::Floor($remainingMs / 1000)
                }
            }
        }

        return @{ success = $true; activeCodes = $activeCodes } | ConvertTo-Json -Depth 3
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Resolve-HostnameAPI {
    param([string]$Hostname)
    try {
        $result = [System.Net.Dns]::GetHostEntry($Hostname)
        $ipAddress = ($result.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1).IPAddressToString

        # Try to detect device type
        $deviceType = "Workstation"
        if ($Hostname -match "^(SRV|SERVER|DC|SQL|WEB|APP|DB)") { $deviceType = "Server" }
        elseif ($Hostname -match "(LAPTOP|NB|NOTEBOOK)") { $deviceType = "Laptop" }
        elseif ($Hostname -match "(VM|VIRTUAL)") { $deviceType = "Virtual" }

        return @{ success = $true; hostname = $result.HostName; ipAddress = $ipAddress; deviceType = $deviceType } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = "Could not resolve hostname" } | ConvertTo-Json
    }
}

function Test-IPPingAPI {
    param([string]$IP)
    try {
        $ping = Test-Connection -ComputerName $IP -Count 1 -Quiet -TimeoutSeconds 2
        return @{ success = $true; reachable = $ping; ip = $IP } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; reachable = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Add-SiteAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        $name = $data.name
        if (-not $name) {
            return @{ success = $false; error = "Site name is required" } | ConvertTo-Json
        }

        $siteId = $name.ToLower() -replace '[^a-z0-9]', '-'

        # Check if site exists
        $existing = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT SiteId FROM Sites WHERE SiteId = @SiteId" -SqlParameters @{ SiteId = $siteId }
        if ($existing) {
            return @{ success = $false; error = "Site already exists" } | ConvertTo-Json
        }

        # Build location from address fields
        $locationParts = @()
        if ($data.city) { $locationParts += $data.city }
        if ($data.state) { $locationParts += $data.state }
        if ($data.country) { $locationParts += $data.country }
        $location = $locationParts -join ', '

        $query = @"
INSERT INTO Sites (SiteId, Name, Location, ContactName, ContactEmail, MainPhone, CellPhone,
    StreetNumber, StreetName, Unit, Building, City, State, Zip, Country, Timezone, Notes, CreatedAt)
VALUES (@SiteId, @Name, @Location, @ContactName, @ContactEmail, @MainPhone, @CellPhone,
    @StreetNumber, @StreetName, @Unit, @Building, @City, @State, @Zip, @Country, @Timezone, @Notes, CURRENT_TIMESTAMP)
"@
        $params = @{
            SiteId = $siteId; Name = $name; Location = $location
            ContactName = $data.contactName; ContactEmail = $data.contactEmail
            MainPhone = $data.mainPhone; CellPhone = $data.cellPhone
            StreetNumber = $data.streetNumber; StreetName = $data.streetName
            Unit = $data.unit; Building = $data.building
            City = $data.city; State = $data.state; Zip = $data.zip; Country = $data.country
            Timezone = $data.timezone; Notes = $data.notes
        }
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params

        return @{ success = $true; siteId = $siteId; name = $name } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Update-SiteAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        $siteId = $data.siteId
        if (-not $siteId) {
            return @{ success = $false; error = "Site ID is required" } | ConvertTo-Json
        }

        # Build dynamic update
        $updates = @()
        $params = @{ SiteId = $siteId }
        $fields = @('name','contactName','contactEmail','mainPhone','cellPhone','streetNumber','streetName','unit','building','city','state','zip','country','timezone','notes')
        $dbFields = @('Name','ContactName','ContactEmail','MainPhone','CellPhone','StreetNumber','StreetName','Unit','Building','City','State','Zip','Country','Timezone','Notes')

        for ($i = 0; $i -lt $fields.Count; $i++) {
            $jsField = $fields[$i]
            $dbField = $dbFields[$i]
            if ($data.PSObject.Properties.Name -contains $jsField) {
                $updates += "$dbField = @$dbField"
                $params[$dbField] = $data.$jsField
            }
        }

        if ($updates.Count -eq 0) {
            return @{ success = $false; error = "No fields to update" } | ConvertTo-Json
        }

        # Update Location if address changed
        if ($data.city -or $data.state -or $data.country) {
            $locationParts = @($data.city, $data.state, $data.country) | Where-Object { $_ }
            $params['Location'] = $locationParts -join ', '
            $updates += "Location = @Location"
        }

        $query = "UPDATE Sites SET " + ($updates -join ', ') + " WHERE SiteId = @SiteId"
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params

        return @{ success = $true; message = "Site updated" } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Remove-SiteAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        $siteId = $data.siteId
        $action = $data.action  # 'delete', 'cascade', or 'reassign'
        $targetSiteId = $data.targetSiteId  # For reassign action

        if (-not $siteId) {
            return @{ success = $false; error = "Site ID is required" } | ConvertTo-Json
        }

        # Check for devices
        $deviceCount = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Devices WHERE SiteId = @SiteId" -SqlParameters @{ SiteId = $siteId }).Count

        if ($deviceCount -gt 0) {
            if ($action -eq 'cascade') {
                # Delete all devices assigned to this site
                Invoke-SqliteQuery -DataSource $DatabasePath -Query "DELETE FROM Metrics WHERE DeviceId IN (SELECT DeviceId FROM Devices WHERE SiteId = @SiteId)" -SqlParameters @{ SiteId = $siteId }
                Invoke-SqliteQuery -DataSource $DatabasePath -Query "DELETE FROM Alerts WHERE DeviceId IN (SELECT DeviceId FROM Devices WHERE SiteId = @SiteId)" -SqlParameters @{ SiteId = $siteId }
                Invoke-SqliteQuery -DataSource $DatabasePath -Query "DELETE FROM Actions WHERE DeviceId IN (SELECT DeviceId FROM Devices WHERE SiteId = @SiteId)" -SqlParameters @{ SiteId = $siteId }
                Invoke-SqliteQuery -DataSource $DatabasePath -Query "DELETE FROM Inventory WHERE DeviceId IN (SELECT DeviceId FROM Devices WHERE SiteId = @SiteId)" -SqlParameters @{ SiteId = $siteId }
                Invoke-SqliteQuery -DataSource $DatabasePath -Query "DELETE FROM Devices WHERE SiteId = @SiteId" -SqlParameters @{ SiteId = $siteId }
            }
            elseif ($action -eq 'reassign' -and $targetSiteId) {
                # Move devices to target site
                Invoke-SqliteQuery -DataSource $DatabasePath -Query "UPDATE Devices SET SiteId = @TargetSiteId WHERE SiteId = @SiteId" -SqlParameters @{ SiteId = $siteId; TargetSiteId = $targetSiteId }
            }
            else {
                # No action specified and devices exist - block deletion
                return @{ success = $false; error = "Cannot delete site: $deviceCount devices are assigned to it" } | ConvertTo-Json
            }
        }

        # Delete site URLs and site
        Invoke-SqliteQuery -DataSource $DatabasePath -Query "DELETE FROM SiteURLs WHERE SiteId = @SiteId" -SqlParameters @{ SiteId = $siteId }
        Invoke-SqliteQuery -DataSource $DatabasePath -Query "DELETE FROM Sites WHERE SiteId = @SiteId" -SqlParameters @{ SiteId = $siteId }

        $message = if ($action -eq 'cascade') { "Site and $deviceCount device(s) deleted" }
                   elseif ($action -eq 'reassign') { "Site deleted, $deviceCount device(s) reassigned" }
                   else { "Site deleted" }

        return @{ success = $true; message = $message } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Add-SiteURLAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        if (-not $data.siteId -or -not $data.url) {
            return @{ success = $false; error = "Site ID and URL are required" } | ConvertTo-Json
        }

        $query = "INSERT INTO SiteURLs (SiteId, URL, Label, CreatedAt) VALUES (@SiteId, @URL, @Label, CURRENT_TIMESTAMP)"
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ SiteId = $data.siteId; URL = $data.url; Label = $data.label }

        return @{ success = $true; message = "URL added" } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Remove-SiteURLAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        if (-not $data.urlId) {
            return @{ success = $false; error = "URL ID is required" } | ConvertTo-Json
        }

        Invoke-SqliteQuery -DataSource $DatabasePath -Query "DELETE FROM SiteURLs WHERE URLId = @URLId" -SqlParameters @{ URLId = $data.urlId }

        return @{ success = $true; message = "URL removed" } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Remove-DeviceAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        $deviceId = $data.deviceId
        if (-not $deviceId) {
            return @{ success = $false; error = "Device ID is required" } | ConvertTo-Json
        }

        $query = "DELETE FROM Devices WHERE DeviceId = @DeviceId"
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ DeviceId = $deviceId }

        return @{ success = $true; message = "Device removed" } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Get-SitesJSON {
    try {
        $query = "SELECT * FROM Sites ORDER BY Name"
        $sites = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query

        # Get URLs for each site
        foreach ($site in $sites) {
            $urlQuery = "SELECT URLId, URL, Label FROM SiteURLs WHERE SiteId = @SiteId ORDER BY Label"
            $urls = Invoke-SqliteQuery -DataSource $DatabasePath -Query $urlQuery -SqlParameters @{ SiteId = $site.SiteId }
            $site | Add-Member -NotePropertyName 'URLs' -NotePropertyValue @($urls) -Force
        }

        return @{ sites = @($sites) } | ConvertTo-Json -Depth 4
    }
    catch {
        return @{ error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Get-SiteJSON {
    param([string]$SiteId)
    try {
        $query = "SELECT * FROM Sites WHERE SiteId = @SiteId"
        $site = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ SiteId = $SiteId }

        if (-not $site) {
            return @{ error = "Site not found" } | ConvertTo-Json
        }

        # Get URLs
        $urlQuery = "SELECT URLId, URL, Label FROM SiteURLs WHERE SiteId = @SiteId ORDER BY Label"
        $urls = Invoke-SqliteQuery -DataSource $DatabasePath -Query $urlQuery -SqlParameters @{ SiteId = $SiteId }
        $site | Add-Member -NotePropertyName 'URLs' -NotePropertyValue @($urls) -Force

        return @{ site = $site } | ConvertTo-Json -Depth 4
    }
    catch {
        return @{ error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Get-SiteDevicesJSON {
    param([string]$SiteId)
    try {
        $query = "SELECT DeviceId, Hostname FROM Devices WHERE SiteId = @SiteId"
        $devices = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ SiteId = $SiteId })

        return @{
            deviceCount = $devices.Count
            devices = $devices
        } | ConvertTo-Json -Depth 4
    }
    catch {
        return @{ error = $_.Exception.Message; deviceCount = 0; devices = @() } | ConvertTo-Json
    }
}

#endregion

#region Main Execution

Write-Host "[INFO] Starting myTech.Today RMM Web Dashboard..." -ForegroundColor Cyan
Write-Host "[INFO] Port: $Port" -ForegroundColor Gray
Write-Host "[INFO] Web Root: $WebRoot" -ForegroundColor Gray

# Create HTTP listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Prefixes.Add("http://127.0.0.1:$Port/")

try {
    $listener.Start()
    Write-Host "[SUCCESS] Web dashboard started successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Access the dashboard at:" -ForegroundColor Cyan
    Write-Host "  http://localhost:$Port" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Press Ctrl+C to stop the server..." -ForegroundColor Yellow
    Write-Host ""

    if ($OpenBrowser) {
        Start-Process "http://localhost:$Port"
    }

    # Main request loop
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $url = $request.Url.LocalPath
        $method = $request.HttpMethod

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $method $url" -ForegroundColor Gray

        # Route handling
        $responseContent = ""
        $contentType = "text/html; charset=utf-8"

        try {
            switch -Regex ($url) {
                "^/$" {
                    # Main dashboard
                    $responseContent = Get-DashboardHTML
                }
                "^/api/fleet$" {
                    # Fleet status API
                    $contentType = "application/json"
                    $responseContent = Get-FleetStatusJSON
                }
                "^/api/devices$" {
                    # Devices list API
                    $contentType = "application/json"
                    $responseContent = Get-DevicesJSON
                }
                "^/api/devices/(\w+)$" {
                    # Individual device API
                    $contentType = "application/json"
                    $deviceId = $matches[1]
                    $responseContent = Get-DeviceDetailsJSON -DeviceId $deviceId
                }
                "^/api/alerts$" {
                    # Alerts API
                    $contentType = "application/json"
                    $responseContent = Get-AlertsJSON
                }
                "^/api/actions$" {
                    # Recent actions API
                    $contentType = "application/json"
                    $responseContent = Get-ActionsJSON
                }
                "^/devices$" {
                    # Devices page
                    $responseContent = Get-DevicesPageHTML
                }
                "^/alerts$" {
                    # Alerts page
                    $responseContent = Get-AlertsPageHTML
                }
                "^/reports$" {
                    # Reports page
                    $responseContent = Get-ReportsPageHTML
                }
                "^/actions$" {
                    # Actions page
                    $responseContent = Get-ActionsPageHTML
                }
                "^/settings$" {
                    # Settings page
                    $responseContent = Get-SettingsPageHTML
                }
                "^/sites$" {
                    # Sites page
                    $responseContent = Get-SitesPageHTML
                }
                "^/devices/([a-zA-Z0-9\-]+)$" {
                    # Individual device page
                    $deviceId = $matches[1]
                    $responseContent = Get-DeviceDetailPageHTML -DeviceId $deviceId
                }
                "^/api/actions/execute$" {
                    # Execute action API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Invoke-ActionExecution -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/actions/clear$" {
                    # Clear actions history API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $result = Clear-ActionsHistory
                        $responseContent = $result | ConvertTo-Json
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/alerts/acknowledge$" {
                    # Acknowledge alert API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Set-AlertAcknowledgedAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/alerts/resolve$" {
                    # Resolve alert API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Set-AlertResolvedAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/devices/add$" {
                    # Add device API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Add-DeviceAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/devices/update$" {
                    # Update device API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Update-DeviceAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/devices/export" {
                    # Export devices API
                    $contentType = "application/json"
                    $format = "json"
                    if ($url -match "format=(\w+)") { $format = $matches[1] }
                    $responseContent = Export-DevicesAPI -Format $format
                    if ($format -eq "csv") { $contentType = "text/csv" }
                }
                "^/api/devices/delete$" {
                    # Delete device API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Remove-DeviceAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/pairing/create$" {
                    # Create pairing code API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Add-PairingCodeAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/network/resolve" {
                    # Resolve hostname API
                    $contentType = "application/json"
                    $hostname = ""
                    if ($url -match "hostname=([^&]+)") { $hostname = [System.Web.HttpUtility]::UrlDecode($matches[1]) }
                    $responseContent = Resolve-HostnameAPI -Hostname $hostname
                }
                "^/api/network/ping" {
                    # Ping IP API
                    $contentType = "application/json"
                    $ip = ""
                    if ($url -match "ip=([^&]+)") { $ip = [System.Web.HttpUtility]::UrlDecode($matches[1]) }
                    $responseContent = Test-IPPingAPI -IP $ip
                }
                "^/api/sites$" {
                    # Sites list API
                    $contentType = "application/json"
                    $responseContent = Get-SitesJSON
                }
                "^/api/sites/add$" {
                    # Add site API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Add-SiteAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/sites/update$" {
                    # Update site API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Update-SiteAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/sites/delete$" {
                    # Delete site API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Remove-SiteAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/sites/([a-zA-Z0-9\-]+)/devices$" {
                    # Get devices for a site API
                    $contentType = "application/json"
                    $siteId = $matches[1]
                    $responseContent = Get-SiteDevicesJSON -SiteId $siteId
                }
                "^/api/sites/(?!add$|update$|delete$|urls$)([a-zA-Z0-9\-]+)$" {
                    # Get single site API (excludes reserved words: add, update, delete, urls)
                    $contentType = "application/json"
                    $siteId = $matches[1]
                    $responseContent = Get-SiteJSON -SiteId $siteId
                }
                "^/api/sites/urls/add$" {
                    # Add site URL API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Add-SiteURLAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/sites/urls/delete$" {
                    # Remove site URL API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Remove-SiteURLAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/pairing/register$" {
                    # Register device with pairing code API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Register-DeviceWithPairingCodeAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/pairing/status$" {
                    # Get pairing codes status API
                    $contentType = "application/json"
                    $responseContent = Get-PairingStatusAPI
                }
                "^/api/metrics$" {
                    # Metrics API
                    $contentType = "application/json"
                    $responseContent = Get-MetricsJSON
                }
                "^/styles\.css$" {
                    # CSS file
                    $contentType = "text/css"
                    $cssPath = Join-Path $WebRoot "styles.css"
                    if (Test-Path $cssPath) {
                        $responseContent = Get-Content $cssPath -Raw
                    } else {
                        $responseContent = Get-DefaultCSS
                    }
                }
                "^/app\.js$" {
                    # JavaScript file
                    $contentType = "application/javascript"
                    $jsPath = Join-Path $WebRoot "app.js"
                    if (Test-Path $jsPath) {
                        $responseContent = Get-Content $jsPath -Raw
                    } else {
                        $responseContent = Get-DefaultJS
                    }
                }
                default {
                    # 404 Not Found
                    $response.StatusCode = 404
                    $responseContent = "<html><body><h1>404 - Not Found</h1><p>$url</p></body></html>"
                }
            }
        }
        catch {
            # 500 Internal Server Error
            $response.StatusCode = 500
            $responseContent = "<html><body><h1>500 - Internal Server Error</h1><p>$($_.Exception.Message)</p></body></html>"
            Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
            Write-RMMLog "HTTP 500 Error on $url - $($_.Exception.Message)" -Level ERROR -Component "Web-Dashboard"
        }

        # Send response
        $response.ContentType = $contentType
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseContent)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.OutputStream.Close()
    }
}
catch {
    Write-Host "[ERROR] Failed to start web server: $_" -ForegroundColor Red
    Write-Host "[INFO] Make sure port $Port is not in use." -ForegroundColor Yellow
    Write-RMMLog "Failed to start web server on port $Port - $_" -Level ERROR -Component "Web-Dashboard"
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
    Write-Host ""
    Write-Host "[INFO] Web dashboard stopped." -ForegroundColor Cyan
    Write-RMMLog "Web Dashboard stopped" -Level INFO -Component "Web-Dashboard"
}

#endregion
