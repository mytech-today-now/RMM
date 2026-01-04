# myTech.Today RMM - API Reference

## RMM-Core.psm1 Exported Functions

### Initialization

#### Initialize-RMM
Bootstrap the RMM environment.

```powershell
Initialize-RMM [-Mode <String>] [-ImportDevices <String>]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| Mode | String | No | "Install" for fresh install, "Update" for upgrade |
| ImportDevices | String | No | Path to CSV file for bulk device import |

**Example:**
```powershell
Initialize-RMM -Mode Install
Initialize-RMM -ImportDevices ".\sample-devices.csv"
```

---

### Configuration Management

#### Get-RMMConfig
Retrieve current configuration.

```powershell
Get-RMMConfig [-Section <String>]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| Section | String | No | Specific section: General, Monitoring, Alerting, etc. |

**Returns:** PSCustomObject with configuration settings.

**Example:**
```powershell
$config = Get-RMMConfig
$monitoringConfig = Get-RMMConfig -Section "Monitoring"
```

#### Set-RMMConfig
Update configuration settings.

```powershell
Set-RMMConfig -Section <String> -Key <String> -Value <Object>
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| Section | String | Yes | Configuration section to update |
| Key | String | Yes | Setting key name |
| Value | Object | Yes | New value |

**Example:**
```powershell
Set-RMMConfig -Section "Monitoring" -Key "PollingInterval" -Value 300
```

---

### Device Management

#### Get-RMMDevice
Retrieve device information.

```powershell
Get-RMMDevice [-DeviceId <String>] [-Hostname <String>] [-SiteId <String>] [-Status <String>]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| DeviceId | String | No | Specific device GUID |
| Hostname | String | No | Filter by hostname |
| SiteId | String | No | Filter by site |
| Status | String | No | Filter: Online, Offline, Warning, Critical |

**Returns:** Array of device objects.

**Example:**
```powershell
$allDevices = Get-RMMDevice
$server = Get-RMMDevice -Hostname "SERVER01"
$siteDevices = Get-RMMDevice -SiteId "main" -Status "Online"
```

#### Add-RMMDevice
Add a new managed device.

```powershell
Add-RMMDevice -Hostname <String> [-IPAddress <String>] [-FQDN <String>] [-MACAddress <String>]
              [-SiteId <String>] [-DeviceType <String>] [-Description <String>]
              [-Tags <String[]>] [-CredentialName <String>] [-Credential <PSCredential>] [-SaveCredential]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| Hostname | String | Yes | Device hostname |
| IPAddress | String | No | Device IP address |
| FQDN | String | No | Fully qualified domain name |
| MACAddress | String | No | Device MAC address |
| SiteId | String | No | Site identifier (default: "main") |
| DeviceType | String | No | Workstation, Server, Laptop, Virtual, Container, Other |
| Description | String | No | Device description |
| Tags | String[] | No | Tags for categorization |
| CredentialName | String | No | Name of saved WinRM credential |
| Credential | PSCredential | No | PSCredential object for WinRM |
| SaveCredential | Switch | No | Save the credential for future use |

**Returns:** Created device object.

**Example:**
```powershell
Add-RMMDevice -Hostname "SERVER01" -IPAddress "192.168.1.10" -SiteId "main" -Tags "production","critical"
Add-RMMDevice -Hostname "LAPTOP01" -DeviceType "Laptop" -Description "Sales team laptop" -Tags "sales"
```

#### Update-RMMDevice
Update device properties.

```powershell
Update-RMMDevice -Hostname <String> [-Status <String>] [-Tags <String[]>] [-SiteId <String>]
```

**Example:**
```powershell
Update-RMMDevice -Hostname "SERVER01" -Status "Online"
```

#### Remove-RMMDevice
Remove a device from management.

```powershell
Remove-RMMDevice -Hostname <String> [-Confirm]
```

**Example:**
```powershell
Remove-RMMDevice -Hostname "OLD-SERVER" -Confirm:$false
```

#### Import-RMMDevices
Import devices from a file.

```powershell
Import-RMMDevices -Path <String> [-UpdateExisting]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| Path | String | Yes | Path to CSV, JSON, XLS, or XLSX file |
| UpdateExisting | Switch | No | Update existing devices instead of skipping |

