/**
 * myTech.Today RMM Dashboard - JavaScript Application
 */
const refreshInterval = 30000;
let refreshCountdown = 30;
let countdownTimer = null;
let deviceStatusChart = null;
let alertSeverityChart = null;

async function loadDashboardData() {
    try { await Promise.all([loadFleetStatus(), loadAlertsPreview(), loadActionsPreview()]); }
    catch (error) { console.error('Error loading dashboard data:', error); }
}

async function loadFleetStatus() {
    try {
        const fleetOnline = document.getElementById('fleet-online');
        const fleetPercent = document.getElementById('fleet-percent');
        const offlineCount = document.getElementById('offline-count');
        if (!fleetOnline || !fleetPercent || !offlineCount) return; // Not on dashboard page
        const data = await (await fetch('/api/fleet')).json();
        fleetOnline.textContent = (data.Online || 0) + '/' + (data.Total || 0);
        fleetPercent.textContent = (data.Total > 0 ? Math.round((data.Online / data.Total) * 100) : 0) + '% Online';
        offlineCount.textContent = data.Offline || 0;
    } catch (e) { console.error('Error loading fleet:', e); }
}

async function loadAlertsPreview() {
    try {
        const alertCount = document.getElementById('alert-count');
        const alertCritical = document.getElementById('alert-critical');
        if (!alertCount || !alertCritical) return; // Not on dashboard page
        const data = await (await fetch('/api/alerts')).json();
        alertCount.textContent = data.Total || 0;
        alertCritical.textContent = (data.Critical || 0) + ' Critical';
        const c = document.getElementById('alerts-list');
        if (c && data.Alerts && data.Alerts.length > 0) {
            let h = '<table><thead><tr><th>Severity</th><th>Device</th><th>Alert</th><th>Time</th></tr></thead><tbody>';
            data.Alerts.forEach(a => { h += '<tr><td><span class="badge badge-' + (a.Severity||'low').toLowerCase() + '">' + a.Severity + '</span></td><td>' + a.DeviceId + '</td><td>' + a.Title + '</td><td>' + a.CreatedAt + '</td></tr>'; });
            c.innerHTML = h + '</tbody></table>';
        } else if (c) { c.innerHTML = '<p class="success-text">No active alerts!</p>'; }
    } catch (e) { console.error('Error loading alerts:', e); }
}

async function loadActionsPreview() {
    try {
        const actionCount = document.getElementById('action-count');
        if (!actionCount) return; // Not on dashboard page
        const data = await (await fetch('/api/actions')).json();
        actionCount.textContent = (data.actions || []).length;
        const c = document.getElementById('actions-list');
        if (c && data.actions && data.actions.length > 0) {
            let h = '<table><thead><tr><th>Device</th><th>Action</th><th>Status</th><th>Time</th></tr></thead><tbody>';
            data.actions.forEach(a => {
                let s = 'warning';
                if (a.Status === 'Completed') s = 'success';
                else if (a.Status === 'Failed') s = 'danger';
                h += '<tr><td>' + (a.DeviceId||'N/A') + '</td><td>' + a.ActionType + '</td><td><span class="badge badge-' + s + '">' + a.Status + '</span></td><td>' + a.CreatedAt + '</td></tr>';
            });
            c.innerHTML = h + '</tbody></table>';
        } else if (c) { c.innerHTML = '<p>No recent actions.</p>'; }
    } catch (e) { console.error('Error loading actions:', e); }
}

async function loadDevices() {
    try {
        const data = await (await fetch('/api/devices')).json();
        const c = document.getElementById('devices-list');
        if (c && data.devices && data.devices.length > 0) {
            let h = '<table><thead><tr><th>Hostname</th><th>IP</th><th>Status</th><th>Last Seen</th><th>Actions</th></tr></thead><tbody>';
            data.devices.forEach(d => { h += '<tr><td><a href="/devices/' + d.DeviceId + '">' + d.Hostname + '</a></td><td>' + (d.IPAddress||'N/A') + '</td><td><span class="badge badge-' + (d.Status==='Online'?'online':'offline') + '">' + d.Status + '</span></td><td>' + (d.LastSeen||'Never') + '</td><td><button class="btn btn-primary" onclick="executeDeviceAction(\'' + d.DeviceId + '\',\'HealthCheck\')">Check</button></td></tr>'; });
            c.innerHTML = h + '</tbody></table>';
        } else if (c) { c.innerHTML = '<p>No devices found.</p>'; }
    } catch (e) { console.error('Error loading devices:', e); }
}

async function loadAlerts() {
    try {
        const data = await (await fetch('/api/alerts')).json();
        const c = document.getElementById('alerts-list');
        if (c && data.Alerts && data.Alerts.length > 0) {
            let h = '<table><thead><tr><th>Severity</th><th>Device</th><th>Title</th><th>Created</th><th>Actions</th></tr></thead><tbody>';
            data.Alerts.forEach(a => { h += '<tr><td><span class="badge badge-' + (a.Severity||'low').toLowerCase() + '">' + a.Severity + '</span></td><td>' + a.DeviceId + '</td><td>' + a.Title + '</td><td>' + a.CreatedAt + '</td><td><button class="btn" onclick="acknowledgeAlert(\'' + a.AlertId + '\')">Ack</button> <button class="btn btn-success" onclick="resolveAlert(\'' + a.AlertId + '\')">Resolve</button></td></tr>'; });
            c.innerHTML = h + '</tbody></table>';
        } else if (c) { c.innerHTML = '<p class="success-text">No active alerts!</p>'; }
    } catch (e) { console.error('Error loading alerts:', e); }
}

