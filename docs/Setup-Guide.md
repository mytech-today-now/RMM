# myTech.Today RMM - Setup Guide

## Quick Start

### Windows (One Command)

```powershell
git clone https://github.com/mytech-today/rmm.git
cd rmm
.\Install.ps1
```

### MacOS

```bash
git clone https://github.com/mytech-today/rmm.git
cd rmm
chmod +x install-macos.sh
./install-macos.sh
```

### Linux (Ubuntu, Debian, CentOS, RHEL, Fedora)

```bash
git clone https://github.com/mytech-today/rmm.git
cd rmm
chmod +x install-linux.sh
./install-linux.sh
```

That's it! The automated installer handles everything.

## What the Installer Does

The `Install.ps1` script performs these steps automatically:

1. **Installs Dependencies** - PSSQLite, ImportExcel, PSWriteHTML modules
2. **Creates Directory Structure** - Sets up folders at `%USERPROFILE%\myTech.Today\`
3. **Copies RMM Files** - Installs scripts to `%USERPROFILE%\myTech.Today\RMM\`
4. **Initializes Database** - Creates SQLite database with full schema
5. **Creates Configuration** - Generates settings.json with defaults
6. **Registers PowerShell Module** - Enables `Import-Module RMM` from anywhere
7. **Creates Shortcuts** - Desktop and Start Menu shortcuts for the Web Dashboard

## Installation Paths

| Component | Path |
|-----------|------|
| RMM Scripts | `%USERPROFILE%\myTech.Today\RMM\` |
| Database | `%USERPROFILE%\myTech.Today\data\devices.db` |
| Configuration | `%USERPROFILE%\myTech.Today\config\settings.json` |
| Logs | `%USERPROFILE%\myTech.Today\logs\` |
| Secrets | `%USERPROFILE%\myTech.Today\secrets\` |
| Module | `Documents\WindowsPowerShell\Modules\RMM\` |
| Desktop Shortcut | `Desktop\myTech.Today RMM Dashboard.lnk` |
| Start Menu | `Start Menu\Programs\myTech.Today\` |

## After Installation

### Option 1: Use the Desktop/Start Menu Shortcut

Double-click **"myTech.Today RMM Dashboard"** on your Desktop or find it in the Start Menu under **myTech.Today**.

### Option 2: Use PowerShell

```powershell
# Import and initialize the RMM module
Import-Module RMM
Initialize-RMM

# List devices
Get-RMMDevice

# Launch the Web Dashboard
& "$(Get-RMMInstallPath)\scripts\ui\Start-WebDashboard.ps1" -OpenBrowser
```

### Option 3: Portable Mode (Development)

Run directly from the source folder without installing:

```powershell
cd path\to\RMM
Import-Module .\scripts\core\RMM-Core.psm1
Initialize-RMM
```

## Uninstall

Multiple uninstall options are available:

### Option 1: Dedicated Uninstall Script (Recommended)

```powershell
# Basic uninstall - preserves data
.\Uninstall.ps1

# Complete removal including all data
.\Uninstall.ps1 -RemoveData