**Supported Formats:** CSV, JSON, XLS, XLSX

**Example:**
```powershell
Import-RMMDevices -Path ".\devices.csv"
Import-RMMDevices -Path ".\inventory.xlsx" -UpdateExisting
```

#### Export-RMMDevices
Export devices to a file.

```powershell
Export-RMMDevices -Path <String> [-SiteId <String>] [-Status <String>] [-Tags <String[]>] [-IncludeCredentials]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| Path | String | Yes | Output file path (.csv, .json, .xls, .xlsx) |
| SiteId | String | No | Filter by site |
| Status | String | No | Filter by status |
| Tags | String[] | No | Filter by tags |
| IncludeCredentials | Switch | No | Include credential names in export |

**Example:**
```powershell
Export-RMMDevices -Path ".\backup.csv"
Export-RMMDevices -Path ".\servers.xlsx" -SiteId "datacenter" -Status "Online"
```

---

### Action Execution

#### Invoke-RMMAction
Execute actions on devices.

```powershell
Invoke-RMMAction -ActionType <String> -Targets <String[]> [-Parameters <Hashtable>]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| ActionType | String | Yes | Action: Restart, Shutdown, RunScript, etc. |
| Targets | String[] | Yes | Target device hostnames |
| Parameters | Hashtable | No | Action-specific parameters |

**Returns:** Action result object with Status and Output.

**Example:**
```powershell
Invoke-RMMAction -ActionType "Restart" -Targets @("SERVER01","SERVER02")
Invoke-RMMAction -ActionType "RunScript" -Targets @("WS-001") -Parameters @{Script="Get-Process"}
```

---

### Health & Database

#### Get-RMMHealth
Get system health summary.

```powershell
Get-RMMHealth [-DeviceId <String>]
```

**Returns:** Health summary with device counts, alert counts, overall status.

**Example:**
```powershell
$health = Get-RMMHealth
Write-Host "Online: $($health.OnlineCount) | Offline: $($health.OfflineCount)"
```

#### Get-RMMDatabase
Get database connection path.

```powershell
Get-RMMDatabase
```

**Returns:** Full path to SQLite database file.

---

### Remoting (Workgroup/Non-Domain Support)

The RMM module provides secure remoting functions that automatically handle domain and workgroup environments.

#### Test-RMMRemoteEnvironment
Analyze connection requirements for a target computer.

```powershell
Test-RMMRemoteEnvironment -ComputerName <String>
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| ComputerName | String | Yes | Target computer hostname or IP |

**Returns:** PSCustomObject with:
- `LocalIsDomainJoined` - Whether local machine is domain-joined
- `HTTPSAvailable` - Whether target has HTTPS listener (port 5986)
- `HTTPAvailable` - Whether target has HTTP listener (port 5985)
- `InTrustedHosts` - Whether target is in TrustedHosts
- `RecommendedTransport` - HTTP or HTTPS
- `RequiresTrustedHost` - Whether TrustedHosts entry is needed
- `ConnectionReady` - Whether connection should work

**Example:**
```powershell
$env = Test-RMMRemoteEnvironment -ComputerName "WORKGROUP-PC"
if ($env.HTTPSAvailable) { Write-Host "HTTPS available - secure connection possible" }
```

#### New-RMMRemoteSession
Create a PSSession with automatic transport and TrustedHosts handling.

```powershell
New-RMMRemoteSession -ComputerName <String> [-Credential <PSCredential>] [-UseHTTPS] [-RequireHTTPS] [-SkipTrustedHostsManagement]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| ComputerName | String | Yes | Target computer hostname or IP |
| Credential | PSCredential | No | Credentials for authentication (required for workgroup) |
| UseHTTPS | Switch | No | Force HTTPS transport |
| RequireHTTPS | Switch | No | Require HTTPS - fail if not available |
| SkipTrustedHostsManagement | Switch | No | Do not auto-manage TrustedHosts |

**Returns:** PSSession object if successful, $null if failed.

