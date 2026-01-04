# myTech.Today RMM - Troubleshooting Guide

## Log File Locations

All logs are stored in: `%USERPROFILE%\myTech.Today\logs\`

| Log File | Contents |
|----------|----------|
| `rmm-YYYYMMDD.log` | Main RMM operations |
| `devices\<hostname>.log` | Per-device activity |
| `errors.log` | Error details |
| `audit.log` | Security audit trail |

## Common Issues and Solutions

### 1. WinRM Connection Failures

**Symptoms:** "WinRM cannot complete the operation" or "Access denied"

**Automatic Handling:** The RMM module automatically handles most connection issues:

- Prefers HTTPS (port 5986) for workgroup targets when available
- Automatically manages TrustedHosts for HTTP connections
- Provides clear error messages with remediation steps

**Diagnostic Commands:**

```powershell
# Use RMM's built-in environment check
Test-RMMRemoteEnvironment -ComputerName "TARGET-SERVER"

# This returns:
# - LocalIsDomainJoined: Whether your machine is domain-joined
# - HTTPSAvailable: Whether target has HTTPS listener (port 5986)
# - HTTPAvailable: Whether target has HTTP listener (port 5985)
# - InTrustedHosts: Whether target is already trusted
# - RecommendedTransport: HTTP or HTTPS
# - ConnectionReady: Whether connection should work

# Check current TrustedHosts
Get-RMMTrustedHosts

# Check remoting preferences
Get-RMMRemotingPreference
```

**Manual Solutions (if automatic handling fails):**

```powershell
# Test WinRM connectivity
Test-WSMan -ComputerName "TARGET-SERVER"

# Check if HTTPS is available (preferred for workgroup)
Test-RMMRemoteHTTPS -ComputerName "TARGET-SERVER"

# Manually add to TrustedHosts (use -Concatenate to preserve existing entries)
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "TARGET-SERVER" -Concatenate -Force

# Or use RMM's safe method
Add-RMMTrustedHost -ComputerName "TARGET-SERVER"

# Test with credentials
$cred = Get-Credential
$session = New-RMMRemoteSession -ComputerName "TARGET-SERVER" -Credential $cred
```

**For Workgroup Environments (HTTPS Recommended):**

```powershell
# On the target server, configure HTTPS listener:
$cert = New-SelfSignedCertificate -DnsName "TARGET-SERVER" -CertStoreLocation Cert:\LocalMachine\My
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force
New-NetFirewallRule -Name "WINRM-HTTPS-In-TCP" -DisplayName "WinRM HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow

# Then connect with HTTPS requirement:
$session = New-RMMRemoteSession -ComputerName "TARGET-SERVER" -Credential $cred -RequireHTTPS
```

### 2. Database Locked Errors

**Symptoms:** "Database is locked" or "Unable to open database"

**Solutions:**

```powershell
# Close all PowerShell sessions using the database
Get-Process powershell | Where-Object { $_.Id -ne $PID } | Stop-Process

# Force garbage collection
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

# Wait and retry
Start-Sleep -Seconds 5

# If persists, check for file locks
$dbPath = Get-RMMDatabase
Get-Process | Where-Object { $_.Modules.FileName -contains $dbPath }
```

### 3. Module Import Failures

**Symptoms:** "Cannot find module" or "Function not exported"

**Solutions:**

```powershell
# Use full path to import
$modulePath = "C:\path\to\RMM\scripts\core\RMM-Core.psm1"
Import-Module $modulePath -Force -Verbose

# Check for syntax errors
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$null, [ref]$errors)
$errors

# Verify required modules are installed
Get-Module -ListAvailable PSSQLite, PSWindowsUpdate, ImportExcel
```

### 4. Credential/Authentication Issues

**Symptoms:** "Access denied" or "Credentials rejected"

**Solutions:**

```powershell
# Clear cached credentials
Remove-RMMCredential -Name "DefaultAdmin"

# Re-save credentials
$cred = Get-Credential
Save-RMMCredential -Name "DefaultAdmin" -Credential $cred