# Skip confirmation prompts
.\Uninstall.ps1 -Force
```

### Option 2: Via Install Script

```powershell
.\Install.ps1 -Uninstall
```

### Option 3: Via PowerShell Module

```powershell
Import-Module RMM
Initialize-RMM -Mode Uninstall
```

### Option 4: Via Web Dashboard

1. Open the Web Dashboard (http://localhost:8080)
2. Navigate to **Settings**
3. Scroll to the **Uninstall RMM** section
4. Follow the displayed instructions

### What Gets Removed

All uninstall methods remove:

- RMM installation folder (`%USERPROFILE%\myTech.Today\RMM\`)
- PowerShell module registration
- Desktop shortcut
- Start Menu folder and shortcuts
- Running dashboard processes

### What Gets Preserved (by default)

Your data is preserved at `%USERPROFILE%\myTech.Today\`:

- Database (`data\devices.db`)
- Logs (`logs\`)
- Configuration (`config\`)

### Complete Removal

To remove everything including data:

```powershell
.\Uninstall.ps1 -RemoveData
```

Or manually:

```powershell
Remove-Item "$env:USERPROFILE\myTech.Today" -Recurse -Force
```

## Reinstall / Update

```powershell
.\Install.ps1 -Force
```

---

## Prerequisites

### System Requirements

- **Operating System**: Windows 10/11 or Windows Server 2016+
- **PowerShell**: Version 5.1 minimum, PowerShell 7+ recommended
- **Administrator Rights**: Recommended (required for All Users Start Menu shortcut)
- **Memory**: 4GB minimum, 8GB+ for 500+ endpoints

### Network Requirements

- **Port 5985** (HTTP) or **Port 5986** (HTTPS) for WinRM
- **Port 8080** for Web Dashboard (configurable)

### Required PowerShell Modules

| Module | Purpose | Auto-Installed |
|--------|---------|----------------|
| PSSQLite | SQLite database operations | ✅ Yes |
| ImportExcel | Excel report generation | ✅ Yes |
| PSWriteHTML | HTML report generation | ✅ Yes |

## WinRM Configuration

### On the Central Console (Management Server)

```powershell
# Enable WinRM
Enable-PSRemoting -Force

# Configure TrustedHosts for workgroup environments
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

# Verify configuration
Get-Item WSMan:\localhost\Client\TrustedHosts
```

### On Remote Endpoints

```powershell
# Run on each endpoint (via GPO or deployment script)
Enable-PSRemoting -Force
Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -RemoteAddress Any

# For HTTPS (recommended for production)
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force
```

## First Device Onboarding

### Add a Single Device

```powershell
Import-Module RMM
Initialize-RMM

# Add localhost as first device
Add-RMMDevice -Hostname "localhost" -IPAddress "127.0.0.1" -SiteId "main" -Tags "local,test"

# Verify device was added
Get-RMMDevice -Hostname "localhost"
```

### Import Devices from CSV

```powershell
# Import devices from sample file (located at the RMM install path)
$rmmPath = Get-RMMInstallPath
Import-RMMDevices -Path "$rmmPath\sample-devices.csv"
```

CSV Format:

```csv
Hostname,FQDN,IPAddress,MACAddress,SiteId,OSName,OSVersion,Tags
SERVER01,server01.domain.local,192.168.1.10,00:15:5D:00:01:01,main,Windows Server 2022,10.0.20348,"production,critical"
```

### Add Devices via Web Interface

The web dashboard provides a user-friendly interface for adding devices:

1. Open the Web Dashboard (http://localhost:8080)
2. Navigate to **Devices**
3. Click **"+ Add Device"**
4. Fill in the device details:
   - **Hostname**: Enter hostname (auto-validates via DNS, shows ✅ if resolved)
   - **IP Address**: Enter IP (auto-validates via ping, shows ✅ if reachable)
   - **Site**: Select existing site or click "+ Add New Site..." to create one inline
   - **Device Type**: Workstation, Server, Laptop, Virtual, Container, or Other
   - **Description**: Optional device description
   - **Tags**: Comma-separated tags

### Device Pairing (Client Onboarding)

For remote client onboarding:

1. In the Add Device modal, click **"Generate Code"**
2. A 6-character alphanumeric code appears with a 10-minute countdown
3. Share this code with the remote user
4. The remote user enters the code in their RMM client to register their device

### Remove a Device

1. Navigate to **Devices** → Click on a device
2. Scroll to the **"Danger Zone"** section
3. Click **"Forget Device"** and confirm

### Device Detail Page

Click on any device hostname to view its detail page. The page is organized into sections:

**Read-Only Information:**

- Device ID, Hostname, FQDN, IP Address, MAC Address
- Status (with issue description for non-OK statuses)
- Last Seen timestamp

**System Information:**

- Operating System and version
- OS Build number
- Manufacturer, Model, Serial Number
- Agent Version

**Editable Fields:**

- **Site** - Dropdown to assign device to a site
- **Device Type** - Workstation, Server, Laptop, Virtual Machine, Network Device, Mobile Device, Other
- **Tags** - Comma-separated tags for grouping
- **Description** - Short description of the device
- **Credential Name** - Reference to stored credentials for remote access
- **Notes** - Multi-line notes field

**Timestamps:**

- Created At, Updated At

**Quick Actions:**

- Health Check - Run immediate health check
- Collect Inventory - Gather hardware/software inventory
- Reboot - Restart the device (with confirmation)

**Danger Zone:**

- Forget Device - Remove from database (cannot be undone)

![Device Detail Page](screenshots/device-detail.png)

---

## Client Installation (Managed Devices)

For devices that will be managed by an RMM server (not running the server themselves), use the lightweight client installers.

### MacOS Client

```bash
# Download and run the client installer
chmod +x install-client-macos.sh
./install-client-macos.sh