**Example:**
```powershell
# Auto-detect best transport
$session = New-RMMRemoteSession -ComputerName "SERVER01"

# Require HTTPS for sensitive operations
$session = New-RMMRemoteSession -ComputerName "WORKGROUP-PC" -Credential $cred -RequireHTTPS
```

#### Invoke-RMMRemoteCommand
Execute a command on a remote computer with automatic connection handling.

```powershell
Invoke-RMMRemoteCommand -ComputerName <String> -ScriptBlock <ScriptBlock> [-ArgumentList <Object[]>] [-Credential <PSCredential>] [-RequireHTTPS]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| ComputerName | String | Yes | Target computer hostname or IP |
| ScriptBlock | ScriptBlock | Yes | Script block to execute remotely |
| ArgumentList | Object[] | No | Arguments to pass to the script block |
| Credential | PSCredential | No | Credentials for authentication |
| RequireHTTPS | Switch | No | Require HTTPS transport |

**Example:**
```powershell
Invoke-RMMRemoteCommand -ComputerName "SERVER01" -ScriptBlock { Get-Service WinRM }
$result = Invoke-RMMRemoteCommand -ComputerName "WORKGROUP-PC" -Credential $cred -ScriptBlock { param($svc) Get-Service $svc } -ArgumentList "Spooler"
```

#### Add-RMMTrustedHost
Safely add a computer to TrustedHosts using concatenation.

```powershell
Add-RMMTrustedHost -ComputerName <String> [-Temporary <Boolean>]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| ComputerName | String | Yes | Computer name or IP to add |
| Temporary | Boolean | No | Mark as temporary for cleanup (default: $true) |

**Example:**
```powershell
Add-RMMTrustedHost -ComputerName "WORKGROUP-PC"
```

#### Clear-RMMTemporaryTrustedHosts
Remove all temporarily added TrustedHosts entries.

```powershell
Clear-RMMTemporaryTrustedHosts
```

**Example:**
```powershell
# After completing workgroup operations
Clear-RMMTemporaryTrustedHosts
```

#### Set-RMMRemotingPreference
Configure remoting preferences for the module.