# Test credential
$cred = Get-RMMCredential -Name "DefaultAdmin"
Test-WSMan -ComputerName "TARGET" -Credential $cred
```

### 5. Firewall Blocking Connections

**Symptoms:** Connection timeout, "No route to host"

**Solutions:**

```powershell
# On target machine - open WinRM ports
New-NetFirewallRule -DisplayName "WinRM HTTP" -Direction Inbound -Port 5985 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WinRM HTTPS" -Direction Inbound -Port 5986 -Protocol TCP -Action Allow

# Test port connectivity
Test-NetConnection -ComputerName "TARGET" -Port 5985
```

### 6. Device Appearing Offline Incorrectly

**Symptoms:** Device shows offline but is actually running

**Solutions:**

```powershell
# Force status refresh
$device = Get-RMMDevice -Hostname "DEVICE-NAME"
$pingResult = Test-Connection $device.Hostname -Count 2 -Quiet
if ($pingResult) {
    Update-RMMDevice -Hostname $device.Hostname -Status "Online"
}

# Check cache expiry
Clear-RMMCache -Type "DeviceStatus"

# Verify correct IP address
Resolve-DnsName $device.Hostname
```

### 7. Reports Not Generating

**Symptoms:** Empty reports or generation errors

**Solutions:**

```powershell
# Check data exists
$devices = Get-RMMDevice
if ($devices.Count -eq 0) { Write-Warning "No devices in database" }

# Verify output path exists
$reportPath = ".\reports\"
if (-not (Test-Path $reportPath)) { New-Item -Path $reportPath -ItemType Directory }

# Check ImportExcel module
Import-Module ImportExcel -ErrorAction Stop
```

### 8. Web Dashboard Not Loading

**Symptoms:** "Connection refused" or blank page

**Solutions:**

```powershell
# Check if dashboard is running
Get-Process powershell | Where-Object { $_.CommandLine -like "*WebDashboard*" }

# Verify port is not in use
Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue

# Start dashboard manually
.\scripts\ui\Start-WebDashboard.ps1 -Port 8080 -Verbose

# Check firewall
New-NetFirewallRule -DisplayName "RMM Dashboard" -Direction Inbound -Port 8080 -Protocol TCP -Action Allow
```

## Diagnostic Commands

```powershell
# Full system diagnostic
Import-Module .\scripts\core\RMM-Core.psm1
$health = Get-RMMHealth
$dbStats = Get-RMMDatabaseStats

Write-Host "=== RMM Diagnostics ===" -ForegroundColor Cyan
Write-Host "Database Size: $($dbStats.SizeMB) MB"
Write-Host "Device Count: $($health.TotalDevices)"
Write-Host "Online: $($health.OnlineCount) | Offline: $($health.OfflineCount)"
Write-Host "Active Alerts: $($health.ActiveAlerts)"
```

## Enable Debug Logging

```powershell
# Set verbose logging
Set-RMMConfig -Section "Logging" -Key "Level" -Value "Debug"

# Or set environment variable
$env:RMM_DEBUG = "true"
```

## Database Repair

```powershell
# Backup first
Invoke-RMMDatabaseBackup

# Run integrity check
$dbPath = Get-RMMDatabase
Invoke-SqliteQuery -DataSource $dbPath -Query "PRAGMA integrity_check"

# Vacuum to reclaim space
Invoke-RMMDatabaseVacuum

# If corrupt, restore from backup
Copy-Item ".\data\backups\devices-latest.db" -Destination $dbPath -Force
```

## Reset Installation

```powershell
# WARNING: This deletes all data!
Remove-Item ".\data\devices.db" -Force
Remove-Item ".\logs\*" -Force -Recurse
.\scripts\core\Initialize-RMM.ps1 -Mode Install
```

## Getting Support

1. Check logs at `%USERPROFILE%\myTech.Today\logs\`
2. Run diagnostics: `Get-RMMHealth`
3. Report issues at: https://github.com/mytech-today/rmm/issues

---

*myTech.Today RMM - Troubleshooting Guide v1.0*

