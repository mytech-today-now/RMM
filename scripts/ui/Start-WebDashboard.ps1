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
    # Devices are considered "Online" if they have any active status (Healthy, Warning, Critical, Online)
    # Devices are "Offline" only if Status = 'Offline' or 'Unknown'
    $query = @"
SELECT
    COUNT(*) as Total,
    SUM(CASE WHEN Status IN ('Online', 'Healthy', 'Warning', 'Critical') THEN 1 ELSE 0 END) as Online,
    SUM(CASE WHEN Status IN ('Offline', 'Unknown') OR Status IS NULL THEN 1 ELSE 0 END) as Offline
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
    display: flex;
    justify-content: space-between;
    align-items: center;
    flex-wrap: wrap;
    position: relative;
}

.header-left {
    display: flex;
    flex-direction: column;
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

.header-right {
    display: flex;
    align-items: center;
    gap: 10px;
}

main {
    padding: 2rem;
    max-width: 1400px;
    margin: 0 auto;
    position: relative;
}

.readme-btn {
    background: transparent;
    border: 1px solid #667eea;
    color: #667eea;
    padding: 3px 6px;
    border-radius: 3px;
    cursor: pointer;
    font-size: 9px;
    display: flex;
    align-items: center;
    gap: 3px;
    transition: all 0.3s;
    position: absolute;
    top: 15px;
    right: 20px;
}

.readme-btn:hover {
    background: #667eea;
    color: white;
}

.readme-btn svg {
    width: 10px;
    height: 10px;
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

// Open Readme documentation in new tab - fetch and render HTML
function openReadme() {
    fetch('https://raw.githubusercontent.com/mytech-today-now/RMM/refs/heads/main/readme.html')
        .then(response => {
            if (!response.ok) throw new Error('Failed to fetch readme');
            return response.text();
        })
        .then(html => {
            const newTab = window.open('', '_blank');
            newTab.document.write(html);
            newTab.document.close();
        })
        .catch(err => {
            alert('Error loading readme: ' + err.message);
        });
}

function loadDevices() {
    fetch('/api/devices')
        .then(response => response.json())
        .then(data => {
            const container = document.getElementById('devices-list');
            if (container) {
                let html = '<table><thead><tr><th>Hostname</th><th>IP Address</th><th>Status</th><th>Last Seen</th></tr></thead><tbody>';
                data.devices.forEach(device => {
                    const statusClass = ['Online', 'Healthy', 'Warning', 'Critical'].includes(device.Status) ? (device.Status === 'Critical' ? 'danger' : (device.Status === 'Warning' ? 'warning' : 'success')) : 'secondary';
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
        <div class="header-left">
            <h1>myTech.Today RMM Dashboard</h1>
            <nav>
                <a href="/" class="active">Dashboard</a>
                <a href="/sites-and-devices">Sites &amp; Devices</a>
                <a href="/alerts">Alerts</a>
                <a href="/actions">Actions</a>
                <a href="/reports">Reports</a>
                <a href="/settings">Settings</a>
            </nav>
        </div>
        <button class="readme-btn" onclick="openReadme()" title="View Documentation">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
            Readme
        </button>
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
        <div class="header-left">
            <h1>myTech.Today RMM Dashboard</h1>
            <nav>
                <a href="/">Dashboard</a>
                <a href="/sites-and-devices" class="active">Sites &amp; Devices</a>
                <a href="/alerts">Alerts</a>
                <a href="/actions">Actions</a>
                <a href="/reports">Reports</a>
                <a href="/settings">Settings</a>
            </nav>
        </div>
        <button class="readme-btn" onclick="openReadme()" title="View Documentation">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
            Readme
        </button>
    </header>

    <main>
        <div class="panel">
            <h2>Device Management</h2>
            <div class="device-actions">
                <button onclick="openAddDeviceModal()">+ Add Device</button>
                <button class="secondary" onclick="exportDevices()">Export JSON</button>
                <label class="secondary" style="padding:10px 20px;background:#6c757d;color:white;border:none;border-radius:5px;cursor:pointer;display:inline-block;">
                    Import JSON
                    <input type="file" id="importDevicesFile" accept=".json" style="display:none;" onchange="importDevices(this)">
                </label>
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

        // Export/Import Functions
        async function exportDevices() {
            try {
                const response = await fetch('/api/devices/export');
                const data = await response.json();
                const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = 'devices-export-' + new Date().toISOString().split('T')[0] + '.json';
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);
            } catch (e) {
                alert('Error exporting devices: ' + e.message);
            }
        }

        async function importDevices(input) {
            if (!input.files || !input.files[0]) return;
            const file = input.files[0];
            const reader = new FileReader();
            reader.onload = async function(e) {
                try {
                    const content = e.target.result;
                    const result = await (await fetch('/api/devices/import', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: content
                    })).json();

                    if (result.success) {
                        let msg = 'Import complete!\n';
                        msg += 'Imported: ' + result.imported + '\n';
                        msg += 'Skipped (already exist): ' + result.skipped;
                        if (result.errors && result.errors.length > 0) {
                            msg += '\n\nErrors:\n' + result.errors.join('\n');
                        }
                        alert(msg);
                        loadDevices();
                    } else {
                        alert('Import failed: ' + result.error);
                    }
                } catch (err) {
                    alert('Error importing devices: ' + err.message);
                }
            };
            reader.readAsText(file);
            input.value = ''; // Reset file input
        }
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
        <div class="header-left">
            <h1>myTech.Today RMM Dashboard</h1>
            <nav>
                <a href="/">Dashboard</a>
                <a href="/sites-and-devices">Sites &amp; Devices</a>
                <a href="/alerts" class="active">Alerts</a>
                <a href="/actions">Actions</a>
                <a href="/reports">Reports</a>
                <a href="/settings">Settings</a>
            </nav>
        </div>
        <button class="readme-btn" onclick="openReadme()" title="View Documentation">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
            Readme
        </button>
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
        $statusIcon = if ($device.Status -in @('Online', 'Healthy')) { '[OK]' } elseif ($device.Status -eq 'Offline') { '[OFF]' } elseif ($device.Status -eq 'Critical') { '[!!]' } else { '[!]' }
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
        <div class="header-left">
            <h1>myTech.Today RMM Dashboard</h1>
            <nav>
                <a href="/">Dashboard</a>
                <a href="/sites-and-devices">Sites &amp; Devices</a>
                <a href="/alerts">Alerts</a>
                <a href="/actions" class="active">Actions</a>
                <a href="/reports">Reports</a>
                <a href="/settings">Settings</a>
            </nav>
        </div>
        <button class="readme-btn" onclick="openReadme()" title="View Documentation">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
            Readme
        </button>
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
    <!-- jsPDF for PDF generation -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf-autotable/3.8.1/jspdf.plugin.autotable.min.js"></script>
    <!-- SheetJS for Excel generation -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"></script>
</head>
<body>
    <header>
        <div class="header-left">
            <h1>myTech.Today RMM Dashboard</h1>
            <nav>
                <a href="/">Dashboard</a>
                <a href="/sites-and-devices">Sites &amp; Devices</a>
                <a href="/alerts">Alerts</a>
                <a href="/actions">Actions</a>
                <a href="/reports" class="active">Reports</a>
                <a href="/settings">Settings</a>
            </nav>
        </div>
        <button class="readme-btn" onclick="openReadme()" title="View Documentation">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
            Readme
        </button>
    </header>

    <main>
        <div class="panel">
            <h2>📊 Reports</h2>
            <style>
                .reports-container { display: grid; grid-template-columns: 350px 1fr; gap: 20px; min-height: 600px; }
                .report-selector { background: #1e293b; border-radius: 8px; padding: 20px; }
                .report-preview { background: #1e293b; border-radius: 8px; padding: 20px; overflow: auto; }
                .report-card { background: #334155; border-radius: 6px; padding: 15px; margin-bottom: 10px; cursor: pointer; transition: all 0.2s; border: 2px solid transparent; }
                .report-card:hover { background: #475569; }
                .report-card.selected { border-color: #3b82f6; background: #1e3a5f; }
                .report-card h4 { margin: 0 0 5px 0; color: #f1f5f9; display: flex; align-items: center; gap: 8px; }
                .report-card p { margin: 0; color: #94a3b8; font-size: 13px; }
                .report-icon { font-size: 20px; }
                .date-filters { margin-top: 20px; padding-top: 15px; border-top: 1px solid #475569; }
                .date-filters label { display: block; color: #94a3b8; font-size: 13px; margin-bottom: 5px; }
                .date-filters input { width: 100%; padding: 8px; border: 1px solid #475569; border-radius: 4px; background: #0f172a; color: #f1f5f9; margin-bottom: 10px; box-sizing: border-box; }
                .generate-btn { width: 100%; padding: 12px; background: #3b82f6; color: white; border: none; border-radius: 6px; font-size: 15px; cursor: pointer; margin-top: 10px; }
                .generate-btn:hover { background: #2563eb; }
                .generate-btn:disabled { background: #475569; cursor: not-allowed; }
                .download-btns { display: flex; gap: 8px; margin-top: 10px; }
                .download-btn { flex: 1; padding: 10px; border: none; border-radius: 4px; cursor: pointer; font-size: 13px; display: flex; align-items: center; justify-content: center; gap: 5px; }
                .download-btn.pdf { background: #dc2626; color: white; }
                .download-btn.excel { background: #16a34a; color: white; }
                .download-btn.csv { background: #0891b2; color: white; }
                .download-btn:hover { opacity: 0.9; }
                .download-btn:disabled { background: #475569 !important; cursor: not-allowed; opacity: 0.6; }
                .preview-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; padding-bottom: 15px; border-bottom: 1px solid #475569; }
                .preview-header h3 { margin: 0; color: #f1f5f9; }
                .preview-content { background: #0f172a; border-radius: 6px; padding: 20px; min-height: 400px; }
                .preview-placeholder { color: #64748b; text-align: center; padding: 60px 20px; }
                .preview-placeholder .icon { font-size: 48px; margin-bottom: 15px; }
                .loading-spinner { display: inline-block; width: 20px; height: 20px; border: 2px solid #475569; border-top-color: #3b82f6; border-radius: 50%; animation: spin 1s linear infinite; }
                @keyframes spin { to { transform: rotate(360deg); } }
                .report-table { width: 100%; border-collapse: collapse; }
                .report-table th, .report-table td { padding: 10px 12px; text-align: left; border-bottom: 1px solid #334155; }
                .report-table th { background: #334155; color: #f1f5f9; font-weight: 600; }
                .report-table tr:hover { background: #1e3a5f; }
                .metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 20px; }
                .metric-box { background: #334155; border-radius: 6px; padding: 15px; text-align: center; }
                .metric-box .value { font-size: 28px; font-weight: bold; color: #3b82f6; }
                .metric-box .label { font-size: 13px; color: #94a3b8; margin-top: 5px; }
                .status-online { color: #22c55e; }
                .status-offline { color: #ef4444; }
                .severity-critical { color: #ef4444; font-weight: bold; }
                .severity-high { color: #f97316; }
                .severity-medium { color: #f59e0b; }
                .severity-low { color: #22c55e; }
                @media (max-width: 900px) { .reports-container { grid-template-columns: 1fr; } }
            </style>
            <div class="reports-container">
                <div class="report-selector">
                    <h3 style="margin-top:0;color:#f1f5f9;">Select Report</h3>
                    <div class="report-card selected" data-report="ExecutiveSummary">
                        <h4><span class="report-icon">📈</span> Executive Summary</h4>
                        <p>High-level overview of fleet health, alerts, and key metrics</p>
                    </div>
                    <div class="report-card" data-report="DeviceInventory">
                        <h4><span class="report-icon">💻</span> Device Inventory</h4>
                        <p>Complete list of all managed devices with hardware details</p>
                    </div>
                    <div class="report-card" data-report="AlertSummary">
                        <h4><span class="report-icon">🔔</span> Alert Summary</h4>
                        <p>Active and resolved alerts grouped by severity and type</p>
                    </div>
                    <div class="report-card" data-report="UptimeReport">
                        <h4><span class="report-icon">⏱️</span> Uptime Report</h4>
                        <p>Device availability and uptime statistics</p>
                    </div>
                    <div class="report-card" data-report="PerformanceTrends">
                        <h4><span class="report-icon">📉</span> Performance Trends</h4>
                        <p>CPU, memory, and disk usage trends over time</p>
                    </div>
                    <div class="report-card" data-report="AuditLog">
                        <h4><span class="report-icon">📋</span> Audit Log</h4>
                        <p>Complete log of all actions and changes in the system</p>
                    </div>
                    <div class="date-filters">
                        <label for="startDate">Start Date</label>
                        <input type="date" id="startDate">
                        <label for="endDate">End Date</label>
                        <input type="date" id="endDate">
                    </div>
                    <button class="generate-btn" onclick="generateReport()">
                        <span id="generateBtnText">Generate Report</span>
                    </button>
                    <div class="download-btns">
                        <button class="download-btn pdf" onclick="downloadReport('pdf')" disabled id="downloadPdf">📄 PDF</button>
                        <button class="download-btn excel" onclick="downloadReport('xlsx')" disabled id="downloadExcel">📊 Excel</button>
                        <button class="download-btn csv" onclick="downloadReport('csv')" disabled id="downloadCsv">📋 CSV</button>
                    </div>
                </div>
                <div class="report-preview">
                    <div class="preview-header">
                        <h3 id="previewTitle">Report Preview</h3>
                        <span id="previewDate" style="color:#64748b;font-size:13px;"></span>
                    </div>
                    <div class="preview-content" id="previewContent">
                        <div class="preview-placeholder">
                            <div class="icon">📊</div>
                            <h3>Select a report and click Generate</h3>
                            <p>Choose a report type from the left panel, set your date range, and click Generate Report to preview the data.</p>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </main>

    <footer>
        <p>&copy; 2025 myTech.Today RMM - Powered by PowerShell</p>
    </footer>

    <script src="/app.js"></script>
    <script>
        let selectedReport = 'ExecutiveSummary';
        let currentReportData = null;
        const reportNames = { 'ExecutiveSummary': 'Executive Summary', 'DeviceInventory': 'Device Inventory', 'AlertSummary': 'Alert Summary', 'UptimeReport': 'Uptime Report', 'PerformanceTrends': 'Performance Trends', 'AuditLog': 'Audit Log' };
        const today = new Date();
        const weekAgo = new Date(today);
        weekAgo.setDate(weekAgo.getDate() - 7);
        document.getElementById('endDate').value = today.toISOString().split('T')[0];
        document.getElementById('startDate').value = weekAgo.toISOString().split('T')[0];
        document.querySelectorAll('.report-card').forEach(card => {
            card.addEventListener('click', () => {
                document.querySelectorAll('.report-card').forEach(c => c.classList.remove('selected'));
                card.classList.add('selected');
                selectedReport = card.dataset.report;
            });
        });
        async function generateReport() {
            const startDate = document.getElementById('startDate').value;
            const endDate = document.getElementById('endDate').value;
            const btn = document.querySelector('.generate-btn');
            const btnText = document.getElementById('generateBtnText');
            btn.disabled = true;
            btnText.innerHTML = '<span class="loading-spinner"></span> Generating...';
            try {
                const response = await fetch('/api/reports/generate?type=' + selectedReport + '&startDate=' + startDate + '&endDate=' + endDate);
                const data = await response.json();
                if (data.success) {
                    currentReportData = data;
                    displayReport(data);
                    document.getElementById('downloadPdf').disabled = false;
                    document.getElementById('downloadExcel').disabled = false;
                    document.getElementById('downloadCsv').disabled = false;
                } else {
                    document.getElementById('previewContent').innerHTML = '<div class="preview-placeholder"><div class="icon">❌</div><h3>Error generating report</h3><p>' + (data.error || 'Unknown error') + '</p></div>';
                }
            } catch (error) {
                document.getElementById('previewContent').innerHTML = '<div class="preview-placeholder"><div class="icon">❌</div><h3>Error</h3><p>' + error.message + '</p></div>';
            } finally {
                btn.disabled = false;
                btnText.textContent = 'Generate Report';
            }
        }
        function displayReport(data) {
            document.getElementById('previewTitle').textContent = reportNames[data.reportType] || data.reportType;
            document.getElementById('previewDate').textContent = 'Generated: ' + new Date().toLocaleString();
            document.getElementById('previewContent').innerHTML = data.html || '<p>No data available</p>';
        }

        // Convert report data to array format for export
        function getExportData() {
            if (!currentReportData || !currentReportData.data) return [];
            const data = currentReportData.data;
            if (Array.isArray(data)) return data;
            // Handle object data (like ExecutiveSummary)
            return Object.entries(data).map(([key, value]) => ({ Metric: key, Value: value }));
        }

        // Generate PDF using jsPDF with autoTable
        function generatePDF() {
            const { jsPDF } = window.jspdf;
            const doc = new jsPDF();
            const startDate = document.getElementById('startDate').value;
            const endDate = document.getElementById('endDate').value;
            const title = reportNames[selectedReport] || selectedReport;

            // Add header
            doc.setFontSize(20);
            doc.setTextColor(30, 58, 95);
            doc.text('myTech.Today RMM', 14, 20);
            doc.setFontSize(16);
            doc.setTextColor(59, 130, 246);
            doc.text(title, 14, 30);
            doc.setFontSize(10);
            doc.setTextColor(100);
            doc.text('Date Range: ' + startDate + ' to ' + endDate, 14, 38);
            doc.text('Generated: ' + new Date().toLocaleString(), 14, 44);

            // Get data and create table
            const data = getExportData();
            if (data.length > 0) {
                const headers = Object.keys(data[0]);
                const rows = data.map(item => headers.map(h => item[h] != null ? String(item[h]) : ''));

                doc.autoTable({
                    head: [headers],
                    body: rows,
                    startY: 52,
                    theme: 'striped',
                    headStyles: { fillColor: [59, 130, 246], textColor: 255, fontStyle: 'bold' },
                    styles: { fontSize: 9, cellPadding: 3 },
                    alternateRowStyles: { fillColor: [245, 247, 250] }
                });
            } else {
                doc.setFontSize(12);
                doc.text('No data available for the selected date range.', 14, 55);
            }

            // Add footer
            const pageCount = doc.internal.getNumberOfPages();
            for (let i = 1; i <= pageCount; i++) {
                doc.setPage(i);
                doc.setFontSize(8);
                doc.setTextColor(150);
                doc.text('Page ' + i + ' of ' + pageCount + ' | myTech.Today RMM', doc.internal.pageSize.width / 2, doc.internal.pageSize.height - 10, { align: 'center' });
            }

            doc.save(selectedReport + '_' + startDate + '_to_' + endDate + '.pdf');
        }

        // Generate XLSX using SheetJS
        function generateXLSX() {
            const startDate = document.getElementById('startDate').value;
            const endDate = document.getElementById('endDate').value;
            const title = reportNames[selectedReport] || selectedReport;
            const data = getExportData();

            if (data.length === 0) {
                alert('No data available to export.');
                return;
            }

            // Create workbook and worksheet
            const wb = XLSX.utils.book_new();

            // Add title row and metadata
            const wsData = [
                ['myTech.Today RMM - ' + title],
                ['Date Range: ' + startDate + ' to ' + endDate],
                ['Generated: ' + new Date().toLocaleString()],
                [], // Empty row for spacing
            ];

            // Add headers
            const headers = Object.keys(data[0]);
            wsData.push(headers);

            // Add data rows
            data.forEach(item => {
                wsData.push(headers.map(h => item[h] != null ? item[h] : ''));
            });

            const ws = XLSX.utils.aoa_to_sheet(wsData);

            // Set column widths
            const colWidths = headers.map(h => ({ wch: Math.max(h.length + 2, 15) }));
            ws['!cols'] = colWidths;

            // Merge title cells
            ws['!merges'] = [
                { s: { r: 0, c: 0 }, e: { r: 0, c: headers.length - 1 } },
                { s: { r: 1, c: 0 }, e: { r: 1, c: headers.length - 1 } },
                { s: { r: 2, c: 0 }, e: { r: 2, c: headers.length - 1 } }
            ];

            XLSX.utils.book_append_sheet(wb, ws, title.substring(0, 31)); // Sheet name max 31 chars
            XLSX.writeFile(wb, selectedReport + '_' + startDate + '_to_' + endDate + '.xlsx');
        }

        // Generate CSV (kept for simplicity, uses server-side)
        async function generateCSV() {
            const startDate = document.getElementById('startDate').value;
            const endDate = document.getElementById('endDate').value;
            const data = getExportData();

            if (data.length === 0) {
                alert('No data available to export.');
                return;
            }

            const headers = Object.keys(data[0]);
            const csvRows = [headers.join(',')];
            data.forEach(item => {
                const values = headers.map(h => {
                    const val = item[h] != null ? String(item[h]) : '';
                    // Escape quotes and wrap in quotes if contains comma or quote
                    if (val.includes(',') || val.includes('"') || val.includes('\n')) {
                        return '"' + val.replace(/"/g, '""') + '"';
                    }
                    return val;
                });
                csvRows.push(values.join(','));
            });

            const csvContent = csvRows.join('\n');
            const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = selectedReport + '_' + startDate + '_to_' + endDate + '.csv';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        }

        async function downloadReport(format) {
            if (!currentReportData) return;
            const btn = document.getElementById(format === 'pdf' ? 'downloadPdf' : format === 'xlsx' ? 'downloadExcel' : 'downloadCsv');
            const originalText = btn.innerHTML;
            btn.disabled = true;
            btn.innerHTML = '<span class="loading-spinner"></span>';

            try {
                if (format === 'pdf') {
                    generatePDF();
                } else if (format === 'xlsx') {
                    generateXLSX();
                } else {
                    generateCSV();
                }
            } catch (error) {
                console.error('Export error:', error);
                alert('Error exporting report: ' + error.message);
            } finally {
                setTimeout(() => {
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }, 500);
            }
        }
    </script>
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
        <div class="header-left">
            <h1>myTech.Today RMM Dashboard</h1>
            <nav>
                <a href="/">Dashboard</a>
                <a href="/sites-and-devices">Sites &amp; Devices</a>
                <a href="/alerts">Alerts</a>
                <a href="/actions">Actions</a>
                <a href="/reports">Reports</a>
                <a href="/settings" class="active">Settings</a>
            </nav>
        </div>
        <button class="readme-btn" onclick="openReadme()" title="View Documentation">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
            Readme
        </button>
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
        <div class="header-left">
            <h1>myTech.Today RMM Dashboard</h1>
            <nav>
                <a href="/">Dashboard</a>
                <a href="/sites-and-devices" class="active">Sites &amp; Devices</a>
                <a href="/alerts">Alerts</a>
                <a href="/actions">Actions</a>
                <a href="/reports">Reports</a>
                <a href="/settings">Settings</a>
            </nav>
        </div>
        <button class="readme-btn" onclick="openReadme()" title="View Documentation">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
            Readme
        </button>
    </header>

    <main>
        <div class="panel">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:15px;">
                <h2 style="margin:0;">Sites</h2>
                <div style="display:flex;gap:10px;">
                    <button onclick="exportSites()" style="padding:8px 15px;background:#17a2b8;color:white;border:none;border-radius:5px;cursor:pointer;">Export</button>
                    <label style="padding:8px 15px;background:#6c757d;color:white;border:none;border-radius:5px;cursor:pointer;">
                        Import
                        <input type="file" id="importSitesFile" accept=".json" style="display:none;" onchange="importSites(this)">
                    </label>
                    <button class="btn-primary" onclick="openAddSiteModal()">+ Add Site</button>
                </div>
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
            <!-- Contact Import Section -->
            <div id="contactImportSection" style="background:#f0f7ff;border:1px solid #b3d4fc;border-radius:8px;padding:15px;margin-bottom:20px;">
                <div style="display:flex;justify-content:space-between;align-items:center;">
                    <div>
                        <strong style="color:#0066cc;">📇 Import Contact Information</strong>
                        <p style="margin:5px 0 0 0;font-size:12px;color:#666;">Import from Outlook CSV, vCard, Windows Contacts, or LDIF files</p>
                    </div>
                    <label style="padding:10px 18px;background:#0066cc;color:white;border-radius:5px;cursor:pointer;font-weight:500;">
                        📂 Select Contact File
                        <input type="file" id="contactFileInput" accept=".csv,.vcf,.contact,.wab,.ldif" style="display:none;" onchange="handleContactFileSelect(this)">
                    </label>
                </div>
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
                        <label>Country</label>
                        <select id="country" onchange="onCountryChange()"></select>
                    </div>
                    <div id="stateWrapper">
                        <label id="stateLabel">State</label>
                        <select id="state"></select>
                        <input type="text" id="stateText" placeholder="Province/Region (if applicable)" style="display:none;">
                    </div>
                    <div>
                        <label>ZIP/Postal Code</label>
                        <input type="text" id="zip">
                    </div>
                    <div>
                        <label>Timezone</label>
                        <select id="timezone"></select>
                    </div>
                    <div class="full-width">
                        <label>Notes</label>
                        <textarea id="notes"></textarea>
                    </div>

                    <!-- URLs Section -->
                    <div class="full-width" id="urlsSection" style="margin-top:15px;border-top:1px solid #ddd;padding-top:15px;">
                        <label style="font-size:14px;margin-bottom:10px;display:block;">URLs / Links</label>
                        <div id="urlsList"></div>
                        <div style="display:grid;grid-template-columns:1fr 2fr 1fr 1fr auto;gap:8px;align-items:end;margin-top:10px;">
                            <div>
                                <label style="font-size:11px;">Label</label>
                                <input type="text" id="newUrlLabel" placeholder="e.g., Web Portal">
                            </div>
                            <div>
                                <label style="font-size:11px;">URL</label>
                                <input type="text" id="newUrlValue" placeholder="https://...">
                            </div>
                            <div>
                                <label style="font-size:11px;">Username (optional)</label>
                                <input type="text" id="newUrlUsername" placeholder="Username">
                            </div>
                            <div>
                                <label style="font-size:11px;">Password (optional)</label>
                                <input type="password" id="newUrlPassword" placeholder="Password">
                            </div>
                            <button type="button" onclick="addSiteUrl()" style="padding:8px 12px;background:#28a745;color:white;border:none;border-radius:4px;cursor:pointer;">+</button>
                        </div>
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

    <!-- Contact Selection Modal -->
    <div id="contactSelectModal" class="modal" style="display:none;">
        <div class="modal-content" style="max-width:700px;">
            <div class="modal-header">
                <h3>Select Contact to Import</h3>
                <span class="modal-close" onclick="closeContactSelectModal()">&times;</span>
            </div>
            <div style="padding:15px;">
                <p style="color:#666;margin-bottom:15px;">Multiple contacts found. Search or select the contact you want to import:</p>
                <input type="text" id="contactSearchInput" placeholder="🔍 Search by name, company, or email..."
                    style="width:100%;padding:12px;border:1px solid #ddd;border-radius:5px;font-size:14px;box-sizing:border-box;margin-bottom:15px;"
                    oninput="filterContactList()">
                <div id="contactList" style="max-height:400px;overflow-y:auto;border:1px solid #ddd;border-radius:5px;">
                    <!-- Contacts will be populated here -->
                </div>
                <div style="margin-top:15px;text-align:right;">
                    <button type="button" onclick="closeContactSelectModal()" style="padding:10px 20px;">Cancel</button>
                </div>
            </div>
        </div>
    </div>

    <footer>
        <p>&copy; 2025 myTech.Today RMM - Powered by PowerShell</p>
    </footer>

    <script src="/app.js"></script>
    <script>
        // Country list with United States at top, rest alphabetical
        const countries = [
            'United States',
            'Afghanistan', 'Albania', 'Algeria', 'Andorra', 'Angola', 'Antigua and Barbuda', 'Argentina', 'Armenia', 'Australia', 'Austria',
            'Azerbaijan', 'Bahamas', 'Bahrain', 'Bangladesh', 'Barbados', 'Belarus', 'Belgium', 'Belize', 'Benin', 'Bhutan',
            'Bolivia', 'Bosnia and Herzegovina', 'Botswana', 'Brazil', 'Brunei', 'Bulgaria', 'Burkina Faso', 'Burundi', 'Cabo Verde', 'Cambodia',
            'Cameroon', 'Canada', 'Central African Republic', 'Chad', 'Chile', 'China', 'Colombia', 'Comoros', 'Congo', 'Costa Rica',
            'Croatia', 'Cuba', 'Cyprus', 'Czech Republic', 'Denmark', 'Djibouti', 'Dominica', 'Dominican Republic', 'Ecuador', 'Egypt',
            'El Salvador', 'Equatorial Guinea', 'Eritrea', 'Estonia', 'Eswatini', 'Ethiopia', 'Fiji', 'Finland', 'France', 'Gabon',
            'Gambia', 'Georgia', 'Germany', 'Ghana', 'Greece', 'Grenada', 'Guatemala', 'Guinea', 'Guinea-Bissau', 'Guyana',
            'Haiti', 'Honduras', 'Hungary', 'Iceland', 'India', 'Indonesia', 'Iran', 'Iraq', 'Ireland', 'Israel',
            'Italy', 'Jamaica', 'Japan', 'Jordan', 'Kazakhstan', 'Kenya', 'Kiribati', 'Korea North', 'Korea South', 'Kuwait',
            'Kyrgyzstan', 'Laos', 'Latvia', 'Lebanon', 'Lesotho', 'Liberia', 'Libya', 'Liechtenstein', 'Lithuania', 'Luxembourg',
            'Madagascar', 'Malawi', 'Malaysia', 'Maldives', 'Mali', 'Malta', 'Marshall Islands', 'Mauritania', 'Mauritius', 'Mexico',
            'Micronesia', 'Moldova', 'Monaco', 'Mongolia', 'Montenegro', 'Morocco', 'Mozambique', 'Myanmar', 'Namibia', 'Nauru',
            'Nepal', 'Netherlands', 'New Zealand', 'Nicaragua', 'Niger', 'Nigeria', 'North Macedonia', 'Norway', 'Oman', 'Pakistan',
            'Palau', 'Palestine', 'Panama', 'Papua New Guinea', 'Paraguay', 'Peru', 'Philippines', 'Poland', 'Portugal', 'Qatar',
            'Romania', 'Russia', 'Rwanda', 'Saint Kitts and Nevis', 'Saint Lucia', 'Saint Vincent and the Grenadines', 'Samoa', 'San Marino', 'Sao Tome and Principe', 'Saudi Arabia',
            'Senegal', 'Serbia', 'Seychelles', 'Sierra Leone', 'Singapore', 'Slovakia', 'Slovenia', 'Solomon Islands', 'Somalia', 'South Africa',
            'South Sudan', 'Spain', 'Sri Lanka', 'Sudan', 'Suriname', 'Sweden', 'Switzerland', 'Syria', 'Taiwan', 'Tajikistan',
            'Tanzania', 'Thailand', 'Timor-Leste', 'Togo', 'Tonga', 'Trinidad and Tobago', 'Tunisia', 'Turkey', 'Turkmenistan', 'Tuvalu',
            'Uganda', 'Ukraine', 'United Arab Emirates', 'United Kingdom', 'Uruguay', 'Uzbekistan', 'Vanuatu', 'Vatican City', 'Venezuela', 'Vietnam',
            'Yemen', 'Zambia', 'Zimbabwe'
        ];

        // US States list (alphabetical)
        const usStates = [
            { name: 'Alabama', abbr: 'AL' }, { name: 'Alaska', abbr: 'AK' }, { name: 'Arizona', abbr: 'AZ' }, { name: 'Arkansas', abbr: 'AR' },
            { name: 'California', abbr: 'CA' }, { name: 'Colorado', abbr: 'CO' }, { name: 'Connecticut', abbr: 'CT' }, { name: 'Delaware', abbr: 'DE' },
            { name: 'Florida', abbr: 'FL' }, { name: 'Georgia', abbr: 'GA' }, { name: 'Hawaii', abbr: 'HI' }, { name: 'Idaho', abbr: 'ID' },
            { name: 'Illinois', abbr: 'IL' }, { name: 'Indiana', abbr: 'IN' }, { name: 'Iowa', abbr: 'IA' }, { name: 'Kansas', abbr: 'KS' },
            { name: 'Kentucky', abbr: 'KY' }, { name: 'Louisiana', abbr: 'LA' }, { name: 'Maine', abbr: 'ME' }, { name: 'Maryland', abbr: 'MD' },
            { name: 'Massachusetts', abbr: 'MA' }, { name: 'Michigan', abbr: 'MI' }, { name: 'Minnesota', abbr: 'MN' }, { name: 'Mississippi', abbr: 'MS' },
            { name: 'Missouri', abbr: 'MO' }, { name: 'Montana', abbr: 'MT' }, { name: 'Nebraska', abbr: 'NE' }, { name: 'Nevada', abbr: 'NV' },
            { name: 'New Hampshire', abbr: 'NH' }, { name: 'New Jersey', abbr: 'NJ' }, { name: 'New Mexico', abbr: 'NM' }, { name: 'New York', abbr: 'NY' },
            { name: 'North Carolina', abbr: 'NC' }, { name: 'North Dakota', abbr: 'ND' }, { name: 'Ohio', abbr: 'OH' }, { name: 'Oklahoma', abbr: 'OK' },
            { name: 'Oregon', abbr: 'OR' }, { name: 'Pennsylvania', abbr: 'PA' }, { name: 'Rhode Island', abbr: 'RI' }, { name: 'South Carolina', abbr: 'SC' },
            { name: 'South Dakota', abbr: 'SD' }, { name: 'Tennessee', abbr: 'TN' }, { name: 'Texas', abbr: 'TX' }, { name: 'Utah', abbr: 'UT' },
            { name: 'Vermont', abbr: 'VT' }, { name: 'Virginia', abbr: 'VA' }, { name: 'Washington', abbr: 'WA' }, { name: 'West Virginia', abbr: 'WV' },
            { name: 'Wisconsin', abbr: 'WI' }, { name: 'Wyoming', abbr: 'WY' }
        ];

        // Timezone list with common US timezones at top
        const timezones = [
            { value: 'America/Chicago', label: '(UTC-06:00) Central Time - Chicago, USA' },
            { value: 'America/New_York', label: '(UTC-05:00) Eastern Time - New York, USA' },
            { value: 'America/Denver', label: '(UTC-07:00) Mountain Time - Denver, USA' },
            { value: 'America/Los_Angeles', label: '(UTC-08:00) Pacific Time - Los Angeles, USA' },
            { value: 'America/Anchorage', label: '(UTC-09:00) Alaska Time - Anchorage, USA' },
            { value: 'Pacific/Honolulu', label: '(UTC-10:00) Hawaii Time - Honolulu, USA' },
            { value: 'America/Phoenix', label: '(UTC-07:00) Arizona Time - Phoenix, USA (No DST)' },
            { value: '---', label: '─────────────────────────' },
            { value: 'UTC', label: '(UTC+00:00) Coordinated Universal Time' },
            { value: 'Europe/London', label: '(UTC+00:00) London, Dublin, Edinburgh' },
            { value: 'Europe/Paris', label: '(UTC+01:00) Paris, Berlin, Rome, Madrid' },
            { value: 'Europe/Helsinki', label: '(UTC+02:00) Helsinki, Kyiv, Athens' },
            { value: 'Europe/Moscow', label: '(UTC+03:00) Moscow, St. Petersburg' },
            { value: 'Asia/Dubai', label: '(UTC+04:00) Dubai, Abu Dhabi' },
            { value: 'Asia/Karachi', label: '(UTC+05:00) Karachi, Islamabad' },
            { value: 'Asia/Kolkata', label: '(UTC+05:30) Mumbai, New Delhi, Kolkata' },
            { value: 'Asia/Dhaka', label: '(UTC+06:00) Dhaka, Almaty' },
            { value: 'Asia/Bangkok', label: '(UTC+07:00) Bangkok, Hanoi, Jakarta' },
            { value: 'Asia/Shanghai', label: '(UTC+08:00) Beijing, Shanghai, Hong Kong' },
            { value: 'Asia/Singapore', label: '(UTC+08:00) Singapore, Kuala Lumpur' },
            { value: 'Asia/Tokyo', label: '(UTC+09:00) Tokyo, Seoul, Osaka' },
            { value: 'Australia/Sydney', label: '(UTC+10:00) Sydney, Melbourne, Brisbane' },
            { value: 'Pacific/Auckland', label: '(UTC+12:00) Auckland, Wellington' },
            { value: 'America/Sao_Paulo', label: '(UTC-03:00) Sao Paulo, Buenos Aires' },
            { value: 'America/Mexico_City', label: '(UTC-06:00) Mexico City, Guadalajara' },
            { value: 'America/Toronto', label: '(UTC-05:00) Toronto, Montreal' },
            { value: 'America/Vancouver', label: '(UTC-08:00) Vancouver, Seattle' }
        ];

        // Populate country dropdown
        function populateCountries(selectedValue) {
            const select = document.getElementById('country');
            select.innerHTML = '<option value="">-- Select Country --</option>';
            countries.forEach(country => {
                const opt = document.createElement('option');
                opt.value = country;
                opt.textContent = country;
                if (country === selectedValue) opt.selected = true;
                select.appendChild(opt);
            });
        }

        // Populate US states dropdown
        function populateStates(selectedValue) {
            const select = document.getElementById('state');
            select.innerHTML = '<option value="">-- Select State --</option>';
            usStates.forEach(state => {
                const opt = document.createElement('option');
                opt.value = state.abbr;
                opt.textContent = state.name + ' (' + state.abbr + ')';
                if (state.abbr === selectedValue || state.name === selectedValue) opt.selected = true;
                select.appendChild(opt);
            });
        }

        // Populate timezone dropdown
        function populateTimezones(selectedValue) {
            const select = document.getElementById('timezone');
            select.innerHTML = '<option value="">-- Select Timezone --</option>';
            timezones.forEach(tz => {
                const opt = document.createElement('option');
                if (tz.value === '---') {
                    opt.disabled = true;
                    opt.textContent = tz.label;
                } else {
                    opt.value = tz.value;
                    opt.textContent = tz.label;
                    if (tz.value === selectedValue) opt.selected = true;
                }
                select.appendChild(opt);
            });
        }

        // Check if country is United States (handles various formats)
        function isUnitedStates(country) {
            if (!country) return false;
            const normalized = country.toLowerCase().trim();
            return normalized === 'united states' ||
                   normalized === 'usa' ||
                   normalized === 'us' ||
                   normalized === 'united states of america';
        }

        // Normalize country value to standard format
        function normalizeCountry(country) {
            if (isUnitedStates(country)) return 'United States';
            return country;
        }

        // Handle country change - show state dropdown for US, text input for others
        function onCountryChange() {
            const country = document.getElementById('country').value;
            const stateSelect = document.getElementById('state');
            const stateText = document.getElementById('stateText');
            const stateLabel = document.getElementById('stateLabel');
            const isUS = isUnitedStates(country);

            if (isUS) {
                stateLabel.textContent = 'State *';
                stateSelect.style.display = 'block';
                stateSelect.required = true;
                stateText.style.display = 'none';
                stateText.value = '';
                // If no state selected, default to Illinois
                if (!stateSelect.value) {
                    stateSelect.value = 'IL';
                }
            } else {
                stateLabel.textContent = 'Province/Region';
                stateSelect.style.display = 'none';
                stateSelect.required = false;
                stateSelect.value = '';
                stateText.style.display = 'block';
            }
        }

        // Initialize dropdowns on page load
        function initializeDropdowns() {
            populateCountries('United States');
            populateStates('IL');
            populateTimezones('America/Chicago');
        }

        // Initialize on page load
        initializeDropdowns();
        loadSites();

        // =========================================================
        // Contact Import Functionality
        // =========================================================
        let parsedContacts = [];

        function handleContactFileSelect(input) {
            if (!input.files || !input.files[0]) return;
            const file = input.files[0];
            const ext = file.name.split('.').pop().toLowerCase();
            const reader = new FileReader();

            reader.onload = function(e) {
                const content = e.target.result;
                try {
                    let contacts = [];
                    switch(ext) {
                        case 'csv':
                            contacts = parseCSV(content);
                            break;
                        case 'vcf':
                            contacts = parseVCF(content);
                            break;
                        case 'contact':
                            contacts = parseWindowsContact(content);
                            break;
                        case 'ldif':
                            contacts = parseLDIF(content);
                            break;
                        case 'wab':
                            alert('WAB format requires binary parsing which is not supported in the browser. Please export to VCF or CSV first.');
                            return;
                        default:
                            alert('Unsupported file format: .' + ext);
                            return;
                    }

                    if (contacts.length === 0) {
                        alert('No contacts found in the file. Please check the file format.');
                        return;
                    }

                    parsedContacts = contacts;

                    if (contacts.length === 1) {
                        // Single contact - auto-populate
                        populateFormFromContact(contacts[0]);
                        showImportSuccess('Contact imported: ' + (contacts[0].company || contacts[0].fullName || 'Unknown'));
                    } else {
                        // Multiple contacts - show selection modal
                        showContactSelectModal(contacts);
                    }
                } catch (err) {
                    alert('Error parsing file: ' + err.message);
                    console.error('Contact parse error:', err);
                }
            };

            reader.readAsText(file);
            input.value = ''; // Reset for re-selection
        }

        function showImportSuccess(msg) {
            const section = document.getElementById('contactImportSection');
            section.innerHTML = '<div style="display:flex;justify-content:space-between;align-items:center;">' +
                '<div><span style="color:#28a745;font-size:18px;">✓</span> <strong style="color:#28a745;">' + msg + '</strong></div>' +
                '<label style="padding:8px 15px;background:#6c757d;color:white;border-radius:5px;cursor:pointer;font-size:13px;">' +
                'Import Different Contact<input type="file" id="contactFileInput" accept=".csv,.vcf,.contact,.wab,.ldif" style="display:none;" onchange="handleContactFileSelect(this)">' +
                '</label></div>';
        }

        // Parse CSV (Outlook export format)
        function parseCSV(content) {
            const lines = content.split(/\r?\n/);
            if (lines.length < 2) return [];

            // Parse header row - handle quoted fields
            const headers = parseCSVLine(lines[0]);
            const contacts = [];

            for (let i = 1; i < lines.length; i++) {
                if (!lines[i].trim()) continue;
                const values = parseCSVLine(lines[i]);
                const contact = {};

                headers.forEach((h, idx) => {
                    const key = h.trim().toLowerCase().replace(/[^a-z0-9]/g, '_');
                    contact[key] = values[idx] ? values[idx].trim() : '';
                });

                // Map to standard contact format
                const mapped = mapCSVToContact(contact);
                if (mapped.fullName || mapped.company || mapped.email) {
                    contacts.push(mapped);
                }
            }
            return contacts;
        }

        function parseCSVLine(line) {
            const result = [];
            let current = '';
            let inQuotes = false;

            for (let i = 0; i < line.length; i++) {
                const char = line[i];
                if (char === '"') {
                    if (inQuotes && line[i+1] === '"') {
                        current += '"';
                        i++;
                    } else {
                        inQuotes = !inQuotes;
                    }
                } else if (char === ',' && !inQuotes) {
                    result.push(current);
                    current = '';
                } else {
                    current += char;
                }
            }
            result.push(current);
            return result;
        }

        function mapCSVToContact(row) {
            // Build full name from parts
            let fullName = [row.first_name, row.middle_name, row.last_name].filter(x => x).join(' ');
            if (!fullName && row.name) fullName = row.name;

            return {
                fullName: fullName,
                firstName: row.first_name || '',
                lastName: row.last_name || '',
                company: row.company || row.organization || '',
                jobTitle: row.job_title || row.title || '',
                department: row.department || '',
                email: row.e_mail_address || row.email_address || row.email || row.e_mail || '',
                email2: row.e_mail_2_address || row.email_2_address || '',
                email3: row.e_mail_3_address || row.email_3_address || '',
                businessPhone: row.business_phone || row.work_phone || row.phone || '',
                businessPhone2: row.business_phone_2 || '',
                mobilePhone: row.mobile_phone || row.cell_phone || row.mobile || '',
                homePhone: row.home_phone || '',
                mainPhone: row.primary_phone || row.main_phone || '',
                fax: row.business_fax || row.fax || '',
                streetAddress: row.business_street || row.street || row.address || '',
                city: row.business_city || row.city || '',
                state: row.business_state || row.state || '',
                postalCode: row.business_postal_code || row.postal_code || row.zip || '',
                country: row.business_country_region || row.country_region || row.country || '',
                website: row.web_page || row.personal_web_page || row.website || '',
                notes: row.notes || ''
            };
        }

        // Parse VCF (vCard format)
        function parseVCF(content) {
            const contacts = [];
            const vcards = content.split(/(?=BEGIN:VCARD)/i);

            for (const vcard of vcards) {
                if (!vcard.trim() || !vcard.toUpperCase().includes('BEGIN:VCARD')) continue;

                const contact = {
                    fullName: '', firstName: '', lastName: '', company: '', jobTitle: '',
                    department: '', email: '', email2: '', email3: '', businessPhone: '',
                    mobilePhone: '', homePhone: '', mainPhone: '', fax: '', streetAddress: '',
                    city: '', state: '', postalCode: '', country: '', website: '', notes: ''
                };

                // Unfold lines (handle line continuations)
                const unfolded = vcard.replace(/\r?\n[ \t]/g, '');
                const lines = unfolded.split(/\r?\n/);

                let emails = [];
                let phones = { work: [], cell: [], home: [], fax: [] };

                for (const line of lines) {
                    const colonIdx = line.indexOf(':');
                    if (colonIdx === -1) continue;

                    const propPart = line.substring(0, colonIdx).toUpperCase();
                    const value = line.substring(colonIdx + 1).trim();
                    const prop = propPart.split(';')[0];

                    switch(prop) {
                        case 'FN':
                            contact.fullName = value;
                            break;
                        case 'N':
                            const parts = value.split(';');
                            contact.lastName = parts[0] || '';
                            contact.firstName = parts[1] || '';
                            break;
                        case 'ORG':
                            const orgParts = value.split(';');
                            contact.company = orgParts[0] || '';
                            if (orgParts[1]) contact.department = orgParts[1];
                            break;
                        case 'TITLE':
                            contact.jobTitle = value;
                            break;
                        case 'EMAIL':
                            emails.push(value);
                            break;
                        case 'TEL':
                            if (propPart.includes('WORK') || propPart.includes('VOICE')) phones.work.push(value);
                            else if (propPart.includes('CELL') || propPart.includes('MOBILE')) phones.cell.push(value);
                            else if (propPart.includes('HOME')) phones.home.push(value);
                            else if (propPart.includes('FAX')) phones.fax.push(value);
                            else phones.work.push(value);
                            break;
                        case 'ADR':
                            const addrParts = value.split(';');
                            // ADR format: PO Box;Extended;Street;City;State;PostalCode;Country
                            contact.streetAddress = addrParts[2] || '';
                            contact.city = addrParts[3] || '';
                            contact.state = addrParts[4] || '';
                            contact.postalCode = addrParts[5] || '';
                            contact.country = addrParts[6] || '';
                            break;
                        case 'URL':
                            contact.website = value;
                            break;
                        case 'NOTE':
                            contact.notes = value.replace(/\\n/g, '\n');
                            break;
                    }
                }

                contact.email = emails[0] || '';
                contact.email2 = emails[1] || '';
                contact.email3 = emails[2] || '';
                contact.businessPhone = phones.work[0] || '';
                contact.mobilePhone = phones.cell[0] || '';
                contact.homePhone = phones.home[0] || '';
                contact.fax = phones.fax[0] || '';

                if (contact.fullName || contact.company || contact.email) {
                    contacts.push(contact);
                }
            }
            return contacts;
        }

        // Parse Windows .contact (XML format)
        function parseWindowsContact(content) {
            const contacts = [];
            try {
                const parser = new DOMParser();
                const doc = parser.parseFromString(content, 'text/xml');

                // Windows .contact files are typically single contacts
                const contact = {
                    fullName: '', firstName: '', lastName: '', company: '', jobTitle: '',
                    department: '', email: '', email2: '', email3: '', businessPhone: '',
                    mobilePhone: '', homePhone: '', mainPhone: '', fax: '', streetAddress: '',
                    city: '', state: '', postalCode: '', country: '', website: '', notes: ''
                };

                const getText = (tag) => {
                    const el = doc.getElementsByTagName(tag)[0];
                    return el ? el.textContent || '' : '';
                };

                contact.firstName = getText('GivenName') || getText('c:GivenName');
                contact.lastName = getText('FamilyName') || getText('c:FamilyName');
                contact.fullName = contact.firstName + ' ' + contact.lastName;
                contact.company = getText('Company') || getText('c:Company');
                contact.jobTitle = getText('JobTitle') || getText('c:JobTitle');
                contact.email = getText('EmailAddress1') || getText('c:EmailAddress1') || getText('Email');
                contact.businessPhone = getText('Business1PhoneNumber') || getText('c:Business1PhoneNumber');
                contact.mobilePhone = getText('MobilePhoneNumber') || getText('c:MobilePhoneNumber');
                contact.homePhone = getText('Home1PhoneNumber') || getText('c:Home1PhoneNumber');
                contact.streetAddress = getText('Street') || getText('c:Street');
                contact.city = getText('Locality') || getText('c:Locality');
                contact.state = getText('Region') || getText('c:Region');
                contact.postalCode = getText('PostalCode') || getText('c:PostalCode');
                contact.country = getText('Country') || getText('c:Country');
                contact.website = getText('Url') || getText('c:Url');
                contact.notes = getText('Notes') || getText('c:Notes');

                if (contact.fullName.trim() || contact.company || contact.email) {
                    contacts.push(contact);
                }
            } catch (e) {
                console.error('Error parsing Windows Contact:', e);
            }
            return contacts;
        }

        // Parse LDIF (LDAP format)
        function parseLDIF(content) {
            const contacts = [];
            const entries = content.split(/(?=^dn:)/gm);

            for (const entry of entries) {
                if (!entry.trim()) continue;

                const contact = {
                    fullName: '', firstName: '', lastName: '', company: '', jobTitle: '',
                    department: '', email: '', email2: '', email3: '', businessPhone: '',
                    mobilePhone: '', homePhone: '', mainPhone: '', fax: '', streetAddress: '',
                    city: '', state: '', postalCode: '', country: '', website: '', notes: ''
                };

                const lines = entry.split(/\r?\n/);

                for (const line of lines) {
                    const [key, ...valueParts] = line.split(':');
                    if (!key) continue;
                    const value = valueParts.join(':').trim();
                    const lowerKey = key.toLowerCase();

                    switch(lowerKey) {
                        case 'cn': contact.fullName = value; break;
                        case 'givenname': contact.firstName = value; break;
                        case 'sn': contact.lastName = value; break;
                        case 'o': case 'organizationname': contact.company = value; break;
                        case 'title': contact.jobTitle = value; break;
                        case 'ou': case 'department': contact.department = value; break;
                        case 'mail': if (!contact.email) contact.email = value; else if (!contact.email2) contact.email2 = value; break;
                        case 'telephonenumber': contact.businessPhone = value; break;
                        case 'mobile': contact.mobilePhone = value; break;
                        case 'homephone': contact.homePhone = value; break;
                        case 'facsimiletelephonenumber': contact.fax = value; break;
                        case 'street': case 'streetaddress': contact.streetAddress = value; break;
                        case 'l': contact.city = value; break;
                        case 'st': contact.state = value; break;
                        case 'postalcode': contact.postalCode = value; break;
                        case 'c': case 'co': contact.country = value; break;
                        case 'labeleduri': contact.website = value; break;
                        case 'description': contact.notes = value; break;
                    }
                }

                if (!contact.fullName && (contact.firstName || contact.lastName)) {
                    contact.fullName = (contact.firstName + ' ' + contact.lastName).trim();
                }

                if (contact.fullName || contact.company || contact.email) {
                    contacts.push(contact);
                }
            }
            return contacts;
        }

        // Show contact selection modal
        function showContactSelectModal(contacts) {
            const modal = document.getElementById('contactSelectModal');
            const list = document.getElementById('contactList');

            let html = '';
            contacts.forEach((c, idx) => {
                const displayName = c.fullName || 'No Name';
                const displayCompany = c.company || '';
                const displayEmail = c.email || '';

                html += '<div class="contact-item" data-index="' + idx + '" onclick="selectContact(' + idx + ')" ' +
                    'style="padding:12px 15px;border-bottom:1px solid #eee;cursor:pointer;display:flex;justify-content:space-between;align-items:center;" ' +
                    'onmouseover="this.style.background=\'#f0f7ff\'" onmouseout="this.style.background=\'white\'">' +
                    '<div>' +
                    '<strong style="color:#333;">' + escapeHtml(displayName) + '</strong>' +
                    (displayCompany ? '<span style="color:#0066cc;margin-left:10px;">' + escapeHtml(displayCompany) + '</span>' : '') +
                    '<br><span style="font-size:12px;color:#666;">' + escapeHtml(displayEmail) + '</span>' +
                    '</div>' +
                    '<span style="color:#28a745;font-size:12px;">Select →</span>' +
                    '</div>';
            });

            list.innerHTML = html;
            document.getElementById('contactSearchInput').value = '';
            modal.style.display = 'block';
        }

        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        function filterContactList() {
            const search = document.getElementById('contactSearchInput').value.toLowerCase();
            const items = document.querySelectorAll('#contactList .contact-item');

            items.forEach((item, idx) => {
                const contact = parsedContacts[idx];
                const searchText = (contact.fullName + ' ' + contact.company + ' ' + contact.email).toLowerCase();
                item.style.display = searchText.includes(search) ? '' : 'none';
            });
        }

        function selectContact(index) {
            const contact = parsedContacts[index];
            populateFormFromContact(contact);
            closeContactSelectModal();
            showImportSuccess('Contact imported: ' + (contact.company || contact.fullName || 'Unknown'));
        }

        function closeContactSelectModal() {
            document.getElementById('contactSelectModal').style.display = 'none';
        }

        // Populate form fields from contact
        function populateFormFromContact(contact) {
            // Site Name - prefer company, fallback to full name
            if (contact.company) {
                document.getElementById('siteName').value = contact.company;
            } else if (contact.fullName) {
                document.getElementById('siteName').value = contact.fullName;
            }

            // Contact Name
            document.getElementById('contactName').value = contact.fullName || '';

            // Email - prefer business email
            document.getElementById('contactEmail').value = contact.email || '';

            // Phones - main phone gets business phone or mobile
            document.getElementById('mainPhone').value = contact.businessPhone || contact.mainPhone || '';
            document.getElementById('cellPhone').value = contact.mobilePhone || '';

            // Address parsing
            if (contact.streetAddress) {
                // Try to split street number from street name
                const addrMatch = contact.streetAddress.match(/^(\d+[-/]?\d*)\s+(.+)$/);
                if (addrMatch) {
                    document.getElementById('streetNumber').value = addrMatch[1];
                    document.getElementById('streetName').value = addrMatch[2];
                } else {
                    document.getElementById('streetName').value = contact.streetAddress;
                }
            }

            document.getElementById('city').value = contact.city || '';
            document.getElementById('zip').value = contact.postalCode || '';

            // Country handling
            if (contact.country) {
                const normalizedCountry = normalizeCountry(contact.country);
                populateCountries(normalizedCountry);
                onCountryChange();
            }

            // State handling
            if (contact.state) {
                const countryVal = document.getElementById('country').value;
                if (isUnitedStates(countryVal)) {
                    // Try to match state abbreviation or name
                    const stateMatch = usStates.find(s =>
                        s.abbr.toLowerCase() === contact.state.toLowerCase() ||
                        s.name.toLowerCase() === contact.state.toLowerCase()
                    );
                    if (stateMatch) {
                        document.getElementById('state').value = stateMatch.abbr;
                    }
                } else {
                    document.getElementById('stateText').value = contact.state;
                }
            }

            // Notes - combine job title, department, and notes
            let notesArr = [];
            if (contact.jobTitle) notesArr.push('Title: ' + contact.jobTitle);
            if (contact.department) notesArr.push('Dept: ' + contact.department);
            if (contact.website) notesArr.push('Website: ' + contact.website);
            if (contact.fax) notesArr.push('Fax: ' + contact.fax);
            if (contact.email2) notesArr.push('Email 2: ' + contact.email2);
            if (contact.email3) notesArr.push('Email 3: ' + contact.email3);
            if (contact.notes) notesArr.push('Notes: ' + contact.notes);

            if (notesArr.length > 0) {
                document.getElementById('notes').value = notesArr.join('\n');
            }
        }

        // =========================================================
        // End Contact Import Functionality
        // =========================================================

        // Export/Import Functions
        async function exportSites() {
            try {
                const response = await fetch('/api/sites/export');
                const data = await response.json();
                const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = 'sites-export-' + new Date().toISOString().split('T')[0] + '.json';
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);
            } catch (e) {
                alert('Error exporting sites: ' + e.message);
            }
        }

        async function importSites(input) {
            if (!input.files || !input.files[0]) return;
            const file = input.files[0];
            const reader = new FileReader();
            reader.onload = async function(e) {
                try {
                    const content = e.target.result;
                    const result = await (await fetch('/api/sites/import', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: content
                    })).json();

                    if (result.success) {
                        let msg = 'Import complete!\n';
                        msg += 'Imported: ' + result.imported + '\n';
                        msg += 'Skipped (already exist): ' + result.skipped;
                        if (result.errors && result.errors.length > 0) {
                            msg += '\n\nErrors:\n' + result.errors.join('\n');
                        }
                        alert(msg);
                        loadSites();
                    } else {
                        alert('Import failed: ' + result.error);
                    }
                } catch (err) {
                    alert('Error importing sites: ' + err.message);
                }
            };
            reader.readAsText(file);
            input.value = ''; // Reset file input
        }

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
                            html += '<div class="urls" style="margin-top:10px;">';
                            s.URLs.forEach(u => {
                                const hasPassword = u.HasPassword === 1 || u.HasPassword === true;
                                const credIcon = hasPassword ? ' 🔐' : (u.Username ? ' 👤' : '');
                                html += '<a href="#" onclick="openProtocolUrl(\'' + escapeHtml(u.URL) + '\', ' + u.URLId + ', \'site\'); return false;" style="display:inline-block;margin-right:10px;margin-bottom:5px;padding:3px 8px;background:#f0f0f0;border-radius:3px;font-size:12px;">' + (u.Label || u.URL) + credIcon + '</a>';
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
            // Apply defaults for new site
            populateCountries('United States');
            populateStates('IL');
            populateTimezones('America/Chicago');
            onCountryChange();
            // Clear URLs section (URLs can only be added after site is saved)
            document.getElementById('urlsList').innerHTML = '<p style="color:#999;font-size:12px;">Save the site first, then edit to add URLs.</p>';
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
                document.getElementById('zip').value = s.Zip || '';
                document.getElementById('notes').value = s.Notes || '';

                // Populate dropdowns with existing values or defaults
                // Normalize country value (handles USA, US, etc.)
                const rawCountry = s.Country || 'United States';
                const existingCountry = normalizeCountry(rawCountry);
                const existingState = s.State || 'IL';
                const existingTimezone = s.Timezone || 'America/Chicago';

                populateCountries(existingCountry);
                populateStates(existingState);
                populateTimezones(existingTimezone);

                // Handle non-US countries - put state in text field
                const isUS = isUnitedStates(existingCountry);
                if (!isUS && s.State) {
                    document.getElementById('stateText').value = s.State;
                }
                onCountryChange();

                // Render URLs
                renderSiteUrls(s.URLs || []);

                document.getElementById('siteModal').style.display = 'block';
            }
        }

        async function saveSite(e) {
            e.preventDefault();
            const siteId = document.getElementById('editSiteId').value;
            const country = document.getElementById('country').value;
            const isUS = isUnitedStates(country);

            // Get state from the correct field based on country
            const stateValue = isUS
                ? document.getElementById('state').value
                : document.getElementById('stateText').value;

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
                state: stateValue,
                zip: document.getElementById('zip').value,
                country: country,
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

        // URL Management Functions
        function renderSiteUrls(urls) {
            const container = document.getElementById('urlsList');
            if (!urls || urls.length === 0) {
                container.innerHTML = '<p style="color:#999;font-size:12px;">No URLs added yet.</p>';
                return;
            }
            let html = '<table style="width:100%;font-size:12px;border-collapse:collapse;">';
            html += '<tr style="background:#f5f5f5;"><th style="padding:5px;text-align:left;">Label</th><th style="padding:5px;text-align:left;">URL</th><th style="padding:5px;text-align:left;">Username</th><th style="padding:5px;text-align:center;">Creds</th><th style="padding:5px;"></th></tr>';
            urls.forEach(u => {
                const hasPassword = u.HasPassword === 1 || u.HasPassword === true;
                html += '<tr style="border-bottom:1px solid #eee;">';
                html += '<td style="padding:5px;">' + (u.Label || '-') + '</td>';
                html += '<td style="padding:5px;"><a href="#" onclick="openProtocolUrl(\'' + escapeHtml(u.URL) + '\', ' + u.URLId + ', \'site\'); return false;">' + escapeHtml(u.URL) + '</a></td>';
                html += '<td style="padding:5px;">' + (u.Username || '-') + '</td>';
                html += '<td style="padding:5px;text-align:center;">' + (hasPassword ? '🔐' : '-') + '</td>';
                html += '<td style="padding:5px;"><button type="button" onclick="removeSiteUrl(' + u.URLId + ')" style="background:#dc3545;color:white;border:none;padding:3px 8px;border-radius:3px;cursor:pointer;font-size:11px;">×</button></td>';
                html += '</tr>';
            });
            html += '</table>';
            container.innerHTML = html;
        }

        function escapeHtml(text) {
            if (!text) return '';
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        async function addSiteUrl() {
            const siteId = document.getElementById('editSiteId').value;
            if (!siteId) {
                alert('Please save the site first before adding URLs.');
                return;
            }
            const url = document.getElementById('newUrlValue').value.trim();
            if (!url) {
                alert('URL is required');
                return;
            }
            const label = document.getElementById('newUrlLabel').value.trim();
            const username = document.getElementById('newUrlUsername').value.trim();
            const password = document.getElementById('newUrlPassword').value;

            const result = await (await fetch('/api/sites/urls/add', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ siteId, url, label, username, password })
            })).json();

            if (result.success) {
                // Clear inputs
                document.getElementById('newUrlValue').value = '';
                document.getElementById('newUrlLabel').value = '';
                document.getElementById('newUrlUsername').value = '';
                document.getElementById('newUrlPassword').value = '';
                // Reload site to get updated URLs
                const data = await (await fetch('/api/sites/' + siteId)).json();
                if (data.site && data.site.URLs) {
                    renderSiteUrls(data.site.URLs);
                }
            } else {
                alert('Error adding URL: ' + (result.error || 'Unknown error'));
            }
        }

        async function removeSiteUrl(urlId) {
            if (!confirm('Remove this URL?')) return;
            const siteId = document.getElementById('editSiteId').value;
            const result = await (await fetch('/api/sites/urls/delete', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ urlId })
            })).json();

            if (result.success) {
                const data = await (await fetch('/api/sites/' + siteId)).json();
                if (data.site) {
                    renderSiteUrls(data.site.URLs || []);
                }
            } else {
                alert('Error removing URL: ' + (result.error || 'Unknown error'));
            }
        }

        // Protocol-aware URL opening
        function openProtocolUrl(url, urlId, type) {
            const protocol = url.split(':')[0].toLowerCase();
            if (protocol === 'http' || protocol === 'https') {
                window.open(url, '_blank');
            } else if (protocol === 'smb' || protocol === 'file') {
                // For SMB/file shares, try to open in Explorer
                // Note: This may not work in all browsers due to security restrictions
                window.location.href = url;
            } else if (protocol === 'ftp' || protocol === 'sftp') {
                window.open(url, '_blank');
            } else if (protocol === 'rdp') {
                // For RDP, we could potentially generate an .rdp file
                alert('RDP connections should be opened using Remote Desktop Connection.\nHost: ' + url.replace('rdp://', ''));
            } else if (protocol === 'ssh') {
                alert('SSH connections should be opened using an SSH client.\nHost: ' + url.replace('ssh://', ''));
            } else {
                // Default: try to open with OS handler
                window.location.href = url;
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

function Get-SitesAndDevicesPageHTML {
    # Get sites for dropdown in Add Device modal
    $sitesQuery = "SELECT SiteId, Name FROM Sites ORDER BY Name"
    $sites = Invoke-SqliteQuery -DataSource $DatabasePath -Query $sitesQuery
    $siteOptions = "<option value=''>-- Select a Site --</option>`n"
    foreach ($site in $sites) {
        $siteOptions += "<option value='$($site.SiteId)'>$($site.Name)</option>`n"
    }
    $hasSites = if ($sites -and @($sites).Count -gt 0) { "true" } else { "false" }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sites and Devices - myTech.Today RMM</title>
    <link rel="stylesheet" href="/styles.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🖥️</text></svg>">
    <style>
        /* Site Card Styles */
        .site-section { background: white; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); overflow: hidden; }
        .site-header { display: flex; justify-content: space-between; align-items: center; padding: 15px 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; cursor: pointer; user-select: none; }
        .site-header:hover { background: linear-gradient(135deg, #5a6fd6 0%, #6a4190 100%); }
        .site-header h3 { margin: 0; display: flex; align-items: center; gap: 10px; }
        .site-header .site-info { font-size: 12px; opacity: 0.9; margin-top: 3px; }
        .site-header .site-actions { display: flex; gap: 8px; align-items: center; }
        .site-header .device-count { background: rgba(255,255,255,0.2); padding: 4px 10px; border-radius: 12px; font-size: 12px; }
        .site-header .collapse-icon { font-size: 18px; transition: transform 0.2s; }
        .site-header.collapsed .collapse-icon { transform: rotate(-90deg); }
        .site-content { padding: 0; max-height: 2000px; overflow: hidden; transition: max-height 0.3s ease-out, padding 0.3s; }
        .site-content.collapsed { max-height: 0; padding: 0; }
        .site-content-inner { padding: 15px 20px; }

        /* Site Info Bar */
        .site-info-bar { display: flex; flex-wrap: wrap; gap: 15px; padding: 10px 0; border-bottom: 1px solid #eee; margin-bottom: 15px; font-size: 13px; color: #666; }
        .site-info-bar .info-item { display: flex; align-items: center; gap: 5px; }
        .site-info-bar .info-item strong { color: #333; }

        /* Device Table */
        .device-table { width: 100%; border-collapse: collapse; }
        .device-table th { background: #f8f9fa; padding: 10px; text-align: left; border-bottom: 2px solid #dee2e6; cursor: pointer; white-space: nowrap; }
        .device-table th:hover { background: #e9ecef; }
        .device-table th .sort-icon { margin-left: 5px; opacity: 0.3; }
        .device-table th.sorted .sort-icon { opacity: 1; }
        .device-table td { padding: 10px; border-bottom: 1px solid #eee; }
        .device-table tr:hover { background: #f8f9fa; }
        .device-table .hostname-link { color: #667eea; text-decoration: none; font-weight: 500; }
        .device-table .hostname-link:hover { text-decoration: underline; }

        /* Action Buttons */
        .btn-sm { padding: 5px 10px; font-size: 12px; border: none; border-radius: 4px; cursor: pointer; margin-right: 5px; }
        .btn-edit { background: #17a2b8; color: white; }
        .btn-delete { background: #dc3545; color: white; }
        .btn-action { background: #667eea; color: white; }
        .btn-primary { background: #667eea; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; }
        .btn-secondary { background: #6c757d; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; }

        /* Header Controls */
        .page-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; flex-wrap: wrap; gap: 15px; }
        .page-header h2 { margin: 0; }
        .header-actions { display: flex; gap: 10px; flex-wrap: wrap; align-items: center; }

        /* Button Groups for logical separation */
        .btn-group { display: flex; gap: 5px; padding: 5px 10px; background: #f8f9fa; border-radius: 5px; border: 1px solid #e9ecef; }
        .btn-group-label { font-size: 11px; color: #666; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 3px; display: block; }
        .btn-group-wrapper { display: flex; flex-direction: column; align-items: flex-start; }

        /* Sort Sites Control */
        .sort-control { display: flex; align-items: center; gap: 10px; background: #f8f9fa; padding: 8px 15px; border-radius: 5px; }
        .sort-control label { font-size: 13px; color: #666; }
        .sort-control select { padding: 5px 10px; border: 1px solid #ddd; border-radius: 4px; }

        /* Expand/Collapse All */
        .toggle-all-btn { background: #f8f9fa; border: 1px solid #ddd; padding: 8px 15px; border-radius: 5px; cursor: pointer; font-size: 13px; }
        .toggle-all-btn:hover { background: #e9ecef; }

        /* Import/Export buttons */
        .btn-import { background: #28a745; color: white; }
        .btn-import:hover { background: #218838; }
        .btn-export { background: #6c757d; color: white; }
        .btn-export:hover { background: #5a6268; }
        .btn-export:disabled, .btn-import:disabled { opacity: 0.5; cursor: not-allowed; }

        /* Site section header action bar */
        .site-action-bar { display: flex; justify-content: space-between; align-items: center; padding: 10px 0; border-bottom: 1px solid #eee; margin-bottom: 15px; }
        .site-action-group { display: flex; gap: 8px; align-items: center; }
        .site-action-group .group-label { font-size: 11px; color: #888; text-transform: uppercase; margin-right: 5px; }

        /* Hidden file input for import */
        .hidden-file-input { display: none; }

        /* Modal Styles */
        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 1000; }
        .modal.active { display: flex; justify-content: center; align-items: center; }
        .modal-content { background: white; padding: 30px; border-radius: 10px; max-width: 800px; width: 90%; max-height: 85vh; overflow-y: auto; }
        .modal-content h3 { margin-top: 0; }
        .form-group { margin-bottom: 15px; }
        .form-group label { display: block; margin-bottom: 5px; font-weight: bold; }
        .form-group input, .form-group select, .form-group textarea { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; }
        .form-row { display: flex; gap: 15px; }
        .form-row .form-group { flex: 1; }
        .btn-row { display: flex; gap: 10px; margin-top: 20px; }
        .btn-cancel { background: #6c757d; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; }

        /* Site Form Styles */
        .site-form { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; }
        .site-form .full-width { grid-column: 1 / -1; }
        .site-form label { display: block; margin-bottom: 5px; font-weight: bold; color: #555; font-size: 12px; }
        .site-form input, .site-form textarea, .site-form select { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; }

        /* Pairing section */
        .pairing-section { background: #f8f9fa; padding: 15px; border-radius: 8px; margin-bottom: 15px; border: 2px dashed #667eea; }
        .pairing-code { font-size: 32px; font-family: monospace; letter-spacing: 5px; text-align: center; color: #667eea; font-weight: bold; }
        .pairing-timer { text-align: center; font-size: 14px; color: #666; margin-top: 5px; }
        .pairing-timer.expired { color: #dc3545; font-weight: bold; }

        /* No devices message */
        .no-devices { padding: 20px; text-align: center; color: #666; font-style: italic; }

        /* Loading state */
        .loading { text-align: center; padding: 40px; color: #666; }

        /* URLs display */
        .site-urls { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 10px; }
        .site-urls a { display: inline-block; padding: 3px 8px; background: #e9ecef; border-radius: 3px; font-size: 12px; color: #667eea; text-decoration: none; }
        .site-urls a:hover { background: #dee2e6; }
    </style>
</head>
<body>
    <header>
        <div class="header-left">
            <h1>myTech.Today RMM Dashboard</h1>
            <nav>
                <a href="/">Dashboard</a>
                <a href="/sites-and-devices" class="active">Sites &amp; Devices</a>
                <a href="/alerts">Alerts</a>
                <a href="/actions">Actions</a>
                <a href="/reports">Reports</a>
                <a href="/settings">Settings</a>
            </nav>
        </div>
        <button class="readme-btn" onclick="openReadme()" title="View Documentation">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
            Readme
        </button>
    </header>

    <main>
        <div class="panel">
            <div class="page-header">
                <h2>Sites &amp; Devices</h2>
                <div class="header-actions">
                    <div class="sort-control">
                        <label>Sort Sites:</label>
                        <select id="siteSortOrder" onchange="sortSites()">
                            <option value="name-asc">Name (A-Z)</option>
                            <option value="name-desc">Name (Z-A)</option>
                            <option value="devices-desc">Most Devices</option>
                            <option value="devices-asc">Fewest Devices</option>
                        </select>
                    </div>
                    <button class="toggle-all-btn" onclick="toggleAllSites()" title="Expand or collapse all site sections">
                        <span id="toggleAllText">Collapse All</span>
                    </button>
                    <!-- Site Actions Group -->
                    <div class="btn-group" title="Site management actions">
                        <button class="btn-sm btn-primary" onclick="openAddSiteModal()" title="Create a new site">+ Add Site</button>
                        <button class="btn-sm btn-import" onclick="triggerSiteImport()" title="Import sites from JSON file">↑ Import</button>
                        <button class="btn-sm btn-export" id="exportSitesBtn" onclick="exportAllSites()" title="Export all sites to JSON file">↓ Export</button>
                    </div>
                    <!-- Global Add Device (prompts for site selection) -->
                    <button class="btn-primary" onclick="openAddDeviceModal()" title="Add a new device (select site in the form)">+ Add Device</button>
                </div>
                <!-- Hidden file inputs for import functionality -->
                <input type="file" id="siteImportInput" class="hidden-file-input" accept=".json" onchange="handleSiteImport(event)">
                <input type="file" id="deviceImportInput" class="hidden-file-input" accept=".json" onchange="handleDeviceImport(event)">
            </div>
            <div id="sites-devices-list" class="loading">Loading sites and devices...</div>
        </div>
    </main>

    <!-- Add Site Modal -->
    <div id="siteModal" class="modal">
        <div class="modal-content">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:15px;">
                <h3 id="siteModalTitle" style="margin:0;">Add New Site</h3>
                <label class="btn-import-contact" style="padding:6px 12px;background:#17a2b8;color:white;border-radius:5px;cursor:pointer;font-size:13px;" title="Import contact from CSV, VCF, or other contact file">
                    📇 Import Contact
                    <input type="file" id="importContactFile" accept=".csv,.vcf,.contact,.ldif,.wab" style="display:none;" onchange="importContactFile(this)">
                </label>
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
                        <label>Country</label>
                        <select id="country" onchange="onCountryChange()"></select>
                    </div>
                    <div id="stateWrapper">
                        <label id="stateLabel">State</label>
                        <select id="state"></select>
                        <input type="text" id="stateText" placeholder="Province/Region" style="display:none;">
                    </div>
                    <div>
                        <label>ZIP/Postal Code</label>
                        <input type="text" id="zip">
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
                <div class="btn-row">
                    <button type="submit" class="btn-primary">Save Site</button>
                    <button type="button" class="btn-cancel" onclick="closeSiteModal()">Cancel</button>
                </div>
            </form>
        </div>
    </div>

    <!-- Add Device Modal -->
    <div id="addDeviceModal" class="modal">
        <div class="modal-content">
            <h3>Add New Device</h3>
            <div class="pairing-section">
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;">
                    <strong>Client Pairing Code</strong>
                    <button type="button" class="btn-sm btn-action" onclick="generatePairingCode()">Generate Code</button>
                </div>
                <div class="pairing-code" id="pairingCode">------</div>
                <div class="pairing-timer" id="pairingTimer">Click Generate to create a 10-minute code</div>
            </div>
            <form id="addDeviceForm" onsubmit="submitAddDevice(event)">
                <div class="form-row">
                    <div class="form-group">
                        <label for="hostname">Hostname *</label>
                        <input type="text" id="hostname" name="hostname" required placeholder="e.g., SERVER01">
                    </div>
                    <div class="form-group">
                        <label for="ipAddress">IP Address</label>
                        <input type="text" id="ipAddress" name="ipAddress" placeholder="e.g., 192.168.1.10">
                    </div>
                </div>
                <div class="form-row">
                    <div class="form-group">
                        <label for="siteId">Site *</label>
                        <select id="siteId" name="siteId" required>
                            $siteOptions
                        </select>
                        <div id="siteRequiredMsg" style="display:none;color:#dc3545;font-size:12px;margin-top:5px;">
                            Please select a site for this device.
                        </div>
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
                    <button type="button" class="btn-cancel" onclick="closeDeviceModal()">Cancel</button>
                </div>
            </form>
        </div>
    </div>

    <!-- Delete Site Options Modal -->
    <div id="deleteOptionsModal" class="modal">
        <div class="modal-content" style="max-width:500px;">
            <h3 id="deleteModalTitle">Delete Site</h3>
            <div style="padding:10px 0;">
                <p id="deviceCountInfo" style="background:#fff3cd;padding:15px;border-radius:5px;border-left:4px solid #ffc107;margin-bottom:20px;"></p>
                <p><strong>What would you like to do?</strong></p>
                <div style="margin:15px 0;">
                    <select id="deleteOption" onchange="onDeleteOptionChange()" style="width:100%;padding:10px;font-size:14px;">
                        <option value="">-- Select an option --</option>
                        <option value="deleteall">Delete site AND all devices</option>
                        <option value="reassign">Move devices to another site</option>
                    </select>
                </div>
                <div id="reassignSection" style="display:none;margin:15px 0;padding:15px;background:#f8f9fa;border-radius:5px;">
                    <label><strong>Select destination site:</strong></label>
                    <select id="reassignSiteId" style="width:100%;padding:10px;margin-top:8px;font-size:14px;">
                        <option value="">-- Select a site --</option>
                    </select>
                </div>
                <div class="btn-row">
                    <button type="button" class="btn-delete" onclick="confirmDeleteWithOption()">Delete Site</button>
                    <button type="button" class="btn-cancel" onclick="closeDeleteOptionsModal()">Cancel</button>
                </div>
            </div>
        </div>
    </div>

    <!-- Contact Selection Modal (for multi-contact files) -->
    <div id="contactSelectModal" class="modal">
        <div class="modal-content" style="max-width:600px;">
            <h3>Select a Contact</h3>
            <div style="margin-bottom:15px;">
                <input type="text" id="contactSearchInput" placeholder="Search by name, company, or email..."
                       style="width:100%;padding:10px;font-size:14px;border:1px solid #ddd;border-radius:5px;"
                       oninput="filterContactList()">
            </div>
            <div id="contactListContainer" style="max-height:350px;overflow-y:auto;border:1px solid #eee;border-radius:5px;">
                <!-- Contact list will be populated here -->
            </div>
            <div class="btn-row" style="margin-top:15px;">
                <button type="button" class="btn-cancel" onclick="closeContactSelectModal()">Cancel</button>
            </div>
        </div>
    </div>

    <footer>
        <p>&copy; 2025 myTech.Today RMM - Powered by PowerShell</p>
    </footer>

    <script src="/app.js"></script>
    <script>
        // Global state
        let sitesData = [];
        let allExpanded = true;
        let pairingInterval = null;
        let pairingExpiry = null;
        window.deletingSiteId = null;
        let parsedContacts = []; // Holds contacts from imported file

        // Country and state data
        const countries = ['United States', 'Afghanistan', 'Albania', 'Algeria', 'Andorra', 'Angola', 'Argentina', 'Armenia', 'Australia', 'Austria', 'Azerbaijan', 'Bahamas', 'Bahrain', 'Bangladesh', 'Barbados', 'Belarus', 'Belgium', 'Belize', 'Benin', 'Bhutan', 'Bolivia', 'Bosnia and Herzegovina', 'Botswana', 'Brazil', 'Brunei', 'Bulgaria', 'Burkina Faso', 'Burundi', 'Cambodia', 'Cameroon', 'Canada', 'Central African Republic', 'Chad', 'Chile', 'China', 'Colombia', 'Comoros', 'Congo', 'Costa Rica', 'Croatia', 'Cuba', 'Cyprus', 'Czech Republic', 'Denmark', 'Djibouti', 'Dominica', 'Dominican Republic', 'Ecuador', 'Egypt', 'El Salvador', 'Equatorial Guinea', 'Eritrea', 'Estonia', 'Eswatini', 'Ethiopia', 'Fiji', 'Finland', 'France', 'Gabon', 'Gambia', 'Georgia', 'Germany', 'Ghana', 'Greece', 'Grenada', 'Guatemala', 'Guinea', 'Guinea-Bissau', 'Guyana', 'Haiti', 'Honduras', 'Hungary', 'Iceland', 'India', 'Indonesia', 'Iran', 'Iraq', 'Ireland', 'Israel', 'Italy', 'Jamaica', 'Japan', 'Jordan', 'Kazakhstan', 'Kenya', 'Kiribati', 'Korea North', 'Korea South', 'Kuwait', 'Kyrgyzstan', 'Laos', 'Latvia', 'Lebanon', 'Lesotho', 'Liberia', 'Libya', 'Liechtenstein', 'Lithuania', 'Luxembourg', 'Madagascar', 'Malawi', 'Malaysia', 'Maldives', 'Mali', 'Malta', 'Marshall Islands', 'Mauritania', 'Mauritius', 'Mexico', 'Micronesia', 'Moldova', 'Monaco', 'Mongolia', 'Montenegro', 'Morocco', 'Mozambique', 'Myanmar', 'Namibia', 'Nauru', 'Nepal', 'Netherlands', 'New Zealand', 'Nicaragua', 'Niger', 'Nigeria', 'North Macedonia', 'Norway', 'Oman', 'Pakistan', 'Palau', 'Palestine', 'Panama', 'Papua New Guinea', 'Paraguay', 'Peru', 'Philippines', 'Poland', 'Portugal', 'Qatar', 'Romania', 'Russia', 'Rwanda', 'Saint Kitts and Nevis', 'Saint Lucia', 'Saint Vincent and the Grenadines', 'Samoa', 'San Marino', 'Sao Tome and Principe', 'Saudi Arabia', 'Senegal', 'Serbia', 'Seychelles', 'Sierra Leone', 'Singapore', 'Slovakia', 'Slovenia', 'Solomon Islands', 'Somalia', 'South Africa', 'South Sudan', 'Spain', 'Sri Lanka', 'Sudan', 'Suriname', 'Sweden', 'Switzerland', 'Syria', 'Taiwan', 'Tajikistan', 'Tanzania', 'Thailand', 'Timor-Leste', 'Togo', 'Tonga', 'Trinidad and Tobago', 'Tunisia', 'Turkey', 'Turkmenistan', 'Tuvalu', 'Uganda', 'Ukraine', 'United Arab Emirates', 'United Kingdom', 'Uruguay', 'Uzbekistan', 'Vanuatu', 'Vatican City', 'Venezuela', 'Vietnam', 'Yemen', 'Zambia', 'Zimbabwe'];
        const usStates = [{name:'Alabama',abbr:'AL'},{name:'Alaska',abbr:'AK'},{name:'Arizona',abbr:'AZ'},{name:'Arkansas',abbr:'AR'},{name:'California',abbr:'CA'},{name:'Colorado',abbr:'CO'},{name:'Connecticut',abbr:'CT'},{name:'Delaware',abbr:'DE'},{name:'Florida',abbr:'FL'},{name:'Georgia',abbr:'GA'},{name:'Hawaii',abbr:'HI'},{name:'Idaho',abbr:'ID'},{name:'Illinois',abbr:'IL'},{name:'Indiana',abbr:'IN'},{name:'Iowa',abbr:'IA'},{name:'Kansas',abbr:'KS'},{name:'Kentucky',abbr:'KY'},{name:'Louisiana',abbr:'LA'},{name:'Maine',abbr:'ME'},{name:'Maryland',abbr:'MD'},{name:'Massachusetts',abbr:'MA'},{name:'Michigan',abbr:'MI'},{name:'Minnesota',abbr:'MN'},{name:'Mississippi',abbr:'MS'},{name:'Missouri',abbr:'MO'},{name:'Montana',abbr:'MT'},{name:'Nebraska',abbr:'NE'},{name:'Nevada',abbr:'NV'},{name:'New Hampshire',abbr:'NH'},{name:'New Jersey',abbr:'NJ'},{name:'New Mexico',abbr:'NM'},{name:'New York',abbr:'NY'},{name:'North Carolina',abbr:'NC'},{name:'North Dakota',abbr:'ND'},{name:'Ohio',abbr:'OH'},{name:'Oklahoma',abbr:'OK'},{name:'Oregon',abbr:'OR'},{name:'Pennsylvania',abbr:'PA'},{name:'Rhode Island',abbr:'RI'},{name:'South Carolina',abbr:'SC'},{name:'South Dakota',abbr:'SD'},{name:'Tennessee',abbr:'TN'},{name:'Texas',abbr:'TX'},{name:'Utah',abbr:'UT'},{name:'Vermont',abbr:'VT'},{name:'Virginia',abbr:'VA'},{name:'Washington',abbr:'WA'},{name:'West Virginia',abbr:'WV'},{name:'Wisconsin',abbr:'WI'},{name:'Wyoming',abbr:'WY'}];
        const timezones = [{value:'America/Chicago',label:'(UTC-06:00) Central Time'},{value:'America/New_York',label:'(UTC-05:00) Eastern Time'},{value:'America/Denver',label:'(UTC-07:00) Mountain Time'},{value:'America/Los_Angeles',label:'(UTC-08:00) Pacific Time'},{value:'America/Anchorage',label:'(UTC-09:00) Alaska Time'},{value:'Pacific/Honolulu',label:'(UTC-10:00) Hawaii Time'},{value:'UTC',label:'(UTC+00:00) UTC'},{value:'Europe/London',label:'(UTC+00:00) London'},{value:'Europe/Paris',label:'(UTC+01:00) Paris, Berlin'},{value:'Asia/Tokyo',label:'(UTC+09:00) Tokyo'},{value:'Australia/Sydney',label:'(UTC+10:00) Sydney'}];

        // Initialize on page load
        document.addEventListener('DOMContentLoaded', loadSitesAndDevices);

        async function loadSitesAndDevices() {
            try {
                const [sitesRes, devicesRes] = await Promise.all([
                    fetch('/api/sites').then(r => r.json()),
                    fetch('/api/devices').then(r => r.json())
                ]);

                const sites = sitesRes.sites || [];
                const devices = devicesRes.devices || [];

                // Group devices by SiteId
                const devicesBySite = {};
                devices.forEach(d => {
                    const siteId = d.SiteId || 'unassigned';
                    if (!devicesBySite[siteId]) devicesBySite[siteId] = [];
                    devicesBySite[siteId].push(d);
                });

                // Attach device counts to sites
                sitesData = sites.map(s => ({
                    ...s,
                    devices: devicesBySite[s.SiteId] || [],
                    deviceCount: (devicesBySite[s.SiteId] || []).length
                }));

                // Add unassigned devices as a virtual site if any exist
                if (devicesBySite['unassigned'] && devicesBySite['unassigned'].length > 0) {
                    sitesData.push({
                        SiteId: 'unassigned',
                        Name: '(Unassigned Devices)',
                        devices: devicesBySite['unassigned'],
                        deviceCount: devicesBySite['unassigned'].length,
                        isVirtual: true
                    });
                }

                sortSites();
            } catch (e) {
                console.error('Error loading sites and devices:', e);
                document.getElementById('sites-devices-list').innerHTML = '<p style="color:red;">Error loading data: ' + e.message + '</p>';
            }
        }

        function sortSites() {
            const sortOrder = document.getElementById('siteSortOrder').value;

            sitesData.sort((a, b) => {
                // Always keep unassigned at the bottom
                if (a.isVirtual) return 1;
                if (b.isVirtual) return -1;

                switch(sortOrder) {
                    case 'name-asc':
                        return a.Name.localeCompare(b.Name);
                    case 'name-desc':
                        return b.Name.localeCompare(a.Name);
                    case 'devices-desc':
                        return b.deviceCount - a.deviceCount;
                    case 'devices-asc':
                        return a.deviceCount - b.deviceCount;
                    default:
                        return a.Name.localeCompare(b.Name);
                }
            });

            renderSitesAndDevices();
        }

        function renderSitesAndDevices() {
            const container = document.getElementById('sites-devices-list');

            if (sitesData.length === 0) {
                container.innerHTML = '<p style="text-align:center;padding:40px;color:#666;">No sites found. Click "+ Add Site" to create your first site.</p>';
                return;
            }

            let html = '';
            sitesData.forEach((site, index) => {
                const collapsedClass = allExpanded ? '' : 'collapsed';
                const isLargeSite = site.deviceCount > 20;
                const autoCollapse = isLargeSite && index > 0 ? 'collapsed' : collapsedClass;

                html += '<div class="site-section" data-site-id="' + site.SiteId + '" data-device-count="' + site.deviceCount + '">';
                html += '<div class="site-header ' + autoCollapse + '" onclick="toggleSite(\'' + site.SiteId + '\')">';
                html += '<div><h3><span class="collapse-icon">▼</span> ' + escapeHtml(site.Name) + '</h3>';

                // Site info line
                if (!site.isVirtual && (site.City || site.ContactName)) {
                    let infoLine = [];
                    if (site.City) infoLine.push(site.City + (site.State ? ', ' + site.State : ''));
                    if (site.ContactName) infoLine.push('📞 ' + site.ContactName);
                    html += '<div class="site-info">' + infoLine.join(' | ') + '</div>';
                }
                html += '</div>';

                html += '<div class="site-actions">';
                html += '<span class="device-count">' + site.deviceCount + ' device' + (site.deviceCount !== 1 ? 's' : '') + '</span>';
                html += '</div></div>';

                html += '<div class="site-content ' + autoCollapse + '">';
                html += '<div class="site-content-inner">';

                // Site action bar with grouped controls
                html += '<div class="site-action-bar">';

                // Left side: Site-level actions
                html += '<div class="site-action-group">';
                html += '<span class="group-label">Site:</span>';
                if (!site.isVirtual) {
                    html += '<button class="btn-sm btn-edit" onclick="editSite(\'' + site.SiteId + '\')" title="Edit site properties">✏️ Edit</button>';
                    html += '<button class="btn-sm btn-export" onclick="exportSite(\'' + site.SiteId + '\', \'' + escapeHtml(site.Name) + '\')" title="Export this site and its devices">↓ Export</button>';
                    html += '<button class="btn-sm btn-delete" onclick="deleteSite(\'' + site.SiteId + '\', \'' + escapeHtml(site.Name) + '\', ' + site.deviceCount + ')" title="Delete this site">🗑️ Delete</button>';
                }
                html += '</div>';

                // Right side: Device-level actions (scoped to this site)
                html += '<div class="site-action-group">';
                html += '<span class="group-label">Devices:</span>';
                if (!site.isVirtual) {
                    html += '<button class="btn-sm btn-primary" onclick="openAddDeviceModalForSite(\'' + site.SiteId + '\', \'' + escapeHtml(site.Name) + '\')" title="Add a new device to this site">+ Add Device</button>';
                    html += '<button class="btn-sm btn-import" onclick="triggerDeviceImportForSite(\'' + site.SiteId + '\', \'' + escapeHtml(site.Name) + '\')" title="Import devices into this site">↑ Import</button>';
                }
                const hasDevices = site.deviceCount > 0;
                html += '<button class="btn-sm btn-export" onclick="exportSiteDevices(\'' + site.SiteId + '\', \'' + escapeHtml(site.Name) + '\')" ' + (hasDevices ? '' : 'disabled') + ' title="' + (hasDevices ? 'Export devices from this site' : 'No devices to export') + '">↓ Export</button>';
                html += '</div>';

                html += '</div>';

                // Site info bar (contact, address, etc.)
                if (!site.isVirtual) {
                    let hasInfo = site.ContactEmail || site.MainPhone || site.StreetName;
                    if (hasInfo) {
                        html += '<div class="site-info-bar">';
                        if (site.ContactEmail) html += '<div class="info-item">📧 <a href="mailto:' + site.ContactEmail + '">' + site.ContactEmail + '</a></div>';
                        if (site.MainPhone) html += '<div class="info-item">📞 ' + site.MainPhone + '</div>';
                        if (site.CellPhone) html += '<div class="info-item">📱 ' + site.CellPhone + '</div>';
                        if (site.StreetName) {
                            let addr = [site.StreetNumber, site.StreetName].filter(x => x).join(' ');
                            html += '<div class="info-item">📍 ' + addr + '</div>';
                        }
                        html += '</div>';
                    }
                }

                // Devices table
                if (site.devices.length === 0) {
                    html += '<div class="no-devices">No devices in this site. Click "+ Add Device" above to add your first device.</div>';
                } else {
                    html += renderDeviceTable(site.SiteId, site.devices);
                }

                html += '</div></div></div>';
            });

            container.innerHTML = html;
        }

        function renderDeviceTable(siteId, devices) {
            let html = '<table class="device-table" data-site-id="' + siteId + '">';
            html += '<thead><tr>';
            html += '<th onclick="sortTable(\'' + siteId + '\', 0)">Hostname <span class="sort-icon">↕</span></th>';
            html += '<th onclick="sortTable(\'' + siteId + '\', 1)">IP Address <span class="sort-icon">↕</span></th>';
            html += '<th onclick="sortTable(\'' + siteId + '\', 2)">Type <span class="sort-icon">↕</span></th>';
            html += '<th onclick="sortTable(\'' + siteId + '\', 3)">Status <span class="sort-icon">↕</span></th>';
            html += '<th onclick="sortTable(\'' + siteId + '\', 4)">Last Seen <span class="sort-icon">↕</span></th>';
            html += '<th onclick="sortTable(\'' + siteId + '\', 5)">OS <span class="sort-icon">↕</span></th>';
            html += '<th>Actions</th>';
            html += '</tr></thead><tbody>';

            // Sort by hostname by default
            devices.sort((a, b) => (a.Hostname || '').localeCompare(b.Hostname || ''));

            devices.forEach(d => {
                const statusClass = d.Status === 'Online' ? 'success' : (d.Status === 'Warning' ? 'warning' : 'danger');
                html += '<tr>';
                html += '<td><a href="/devices/' + d.DeviceId + '" class="hostname-link">' + escapeHtml(d.Hostname || 'Unknown') + '</a></td>';
                html += '<td>' + (d.IPAddress || 'N/A') + '</td>';
                html += '<td>' + (d.DeviceType || 'Unknown') + '</td>';
                html += '<td><span class="badge badge-' + statusClass + '">' + (d.Status || 'Unknown') + '</span></td>';
                html += '<td>' + formatLastSeen(d.LastSeen) + '</td>';
                html += '<td>' + (d.OSName || 'Unknown') + '</td>';
                html += '<td>';
                html += '<button class="btn-sm btn-action" onclick="executeDeviceAction(\'' + d.DeviceId + '\', \'HealthCheck\')">Check</button>';
                html += '<button class="btn-sm btn-delete" onclick="deleteDevice(\'' + d.DeviceId + '\', \'' + escapeHtml(d.Hostname || '') + '\')">Delete</button>';
                html += '</td></tr>';
            });

            html += '</tbody></table>';
            return html;
        }

        function formatLastSeen(lastSeen) {
            if (!lastSeen) return 'Never';
            try {
                const date = new Date(lastSeen);
                const now = new Date();
                const diffMs = now - date;
                const diffMins = Math.floor(diffMs / 60000);
                if (diffMins < 1) return 'Just now';
                if (diffMins < 60) return diffMins + 'm ago';
                const diffHours = Math.floor(diffMins / 60);
                if (diffHours < 24) return diffHours + 'h ago';
                const diffDays = Math.floor(diffHours / 24);
                if (diffDays < 7) return diffDays + 'd ago';
                return date.toLocaleDateString();
            } catch (e) {
                return lastSeen;
            }
        }

        function toggleSite(siteId) {
            const section = document.querySelector('.site-section[data-site-id="' + siteId + '"]');
            const header = section.querySelector('.site-header');
            const content = section.querySelector('.site-content');
            header.classList.toggle('collapsed');
            content.classList.toggle('collapsed');
        }

        function toggleAllSites() {
            allExpanded = !allExpanded;
            document.querySelectorAll('.site-section').forEach(section => {
                const header = section.querySelector('.site-header');
                const content = section.querySelector('.site-content');
                if (allExpanded) {
                    header.classList.remove('collapsed');
                    content.classList.remove('collapsed');
                } else {
                    header.classList.add('collapsed');
                    content.classList.add('collapsed');
                }
            });
            document.getElementById('toggleAllText').textContent = allExpanded ? 'Collapse All' : 'Expand All';
        }

        function sortTable(siteId, colIndex) {
            const table = document.querySelector('.device-table[data-site-id="' + siteId + '"]');
            const tbody = table.querySelector('tbody');
            const rows = Array.from(tbody.querySelectorAll('tr'));
            const th = table.querySelectorAll('th')[colIndex];

            // Determine sort direction
            const isAsc = !th.classList.contains('sorted-asc');

            // Clear all sorted classes
            table.querySelectorAll('th').forEach(h => {
                h.classList.remove('sorted', 'sorted-asc', 'sorted-desc');
            });

            th.classList.add('sorted', isAsc ? 'sorted-asc' : 'sorted-desc');

            rows.sort((a, b) => {
                let aVal = a.cells[colIndex].textContent.trim();
                let bVal = b.cells[colIndex].textContent.trim();

                // Handle numeric values
                if (!isNaN(aVal) && !isNaN(bVal)) {
                    return isAsc ? aVal - bVal : bVal - aVal;
                }

                return isAsc ? aVal.localeCompare(bVal) : bVal.localeCompare(aVal);
            });

            rows.forEach(row => tbody.appendChild(row));
        }

        function escapeHtml(text) {
            if (!text) return '';
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        // Site Modal Functions
        function openAddSiteModal() {
            document.getElementById('siteModalTitle').textContent = 'Add New Site';
            document.getElementById('siteForm').reset();
            document.getElementById('editSiteId').value = '';
            populateCountries('United States');
            populateStates('IL');
            populateTimezones('America/Chicago');
            onCountryChange();
            document.getElementById('siteModal').classList.add('active');
        }

        function closeSiteModal() {
            document.getElementById('siteModal').classList.remove('active');
        }

        // ===== CONTACT IMPORT FUNCTIONS =====

        function closeContactSelectModal() {
            document.getElementById('contactSelectModal').classList.remove('active');
            parsedContacts = [];
        }

        function filterContactList() {
            const search = document.getElementById('contactSearchInput').value.toLowerCase();
            const items = document.querySelectorAll('.contact-list-item');
            items.forEach(item => {
                const text = item.textContent.toLowerCase();
                item.style.display = text.includes(search) ? '' : 'none';
            });
        }

        async function importContactFile(input) {
            if (!input.files || !input.files[0]) return;
            const file = input.files[0];
            const ext = file.name.split('.').pop().toLowerCase();

            try {
                const content = await file.text();
                let contacts = [];

                if (ext === 'csv') {
                    contacts = parseCSVContacts(content);
                } else if (ext === 'vcf') {
                    contacts = parseVCardContacts(content);
                } else if (ext === 'ldif') {
                    contacts = parseLDIFContacts(content);
                } else if (ext === 'contact') {
                    contacts = parseWindowsContact(content);
                } else {
                    alert('Unsupported file format: .' + ext + '\n\nSupported formats: .csv, .vcf, .ldif, .contact');
                    input.value = '';
                    return;
                }

                if (contacts.length === 0) {
                    alert('No contacts found in the file.');
                    input.value = '';
                    return;
                }

                if (contacts.length === 1) {
                    // Auto-populate with the single contact
                    applyContactToSiteForm(contacts[0]);
                } else {
                    // Show selection modal
                    parsedContacts = contacts;
                    showContactSelectionModal(contacts);
                }
            } catch (err) {
                alert('Error parsing contact file: ' + err.message);
            }

            input.value = ''; // Reset file input
        }

        function showContactSelectionModal(contacts) {
            const container = document.getElementById('contactListContainer');
            let html = '';

            contacts.forEach((c, idx) => {
                const name = c.contactName || c.company || 'Unknown';
                const company = c.company || '';
                const email = c.email || '';
                const phone = c.mainPhone || c.cellPhone || '';

                html += '<div class="contact-list-item" onclick="selectContact(' + idx + ')" ' +
                        'style="padding:12px;border-bottom:1px solid #eee;cursor:pointer;transition:background 0.2s;" ' +
                        'onmouseover="this.style.background=\'#f0f7ff\'" onmouseout="this.style.background=\'white\'">' +
                        '<div style="font-weight:bold;">' + escapeHtml(name) + '</div>' +
                        (company ? '<div style="color:#666;font-size:13px;">' + escapeHtml(company) + '</div>' : '') +
                        '<div style="color:#888;font-size:12px;">' +
                        (email ? '✉ ' + escapeHtml(email) : '') +
                        (email && phone ? ' | ' : '') +
                        (phone ? '📞 ' + escapeHtml(phone) : '') +
                        '</div></div>';
            });

            container.innerHTML = html;
            document.getElementById('contactSearchInput').value = '';
            document.getElementById('contactSelectModal').classList.add('active');
        }

        function selectContact(idx) {
            if (parsedContacts[idx]) {
                applyContactToSiteForm(parsedContacts[idx]);
                closeContactSelectModal();
            }
        }

        function applyContactToSiteForm(contact) {
            // Map contact fields to site form fields
            if (contact.company) document.getElementById('siteName').value = contact.company;
            if (contact.contactName) document.getElementById('contactName').value = contact.contactName;
            if (contact.email) document.getElementById('contactEmail').value = contact.email;
            if (contact.mainPhone) document.getElementById('mainPhone').value = contact.mainPhone;
            if (contact.cellPhone) document.getElementById('cellPhone').value = contact.cellPhone;
            if (contact.streetNumber) document.getElementById('streetNumber').value = contact.streetNumber;
            if (contact.streetName) document.getElementById('streetName').value = contact.streetName;
            if (contact.unit) document.getElementById('unit').value = contact.unit;
            if (contact.city) document.getElementById('city').value = contact.city;
            if (contact.zip) document.getElementById('zip').value = contact.zip;
            if (contact.notes) document.getElementById('notes').value = contact.notes;

            // Handle country and state
            if (contact.country) {
                populateCountries(contact.country);
                onCountryChange();
            }
            if (contact.state) {
                const isUS = (contact.country || 'United States') === 'United States';
                if (isUS) {
                    populateStates(contact.state);
                } else {
                    document.getElementById('stateText').value = contact.state;
                }
            }
        }

        // Parse Outlook/Google CSV format
        function parseCSVContacts(content) {
            const lines = content.split(/\r?\n/);
            if (lines.length < 2) return [];

            // Parse header row
            const headers = parseCSVLine(lines[0]);
            const contacts = [];

            for (let i = 1; i < lines.length; i++) {
                if (!lines[i].trim()) continue;
                const values = parseCSVLine(lines[i]);
                const row = {};
                headers.forEach((h, idx) => {
                    row[h.trim()] = (values[idx] || '').trim();
                });

                // Map CSV fields to our contact structure
                const contact = {
                    contactName: [row['First Name'], row['Middle Name'], row['Last Name']].filter(Boolean).join(' ') ||
                                 row['Full Name'] || row['Name'] || '',
                    company: row['Company'] || row['Organization'] || '',
                    email: row['E-mail Address'] || row['E-mail 1 - Value'] || row['Email'] || row['Primary Email'] || '',
                    mainPhone: row['Business Phone'] || row['Primary Phone'] || row['Phone 1 - Value'] || row['Work Phone'] || '',
                    cellPhone: row['Mobile Phone'] || row['Cell Phone'] || '',
                    streetNumber: '', // Will parse from street address
                    streetName: row['Business Street'] || row['Address 1 - Street'] || row['Work Address'] || '',
                    unit: row['Business Street 2'] || '',
                    city: row['Business City'] || row['Address 1 - City'] || row['Work City'] || '',
                    state: row['Business State'] || row['Address 1 - Region'] || row['Work State'] || '',
                    zip: row['Business Postal Code'] || row['Address 1 - Postal Code'] || row['Work Zip'] || '',
                    country: row['Business Country/Region'] || row['Address 1 - Country'] || row['Work Country'] || 'United States',
                    notes: row['Notes'] || ''
                };

                // Try to extract street number from street name
                const streetMatch = contact.streetName.match(/^(\d+[\w-]*)\s+(.+)$/);
                if (streetMatch) {
                    contact.streetNumber = streetMatch[1];
                    contact.streetName = streetMatch[2];
                }

                // Normalize country
                contact.country = normalizeCountry(contact.country);

                // Only add if has meaningful data
                if (contact.contactName || contact.company || contact.email) {
                    contacts.push(contact);
                }
            }

            return contacts;
        }

        function parseCSVLine(line) {
            const result = [];
            let current = '';
            let inQuotes = false;

            for (let i = 0; i < line.length; i++) {
                const char = line[i];
                if (char === '"') {
                    if (inQuotes && line[i+1] === '"') {
                        current += '"';
                        i++;
                    } else {
                        inQuotes = !inQuotes;
                    }
                } else if (char === ',' && !inQuotes) {
                    result.push(current);
                    current = '';
                } else {
                    current += char;
                }
            }
            result.push(current);
            return result;
        }

        // Parse vCard (.vcf) format
        function parseVCardContacts(content) {
            const contacts = [];
            const vcards = content.split(/(?=BEGIN:VCARD)/i);

            vcards.forEach(vcard => {
                if (!vcard.trim() || !vcard.toUpperCase().includes('BEGIN:VCARD')) return;

                const contact = {
                    contactName: '', company: '', email: '', mainPhone: '', cellPhone: '',
                    streetNumber: '', streetName: '', unit: '', city: '', state: '', zip: '', country: 'United States', notes: ''
                };

                // Parse each line
                const lines = vcard.split(/\r?\n/);
                let currentField = '';

                lines.forEach(line => {
                    // Handle folded lines (continuation)
                    if (line.startsWith(' ') || line.startsWith('\t')) {
                        currentField += line.substring(1);
                        return;
                    }

                    // Process previous field
                    processVCardField(currentField, contact);
                    currentField = line;
                });
                processVCardField(currentField, contact);

                if (contact.contactName || contact.company || contact.email) {
                    contacts.push(contact);
                }
            });

            return contacts;
        }

        function processVCardField(line, contact) {
            if (!line) return;

            const colonIdx = line.indexOf(':');
            if (colonIdx === -1) return;

            const keyPart = line.substring(0, colonIdx).toUpperCase();
            let value = line.substring(colonIdx + 1);

            // Decode quoted-printable if needed
            if (keyPart.includes('ENCODING=QUOTED-PRINTABLE')) {
                value = decodeQuotedPrintable(value);
            }

            // Get the base field name
            const baseKey = keyPart.split(';')[0];

            if (baseKey === 'FN' || (baseKey === 'N' && !contact.contactName)) {
                if (baseKey === 'N') {
                    // N format: Last;First;Middle;Prefix;Suffix
                    const parts = value.split(';');
                    contact.contactName = [parts[1], parts[0]].filter(Boolean).join(' ');
                } else {
                    contact.contactName = value;
                }
            } else if (baseKey === 'ORG') {
                contact.company = value.split(';')[0];
            } else if (baseKey === 'EMAIL') {
                if (!contact.email) contact.email = value;
            } else if (baseKey === 'TEL') {
                if (keyPart.includes('WORK') || keyPart.includes('VOICE')) {
                    if (!contact.mainPhone) contact.mainPhone = value;
                } else if (keyPart.includes('CELL') || keyPart.includes('MOBILE')) {
                    if (!contact.cellPhone) contact.cellPhone = value;
                } else if (!contact.mainPhone) {
                    contact.mainPhone = value;
                }
            } else if (baseKey === 'ADR' && (keyPart.includes('WORK') || !keyPart.includes('HOME'))) {
                // ADR format: PO Box;Extended;Street;City;State;ZIP;Country
                const parts = value.split(';');
                if (parts[2]) {
                    const streetMatch = parts[2].match(/^(\d+[\w-]*)\s+(.+)$/);
                    if (streetMatch) {
                        contact.streetNumber = streetMatch[1];
                        contact.streetName = streetMatch[2];
                    } else {
                        contact.streetName = parts[2];
                    }
                }
                if (parts[3]) contact.city = parts[3];
                if (parts[4]) contact.state = parts[4];
                if (parts[5]) contact.zip = parts[5];
                if (parts[6]) contact.country = normalizeCountry(parts[6]);
            } else if (baseKey === 'NOTE') {
                contact.notes = value;
            }
        }

        function decodeQuotedPrintable(str) {
            return str.replace(/=([0-9A-Fa-f]{2})/g, (_, hex) =>
                String.fromCharCode(parseInt(hex, 16))
            ).replace(/=\r?\n/g, '');
        }

        // Parse LDIF format
        function parseLDIFContacts(content) {
            const contacts = [];
            const entries = content.split(/\n\n+/);

            entries.forEach(entry => {
                if (!entry.trim()) return;

                const contact = {
                    contactName: '', company: '', email: '', mainPhone: '', cellPhone: '',
                    streetNumber: '', streetName: '', unit: '', city: '', state: '', zip: '', country: 'United States', notes: ''
                };

                const lines = entry.split(/\r?\n/);
                lines.forEach(line => {
                    const colonIdx = line.indexOf(':');
                    if (colonIdx === -1) return;

                    const key = line.substring(0, colonIdx).toLowerCase();
                    let value = line.substring(colonIdx + 1).trim();

                    // Handle base64 encoding
                    if (value.startsWith(':')) {
                        try { value = atob(value.substring(1).trim()); } catch (e) {}
                    }

                    if (key === 'cn' || key === 'displayname') contact.contactName = value;
                    else if (key === 'o' || key === 'company') contact.company = value;
                    else if (key === 'mail') contact.email = value;
                    else if (key === 'telephonenumber') contact.mainPhone = value;
                    else if (key === 'mobile') contact.cellPhone = value;
                    else if (key === 'street' || key === 'streetaddress') contact.streetName = value;
                    else if (key === 'l' || key === 'locality') contact.city = value;
                    else if (key === 'st' || key === 'state') contact.state = value;
                    else if (key === 'postalcode') contact.zip = value;
                    else if (key === 'c' || key === 'country') contact.country = normalizeCountry(value);
                    else if (key === 'description') contact.notes = value;
                });

                if (contact.contactName || contact.company || contact.email) {
                    contacts.push(contact);
                }
            });

            return contacts;
        }

        // Parse Windows .contact XML format
        function parseWindowsContact(content) {
            const contacts = [];

            try {
                const parser = new DOMParser();
                const doc = parser.parseFromString(content, 'text/xml');

                const contact = {
                    contactName: '', company: '', email: '', mainPhone: '', cellPhone: '',
                    streetNumber: '', streetName: '', unit: '', city: '', state: '', zip: '', country: 'United States', notes: ''
                };

                // Try to extract fields from Windows Contact XML
                const getText = (tag) => {
                    const el = doc.querySelector(tag);
                    return el ? el.textContent.trim() : '';
                };

                contact.contactName = getText('FormattedName') || getText('NickName') ||
                                      [getText('GivenName'), getText('FamilyName')].filter(Boolean).join(' ');
                contact.company = getText('Company') || getText('Organization');
                contact.email = getText('Address[Type="Email"]') || getText('EmailAddress');
                contact.mainPhone = getText('Number[Type="Work"]') || getText('PhoneNumber');
                contact.cellPhone = getText('Number[Type="Cell"]') || getText('Number[Type="Mobile"]');
                contact.streetName = getText('Street');
                contact.city = getText('Locality') || getText('City');
                contact.state = getText('Region') || getText('State');
                contact.zip = getText('PostalCode');
                contact.country = normalizeCountry(getText('Country') || 'United States');
                contact.notes = getText('Notes');

                if (contact.contactName || contact.company || contact.email) {
                    contacts.push(contact);
                }
            } catch (e) {
                console.error('Error parsing Windows Contact:', e);
            }

            return contacts;
        }

        function normalizeCountry(country) {
            if (!country) return 'United States';
            const c = country.trim();
            // Common variations
            const map = {
                'US': 'United States', 'USA': 'United States', 'U.S.': 'United States', 'U.S.A.': 'United States',
                'United States of America': 'United States',
                'UK': 'United Kingdom', 'GB': 'United Kingdom', 'Great Britain': 'United Kingdom',
                'CA': 'Canada', 'AU': 'Australia', 'DE': 'Germany', 'FR': 'France'
            };
            return map[c.toUpperCase()] || c;
        }

        // ===== END CONTACT IMPORT FUNCTIONS =====

        async function editSite(siteId) {
            const data = await (await fetch('/api/sites/' + siteId)).json();
            if (data.site) {
                const s = data.site;
                document.getElementById('siteModalTitle').textContent = 'Edit Site: ' + s.Name;
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
                document.getElementById('zip').value = s.Zip || '';
                document.getElementById('notes').value = s.Notes || '';

                const country = s.Country || 'United States';
                populateCountries(country);
                populateStates(s.State || 'IL');
                populateTimezones(s.Timezone || 'America/Chicago');
                onCountryChange();

                document.getElementById('siteModal').classList.add('active');
            }
        }

        async function saveSite(e) {
            e.preventDefault();
            const siteId = document.getElementById('editSiteId').value;
            const country = document.getElementById('country').value;
            const isUS = country === 'United States';

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
                state: isUS ? document.getElementById('state').value : document.getElementById('stateText').value,
                zip: document.getElementById('zip').value,
                country: country,
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
                loadSitesAndDevices();
            } else {
                alert('Error: ' + (result.error || 'Unknown error'));
            }
        }

        async function deleteSite(siteId, siteName, deviceCount) {
            if (deviceCount === 0) {
                if (confirm('Are you sure you want to delete the site "' + siteName + '"?')) {
                    const result = await (await fetch('/api/sites/delete', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ siteId: siteId, action: 'cascade' })
                    })).json();
                    if (result.success) loadSitesAndDevices();
                    else alert('Error: ' + result.error);
                }
            } else {
                window.deletingSiteId = siteId;
                document.getElementById('deleteModalTitle').textContent = 'Delete Site: ' + siteName;
                document.getElementById('deviceCountInfo').innerHTML = '<strong>⚠️ This site has ' + deviceCount + ' device(s).</strong><br>You must choose what to do with them before deleting the site.';
                document.getElementById('deleteOption').value = '';
                document.getElementById('reassignSection').style.display = 'none';

                // Populate reassign dropdown
                const select = document.getElementById('reassignSiteId');
                select.innerHTML = '<option value="">-- Select a site --</option>';
                sitesData.filter(s => s.SiteId !== siteId && !s.isVirtual).forEach(s => {
                    select.innerHTML += '<option value="' + s.SiteId + '">' + escapeHtml(s.Name) + '</option>';
                });

                document.getElementById('deleteOptionsModal').classList.add('active');
            }
        }

        function closeDeleteOptionsModal() {
            document.getElementById('deleteOptionsModal').classList.remove('active');
            window.deletingSiteId = null;
        }

        function onDeleteOptionChange() {
            const option = document.getElementById('deleteOption').value;
            document.getElementById('reassignSection').style.display = option === 'reassign' ? 'block' : 'none';
        }

        async function confirmDeleteWithOption() {
            const option = document.getElementById('deleteOption').value;
            const siteId = window.deletingSiteId;

            if (!option) { alert('Please select an option'); return; }

            let targetSiteId = null;
            if (option === 'reassign') {
                targetSiteId = document.getElementById('reassignSiteId').value;
                if (!targetSiteId) { alert('Please select a destination site'); return; }
            }

            const result = await (await fetch('/api/sites/delete', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    siteId: siteId,
                    action: option === 'deleteall' ? 'cascade' : 'reassign',
                    targetSiteId: targetSiteId
                })
            })).json();

            if (result.success) {
                closeDeleteOptionsModal();
                loadSitesAndDevices();
            } else {
                alert('Error: ' + (result.error || 'Unknown error'));
            }
        }

        // ===== IMPORT/EXPORT FUNCTIONS =====

        // Global site import trigger
        function triggerSiteImport() {
            document.getElementById('siteImportInput').click();
        }

        // Handle site import file selection
        async function handleSiteImport(event) {
            const file = event.target.files[0];
            if (!file) return;

            const reader = new FileReader();
            reader.onload = async function(e) {
                try {
                    const content = e.target.result;
                    const result = await (await fetch('/api/sites/import', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: content
                    })).json();

                    if (result.success) {
                        let msg = '✓ Site import complete!\n';
                        msg += 'Imported: ' + result.imported + ' sites\n';
                        msg += 'Skipped: ' + result.skipped + ' (already exist)';
                        if (result.errors && result.errors.length > 0) {
                            msg += '\n\nErrors:\n' + result.errors.join('\n');
                        }
                        alert(msg);
                        loadSitesAndDevices();
                    } else {
                        alert('Import failed: ' + (result.error || 'Unknown error'));
                    }
                } catch (err) {
                    alert('Error reading file: ' + err.message);
                }
            };
            reader.readAsText(file);
            event.target.value = ''; // Reset for future imports
        }

        // Export all sites to JSON
        async function exportAllSites() {
            try {
                const response = await fetch('/api/sites/export');
                const data = await response.json();

                if (data.sites && data.sites.length === 0) {
                    alert('No sites to export.');
                    return;
                }

                const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = 'sites-export-' + new Date().toISOString().split('T')[0] + '.json';
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);
            } catch (e) {
                alert('Error exporting sites: ' + e.message);
            }
        }

        // Export a single site with its devices
        async function exportSite(siteId, siteName) {
            try {
                const response = await fetch('/api/sites/' + siteId + '/export');
                const data = await response.json();

                const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                const safeName = siteName.replace(/[^a-zA-Z0-9]/g, '_');
                a.href = url;
                a.download = 'site-' + safeName + '-' + new Date().toISOString().split('T')[0] + '.json';
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);
            } catch (e) {
                alert('Error exporting site: ' + e.message);
            }
        }

        // Export devices for a specific site
        async function exportSiteDevices(siteId, siteName) {
            try {
                const response = await fetch('/api/sites/' + siteId + '/devices/export');
                const data = await response.json();

                if (data.devices && data.devices.length === 0) {
                    alert('No devices to export for this site.');
                    return;
                }

                const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                const safeName = siteName.replace(/[^a-zA-Z0-9]/g, '_');
                a.href = url;
                a.download = 'devices-' + safeName + '-' + new Date().toISOString().split('T')[0] + '.json';
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);
            } catch (e) {
                alert('Error exporting devices: ' + e.message);
            }
        }

        // Store current import target site
        let importTargetSiteId = null;
        let importTargetSiteName = null;

        // Trigger device import for a specific site
        function triggerDeviceImportForSite(siteId, siteName) {
            importTargetSiteId = siteId;
            importTargetSiteName = siteName;
            document.getElementById('deviceImportInput').click();
        }

        // Handle device import file selection
        async function handleDeviceImport(event) {
            const file = event.target.files[0];
            if (!file) return;

            const reader = new FileReader();
            reader.onload = async function(e) {
                try {
                    let importData = JSON.parse(e.target.result);

                    // If importing into a specific site, override the siteId for all devices
                    if (importTargetSiteId && importData.devices) {
                        importData.devices = importData.devices.map(d => ({
                            ...d,
                            siteId: importTargetSiteId
                        }));
                    }

                    const result = await (await fetch('/api/devices/import', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(importData)
                    })).json();

                    if (result.success) {
                        let msg = '✓ Device import complete!\n';
                        if (importTargetSiteName) msg += 'Imported into: ' + importTargetSiteName + '\n';
                        msg += 'Imported: ' + result.imported + ' devices\n';
                        msg += 'Skipped: ' + result.skipped + ' (already exist)';
                        if (result.errors && result.errors.length > 0) {
                            msg += '\n\nErrors:\n' + result.errors.join('\n');
                        }
                        alert(msg);
                        loadSitesAndDevices();
                    } else {
                        alert('Import failed: ' + (result.error || 'Unknown error'));
                    }
                } catch (err) {
                    alert('Error reading file: ' + err.message);
                }
            };
            reader.readAsText(file);
            event.target.value = ''; // Reset for future imports
            importTargetSiteId = null;
            importTargetSiteName = null;
        }

        // ===== DEVICE MODAL FUNCTIONS =====

        // Flag indicating whether sites exist (set from server-side)
        const hasSites = $hasSites;

        // Open Add Device modal (global - no site pre-selected)
        function openAddDeviceModal() {
            // Check if any sites exist
            if (!hasSites && sitesData.length === 0) {
                alert('No sites exist yet. Please create a site first before adding devices.');
                return;
            }

            document.getElementById('addDeviceForm').reset();
            document.getElementById('addDeviceResult').innerHTML = '';
            document.getElementById('pairingCode').textContent = '------';
            document.getElementById('pairingTimer').textContent = 'Click Generate to create a 10-minute code';
            // No site pre-selected when opening from global button - user must select
            document.getElementById('siteId').value = '';
            document.getElementById('siteRequiredMsg').style.display = 'none';
            // Reset modal title to default
            const modalTitle = document.querySelector('#addDeviceModal h3');
            if (modalTitle) {
                modalTitle.textContent = 'Add New Device';
            }
            document.getElementById('addDeviceModal').classList.add('active');
        }

        // Open Add Device modal with site pre-selected (from site action bar)
        // This ensures the device is automatically associated with the parent site
        function openAddDeviceModalForSite(siteId, siteName) {
            document.getElementById('addDeviceForm').reset();
            document.getElementById('addDeviceResult').innerHTML = '';
            document.getElementById('pairingCode').textContent = '------';
            document.getElementById('pairingTimer').textContent = 'Click Generate to create a 10-minute code';
            // Pre-select the parent site (device inherits site association automatically)
            document.getElementById('siteId').value = siteId;
            document.getElementById('siteRequiredMsg').style.display = 'none';
            // Update the modal title to show context
            const modalTitle = document.querySelector('#addDeviceModal h3');
            if (modalTitle) {
                modalTitle.textContent = 'Add New Device to ' + siteName;
            }
            document.getElementById('addDeviceModal').classList.add('active');
        }

        function closeDeviceModal() {
            document.getElementById('addDeviceModal').classList.remove('active');
            if (pairingInterval) { clearInterval(pairingInterval); pairingInterval = null; }
            document.getElementById('siteRequiredMsg').style.display = 'none';
            // Reset modal title to default
            const modalTitle = document.querySelector('#addDeviceModal h3');
            if (modalTitle) {
                modalTitle.textContent = 'Add New Device';
            }
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

        async function submitAddDevice(e) {
            e.preventDefault();
            const f = e.target;

            // Validate that a site is selected (critical data integrity requirement)
            if (!f.siteId.value) {
                document.getElementById('siteRequiredMsg').style.display = 'block';
                document.getElementById('addDeviceResult').innerHTML =
                    '<div style="color:#721c24;padding:10px;background:#f8d7da;border-radius:5px;">Please select a site for this device.</div>';
                return;
            }
            document.getElementById('siteRequiredMsg').style.display = 'none';

            const result = await (await fetch('/api/devices/add', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    hostname: f.hostname.value,
                    ipAddress: f.ipAddress.value,
                    siteId: f.siteId.value,
                    deviceType: f.deviceType.value,
                    description: f.description.value,
                    tags: f.tags.value
                })
            })).json();

            const div = document.getElementById('addDeviceResult');
            if (result.success) {
                div.innerHTML = '<div style="color:#28a745;padding:10px;background:#d4edda;border-radius:5px;">Device added successfully!</div>';
                setTimeout(() => { closeDeviceModal(); loadSitesAndDevices(); }, 1500);
            } else {
                div.innerHTML = '<div style="color:#721c24;padding:10px;background:#f8d7da;border-radius:5px;">Error: ' + result.error + '</div>';
            }
        }

        async function deleteDevice(deviceId, hostname) {
            if (!confirm('Are you sure you want to delete device "' + hostname + '"?')) return;
            const result = await (await fetch('/api/devices/delete', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ deviceId: deviceId })
            })).json();
            if (result.success) loadSitesAndDevices();
            else alert('Error: ' + result.error);
        }

        // Dropdown population functions
        function populateCountries(selectedValue) {
            const select = document.getElementById('country');
            select.innerHTML = '<option value="">-- Select Country --</option>';
            countries.forEach(country => {
                const opt = document.createElement('option');
                opt.value = country;
                opt.textContent = country;
                if (country === selectedValue) opt.selected = true;
                select.appendChild(opt);
            });
        }

        function populateStates(selectedValue) {
            const select = document.getElementById('state');
            select.innerHTML = '<option value="">-- Select State --</option>';
            usStates.forEach(state => {
                const opt = document.createElement('option');
                opt.value = state.abbr;
                opt.textContent = state.name + ' (' + state.abbr + ')';
                if (state.abbr === selectedValue) opt.selected = true;
                select.appendChild(opt);
            });
        }

        function populateTimezones(selectedValue) {
            const select = document.getElementById('timezone');
            select.innerHTML = '<option value="">-- Select Timezone --</option>';
            timezones.forEach(tz => {
                const opt = document.createElement('option');
                opt.value = tz.value;
                opt.textContent = tz.label;
                if (tz.value === selectedValue) opt.selected = true;
                select.appendChild(opt);
            });
        }

        function onCountryChange() {
            const country = document.getElementById('country').value;
            const stateSelect = document.getElementById('state');
            const stateText = document.getElementById('stateText');
            const stateLabel = document.getElementById('stateLabel');

            if (country === 'United States') {
                stateSelect.style.display = 'block';
                stateText.style.display = 'none';
                stateLabel.textContent = 'State';
            } else {
                stateSelect.style.display = 'none';
                stateText.style.display = 'block';
                stateLabel.textContent = 'Province/Region';
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
        <div class="header-left">
            <h1>myTech.Today RMM Dashboard</h1>
            <nav>
                <a href="/">Dashboard</a>
                <a href="/sites-and-devices" class="active">Sites &amp; Devices</a>
                <a href="/alerts">Alerts</a>
                <a href="/actions">Actions</a>
                <a href="/reports">Reports</a>
                <a href="/settings">Settings</a>
            </nav>
        </div>
        <button class="readme-btn" onclick="openReadme()" title="View Documentation">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
            Readme
        </button>
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

                <div class="section-header">Device Login Credentials</div>
                <p style="color:#666;font-size:12px;margin-bottom:10px;">Admin/login credentials for remote access to this device. Passwords are encrypted.</p>
                <div class="field-row">
                    <div class="field-label">Admin Username</div>
                    <div class="field-value"><input type="text" id="adminUsername" placeholder="Administrator username"></div>
                </div>
                <div class="field-row">
                    <div class="field-label">Admin Password</div>
                    <div class="field-value" style="position:relative;">
                        <input type="password" id="adminPassword" placeholder="Password (encrypted)">
                        <button type="button" onclick="togglePasswordVisibility()" style="position:absolute;right:5px;top:50%;transform:translateY(-50%);background:none;border:none;cursor:pointer;font-size:16px;padding:5px;" title="Show/Hide Password">
                            <span id="eyeIcon">👁️</span>
                        </button>
                    </div>
                </div>
                <div style="margin-bottom:15px;">
                    <button type="button" onclick="saveDeviceCredentials()" style="padding:8px 15px;background:#17a2b8;color:white;border:none;border-radius:4px;cursor:pointer;">Save Credentials</button>
                    <span id="credentialSaveResult" style="margin-left:10px;font-size:12px;"></span>
                </div>

                <div class="section-header">Device URLs / Links</div>
                <div id="deviceUrlsList" style="margin-bottom:15px;"></div>
                <div style="display:grid;grid-template-columns:1fr 2fr 1fr 1fr auto;gap:8px;align-items:end;">
                    <div>
                        <label style="font-size:11px;display:block;margin-bottom:3px;">Label</label>
                        <input type="text" id="newDeviceUrlLabel" placeholder="e.g., RDP" style="padding:6px 10px;border:1px solid #ddd;border-radius:4px;width:100%;box-sizing:border-box;">
                    </div>
                    <div>
                        <label style="font-size:11px;display:block;margin-bottom:3px;">URL</label>
                        <input type="text" id="newDeviceUrlValue" placeholder="rdp://hostname or https://..." style="padding:6px 10px;border:1px solid #ddd;border-radius:4px;width:100%;box-sizing:border-box;">
                    </div>
                    <div>
                        <label style="font-size:11px;display:block;margin-bottom:3px;">Username (optional)</label>
                        <input type="text" id="newDeviceUrlUsername" placeholder="Username" style="padding:6px 10px;border:1px solid #ddd;border-radius:4px;width:100%;box-sizing:border-box;">
                    </div>
                    <div>
                        <label style="font-size:11px;display:block;margin-bottom:3px;">Password (optional)</label>
                        <input type="password" id="newDeviceUrlPassword" placeholder="Password" style="padding:6px 10px;border:1px solid #ddd;border-radius:4px;width:100%;box-sizing:border-box;">
                    </div>
                    <button type="button" onclick="addDeviceUrl()" style="padding:8px 12px;background:#28a745;color:white;border:none;border-radius:4px;cursor:pointer;">+</button>
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

        // Device URL Management
        const currentDeviceId = '$($device.DeviceId)';

        function escapeHtml(text) {
            if (!text) return '';
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        function renderDeviceUrls(urls) {
            const container = document.getElementById('deviceUrlsList');
            if (!urls || urls.length === 0) {
                container.innerHTML = '<p style="color:#999;font-size:12px;">No URLs added yet.</p>';
                return;
            }
            let html = '<table style="width:100%;font-size:12px;border-collapse:collapse;">';
            html += '<tr style="background:#f5f5f5;"><th style="padding:5px;text-align:left;">Label</th><th style="padding:5px;text-align:left;">URL</th><th style="padding:5px;text-align:left;">Username</th><th style="padding:5px;text-align:center;">Creds</th><th style="padding:5px;"></th></tr>';
            urls.forEach(u => {
                const hasPassword = u.HasPassword === 1 || u.HasPassword === true;
                html += '<tr style="border-bottom:1px solid #eee;">';
                html += '<td style="padding:5px;">' + (u.Label || '-') + '</td>';
                html += '<td style="padding:5px;"><a href="#" onclick="openProtocolUrl(\'' + escapeHtml(u.URL) + '\', ' + u.URLId + ', \'device\'); return false;">' + escapeHtml(u.URL) + '</a></td>';
                html += '<td style="padding:5px;">' + (u.Username || '-') + '</td>';
                html += '<td style="padding:5px;text-align:center;">' + (hasPassword ? '🔐' : '-') + '</td>';
                html += '<td style="padding:5px;"><button type="button" onclick="removeDeviceUrl(' + u.URLId + ')" style="background:#dc3545;color:white;border:none;padding:3px 8px;border-radius:3px;cursor:pointer;font-size:11px;">×</button></td>';
                html += '</tr>';
            });
            html += '</table>';
            container.innerHTML = html;
        }

        async function loadDeviceUrls() {
            try {
                const response = await fetch('/api/devices/' + currentDeviceId + '/urls');
                const data = await response.json();
                if (data.urls) {
                    renderDeviceUrls(data.urls);
                }
            } catch (e) {
                console.error('Error loading device URLs:', e);
            }
        }

        async function addDeviceUrl() {
            const url = document.getElementById('newDeviceUrlValue').value.trim();
            if (!url) {
                alert('URL is required');
                return;
            }
            const label = document.getElementById('newDeviceUrlLabel').value.trim();
            const username = document.getElementById('newDeviceUrlUsername').value.trim();
            const password = document.getElementById('newDeviceUrlPassword').value;

            const result = await (await fetch('/api/devices/urls/add', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ deviceId: currentDeviceId, url, label, username, password })
            })).json();

            if (result.success) {
                document.getElementById('newDeviceUrlValue').value = '';
                document.getElementById('newDeviceUrlLabel').value = '';
                document.getElementById('newDeviceUrlUsername').value = '';
                document.getElementById('newDeviceUrlPassword').value = '';
                loadDeviceUrls();
            } else {
                alert('Error adding URL: ' + (result.error || 'Unknown error'));
            }
        }

        async function removeDeviceUrl(urlId) {
            if (!confirm('Remove this URL?')) return;
            const result = await (await fetch('/api/devices/urls/delete', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ urlId })
            })).json();

            if (result.success) {
                loadDeviceUrls();
            } else {
                alert('Error removing URL: ' + (result.error || 'Unknown error'));
            }
        }

        function openProtocolUrl(url, urlId, type) {
            const protocol = url.split(':')[0].toLowerCase();
            if (protocol === 'http' || protocol === 'https') {
                window.open(url, '_blank');
            } else if (protocol === 'smb' || protocol === 'file') {
                window.location.href = url;
            } else if (protocol === 'ftp' || protocol === 'sftp') {
                window.open(url, '_blank');
            } else if (protocol === 'rdp') {
                alert('RDP connections should be opened using Remote Desktop Connection.\\nHost: ' + url.replace('rdp://', ''));
            } else if (protocol === 'ssh') {
                alert('SSH connections should be opened using an SSH client.\\nHost: ' + url.replace('ssh://', ''));
            } else {
                window.location.href = url;
            }
        }

        // Load URLs on page load
        loadDeviceUrls();

        // Device Credentials Management
        let passwordVisible = false;

        function togglePasswordVisibility() {
            const input = document.getElementById('adminPassword');
            const icon = document.getElementById('eyeIcon');
            passwordVisible = !passwordVisible;
            input.type = passwordVisible ? 'text' : 'password';
            icon.textContent = passwordVisible ? '🙈' : '👁️';
        }

        async function loadDeviceCredentials() {
            try {
                const response = await fetch('/api/devices/' + currentDeviceId + '/credentials');
                const data = await response.json();
                if (data.success) {
                    document.getElementById('adminUsername').value = data.adminUsername || '';
                    document.getElementById('adminPassword').value = data.adminPassword || '';
                }
            } catch (e) {
                console.error('Error loading device credentials:', e);
            }
        }

        async function saveDeviceCredentials() {
            const username = document.getElementById('adminUsername').value.trim();
            const password = document.getElementById('adminPassword').value;
            const resultSpan = document.getElementById('credentialSaveResult');

            try {
                const result = await (await fetch('/api/devices/credentials/save', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        deviceId: currentDeviceId,
                        adminUsername: username,
                        adminPassword: password
                    })
                })).json();

                if (result.success) {
                    resultSpan.textContent = '✓ Saved';
                    resultSpan.style.color = '#28a745';
                    setTimeout(() => { resultSpan.textContent = ''; }, 3000);
                } else {
                    resultSpan.textContent = '✗ ' + result.error;
                    resultSpan.style.color = '#dc3545';
                }
            } catch (e) {
                resultSpan.textContent = '✗ Error: ' + e.message;
                resultSpan.style.color = '#dc3545';
            }
        }

        // Load credentials on page load
        loadDeviceCredentials();
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

        # Validate site selection (critical data integrity requirement)
        if (-not $data.siteId -or $data.siteId -eq '') {
            Write-RMMLog "Add device failed: Site selection is required" -Level WARNING -Component "Web-Dashboard"
            return @{ success = $false; error = "Please select a site for this device" } | ConvertTo-Json
        }

        # Verify the site exists
        $siteQuery = "SELECT SiteId FROM Sites WHERE SiteId = @SiteId"
        $siteExists = Invoke-SqliteQuery -DataSource $DatabasePath -Query $siteQuery -SqlParameters @{ SiteId = $data.siteId }
        if (-not $siteExists) {
            Write-RMMLog "Add device failed: Site '$($data.siteId)' does not exist" -Level WARNING -Component "Web-Dashboard"
            return @{ success = $false; error = "Selected site does not exist" } | ConvertTo-Json
        }

        # Check if device already exists
        $existingQuery = "SELECT DeviceId FROM Devices WHERE Hostname = @Hostname"
        $existing = Invoke-SqliteQuery -DataSource $DatabasePath -Query $existingQuery -SqlParameters @{ Hostname = $data.hostname }
        if ($existing) {
            Write-RMMLog "Add device failed: Device '$($data.hostname)' already exists" -Level WARNING -Component "Web-Dashboard"
            return @{ success = $false; error = "Device with hostname '$($data.hostname)' already exists" } | ConvertTo-Json
        }

        $deviceId = [guid]::NewGuid().ToString()
        $siteId = $data.siteId
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

        # Encrypt password if provided
        $encryptedPassword = $null
        if ($data.password) {
            $encryptedPassword = Protect-RMMString -PlainText $data.password
        }

        $query = "INSERT INTO SiteURLs (SiteId, URL, Label, Username, EncryptedPassword, CreatedAt) VALUES (@SiteId, @URL, @Label, @Username, @EncryptedPassword, CURRENT_TIMESTAMP)"
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{
            SiteId = $data.siteId
            URL = $data.url
            Label = $data.label
            Username = $data.username
            EncryptedPassword = $encryptedPassword
        }

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

function Add-DeviceURLAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        if (-not $data.deviceId -or -not $data.url) {
            return @{ success = $false; error = "Device ID and URL are required" } | ConvertTo-Json
        }

        # Encrypt password if provided
        $encryptedPassword = $null
        if ($data.password) {
            $encryptedPassword = Protect-RMMString -PlainText $data.password
        }

        $query = "INSERT INTO DeviceURLs (DeviceId, URL, Label, Username, EncryptedPassword, CreatedAt) VALUES (@DeviceId, @URL, @Label, @Username, @EncryptedPassword, CURRENT_TIMESTAMP)"
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{
            DeviceId = $data.deviceId
            URL = $data.url
            Label = $data.label
            Username = $data.username
            EncryptedPassword = $encryptedPassword
        }

        return @{ success = $true; message = "URL added" } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Remove-DeviceURLAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        if (-not $data.urlId) {
            return @{ success = $false; error = "URL ID is required" } | ConvertTo-Json
        }

        Invoke-SqliteQuery -DataSource $DatabasePath -Query "DELETE FROM DeviceURLs WHERE URLId = @URLId" -SqlParameters @{ URLId = $data.urlId }

        return @{ success = $true; message = "URL removed" } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Get-URLCredentialAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        if (-not $data.urlId -or -not $data.type) {
            return @{ success = $false; error = "URL ID and type are required" } | ConvertTo-Json
        }

        $table = if ($data.type -eq 'site') { 'SiteURLs' } else { 'DeviceURLs' }
        $query = "SELECT Username, EncryptedPassword FROM $table WHERE URLId = @URLId"
        $result = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ URLId = $data.urlId }

        if (-not $result) {
            return @{ success = $false; error = "URL not found" } | ConvertTo-Json
        }

        $password = $null
        if ($result.EncryptedPassword) {
            $password = Unprotect-RMMString -EncryptedText $result.EncryptedPassword
        }

        return @{
            success = $true
            username = $result.Username
            password = $password
        } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Save-DeviceCredentialsAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        if (-not $data.deviceId) {
            return @{ success = $false; error = "Device ID is required" } | ConvertTo-Json
        }

        # Encrypt password if provided
        $encryptedPassword = $null
        if ($data.adminPassword) {
            $encryptedPassword = Protect-RMMString -PlainText $data.adminPassword
        }

        $query = "UPDATE Devices SET AdminUsername = @AdminUsername, AdminPasswordEncrypted = @AdminPasswordEncrypted, UpdatedAt = CURRENT_TIMESTAMP WHERE DeviceId = @DeviceId"
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{
            DeviceId = $data.deviceId
            AdminUsername = $data.adminUsername
            AdminPasswordEncrypted = $encryptedPassword
        }

        return @{ success = $true; message = "Credentials saved" } | ConvertTo-Json
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Get-DeviceCredentialsAPI {
    param([string]$DeviceId)
    try {
        $query = "SELECT AdminUsername, AdminPasswordEncrypted FROM Devices WHERE DeviceId = @DeviceId"
        $result = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ DeviceId = $DeviceId }

        if (-not $result) {
            return @{ success = $false; error = "Device not found" } | ConvertTo-Json
        }

        $password = $null
        if ($result.AdminPasswordEncrypted) {
            $password = Unprotect-RMMString -EncryptedText $result.AdminPasswordEncrypted
        }

        return @{
            success = $true
            adminUsername = $result.AdminUsername
            adminPassword = $password
        } | ConvertTo-Json
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

        # Get URLs (include Username and HasPassword flag, but not the actual password)
        $urlQuery = "SELECT URLId, URL, Label, Username, CASE WHEN EncryptedPassword IS NOT NULL AND EncryptedPassword != '' THEN 1 ELSE 0 END AS HasPassword FROM SiteURLs WHERE SiteId = @SiteId ORDER BY Label"
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

function Get-DeviceURLsJSON {
    param([string]$DeviceId)
    try {
        $query = "SELECT URLId, URL, Label, Username, CASE WHEN EncryptedPassword IS NOT NULL AND EncryptedPassword != '' THEN 1 ELSE 0 END AS HasPassword FROM DeviceURLs WHERE DeviceId = @DeviceId ORDER BY Label"
        $urls = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ DeviceId = $DeviceId })

        return @{ urls = $urls } | ConvertTo-Json -Depth 4
    }
    catch {
        return @{ error = $_.Exception.Message; urls = @() } | ConvertTo-Json
    }
}

function Export-SitesJSON {
    try {
        $sitesQuery = "SELECT * FROM Sites ORDER BY Name"
        $sites = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query $sitesQuery)

        # Get URLs for each site (without encrypted passwords for security)
        foreach ($site in $sites) {
            $urlQuery = "SELECT URL, Label, Username FROM SiteURLs WHERE SiteId = @SiteId ORDER BY Label"
            $urls = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query $urlQuery -SqlParameters @{ SiteId = $site.SiteId })
            $site | Add-Member -NotePropertyName 'URLs' -NotePropertyValue $urls -Force
        }

        $export = @{
            exportType = "Sites"
            exportDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            version = "1.0"
            sites = $sites
        }

        return $export | ConvertTo-Json -Depth 5
    }
    catch {
        return @{ error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Export-DevicesJSON {
    try {
        $devicesQuery = "SELECT * FROM Devices ORDER BY Hostname"
        $devices = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query $devicesQuery)

        # Get URLs for each device (without encrypted passwords for security)
        foreach ($device in $devices) {
            $urlQuery = "SELECT URL, Label, Username FROM DeviceURLs WHERE DeviceId = @DeviceId ORDER BY Label"
            $urls = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query $urlQuery -SqlParameters @{ DeviceId = $device.DeviceId })
            $device | Add-Member -NotePropertyName 'URLs' -NotePropertyValue $urls -Force
        }

        $export = @{
            exportType = "Devices"
            exportDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            version = "1.0"
            devices = $devices
        }

        return $export | ConvertTo-Json -Depth 5
    }
    catch {
        return @{ error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Export-SingleSiteJSON {
    param([string]$SiteId)
    try {
        # Get the site
        $siteQuery = "SELECT * FROM Sites WHERE SiteId = @SiteId"
        $site = Invoke-SqliteQuery -DataSource $DatabasePath -Query $siteQuery -SqlParameters @{ SiteId = $SiteId }

        if (-not $site) {
            return @{ error = "Site not found" } | ConvertTo-Json
        }

        # Get URLs for the site (without encrypted passwords for security)
        $urlQuery = "SELECT URL, Label, Username FROM SiteURLs WHERE SiteId = @SiteId ORDER BY Label"
        $urls = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query $urlQuery -SqlParameters @{ SiteId = $SiteId })
        $site | Add-Member -NotePropertyName 'URLs' -NotePropertyValue $urls -Force

        # Get devices for this site
        $devicesQuery = "SELECT * FROM Devices WHERE SiteId = @SiteId ORDER BY Hostname"
        $devices = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query $devicesQuery -SqlParameters @{ SiteId = $SiteId })

        # Get URLs for each device
        foreach ($device in $devices) {
            $deviceUrlQuery = "SELECT URL, Label, Username FROM DeviceURLs WHERE DeviceId = @DeviceId ORDER BY Label"
            $deviceUrls = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query $deviceUrlQuery -SqlParameters @{ DeviceId = $device.DeviceId })
            $device | Add-Member -NotePropertyName 'URLs' -NotePropertyValue $deviceUrls -Force
        }

        $export = @{
            exportType = "SingleSite"
            exportDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            version = "1.0"
            site = $site
            devices = $devices
        }

        return $export | ConvertTo-Json -Depth 5
    }
    catch {
        return @{ error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Export-SiteDevicesJSON {
    param([string]$SiteId)
    try {
        # Verify site exists
        $siteQuery = "SELECT Name FROM Sites WHERE SiteId = @SiteId"
        $site = Invoke-SqliteQuery -DataSource $DatabasePath -Query $siteQuery -SqlParameters @{ SiteId = $SiteId }

        $siteName = if ($site) { $site.Name } else { "Unknown" }

        # Get devices for this site
        $devicesQuery = "SELECT * FROM Devices WHERE SiteId = @SiteId ORDER BY Hostname"
        $devices = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query $devicesQuery -SqlParameters @{ SiteId = $SiteId })

        # Get URLs for each device (without encrypted passwords for security)
        foreach ($device in $devices) {
            $urlQuery = "SELECT URL, Label, Username FROM DeviceURLs WHERE DeviceId = @DeviceId ORDER BY Label"
            $urls = @(Invoke-SqliteQuery -DataSource $DatabasePath -Query $urlQuery -SqlParameters @{ DeviceId = $device.DeviceId })
            $device | Add-Member -NotePropertyName 'URLs' -NotePropertyValue $urls -Force
        }

        $export = @{
            exportType = "SiteDevices"
            exportDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            version = "1.0"
            siteId = $SiteId
            siteName = $siteName
            devices = $devices
        }

        return $export | ConvertTo-Json -Depth 5
    }
    catch {
        return @{ error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Import-SitesAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        if (-not $data.sites) {
            return @{ success = $false; error = "Invalid import format: missing 'sites' array" } | ConvertTo-Json
        }

        $imported = 0
        $skipped = 0
        $errors = @()

        foreach ($site in $data.sites) {
            try {
                # Check if site already exists by SiteId or Name
                $existingById = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT SiteId FROM Sites WHERE SiteId = @SiteId" -SqlParameters @{ SiteId = $site.SiteId }
                $existingByName = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT SiteId FROM Sites WHERE Name = @Name" -SqlParameters @{ Name = $site.Name }

                if ($existingById -or $existingByName) {
                    $skipped++
                    continue
                }

                # Insert site
                $insertQuery = @"
INSERT INTO Sites (SiteId, Name, ContactName, ContactEmail, MainPhone, CellPhone, StreetNumber, StreetName, Unit, Building, City, State, Zip, Country, Timezone, Notes, CreatedAt, UpdatedAt)
VALUES (@SiteId, @Name, @ContactName, @ContactEmail, @MainPhone, @CellPhone, @StreetNumber, @StreetName, @Unit, @Building, @City, @State, @Zip, @Country, @Timezone, @Notes, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
"@
                Invoke-SqliteQuery -DataSource $DatabasePath -Query $insertQuery -SqlParameters @{
                    SiteId = if ($site.SiteId) { $site.SiteId } else { [guid]::NewGuid().ToString() }
                    Name = $site.Name
                    ContactName = $site.ContactName
                    ContactEmail = $site.ContactEmail
                    MainPhone = $site.MainPhone
                    CellPhone = $site.CellPhone
                    StreetNumber = $site.StreetNumber
                    StreetName = $site.StreetName
                    Unit = $site.Unit
                    Building = $site.Building
                    City = $site.City
                    State = $site.State
                    Zip = $site.Zip
                    Country = $site.Country
                    Timezone = $site.Timezone
                    Notes = $site.Notes
                }

                # Import URLs if present
                if ($site.URLs) {
                    foreach ($url in $site.URLs) {
                        $urlInsert = "INSERT INTO SiteURLs (SiteId, URL, Label, Username, CreatedAt) VALUES (@SiteId, @URL, @Label, @Username, CURRENT_TIMESTAMP)"
                        Invoke-SqliteQuery -DataSource $DatabasePath -Query $urlInsert -SqlParameters @{
                            SiteId = $site.SiteId
                            URL = $url.URL
                            Label = $url.Label
                            Username = $url.Username
                        }
                    }
                }

                $imported++
            }
            catch {
                $errors += "Site '$($site.Name)': $($_.Exception.Message)"
            }
        }

        return @{
            success = $true
            imported = $imported
            skipped = $skipped
            errors = $errors
        } | ConvertTo-Json -Depth 3
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Import-DevicesAPI {
    param([string]$Body)
    try {
        $data = $Body | ConvertFrom-Json
        if (-not $data.devices) {
            return @{ success = $false; error = "Invalid import format: missing 'devices' array" } | ConvertTo-Json
        }

        $imported = 0
        $skipped = 0
        $errors = @()

        foreach ($device in $data.devices) {
            try {
                # Check if device already exists by DeviceId or Hostname
                $existingById = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT DeviceId FROM Devices WHERE DeviceId = @DeviceId" -SqlParameters @{ DeviceId = $device.DeviceId }
                $existingByHostname = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT DeviceId FROM Devices WHERE Hostname = @Hostname" -SqlParameters @{ Hostname = $device.Hostname }

                if ($existingById -or $existingByHostname) {
                    $skipped++
                    continue
                }

                # Insert device
                $insertQuery = @"
INSERT INTO Devices (DeviceId, Hostname, IPAddress, Status, SiteId, DeviceType, Tags, Description, CredentialName, Notes, CreatedAt, UpdatedAt)
VALUES (@DeviceId, @Hostname, @IPAddress, @Status, @SiteId, @DeviceType, @Tags, @Description, @CredentialName, @Notes, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
"@
                Invoke-SqliteQuery -DataSource $DatabasePath -Query $insertQuery -SqlParameters @{
                    DeviceId = if ($device.DeviceId) { $device.DeviceId } else { [guid]::NewGuid().ToString() }
                    Hostname = $device.Hostname
                    IPAddress = $device.IPAddress
                    Status = if ($device.Status) { $device.Status } else { "Unknown" }
                    SiteId = $device.SiteId
                    DeviceType = $device.DeviceType
                    Tags = $device.Tags
                    Description = $device.Description
                    CredentialName = $device.CredentialName
                    Notes = $device.Notes
                }

                # Import URLs if present
                if ($device.URLs) {
                    foreach ($url in $device.URLs) {
                        $urlInsert = "INSERT INTO DeviceURLs (DeviceId, URL, Label, Username, CreatedAt) VALUES (@DeviceId, @URL, @Label, @Username, CURRENT_TIMESTAMP)"
                        Invoke-SqliteQuery -DataSource $DatabasePath -Query $urlInsert -SqlParameters @{
                            DeviceId = $device.DeviceId
                            URL = $url.URL
                            Label = $url.Label
                            Username = $url.Username
                        }
                    }
                }

                $imported++
            }
            catch {
                $errors += "Device '$($device.Hostname)': $($_.Exception.Message)"
            }
        }

        return @{
            success = $true
            imported = $imported
            skipped = $skipped
            errors = $errors
        } | ConvertTo-Json -Depth 3
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
    }
}

function Get-ReportDataAPI {
    param(
        [string]$ReportType,
        [string]$StartDate,
        [string]$EndDate
    )

    try {
        $html = ""
        $data = @()

        switch ($ReportType) {
            "ExecutiveSummary" {
                # Get summary metrics
                $deviceCount = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Devices").Count
                $onlineDevices = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Devices WHERE Status IN ('Online', 'Healthy', 'Warning', 'Critical')").Count
                $offlineDevices = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Devices WHERE Status IN ('Offline', 'Unknown') OR Status IS NULL").Count
                $activeAlerts = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Alerts WHERE ResolvedAt IS NULL").Count
                $criticalAlerts = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Alerts WHERE Severity = 'Critical' AND ResolvedAt IS NULL").Count
                $recentActions = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Actions WHERE datetime(CreatedAt) >= datetime('$StartDate')").Count

                $healthPercent = if ($deviceCount -gt 0) { [math]::Round(($onlineDevices / $deviceCount) * 100, 1) } else { 0 }

                $html = @"
<div class="metric-grid">
    <div class="metric-box"><div class="value">$deviceCount</div><div class="label">Total Devices</div></div>
    <div class="metric-box"><div class="value status-online">$onlineDevices</div><div class="label">Online</div></div>
    <div class="metric-box"><div class="value status-offline">$offlineDevices</div><div class="label">Offline</div></div>
    <div class="metric-box"><div class="value">$healthPercent%</div><div class="label">Fleet Health</div></div>
    <div class="metric-box"><div class="value severity-critical">$criticalAlerts</div><div class="label">Critical Alerts</div></div>
    <div class="metric-box"><div class="value">$activeAlerts</div><div class="label">Active Alerts</div></div>
    <div class="metric-box"><div class="value">$recentActions</div><div class="label">Recent Actions</div></div>
</div>
<h4>Alert Summary</h4>
<table class="report-table">
<tr><th>Severity</th><th>Count</th></tr>
"@
                $alertsBySeverity = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT Severity, COUNT(*) as Count FROM Alerts WHERE ResolvedAt IS NULL GROUP BY Severity ORDER BY CASE Severity WHEN 'Critical' THEN 1 WHEN 'High' THEN 2 WHEN 'Medium' THEN 3 ELSE 4 END"
                foreach ($row in $alertsBySeverity) {
                    $sevClass = "severity-$($row.Severity.ToLower())"
                    $html += "<tr><td class=`"$sevClass`">$($row.Severity)</td><td>$($row.Count)</td></tr>"
                }
                $html += "</table>"

                $data = @{
                    TotalDevices = $deviceCount
                    OnlineDevices = $onlineDevices
                    OfflineDevices = $offlineDevices
                    HealthPercent = $healthPercent
                    CriticalAlerts = $criticalAlerts
                    ActiveAlerts = $activeAlerts
                    RecentActions = $recentActions
                }
            }
            "DeviceInventory" {
                $devices = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT DeviceId, Hostname, Status, OS, LastSeen, SiteId FROM Devices ORDER BY Hostname"
                $html = "<table class=`"report-table`"><tr><th>Hostname</th><th>Device ID</th><th>Status</th><th>OS</th><th>Last Seen</th></tr>"
                foreach ($d in $devices) {
                    $statusClass = if ($d.Status -in @('Online', 'Healthy', 'Warning', 'Critical')) { 'status-online' } else { 'status-offline' }
                    $html += "<tr><td>$($d.Hostname)</td><td>$($d.DeviceId)</td><td class=`"$statusClass`">$($d.Status)</td><td>$($d.OS)</td><td>$($d.LastSeen)</td></tr>"
                }
                $html += "</table>"
                $data = $devices
            }
            "AlertSummary" {
                $alerts = Invoke-SqliteQuery -DataSource $DatabasePath -Query @"
SELECT AlertId, DeviceId, AlertType, Severity, Message, CreatedAt, AcknowledgedAt, ResolvedAt
FROM Alerts
WHERE datetime(CreatedAt) >= datetime('$StartDate') AND datetime(CreatedAt) <= datetime('$EndDate 23:59:59')
ORDER BY CreatedAt DESC
"@
                $html = "<table class=`"report-table`"><tr><th>Date</th><th>Device</th><th>Type</th><th>Severity</th><th>Message</th><th>Status</th></tr>"
                foreach ($a in $alerts) {
                    $sevClass = "severity-$($a.Severity.ToLower())"
                    $status = if ($a.ResolvedAt) { "Resolved" } elseif ($a.AcknowledgedAt) { "Acknowledged" } else { "Active" }
                    $html += "<tr><td>$($a.CreatedAt)</td><td>$($a.DeviceId)</td><td>$($a.AlertType)</td><td class=`"$sevClass`">$($a.Severity)</td><td>$($a.Message)</td><td>$status</td></tr>"
                }
                $html += "</table>"
                if (-not $alerts -or $alerts.Count -eq 0) {
                    $html = "<p style='color:#64748b;'>No alerts found in the selected date range.</p>"
                }
                $data = $alerts
            }
            "UptimeReport" {
                $devices = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT DeviceId, Hostname, Status, LastSeen FROM Devices ORDER BY Status DESC, Hostname"
                $html = "<table class=`"report-table`"><tr><th>Hostname</th><th>Device ID</th><th>Status</th><th>Last Seen</th><th>Uptime Status</th></tr>"
                foreach ($d in $devices) {
                    $statusClass = if ($d.Status -in @('Online', 'Healthy', 'Warning', 'Critical')) { 'status-online' } else { 'status-offline' }
                    $uptimeStatus = if ($d.Status -in @('Online', 'Healthy', 'Warning', 'Critical')) { '✅ Available' } else { '❌ Unavailable' }
                    $html += "<tr><td>$($d.Hostname)</td><td>$($d.DeviceId)</td><td class=`"$statusClass`">$($d.Status)</td><td>$($d.LastSeen)</td><td>$uptimeStatus</td></tr>"
                }
                $html += "</table>"
                $data = $devices
            }
            "PerformanceTrends" {
                $metrics = Invoke-SqliteQuery -DataSource $DatabasePath -Query @"
SELECT DeviceId, MetricType, Value, Timestamp
FROM Metrics
WHERE datetime(Timestamp) >= datetime('$StartDate') AND datetime(Timestamp) <= datetime('$EndDate 23:59:59')
ORDER BY Timestamp DESC
LIMIT 100
"@
                $html = "<table class=`"report-table`"><tr><th>Timestamp</th><th>Device</th><th>Metric Type</th><th>Value</th></tr>"
                foreach ($m in $metrics) {
                    $html += "<tr><td>$($m.Timestamp)</td><td>$($m.DeviceId)</td><td>$($m.MetricType)</td><td>$($m.Value)</td></tr>"
                }
                $html += "</table>"
                if (-not $metrics -or $metrics.Count -eq 0) {
                    $html = "<p style='color:#64748b;'>No performance metrics found in the selected date range.</p>"
                }
                $data = $metrics
            }
            "AuditLog" {
                $actions = Invoke-SqliteQuery -DataSource $DatabasePath -Query @"
SELECT ActionId, DeviceId, ActionType, Status, CreatedAt, CompletedAt, Result
FROM Actions
WHERE datetime(CreatedAt) >= datetime('$StartDate') AND datetime(CreatedAt) <= datetime('$EndDate 23:59:59')
ORDER BY CreatedAt DESC
"@
                $html = "<table class=`"report-table`"><tr><th>Timestamp</th><th>Device</th><th>Action Type</th><th>Status</th><th>Result</th></tr>"
                foreach ($a in $actions) {
                    $statusClass = if ($a.Status -eq 'Completed') { 'status-online' } elseif ($a.Status -eq 'Failed') { 'status-offline' } else { '' }
                    $html += "<tr><td>$($a.CreatedAt)</td><td>$($a.DeviceId)</td><td>$($a.ActionType)</td><td class=`"$statusClass`">$($a.Status)</td><td>$($a.Result)</td></tr>"
                }
                $html += "</table>"
                if (-not $actions -or $actions.Count -eq 0) {
                    $html = "<p style='color:#64748b;'>No actions found in the selected date range.</p>"
                }
                $data = $actions
            }
            default {
                $html = "<p>Unknown report type: $ReportType</p>"
            }
        }

        return @{
            success = $true
            reportType = $ReportType
            startDate = $StartDate
            endDate = $EndDate
            html = $html
            data = $data
        } | ConvertTo-Json -Depth 10
    }
    catch {
        return @{
            success = $false
            error = $_.Exception.Message
        } | ConvertTo-Json
    }
}

function Get-ReportDownloadAPI {
    param(
        [string]$ReportType,
        [string]$Format,
        [string]$StartDate,
        [string]$EndDate
    )

    try {
        # Get report data
        $data = @()

        switch ($ReportType) {
            "ExecutiveSummary" {
                $deviceCount = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Devices").Count
                $onlineDevices = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Devices WHERE Status IN ('Online', 'Healthy', 'Warning', 'Critical')").Count
                $activeAlerts = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Alerts WHERE ResolvedAt IS NULL").Count
                $criticalAlerts = (Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM Alerts WHERE Severity = 'Critical' AND ResolvedAt IS NULL").Count

                $data = @(
                    [PSCustomObject]@{ Metric = "Total Devices"; Value = $deviceCount }
                    [PSCustomObject]@{ Metric = "Online Devices"; Value = $onlineDevices }
                    [PSCustomObject]@{ Metric = "Offline Devices"; Value = ($deviceCount - $onlineDevices) }
                    [PSCustomObject]@{ Metric = "Fleet Health %"; Value = [math]::Round(($onlineDevices / [math]::Max($deviceCount, 1)) * 100, 1) }
                    [PSCustomObject]@{ Metric = "Critical Alerts"; Value = $criticalAlerts }
                    [PSCustomObject]@{ Metric = "Active Alerts"; Value = $activeAlerts }
                )
            }
            "DeviceInventory" {
                $data = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT DeviceId, Hostname, Status, OS, LastSeen FROM Devices ORDER BY Hostname"
            }
            "AlertSummary" {
                $data = Invoke-SqliteQuery -DataSource $DatabasePath -Query @"
SELECT AlertId, DeviceId, AlertType, Severity, Message, CreatedAt,
       CASE WHEN ResolvedAt IS NOT NULL THEN 'Resolved' WHEN AcknowledgedAt IS NOT NULL THEN 'Acknowledged' ELSE 'Active' END as Status
FROM Alerts
WHERE datetime(CreatedAt) >= datetime('$StartDate') AND datetime(CreatedAt) <= datetime('$EndDate 23:59:59')
ORDER BY CreatedAt DESC
"@
            }
            "UptimeReport" {
                $data = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT DeviceId, Hostname, Status, LastSeen FROM Devices ORDER BY Hostname"
            }
            "PerformanceTrends" {
                $data = Invoke-SqliteQuery -DataSource $DatabasePath -Query @"
SELECT DeviceId, MetricType, Value, Timestamp
FROM Metrics
WHERE datetime(Timestamp) >= datetime('$StartDate') AND datetime(Timestamp) <= datetime('$EndDate 23:59:59')
ORDER BY Timestamp DESC
"@
            }
            "AuditLog" {
                $data = Invoke-SqliteQuery -DataSource $DatabasePath -Query @"
SELECT ActionId, DeviceId, ActionType, Status, CreatedAt, CompletedAt, Result
FROM Actions
WHERE datetime(CreatedAt) >= datetime('$StartDate') AND datetime(CreatedAt) <= datetime('$EndDate 23:59:59')
ORDER BY CreatedAt DESC
"@
            }
        }

        # Convert to proper format
        switch ($Format) {
            "csv" {
                if ($data -and $data.Count -gt 0) {
                    $csv = $data | ConvertTo-Csv -NoTypeInformation
                    return @{
                        success = $true
                        content = ($csv -join "`n")
                        contentType = "text/csv"
                        filename = "$ReportType`_$StartDate`_to_$EndDate.csv"
                    }
                } else {
                    return @{ success = $true; content = "No data"; contentType = "text/csv"; filename = "$ReportType.csv" }
                }
            }
            "xlsx" {
                # Generate a simple HTML table that can be opened in Excel
                $html = "<html><head><meta charset='UTF-8'></head><body><table border='1'>"
                if ($data -and $data.Count -gt 0) {
                    $props = $data[0].PSObject.Properties.Name
                    $html += "<tr>" + ($props | ForEach-Object { "<th>$_</th>" }) -join "" + "</tr>"
                    foreach ($row in $data) {
                        $html += "<tr>" + ($props | ForEach-Object { "<td>$($row.$_)</td>" }) -join "" + "</tr>"
                    }
                }
                $html += "</table></body></html>"
                return @{
                    success = $true
                    content = $html
                    contentType = "application/vnd.ms-excel"
                    filename = "$ReportType`_$StartDate`_to_$EndDate.xls"
                }
            }
            "pdf" {
                # Generate HTML that can be printed to PDF
                $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <title>$ReportType Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #1e3a5f; border-bottom: 2px solid #3b82f6; padding-bottom: 10px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #3b82f6; color: white; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .header { margin-bottom: 20px; }
        .date-range { color: #666; font-size: 14px; }
    </style>
</head>
<body>
    <div class='header'>
        <h1>$ReportType Report</h1>
        <p class='date-range'>Date Range: $StartDate to $EndDate</p>
        <p class='date-range'>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    </div>
    <table>
"@
                if ($data -and $data.Count -gt 0) {
                    $props = $data[0].PSObject.Properties.Name
                    $html += "<tr>" + (($props | ForEach-Object { "<th>$_</th>" }) -join "") + "</tr>"
                    foreach ($row in $data) {
                        $html += "<tr>" + (($props | ForEach-Object { "<td>$($row.$_)</td>" }) -join "") + "</tr>"
                    }
                } else {
                    $html += "<tr><td>No data available for the selected date range.</td></tr>"
                }
                $html += "</table></body></html>"
                return @{
                    success = $true
                    content = $html
                    contentType = "text/html"
                    filename = "$ReportType`_$StartDate`_to_$EndDate.html"
                }
            }
            default {
                return @{ success = $false; error = "Unknown format: $Format" }
            }
        }
    }
    catch {
        return @{ success = $false; error = $_.Exception.Message }
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
                    # Redirect to unified Sites & Devices page
                    $response.StatusCode = 302
                    $response.Headers.Add("Location", "/sites-and-devices")
                    $responseContent = ""
                }
                "^/sites-and-devices$" {
                    # Unified Sites & Devices page
                    $responseContent = Get-SitesAndDevicesPageHTML
                }
                "^/alerts$" {
                    # Alerts page
                    $responseContent = Get-AlertsPageHTML
                }
                "^/reports$" {
                    # Reports page
                    $responseContent = Get-ReportsPageHTML
                }
                "^/api/reports/generate" {
                    # Generate report API
                    $contentType = "application/json"
                    $reportType = "ExecutiveSummary"
                    $startDate = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")
                    $endDate = (Get-Date).ToString("yyyy-MM-dd")
                    if ($url -match "type=([^&]+)") { $reportType = [System.Web.HttpUtility]::UrlDecode($matches[1]) }
                    if ($url -match "startDate=([^&]+)") { $startDate = [System.Web.HttpUtility]::UrlDecode($matches[1]) }
                    if ($url -match "endDate=([^&]+)") { $endDate = [System.Web.HttpUtility]::UrlDecode($matches[1]) }
                    $responseContent = Get-ReportDataAPI -ReportType $reportType -StartDate $startDate -EndDate $endDate
                }
                "^/api/reports/download" {
                    # Download report API
                    $reportType = "ExecutiveSummary"
                    $format = "csv"
                    $startDate = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")
                    $endDate = (Get-Date).ToString("yyyy-MM-dd")
                    if ($url -match "type=([^&]+)") { $reportType = [System.Web.HttpUtility]::UrlDecode($matches[1]) }
                    if ($url -match "format=([^&]+)") { $format = [System.Web.HttpUtility]::UrlDecode($matches[1]) }
                    if ($url -match "startDate=([^&]+)") { $startDate = [System.Web.HttpUtility]::UrlDecode($matches[1]) }
                    if ($url -match "endDate=([^&]+)") { $endDate = [System.Web.HttpUtility]::UrlDecode($matches[1]) }

                    $result = Get-ReportDownloadAPI -ReportType $reportType -Format $format -StartDate $startDate -EndDate $endDate

                    if ($result.success) {
                        $contentType = $result.contentType
                        $response.Headers.Add("Content-Disposition", "attachment; filename=`"$($result.filename)`"")
                        $responseContent = $result.content
                    } else {
                        $contentType = "application/json"
                        $responseContent = @{ success = $false; error = $result.error } | ConvertTo-Json
                    }
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
                    # Redirect to unified Sites & Devices page
                    $response.StatusCode = 302
                    $response.Headers.Add("Location", "/sites-and-devices")
                    $responseContent = ""
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
                "^/api/sites/([a-zA-Z0-9\-]+)/export$" {
                    # Export a single site with its devices
                    $contentType = "application/json"
                    $siteId = $matches[1]
                    $responseContent = Export-SingleSiteJSON -SiteId $siteId
                }
                "^/api/sites/([a-zA-Z0-9\-]+)/devices/export$" {
                    # Export devices for a specific site
                    $contentType = "application/json"
                    $siteId = $matches[1]
                    $responseContent = Export-SiteDevicesJSON -SiteId $siteId
                }
                "^/api/sites/export$" {
                    # Export all sites to JSON
                    $contentType = "application/json"
                    $responseContent = Export-SitesJSON
                }
                "^/api/sites/import$" {
                    # Import sites from JSON (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Import-SitesAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/devices/export$" {
                    # Export all devices to JSON
                    $contentType = "application/json"
                    $responseContent = Export-DevicesJSON
                }
                "^/api/devices/import$" {
                    # Import devices from JSON (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Import-DevicesAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/sites/(?!add$|update$|delete$|urls$|export$|import$)([a-zA-Z0-9\-]+)$" {
                    # Get single site API (excludes reserved words: add, update, delete, urls, export, import)
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
                "^/api/devices/([^/]+)/urls$" {
                    # Get device URLs API
                    $contentType = "application/json"
                    $deviceId = $matches[1]
                    $responseContent = Get-DeviceURLsJSON -DeviceId $deviceId
                }
                "^/api/devices/urls/add$" {
                    # Add device URL API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Add-DeviceURLAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/devices/urls/delete$" {
                    # Remove device URL API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Remove-DeviceURLAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/urls/credential$" {
                    # Get URL credential API (POST) - returns decrypted password
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Get-URLCredentialAPI -Body $body
                    } else {
                        $response.StatusCode = 405
                        $responseContent = @{ error = "Method not allowed" } | ConvertTo-Json
                    }
                }
                "^/api/devices/([^/]+)/credentials$" {
                    # Get device credentials API
                    $contentType = "application/json"
                    $deviceId = $matches[1]
                    $responseContent = Get-DeviceCredentialsAPI -DeviceId $deviceId
                }
                "^/api/devices/credentials/save$" {
                    # Save device credentials API (POST)
                    if ($method -eq "POST") {
                        $contentType = "application/json"
                        $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                        $responseContent = Save-DeviceCredentialsAPI -Body $body
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