```powershell
Set-RMMRemotingPreference [-PreferHTTPS <Boolean>] [-AutoManageTrustedHosts <Boolean>]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| PreferHTTPS | Boolean | No | Prefer HTTPS when available (default: $true) |
| AutoManageTrustedHosts | Boolean | No | Auto-manage TrustedHosts (default: $true) |

**Example:**
```powershell
# Disable automatic TrustedHosts management
Set-RMMRemotingPreference -AutoManageTrustedHosts $false
```

#### Get-RMMRemotingPreference
Get current remoting preferences.

```powershell
Get-RMMRemotingPreference
```

**Returns:** PSCustomObject with current preferences and temporary TrustedHosts list.

---

### Error Codes

| Code | Meaning |
|------|---------|
| RMM001 | Database connection failed |
| RMM002 | Device not found |
| RMM003 | WinRM connection failed |
| RMM004 | Permission denied |
| RMM005 | Configuration error |
| RMM006 | Action execution failed |

---

## Web Dashboard REST API

The Web Dashboard exposes REST API endpoints for integration and automation.

### Base URL

```
http://localhost:8080/api
```

### Device Endpoints

#### GET /api/devices

Returns all devices.

**Response:**

```json
{
  "devices": [
    {
      "DeviceId": "abc-123",
      "Hostname": "SERVER01",
      "IPAddress": "192.168.1.10",
      "Status": "Online",
      "LastSeen": "2025-12-13 10:30:00"
    }
  ]
}
```

#### GET /api/devices/{deviceId}

Returns details for a specific device.

#### POST /api/devices/add

Add a new device.

**Request Body:**

```json
{
  "hostname": "SERVER01",
  "ipAddress": "192.168.1.10",
  "siteId": "main",
  "deviceType": "Server",
  "description": "Production web server",
  "tags": "production,web"
}
```

#### POST /api/devices/delete

Remove a device.

**Request Body:**

```json
{
  "deviceId": "abc-123-def-456"
}
```

#### GET /api/devices/export?format=csv|json

Export all devices in the specified format.

#### POST /api/devices/update

Update editable fields of a device.

**Request Body:**

```json
{
  "deviceId": "abc-123-def-456",
  "siteId": "site-uuid",
  "deviceType": "Server",
  "tags": "production,web,critical",
  "description": "Main production web server",
  "credentialName": "admin-creds",
  "notes": "Located in Rack 5, U12"
}
```

**Editable Fields:**

| Field | Type | Description |
|-------|------|-------------|
| siteId | string | UUID of the site to assign |
| deviceType | string | Workstation, Server, Laptop, Virtual Machine, Network Device, Mobile Device, Other |
| tags | string | Comma-separated tags |
| description | string | Short device description |
| credentialName | string | Reference to stored credentials |
| notes | string | Multi-line notes |

**Response:**

```json
{
  "success": true,
  "message": "Device updated successfully"
}
```

**Note:** Read-only fields (DeviceId, Hostname, FQDN, IPAddress, MACAddress, Status, LastSeen, OSName, OSVersion, OSBuild, Manufacturer, Model, SerialNumber, AgentVersion, CreatedAt) cannot be modified via this endpoint.

---

### Site Endpoints

#### GET /api/sites

Returns all sites.

#### POST /api/sites/add

Create a new site.

**Request Body:**

```json
{
  "name": "Branch Office"
}
```

---

### Pairing Endpoints

#### POST /api/pairing/create

Create a pairing code for client onboarding.

**Request Body:**

```json
{
  "code": "ABC123",
  "expiresAt": 1702500000000
}
```

#### POST /api/pairing/register

Register a device using a pairing code (called by client agent).

**Request Body:**

```json
{
  "pairingCode": "ABC123",
  "hostname": "WORKSTATION01",
  "ipAddress": "192.168.1.50",
  "osName": "Windows 11",
  "osVersion": "10.0.22631",
  "deviceType": "Workstation",
  "manufacturer": "Dell",
  "model": "OptiPlex 7090",
  "serialNumber": "ABC123XYZ"
}
```

**Response (Success):**

```json
{
  "success": true,
  "deviceId": "new-device-guid",
  "message": "Device registered successfully"
}
```

**Response (Error):**

```json
{
  "success": false,
  "error": "Pairing code has expired"
}
```

#### GET /api/pairing/status

Returns status of active pairing codes.

---

### Network Endpoints

#### GET /api/network/resolve?hostname=SERVER01

Resolve a hostname via DNS.

**Response:**

```json
{
  "success": true,
  "hostname": "SERVER01.domain.local",
  "ipAddress": "192.168.1.10",
  "deviceType": "Server"
}
```

#### GET /api/network/ping?ip=192.168.1.10

Ping an IP address.

**Response:**

```json
{
  "success": true,
  "reachable": true,
  "ip": "192.168.1.10"
}
```

---

### Action Endpoints

#### GET /api/actions

Returns recent actions.

#### POST /api/actions/execute

Queue an action for execution.

**Request Body:**

```json
{
  "deviceId": "abc-123",
  "actionType": "HealthCheck"
}
```

**Available Action Types:**

- Diagnostics: `HealthCheck`, `InventoryCollection`, `GetSystemInfo`
- Maintenance: `ClearTempFiles`, `FlushDNS`, `ClearEventLogs`, `DiskCleanup`
- Updates: `WindowsUpdate`, `CheckUpdates`
- Power: `Reboot`, `Shutdown`
- Network: `RenewIP`, `ResetNetwork`

---

### Alert Endpoints

#### GET /api/alerts

Returns active alerts.

#### POST /api/alerts/acknowledge

Acknowledge an alert.

**Request Body:**

```json
{
  "alertId": "alert-123"
}
```

#### POST /api/alerts/resolve

Resolve an alert.

**Request Body:**

```json
{
  "alertId": "alert-123"
}
```

---

### Error Codes

| Code | Meaning |
|------|---------|
| RMM001 | Database connection failed |
| RMM002 | Device not found |
| RMM003 | WinRM connection failed |
| RMM004 | Permission denied |
| RMM005 | Configuration error |
| RMM006 | Action execution failed |
| RMM007 | Invalid pairing code |
| RMM008 | Pairing code expired |
| RMM009 | Device already registered |

---

*myTech.Today RMM - API Reference v2.0*

