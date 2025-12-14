# PROMPT 09: Automation System

**Previous:** [08-reports.md](08-reports.md) - Complete that first

---

## Your Task

Implement the automation system that applies policies, manages scheduled tasks, and orchestrates multi-step workflows.

---

## Step 1: Create Policy-Engine.ps1

Create `RMM/scripts/automation/Policy-Engine.ps1`:

**Purpose:** Apply configuration policies to device groups

**Policy Types to Support:**
- Security baselines (firewall, BitLocker, password policies)
- Maintenance windows (update/reboot restrictions)
- Software requirements (required/prohibited applications)
- Performance thresholds (custom per group)
- Compliance requirements

**Functions to Implement:**
1. `Get-RMMPolicy` - Retrieve policy by ID or name
2. `Set-RMMPolicy` - Create or update policy
3. `Invoke-RMMPolicy` - Apply policy to devices
4. `Test-RMMPolicyCompliance` - Check device compliance
5. `Get-RMMPolicyViolations` - List non-compliant devices

**Policy Structure (from config/policies/):**
Reference the existing policy JSON files created in Prompt 01.

---

## Step 2: Create Scheduled-Tasks.ps1

Create `RMM/scripts/automation/Scheduled-Tasks.ps1`:

**Purpose:** Manage RMM scheduled operations

**Default Schedules to Create:**

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

**Functions to Implement:**
1. `Register-RMMScheduledTask` - Create Windows scheduled task
2. `Unregister-RMMScheduledTask` - Remove scheduled task
3. `Get-RMMScheduledTask` - List RMM scheduled tasks
4. `Start-RMMScheduledTask` - Run task immediately
5. `Set-RMMScheduledTaskInterval` - Update task schedule

---

## Step 3: Create Workflow-Orchestrator.ps1

Create `RMM/scripts/automation/Workflow-Orchestrator.ps1`:

**Purpose:** Multi-step automated workflows

**Example Workflows to Implement:**

1. **OnboardNewDevice:**
   - Verify connectivity
   - Collect initial inventory
   - Apply security baseline
   - Install required software
   - Move to production group
   - Notify IT team

2. **PatchTuesday:**
   - Scan all devices for updates
   - Install updates on pilot group
   - Wait for reboots
   - Verify pilot health
   - Install updates on production (if pilot successful)
   - Generate compliance report

3. **OfflineDeviceRecovery:**
   - Detect device offline > 24 hours
   - Attempt Wake-on-LAN
   - Escalate alert if still offline
   - Queue pending actions

**Functions to Implement:**
1. `New-RMMWorkflow` - Define new workflow
2. `Start-RMMWorkflow` - Execute workflow
3. `Get-RMMWorkflowStatus` - Check workflow progress
4. `Stop-RMMWorkflow` - Cancel running workflow
5. `Get-RMMWorkflowHistory` - View workflow execution history

**Workflow Definition Format:**
Support YAML or JSON workflow definitions with steps, conditions, and error handling.

---

## Validation

After completing this prompt, verify:

- [ ] All 3 automation scripts are created
- [ ] Each script has comment-based help
- [ ] Policy-Engine.ps1 applies policies to devices
- [ ] Scheduled-Tasks.ps1 creates all default tasks
- [ ] Workflow-Orchestrator.ps1 executes multi-step workflows
- [ ] Policies are loaded from config/policies/
- [ ] Scheduled tasks run on schedule
- [ ] Workflows handle errors gracefully
- [ ] All automation is logged

Test the automation system:

```powershell
# Apply a policy
.\scripts\automation\Policy-Engine.ps1 -PolicyId "default" -Devices "All"

# Register scheduled tasks
.\scripts\automation\Scheduled-Tasks.ps1 -Action "RegisterAll"

# Run a workflow
.\scripts\automation\Workflow-Orchestrator.ps1 -Workflow "OnboardNewDevice" -DeviceId "new-device-01"

# Check scheduled tasks
Get-ScheduledTask | Where-Object {$_.TaskName -like "RMM-*"}
```

---

**NEXT PROMPT:** [10-ui.md](10-ui.md) - Implement user interfaces

---

*This is prompt 10 of 13 in the RMM build sequence*

