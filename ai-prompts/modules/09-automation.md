# Automation (scripts/automation/)

*Previous: [08-reports.md](08-reports.md)*

---

## Policy-Engine.ps1

- **Purpose:** Apply configuration policies to device groups
- **Policy Types:**

```json
{
    "policies": {
        "SecurityBaseline": {
            "targets": ["All Workstations"],
            "settings": {
                "WindowsFirewall": "Enabled",
                "BitLocker": "Required",
                "ScreenLockTimeout": 300,
                "PasswordMinLength": 12
            },
            "remediate": true,
            "schedule": "Daily"
        },
        "MaintenanceWindow": {
            "targets": ["Production Servers"],
            "settings": {
                "AllowUpdates": false,
                "AllowReboots": false
            },
            "activeHours": "06:00-22:00",
            "timezone": "America/New_York"
        }
    }
}
```

---

## Scheduled-Tasks.ps1

- **Purpose:** Manage RMM scheduled operations
- **Default Schedules:**

| Task | Interval | Description |
|------|----------|-------------|
| Availability Check | 5 min | Ping all devices |
| Health Metrics | 5 min | Collect performance data |
| Full Inventory | Daily 2AM | Complete inventory scan |
| Update Scan | Daily 3AM | Check for available updates |
| Security Scan | Daily 4AM | Security posture check |
| Report Generation | Weekly Sun 6AM | Generate weekly reports |
| Data Cleanup | Daily 5AM | Prune old data per retention |
| Database Maintenance | Weekly Sun 3AM | Vacuum SQLite, optimize |

---

## Workflow-Orchestrator.ps1

- **Purpose:** Multi-step automated workflows
- **Example Workflows:**

```yaml
OnboardNewDevice:
  trigger: "Device added to group 'New Devices'"
  steps:
    - name: "Verify Connectivity"
      action: "Test-WinRMConnection"
      onFailure: "notify-admin"
    - name: "Collect Initial Inventory"
      action: "Invoke-Inventory -Full"
    - name: "Apply Security Baseline"
      action: "Apply-Policy -Name SecurityBaseline"
    - name: "Install Required Software"
      action: "Install-RequiredApps"
    - name: "Move to Production Group"
      action: "Set-DeviceGroup -Group 'Production'"
    - name: "Notify IT"
      action: "Send-Notification -Channel Teams"

PatchTuesday:
  trigger: "Schedule: Second Tuesday 10PM"
  steps:
    - name: "Scan All Devices"
      action: "Invoke-UpdateScan -All"
      parallel: true
    - name: "Install Updates - Pilot"
      action: "Install-Updates -Group Pilot"
      waitForReboot: true
    - name: "Verify Pilot Health"
      action: "Test-GroupHealth -Group Pilot"
      onFailure: "rollback-and-notify"
    - name: "Install Updates - Production"
      action: "Install-Updates -Group Production"
      delay: "24h"
```

---

*Next: [10-ui.md](10-ui.md)*

