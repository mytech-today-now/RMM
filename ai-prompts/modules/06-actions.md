# PROMPT 06: Remote Actions System

**Previous:** [05-monitors.md](05-monitors.md) - Complete that first

---

## Your Task

Implement all remote action scripts that enable remote management, script execution, update management, and automated remediation on managed endpoints.

---

## Step 1: Create Remote-Actions.ps1

Create `RMM/scripts/actions/Remote-Actions.ps1`:

**Purpose:** Execute common remote actions on endpoints

**Actions to Implement:**

| Action | Description | Requires Confirmation |
|--------|-------------|----------------------|
| Reboot | Restart computer | Yes |
| Shutdown | Power off computer | Yes |
| WakeOnLAN | Send magic packet | No |
| Lock | Lock workstation | No |
| Logoff | Log off current user | Yes |
| EnableRDP | Enable Remote Desktop | Yes |
| DisableRDP | Disable Remote Desktop | Yes |
| StartRDP | Launch RDP session | No |
| StartRemotePS | Interactive PowerShell session | No |
| FileTransfer | Copy files to/from device | No |
| RegistryEdit | Modify registry keys | Yes |
| ServiceControl | Start/Stop/Restart service | Depends |
| ProcessKill | Terminate process | Yes |
| ClearTemp | Clear temp files | No |
| FlushDNS | Clear DNS cache | No |
| GPUpdate | Force Group Policy update | No |

**Features:**
- Queue actions for offline devices
- Confirmation prompts for destructive actions
- Action history and audit logging
- Retry logic with exponential backoff
- Parallel execution support

---

## Step 2: Create Script-Executor.ps1

Create `RMM/scripts/actions/Script-Executor.ps1`:

**Purpose:** Run custom PowerShell scripts on endpoints

**Features:**
- Script library management (store scripts in database or files)
- Parameter passing to scripts
- Output capture and logging
- Timeout handling (configurable)
- Secure credential injection
- Pre/post execution hooks
- Rollback scripts on failure
- Script versioning

**Actions:**
- Execute script on target devices
- Capture stdout/stderr
- Store results in Actions table
- Generate alerts on failures
- Support both inline scripts and script files

---

## Step 3: Create Update-Manager.ps1

Create `RMM/scripts/actions/Update-Manager.ps1`:

**Purpose:** Windows and application update management

**Capabilities:**
- Scan for Windows Updates (using PSWindowsUpdate module)
- Install Windows Updates with scheduling
- Reboot scheduling (respect maintenance windows)
- WinGet package updates
- Driver updates (optional)
- Feature update management
- Update history tracking
- Rollback support

**Approval Workflow:**
- Auto-approve by classification (Security, Critical, etc.)
- Manual approval queue for other updates
- Staged rollout (pilot group -> production)
- Maintenance window enforcement

**Actions:**
- Scan for updates
- Download updates
- Install updates
- Schedule reboots
- Track update status
- Generate compliance reports

---

## Step 4: Create Remediation-Engine.ps1

Create `RMM/scripts/actions/Remediation-Engine.ps1`:

**Purpose:** Automated issue remediation based on triggers

**Built-in Remediations:**
- Clear temp files when disk space low
- Restart hung services
- Reset Windows Update components
- Clear print queue
- Renew DHCP lease
- Re-register DLLs
- Fix WMI repository
- Reset network stack
- Repair Windows image (DISM)
- Clear DNS cache

**Custom Remediation Support:**
- Define remediation rules in JSON
- Trigger conditions (e.g., "DiskSpace < 10%")
- Remediation actions (script or built-in)
- Auto-remediate flag
- Approval requirements

**Actions:**
- Monitor for trigger conditions
- Execute remediation actions
- Verify remediation success
- Log all remediation attempts
- Generate alerts on failures

---

## Validation

After completing this prompt, verify:

- [ ] All 4 action scripts are created
- [ ] Each script has comment-based help
- [ ] Remote-Actions.ps1 implements all listed actions
- [ ] Script-Executor.ps1 can run custom scripts
- [ ] Update-Manager.ps1 integrates with PSWindowsUpdate
- [ ] Remediation-Engine.ps1 has all built-in remediations
- [ ] All actions are logged to Actions table
- [ ] All actions support queuing for offline devices
- [ ] All actions integrate with audit logging
- [ ] Confirmation prompts work correctly

Test the actions:

```powershell
# Test remote action
.\scripts\actions\Remote-Actions.ps1 -Action "FlushDNS" -Devices "localhost"

# Test script execution
.\scripts\actions\Script-Executor.ps1 -ScriptBlock { Get-Service } -Devices "localhost"

# Test update scanning
.\scripts\actions\Update-Manager.ps1 -Action "Scan" -Devices "localhost"

# Test remediation
.\scripts\actions\Remediation-Engine.ps1 -Remediation "ClearTemp" -Devices "localhost"

# Check action history
Import-Module PSSQLite
Invoke-SqliteQuery -DataSource ".\data\devices.db" -Query "SELECT * FROM Actions ORDER BY CreatedAt DESC LIMIT 10;"
```

---

**NEXT PROMPT:** [07-alerts.md](07-alerts.md) - Implement alerting system

---

*This is prompt 7 of 13 in the RMM build sequence*

