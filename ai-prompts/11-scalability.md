# Scalability Architecture

*Previous: [modules/10-ui.md](modules/10-ui.md)*

---

## Performance Optimizations for 1000+ Endpoints

### Parallel Processing

```powershell
# PS7+ parallel with throttling
$devices | ForEach-Object -Parallel {
    Invoke-Command -ComputerName $_.ComputerName -ScriptBlock $using:scriptBlock
} -ThrottleLimit 50

# PS5.1 fallback with runspace pools
$runspacePool = [RunspaceFactory]::CreateRunspacePool(1, 50)
$runspacePool.Open()
```

### Connection Pooling
- Reuse WinRM sessions across multiple operations
- Session cache with TTL (configurable)
- Graceful session cleanup

### Batch Operations

```powershell
# Group devices by site for network efficiency
$devicesBySite = $devices | Group-Object SiteId
foreach ($site in $devicesBySite) {
    Invoke-ParallelOperation -Devices $site.Group -ThrottleLimit 25
}
```

### Caching Strategy
- Device status: 5-minute cache
- Inventory: 24-hour cache
- Configuration: Hot-reload on change
- Metrics: Write-through with batch commits

### Database Optimization
- Indexed queries for common patterns
- Batch inserts for metrics (100 rows/commit)
- Automatic archival of old data
- Weekly VACUUM for SQLite maintenance

---

## Multi-Site Support

### Relay Agent Architecture

```
Central Console <-- HTTPS --> Site Relay Agent <-- WinRM --> Local Endpoints
                                      |
                               Local Cache DB
                               (sync on schedule)
```

### Site Configuration

```json
{
    "sites": [
        {
            "siteId": "site-alpha",
            "name": "Headquarters",
            "relayAgent": null,
            "directConnect": true
        },
        {
            "siteId": "site-beta",
            "name": "Remote Office",
            "relayAgent": "relay-beta.domain.com",
            "syncInterval": 300,
            "queuedActions": true
        }
    ]
}
```

---

## Scaling Recommendations

| Endpoint Count | Architecture | Recommendations |
|----------------|--------------|-----------------|
| 1-150 | Single console | Direct WinRM, no relay |
| 150-500 | Single console + caching | Increase throttle limit, enable caching |
| 500-2000 | Multi-site with relays | Deploy relay agents per site |
| 2000-10000 | Distributed + sharding | Multiple consoles, database sharding |

---

*Next: [12-security.md](12-security.md)*

