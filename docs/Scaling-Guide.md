# myTech.Today RMM - Scaling Guide

## Scale Targets

| Deployment Size | Endpoints | Recommended Config |
|-----------------|-----------|-------------------|
| Small | 1-150 | Default settings, single console |
| Medium | 150-500 | Increased ThrottleLimit, caching enabled |
| Large | 500-2,000 | Relay agents, batch operations |
| Enterprise | 2,000-10,000+ | Multi-site with local caches |

## Parallel Processing Configuration

### PowerShell 7+ (ForEach-Object -Parallel)

```powershell
# Configure throttle limit based on endpoint count
$devices | ForEach-Object -Parallel {
    # Process device
    Invoke-Command -ComputerName $_.Hostname -ScriptBlock { Get-ComputerInfo }
} -ThrottleLimit 50
```

### PowerShell 5.1 (RunspacePool)

```powershell
# Use Invoke-RMMParallel for automatic PS version detection
$devices | Invoke-RMMParallel -ScriptBlock {
    param($device)
    Test-Connection $device.Hostname -Count 1
} -ThrottleLimit 25
```

### ThrottleLimit Recommendations

| Endpoint Count | ThrottleLimit | Memory (Console) |
|----------------|---------------|------------------|
| 1-50 | 10 | 2GB |
| 50-150 | 25 | 4GB |
| 150-500 | 50 | 8GB |
| 500-2000 | 100 | 16GB |
| 2000+ | 200 | 32GB |

## Connection Pooling

### Session Management

```powershell
# Get or create cached session (5-minute TTL)
$session = Get-RMMSession -ComputerName "SERVER01"

# Execute commands using cached session
Invoke-Command -Session $session -ScriptBlock { Get-Service }

# Close session when done
Close-RMMSession -ComputerName "SERVER01"

# Clear all expired sessions
Clear-ExpiredSessions
```

### Session Pool Configuration

```powershell
# In settings.json
{
    "Scalability": {
        "SessionPoolSize": 50,
        "SessionTTLMinutes": 5,
        "MaxConcurrentSessions": 100
    }
}
```

## Database Optimization

### Indexing Strategy

Indexes are created automatically on:
- `Devices.DeviceId`, `Devices.Hostname`, `Devices.Status`
- `Metrics.DeviceId`, `Metrics.Timestamp`
- `Alerts.Status`, `Alerts.Severity`
- `AuditLog.Timestamp`

### VACUUM Schedule

```powershell
# Run VACUUM weekly (reduces database size)
Invoke-RMMDatabaseVacuum

# Schedule automatic maintenance
Register-RMMMaintenanceTask -Weekly -DayOfWeek Sunday -Time "02:00"
```

### Batch Operations

```powershell
# Insert 100 rows per transaction
$metrics = @(...)  # Large dataset
Invoke-RMMBatchInsert -Table "Metrics" -Data $metrics -BatchSize 100
```

## Caching Strategies

### Cache Types and TTL

| Cache Type | TTL | Use Case |
|------------|-----|----------|
| DeviceStatus | 5 minutes | Real-time status |
| Inventory | 24 hours | Hardware/software |
| Configuration | Hot reload | Settings changes |

### Cache Usage

```powershell
# Set cache
Set-RMMCache -Key "device-status-SERVER01" -Type "DeviceStatus" -Data @{Status="Online"}

# Get cache (returns $null if expired)
$status = Get-RMMCache -Key "device-status-SERVER01" -Type "DeviceStatus"

# Clear cache type
Clear-RMMCache -Type "DeviceStatus"
```

## Multi-Site Deployment

### Relay Agent Architecture

```
Central Console (HQ)
       │
       ├── Site A Relay (50 devices)
       │      └── Local cache
       │
       ├── Site B Relay (200 devices)  
       │      └── Local cache
       │
       └── Site C Relay (500 devices)
              └── Local cache + local DB
```

### Relay Configuration

```powershell
# In settings.json per site
{
    "Site": {
        "SiteId": "site-b",
        "RelayMode": true,
        "CentralConsole": "https://rmm.mytech.today:8443",
        "SyncInterval": 300,
        "LocalCacheEnabled": true
    }
}
```

## Performance Tuning by Scale

### 1-150 Endpoints (Default)
- Use default settings
- Single SQLite database
- No relay agents needed

### 150-500 Endpoints
```powershell
# Increase parallel processing
Set-RMMConfig -Section "Scalability" -Key "ThrottleLimit" -Value 50

# Enable caching
Set-RMMConfig -Section "Scalability" -Key "CachingEnabled" -Value $true
```

### 500-2,000 Endpoints
```powershell
# Deploy relay agents at each site
# Enable batch operations
Set-RMMConfig -Section "Database" -Key "BatchSize" -Value 100

# Schedule staggered collection
Set-RMMConfig -Section "Monitoring" -Key "StaggeredCollection" -Value $true
```

### 2,000-10,000+ Endpoints
- Deploy relay agents with local SQLite databases
- Implement data federation (central aggregation)
- Use geographic load balancing
- Consider PostgreSQL for central database

## Hardware Recommendations

| Endpoints | CPU | RAM | Storage | Network |
|-----------|-----|-----|---------|---------|
| 1-150 | 2 cores | 4GB | 50GB SSD | 100Mbps |
| 150-500 | 4 cores | 8GB | 100GB SSD | 1Gbps |
| 500-2000 | 8 cores | 16GB | 250GB SSD | 1Gbps |
| 2000+ | 16 cores | 32GB | 500GB NVMe | 10Gbps |

---

*myTech.Today RMM - Scaling Guide v1.0*

