# PROMPT 04: Data Collection System

**Previous:** [03-core-framework.md](03-core-framework.md) - Complete that first

---

## Your Task

Implement all data collection scripts that gather inventory, hardware metrics, software information, security posture, and events from managed endpoints.

---

## Step 1: Create Inventory-Collector.ps1

Create `RMM/scripts/collectors/Inventory-Collector.ps1`:

**Purpose:** Complete hardware/software inventory collection

**Parameters:**
- `-Devices` (array, group name, or "All")
- `-Categories [All|Hardware|Software|Security|Network]`
- `-Parallel` (switch, default: $true for PS7+)
- `-ThrottleLimit` (default: 25)
- `-Force` (skip cache, fresh collection)
- `-DatabasePath` (path to devices.db)

**Data to Collect:**

Implement collection for these categories:

1. **Hardware:**
   - System (Win32_ComputerSystem)
   - BIOS (Win32_BIOS)
   - Motherboard (Win32_BaseBoard)
   - Processor (Win32_Processor)
   - Memory (Win32_PhysicalMemory)
   - Disks (Win32_DiskDrive)
   - Volumes (Win32_LogicalDisk)
   - GPU (Win32_VideoController)
   - Network adapters (Get-NetAdapter, Get-NetIPConfiguration)
   - USB controllers (Win32_USBController)
   - Monitors (WmiMonitorID)
   - Battery (Win32_Battery)

2. **Software:**
   - OS (Win32_OperatingSystem)
   - Hotfixes (Get-HotFix)
   - Installed apps (Get-Package)
   - WinGet apps (winget list)
   - Services (Get-Service)
   - Startup programs (Win32_StartupCommand)
   - Scheduled tasks (Get-ScheduledTask)

3. **Security:**
   - Windows Defender status (Get-MpComputerStatus)
   - Firewall profiles (Get-NetFirewallProfile)
   - BitLocker volumes (Get-BitLockerVolume)
   - TPM status (Get-Tpm)
   - Local administrators (Get-LocalGroupMember)
   - Password policy (net accounts)
   - Audit policy (auditpol)

4. **Network:**
   - Adapters (Get-NetAdapter)
   - IP configuration (Get-NetIPConfiguration)
   - Routes (Get-NetRoute)
   - DNS servers (Get-DnsClientServerAddress)
   - SMB shares (Get-SmbShare)
   - Active connections (Get-NetTCPConnection)
   - Firewall rules (Get-NetFirewallRule)

**Actions:**
- Collect data via WinRM from target devices
- Store results in database (Inventory table)
- Cache recent results in JSON (data/cache/)
- Support parallel collection with throttling
- Handle offline devices gracefully
- Log all collection activities

---

## Step 2: Create Hardware-Monitor.ps1

Create `RMM/scripts/collectors/Hardware-Monitor.ps1`:

**Purpose:** Real-time hardware performance metrics collection

**Metrics to collect:**
- CPU: Usage %, temperature, frequency, per-core stats
- Memory: Used/Available, page file, cache
- Disk: IOPS, queue length, latency, space
- Network: Throughput, errors, dropped packets
- GPU: Usage, memory, temperature (if available)

**Actions:**
- Collect metrics every 5 minutes (configurable)
- Store in Metrics table
- Compare against thresholds
- Trigger alerts on threshold breaches

---

## Step 3: Create Software-Auditor.ps1

Create `RMM/scripts/collectors/Software-Auditor.ps1`:

**Purpose:** Software inventory and compliance checking

**Features:**
- Detect unauthorized software (blacklist)
- Find missing required software (whitelist)
- License tracking (registry-based)
- Version compliance checking
- Browser extension inventory

---

## Step 4: Create Security-Scanner.ps1

Create `RMM/scripts/collectors/Security-Scanner.ps1`:

**Purpose:** Security posture assessment

**Checks to perform:**
- Windows Update status
- Antivirus status and definition age
- Firewall configuration
- BitLocker encryption status
- Local admin accounts audit
- Weak password detection
- Open ports scan
- SSL/TLS certificate expiry
- Pending reboots
- Security event log analysis

**Actions:**
- Generate security score (0-100)
- Create alerts for security issues
- Store results in Inventory table

---

## Step 5: Create Event-Collector.ps1

Create `RMM/scripts/collectors/Event-Collector.ps1`:

**Purpose:** Centralized event log collection

**Event sources:**
- System log (Errors, Warnings)
- Application log (Errors, Warnings)
- Security log (Logon failures, privilege use)
- PowerShell log (Script execution)
- Custom event filters (configurable)

**Features:**
- Forward events to central database
- Parse and normalize event data
- Correlate with alerts
- Filter noise (configurable)

---

## Validation

After completing this prompt, verify:

- [ ] All 5 collector scripts are created
- [ ] Each script has comment-based help
- [ ] Inventory-Collector.ps1 collects all 4 categories
- [ ] Hardware-Monitor.ps1 collects performance metrics
- [ ] Software-Auditor.ps1 performs compliance checks
- [ ] Security-Scanner.ps1 generates security scores
- [ ] Event-Collector.ps1 forwards events
- [ ] All scripts integrate with database
- [ ] All scripts use centralized logging
- [ ] Parallel processing works correctly

Test the collectors:

```powershell
# Test inventory collection
.\scripts\collectors\Inventory-Collector.ps1 -Devices "localhost" -Categories All

# Test hardware monitoring
.\scripts\collectors\Hardware-Monitor.ps1 -Devices "localhost"

# Test security scanning
.\scripts\collectors\Security-Scanner.ps1 -Devices "localhost"

# Verify data in database
Import-Module PSSQLite
Invoke-SqliteQuery -DataSource ".\data\devices.db" -Query "SELECT * FROM Inventory LIMIT 10;"
```

---

**NEXT PROMPT:** [05-monitors.md](05-monitors.md) - Implement health monitoring system

---

*This is prompt 5 of 13 in the RMM build sequence*