async function loadActions() {
    try {
        const data = await (await fetch('/api/actions')).json();
        const c = document.getElementById('actions-list');
        if (c && data.actions && data.actions.length > 0) {
            let h = '<table><thead><tr><th>Device</th><th>Action</th><th>Status</th><th>Created</th></tr></thead><tbody>';
            data.actions.forEach(a => {
                let s = 'warning';
                if (a.Status === 'Completed') s = 'success';
                else if (a.Status === 'Failed') s = 'danger';
                else if (a.Status === 'Cancelled') s = 'secondary';
                const deviceDisplay = (a.Site || 'Unknown') + ':' + (a.Hostname || 'Unknown');
                h += '<tr><td>' + deviceDisplay + '</td><td>' + a.ActionType + '</td><td><span class="badge badge-' + s + '">' + a.Status + '</span></td><td>' + a.CreatedAt + '</td></tr>';
            });
            c.innerHTML = h + '</tbody></table>';
        } else if (c) { c.innerHTML = '<p>No recent actions.</p>'; }
    } catch (e) { console.error('Error loading actions:', e); }
}

async function clearActionsHistory() {
    if (!confirm('Are you sure you want to clear all actions history? This cannot be undone.')) return;
    try {
        const result = await (await fetch('/api/actions/clear', { method: 'POST' })).json();
        if (result.success) {
            loadActions();
        } else {
            alert('Error clearing actions: ' + (result.error || 'Unknown error'));
        }
    } catch (e) {
        console.error('Error clearing actions:', e);
        alert('Error clearing actions: ' + e.message);
    }
}

async function executeAction(event) {
    event.preventDefault();
    const deviceId = document.getElementById('deviceId').value;
    const actionType = document.getElementById('actionType').value;
    const resultDiv = document.getElementById('action-result');
    if (!deviceId) { resultDiv.innerHTML = '<div class="action-result error">Please enter a Device ID</div>'; return; }
    try {
        const result = await (await fetch('/api/actions/execute', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ deviceId, actionType }) })).json();
        resultDiv.innerHTML = result.success ? '<div class="action-result success">' + result.message + '</div>' : '<div class="action-result error">' + result.error + '</div>';
        if (result.success) loadActions();
    } catch (e) { resultDiv.innerHTML = '<div class="action-result error">Error: ' + e.message + '</div>'; }
}

async function executeDeviceAction(deviceId, actionType) {
    try {
        const result = await (await fetch('/api/actions/execute', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ deviceId, actionType }) })).json();
        alert(result.success ? result.message : result.error);
    } catch (e) { alert('Error: ' + e.message); }
}

async function acknowledgeAlert(alertId) {
    try {
        const result = await (await fetch('/api/alerts/acknowledge', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ alertId }) })).json();
        if (result.success) loadAlerts(); else alert('Error: ' + result.error);
    } catch (e) { alert('Error: ' + e.message); }
}

async function resolveAlert(alertId) {
    try {
        const result = await (await fetch('/api/alerts/resolve', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ alertId }) })).json();
        if (result.success) loadAlerts(); else alert('Error: ' + result.error);
    } catch (e) { alert('Error: ' + e.message); }
}

async function initCharts() {
    const deviceCanvas = document.getElementById('deviceStatusChart');
    const alertCanvas = document.getElementById('alertSeverityChart');
    if (!deviceCanvas || !alertCanvas) return;
    try {
        const fleetData = await (await fetch('/api/fleet')).json();
        const alertData = await (await fetch('/api/alerts')).json();
        deviceStatusChart = new Chart(deviceCanvas, { type: 'doughnut', data: { labels: ['Online', 'Offline'], datasets: [{ data: [fleetData.Online || 0, fleetData.Offline || 0], backgroundColor: ['#28a745', '#e74c3c'], borderWidth: 0 }] }, options: { responsive: true, plugins: { legend: { position: 'bottom' } } } });
        alertSeverityChart = new Chart(alertCanvas, { type: 'bar', data: { labels: ['Critical', 'High', 'Medium', 'Low'], datasets: [{ label: 'Alerts', data: [alertData.Critical || 0, alertData.High || 0, alertData.Medium || 0, alertData.Low || 0], backgroundColor: ['#e74c3c', '#f39c12', '#3498db', '#95a5a6'] }] }, options: { responsive: true, plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } } } });
    } catch (e) { console.error('Error initializing charts:', e); }
}

function startAutoRefresh() {
    refreshCountdown = 30;
    countdownTimer = setInterval(() => {
        refreshCountdown--;
        const el = document.getElementById('refresh-countdown');
        if (el) el.textContent = refreshCountdown;
        if (refreshCountdown <= 0) { refreshCountdown = 30; loadDashboardData(); updateCharts(); }
    }, 1000);
}

async function updateCharts() {
    if (!deviceStatusChart || !alertSeverityChart) return;
    try {
        const fleetData = await (await fetch('/api/fleet')).json();
        const alertData = await (await fetch('/api/alerts')).json();
        deviceStatusChart.data.datasets[0].data = [fleetData.Online || 0, fleetData.Offline || 0];
        deviceStatusChart.update();
        alertSeverityChart.data.datasets[0].data = [alertData.Critical || 0, alertData.High || 0, alertData.Medium || 0, alertData.Low || 0];
        alertSeverityChart.update();
    } catch (e) { console.error('Error updating charts:', e); }
}

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

document.addEventListener('DOMContentLoaded', () => { loadDashboardData(); initCharts(); startAutoRefresh(); });
console.log('myTech.Today RMM Dashboard loaded');
