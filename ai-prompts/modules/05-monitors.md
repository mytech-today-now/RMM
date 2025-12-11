# Health Monitoring (scripts/monitors/)

*Previous: [04-collectors.md](04-collectors.md)*

---

## Health-Monitor.ps1

- **Purpose:** Comprehensive health assessment
- **Health Score Calculation:**

```powershell
# 0-100 score based on weighted factors
$healthScore = @{
    Availability = 25    # Is device reachable?
    Performance = 25     # CPU/Memory/Disk within thresholds?
    Security = 25        # AV current, firewall on, updates installed?
    Compliance = 25      # Matches policy requirements?
}
```

- **Status Levels:** Healthy, Warning, Critical, Offline, Unknown

---

## Service-Monitor.ps1

- **Purpose:** Critical service monitoring
- **Features:**
  - Monitor list of critical services per device/group
  - Auto-restart failed services (configurable)
  - Service dependency tracking
  - Startup type compliance

---

## Performance-Monitor.ps1

- **Purpose:** Performance threshold monitoring
- **Default Thresholds (configurable in thresholds.json):**

```json
{
    "CPU": { "Warning": 80, "Critical": 95 },
    "Memory": { "Warning": 85, "Critical": 95 },
    "DiskSpace": { "Warning": 20, "Critical": 10 },
    "DiskLatency": { "Warning": 20, "Critical": 50 },
    "NetworkErrors": { "Warning": 100, "Critical": 1000 }
}
```

---

## Availability-Monitor.ps1

- **Purpose:** Uptime and connectivity monitoring
- **Methods:**
  - ICMP Ping (basic)
  - WinRM Test (service availability)
  - Port checks (custom services)
  - HTTP/HTTPS checks (web services)
- **Features:**
  - Latency tracking
  - Packet loss detection
  - Automatic offline/online transitions
  - Maintenance windows support

---

*Next: [06-actions.md](06-actions.md)*

