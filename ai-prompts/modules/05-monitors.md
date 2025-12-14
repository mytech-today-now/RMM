# PROMPT 05: Health Monitoring System

**Previous:** [04-collectors.md](04-collectors.md) - Complete that first

---

## Your Task

Implement all health monitoring scripts that assess device health, monitor services, track performance against thresholds, and check availability.

---

## Step 1: Create Health-Monitor.ps1

Create `RMM/scripts/monitors/Health-Monitor.ps1`:

**Purpose:** Comprehensive health assessment and scoring

**Health Score Calculation:**

Calculate a 0-100 health score based on weighted factors:
- Availability: 25 points (Is device reachable?)
- Performance: 25 points (CPU/Memory/Disk within thresholds?)
- Security: 25 points (AV current, firewall on, updates installed?)
- Compliance: 25 points (Matches policy requirements?)

**Status Levels:**
- Healthy (80-100)
- Warning (60-79)
- Critical (0-59)
- Offline (unreachable)
- Unknown (no data)

**Actions:**
- Calculate health score for each device
- Update device status in database
- Generate alerts for status changes
- Store health history

---

## Step 2: Create Service-Monitor.ps1

Create `RMM/scripts/monitors/Service-Monitor.ps1`:

**Purpose:** Critical service monitoring and auto-remediation

**Features:**
- Monitor list of critical services per device/group
- Auto-restart failed services (configurable)
- Service dependency tracking
- Startup type compliance checking
- Service performance metrics

**Actions:**
- Check service status on all devices
- Restart stopped critical services (if enabled)
- Alert on service failures
- Track service uptime

---

## Step 3: Create Performance-Monitor.ps1

Create `RMM/scripts/monitors/Performance-Monitor.ps1`:

**Purpose:** Performance threshold monitoring and alerting

**Thresholds (from config/thresholds.json):**
- CPU: Warning 80%, Critical 95%
- Memory: Warning 85%, Critical 95%
- DiskSpace: Warning 20% free, Critical 10% free
- DiskLatency: Warning 20ms, Critical 50ms
- NetworkErrors: Warning 100/min, Critical 1000/min

**Actions:**
- Collect current performance metrics
- Compare against thresholds
- Generate alerts on threshold breaches
- Track performance trends
- Support custom thresholds per device/group

---

## Step 4: Create Availability-Monitor.ps1

Create `RMM/scripts/monitors/Availability-Monitor.ps1`:

**Purpose:** Uptime and connectivity monitoring

**Monitoring Methods:**
- ICMP Ping (basic connectivity)
- WinRM Test (service availability)
- Port checks (custom services)
- HTTP/HTTPS checks (web services)

**Features:**
- Latency tracking
- Packet loss detection
- Automatic offline/online status transitions
- Maintenance windows support (skip monitoring during maintenance)
- Uptime percentage calculation

**Actions:**
- Test connectivity to all devices
- Update LastSeen timestamp
- Update device status (Online/Offline)
- Generate alerts on status changes
- Track uptime statistics

---

## Validation

After completing this prompt, verify:

- [ ] All 4 monitor scripts are created
- [ ] Each script has comment-based help
- [ ] Health-Monitor.ps1 calculates health scores correctly
- [ ] Service-Monitor.ps1 can restart services
- [ ] Performance-Monitor.ps1 uses thresholds from config
- [ ] Availability-Monitor.ps1 tests multiple connectivity methods
- [ ] All scripts update database correctly
- [ ] All scripts generate appropriate alerts
- [ ] All scripts use centralized logging

Test the monitors:

```powershell
# Test health monitoring
.\scripts\monitors\Health-Monitor.ps1 -Devices "localhost"

# Test service monitoring
.\scripts\monitors\Service-Monitor.ps1 -Devices "localhost" -Services "Spooler","W32Time"

# Test performance monitoring
.\scripts\monitors\Performance-Monitor.ps1 -Devices "localhost"

# Test availability monitoring
.\scripts\monitors\Availability-Monitor.ps1 -Devices "localhost"

# Check device status
Import-Module PSSQLite
Invoke-SqliteQuery -DataSource ".\data\devices.db" -Query "SELECT Hostname, Status, LastSeen FROM Devices;"
```

---

**NEXT PROMPT:** [06-actions.md](06-actions.md) - Implement remote actions system

---

*This is prompt 6 of 13 in the RMM build sequence*

