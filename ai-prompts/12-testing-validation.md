# PROMPT 12: Testing & Validation

**Previous:** [11-scalability-security-implementation.md](11-scalability-security-implementation.md) - Complete that first

---

## Your Task

Create comprehensive tests, sample data, and validate the entire RMM system is working correctly.

---

## Step 1: Create Sample Data

### sample-devices.csv

Create `RMM/sample-devices.csv` with 10 test devices:

```csv
ComputerName,IPAddress,SiteId,GroupId,Description
localhost,127.0.0.1,site-alpha,workstations,Local test device
WS-001,192.168.1.101,site-alpha,workstations,Test Workstation 1
WS-002,192.168.1.102,site-alpha,workstations,Test Workstation 2
SRV-001,192.168.1.201,site-alpha,servers,Test Server 1
SRV-002,192.168.1.202,site-alpha,servers,Test Server 2
LAPTOP-001,192.168.1.151,site-alpha,laptops,Test Laptop 1
LAPTOP-002,192.168.1.152,site-alpha,laptops,Test Laptop 2
WS-REMOTE-001,10.0.1.101,site-beta,workstations,Remote Office WS 1
SRV-REMOTE-001,10.0.1.201,site-beta,servers,Remote Office Server
DC-001,192.168.1.10,site-alpha,servers,Domain Controller
```

---

## Step 2: Create Pester Tests

### tests/Unit/Core.Tests.ps1

Create unit tests for core framework:

```powershell
Describe "RMM-Core Module Tests" {
    BeforeAll {
        Import-Module "$PSScriptRoot/../../scripts/core/RMM-Core.psm1" -Force
    }
    
    Context "Initialize-RMM" {
        It "Should initialize database" {
            { Initialize-RMM -Mode Install } | Should -Not -Throw
        }
        
        It "Should create required folders" {
            Test-Path "$PSScriptRoot/../../data" | Should -Be $true
            Test-Path "$PSScriptRoot/../../logs" | Should -Be $true
        }
    }
    
    Context "Device Management" {
        It "Should add a device" {
            $device = Add-RMMDevice -ComputerName "TEST-001" -IPAddress "192.168.1.100"
            $device | Should -Not -BeNullOrEmpty
        }
        
        It "Should retrieve device" {
            $device = Get-RMMDevice -ComputerName "TEST-001"
            $device.ComputerName | Should -Be "TEST-001"
        }
        
        It "Should update device" {
            Update-RMMDevice -ComputerName "TEST-001" -Status "Online"
            $device = Get-RMMDevice -ComputerName "TEST-001"
            $device.Status | Should -Be "Online"
        }
    }
}
```

### tests/Integration/Database.Tests.ps1

Create integration tests for database operations:

```powershell
Describe "Database Integration Tests" {
    BeforeAll {
        Import-Module PSSQLite
        $dbPath = "$PSScriptRoot/../../data/devices.db"
    }
    
    It "Should query devices table" {
        $devices = Invoke-SqliteQuery -DataSource $dbPath -Query "SELECT * FROM Devices"
        $devices | Should -Not -BeNullOrEmpty
    }
    
    It "Should insert and retrieve metrics" {
        $query = "INSERT INTO Metrics (DeviceId, MetricType, Value, Timestamp) VALUES ('test-device', 'CPU', 50.0, datetime('now'))"
        Invoke-SqliteQuery -DataSource $dbPath -Query $query
        
        $metrics = Invoke-SqliteQuery -DataSource $dbPath -Query "SELECT * FROM Metrics WHERE DeviceId = 'test-device'"
        $metrics | Should -Not -BeNullOrEmpty
    }
}
```

### tests/Performance/Scale.Tests.ps1

Create performance tests:

```powershell
Describe "Performance Tests" {
    It "Should process 100 devices in under 30 seconds" {
        $devices = 1..100 | ForEach-Object { @{ComputerName = "TEST-$_"; IPAddress = "192.168.1.$_"} }
        
        $elapsed = Measure-Command {
            $devices | ForEach-Object -Parallel {
                # Simulate device processing
                Start-Sleep -Milliseconds 100
            } -ThrottleLimit 50
        }
        
        $elapsed.TotalSeconds | Should -BeLessThan 30
    }
}
```

---

## Step 3: Validation Checklist

Run the following validation steps:

### Basic Functionality

```powershell
# 1. Initialize RMM
.\scripts\core\Initialize-RMM.ps1 -Mode Install

# 2. Import sample devices
.\scripts\core\Initialize-RMM.ps1 -ImportDevices .\sample-devices.csv

# 3. Verify devices in database
Import-Module PSSQLite
Invoke-SqliteQuery -DataSource ".\data\devices.db" -Query "SELECT COUNT(*) as DeviceCount FROM Devices"

# 4. Run inventory collection on localhost
.\scripts\collectors\Inventory-Collector.ps1 -Devices "localhost"

# 5. Run health monitoring
.\scripts\monitors\Health-Monitor.ps1 -Devices "localhost"

# 6. Generate a report
.\scripts\reports\Report-Generator.ps1 -ReportType "ExecutiveSummary" -OutputPath ".\reports\test-report.html"

# 7. Start web dashboard
.\scripts\ui\Start-WebDashboard.ps1 -Port 8080
# Open http://localhost:8080 in browser

# 8. Run Pester tests
Invoke-Pester -Path .\tests\ -Output Detailed
```

### Validation Checklist

- [ ] `Initialize-RMM.ps1` runs without errors
- [ ] Database is created with all tables
- [ ] Sample devices are imported successfully
- [ ] Localhost appears as first managed device
- [ ] Inventory collection completes on localhost
- [ ] Health monitoring calculates health score
- [ ] Alerts can be created and retrieved
- [ ] Reports generate successfully (HTML/Excel)
- [ ] Web dashboard loads at http://localhost:8080
- [ ] CLI console displays menu
- [ ] All Pester tests pass
- [ ] No errors in log files

---

## Step 4: Performance Targets

Verify the following performance targets are met:

| Metric | Target | Test Command |
|--------|--------|--------------|
| Initial deployment | < 15 minutes | Time full setup |
| First inventory (10 devices) | < 2 minutes | Measure inventory collection |
| Alert response time | < 60 seconds | Create alert and verify |
| Web dashboard load | < 3 seconds | Measure page load time |
| Database query (1000 devices) | < 1 second | Query Devices table |

---

## Step 5: Documentation Review

Ensure all documentation is complete:

- [ ] README.md has quick start guide
- [ ] All scripts have comment-based help
- [ ] Configuration files have inline comments
- [ ] Architecture is documented
- [ ] Troubleshooting guide exists

---

## Final Validation

After completing all prompts 00-12, you should have:

1. **Complete folder structure** with all directories
2. **All configuration files** (JSON) in config/
3. **Database schema** with all tables and indexes
4. **Core framework** (RMM-Core.psm1, Initialize-RMM.ps1, etc.)
5. **5 collector scripts** for data collection
6. **4 monitor scripts** for health monitoring
7. **4 action scripts** for remote management
8. **3 alert scripts** for alerting system
9. **3 report scripts** for reporting
10. **3 automation scripts** for policies and workflows
11. **2 UI scripts** (console and web dashboard)
12. **Security and scalability** features implemented
13. **Pester tests** for validation
14. **Sample data** for testing
15. **Complete documentation**

---

**CONGRATULATIONS!** You have completed the myTech.Today RMM build sequence.

---

*This is prompt 13 of 13 in the RMM build sequence*

*Return to: [README.md](README.md) for overview*