# Or with auto-registration (provide server URL and pairing code)
./install-client-macos.sh --server http://YOUR_SERVER:8080 --code ABC123
```

### Linux Client

```bash
# Download and run the client installer
chmod +x install-client-linux.sh
./install-client-linux.sh

# Or with auto-registration
./install-client-linux.sh --server http://YOUR_SERVER:8080 --code ABC123
```

### Windows Client

```powershell
# Run the client agent interactively
.\scripts\core\RMM-Client.ps1 -Interactive

# Or with parameters
.\scripts\core\RMM-Client.ps1 -ServerUrl "http://YOUR_SERVER:8080" -PairingCode "ABC123"
```

### Client Registration Workflow

1. **Administrator** generates a pairing code in the Web Dashboard (valid for 10 minutes)
2. **Administrator** shares the server URL and pairing code with the device user
3. **User** runs the client installer with the provided credentials
4. **Device** automatically registers with the server, sending:
   - Hostname (displayed in uppercase)
   - IP Address
   - Operating System details
   - Device Type (auto-detected)
   - Hardware information (manufacturer, model, serial)
5. **Administrator** sees the new device appear in the dashboard

---

## Verifying Installation

```powershell
# 1. Check module loads
Import-Module RMM -Force
Get-Module RMM

# 2. Check install path
Get-RMMInstallPath  # Should return C:\Users\<username>\myTech.Today\RMM

# 3. Check database
$dbPath = Get-RMMDatabase
Test-Path $dbPath  # Should return True

# 4. Check tables exist
Import-Module PSSQLite
Invoke-SqliteQuery -DataSource $dbPath -Query "SELECT name FROM sqlite_master WHERE type='table'"

# 5. Check device count
(Get-RMMDevice).Count

# 6. Check health status
Get-RMMHealth
```

## Common Installation Issues

### Issue: "Module not found" Error

**Solution**: Run the installer again or import from the install path:

```powershell
# Option 1: Run installer
.\Install.ps1 -Force

# Option 2: Import directly
Import-Module "$env:USERPROFILE\myTech.Today\RMM\scripts\core\RMM-Core.psm1" -Force
```

### Issue: "Access Denied" on WinRM

**Solution**: Run PowerShell as Administrator and verify credentials:

```powershell
Test-WSMan -ComputerName "target-server" -Credential (Get-Credential)
```

### Issue: Database Locked

**Solution**: Close other connections and retry:

```powershell
[System.GC]::Collect()
Start-Sleep -Seconds 2
```

### Issue: Firewall Blocking Connections

**Solution**: Open required ports:

```powershell
New-NetFirewallRule -DisplayName "WinRM HTTP" -Direction Inbound -Port 5985 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WinRM HTTPS" -Direction Inbound -Port 5986 -Protocol TCP -Action Allow
```

### Issue: Start Menu Shortcut Not Created

**Solution**: The All Users Start Menu requires Administrator rights. Run PowerShell as Administrator and reinstall:

```powershell
.\Install.ps1 -Force
```

Or manually create the shortcut in your personal Start Menu folder.

---

myTech.Today RMM - Setup Guide v2.0
