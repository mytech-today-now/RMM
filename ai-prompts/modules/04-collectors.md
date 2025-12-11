# Data Collection (scripts/collectors/)

*Previous: [03-core-framework.md](03-core-framework.md)*

---

## Inventory-Collector.ps1

- **Purpose:** Complete hardware/software inventory
- **Scheduling:** Daily (configurable)
- **Parameters:**
  - `-Devices` (array, group name, or "All")
  - `-Categories [All|Hardware|Software|Security|Network]`
  - `-Parallel` (switch, default: $true for PS7+)
  - `-ThrottleLimit` (default: 25)
  - `-Force` (skip cache, fresh collection)

### Data Collected

```powershell
@{
    Hardware = @{
        System = Get-CimInstance Win32_ComputerSystem
        BIOS = Get-CimInstance Win32_BIOS
        Motherboard = Get-CimInstance Win32_BaseBoard
        Processor = Get-CimInstance Win32_Processor
        Memory = Get-CimInstance Win32_PhysicalMemory
        Disks = Get-CimInstance Win32_DiskDrive
        Volumes = Get-CimInstance Win32_LogicalDisk
        GPU = Get-CimInstance Win32_VideoController
        Network = Get-NetAdapter | Get-NetIPConfiguration
        USB = Get-CimInstance Win32_USBController
        Monitor = Get-CimInstance WmiMonitorID -Namespace root/wmi
        Battery = Get-CimInstance Win32_Battery
    }
    Software = @{
        OS = Get-CimInstance Win32_OperatingSystem
        Hotfixes = Get-HotFix
        InstalledApps = Get-Package
        WinGetApps = winget list --source winget
        Services = Get-Service
        StartupPrograms = Get-CimInstance Win32_StartupCommand
        ScheduledTasks = Get-ScheduledTask
    }
    Security = @{
        Defender = Get-MpComputerStatus
        Firewall = Get-NetFirewallProfile
        BitLocker = Get-BitLockerVolume
        TPM = Get-Tpm
        LocalAdmins = Get-LocalGroupMember -Group "Administrators"
        PasswordPolicy = net accounts
        AuditPolicy = auditpol /get /category:*
    }
    Network = @{
        Adapters = Get-NetAdapter
        IPConfig = Get-NetIPConfiguration
        Routes = Get-NetRoute
        DNSServers = Get-DnsClientServerAddress
        Shares = Get-SmbShare
        Connections = Get-NetTCPConnection -State Established
        FirewallRules = Get-NetFirewallRule | Where Enabled -eq True
    }
}
```

---

## Hardware-Monitor.ps1

- **Purpose:** Real-time hardware metrics
- **Scheduling:** Every 5 minutes (configurable)
- **Metrics:**
  - CPU: Usage %, temperature, frequency, per-core stats
  - Memory: Used/Available, page file, cache
  - Disk: IOPS, queue length, latency, space
  - Network: Throughput, errors, dropped packets
  - GPU: Usage, memory, temperature (NVIDIA/AMD if available)

---

## Software-Auditor.ps1

- **Purpose:** Software inventory and compliance
- **Features:**
  - Detect unauthorized software (blacklist)
  - Find missing required software (whitelist)
  - License tracking (registry-based)
  - Version compliance checking
  - Browser extension inventory

---

## Security-Scanner.ps1

- **Purpose:** Security posture assessment
- **Checks:**
  - Windows Update status
  - Antivirus status and definitions age
  - Firewall configuration
  - BitLocker encryption status
  - Local admin accounts audit
  - Weak password detection
  - Open ports scan
  - SSL/TLS certificate expiry
  - Pending reboots
  - Security event log analysis

---

## Event-Collector.ps1

- **Purpose:** Centralized event log collection
- **Event Sources:**
  - System (Errors, Warnings)
  - Application (Errors, Warnings)
  - Security (Logon failures, privilege use)
  - PowerShell (Script execution)
  - Custom event filters (configurable)
- **Features:**
  - Forward to central collector
  - Parse and normalize events
  - Correlation with alerts

---

*Next: [05-monitors.md](05-monitors.md)*

