# Remote Actions (scripts/actions/)

*Previous: [05-monitors.md](05-monitors.md)*

---

## Remote-Actions.ps1

### Actions Available

| Action | Description | Confirmation |
|--------|-------------|--------------|
| Reboot | Restart computer | Yes |
| Shutdown | Power off | Yes |
| WakeOnLAN | Send magic packet | No |
| Lock | Lock workstation | No |
| Logoff | Log off current user | Yes |
| EnableRDP | Enable Remote Desktop | Yes |
| DisableRDP | Disable Remote Desktop | Yes |
| StartRDP | Launch RDP session | No |
| StartRemotePS | Interactive PS session | No |
| FileTransfer | Copy files to/from | No |
| RegistryEdit | Modify registry | Yes |
| ServiceControl | Start/Stop/Restart service | Depends |
| ProcessKill | Terminate process | Yes |
| ClearTemp | Clear temp files | No |
| FlushDNS | Clear DNS cache | No |
| GPUpdate | Force Group Policy update | No |

---

## Script-Executor.ps1

- **Purpose:** Run custom scripts on endpoints
- **Features:**
  - Script library management
  - Parameter passing
  - Output capture and logging
  - Timeout handling
  - Credential injection (secure)
  - Pre/post execution hooks
  - Rollback scripts

---

## Update-Manager.ps1

- **Purpose:** Windows and application updates
- **Capabilities:**
  - Scan for Windows Updates
  - Install Windows Updates (with scheduling)
  - Reboot scheduling (maintenance windows)
  - WinGet package updates
  - Driver updates (optional)
  - Feature update management
  - Update history tracking
  - Rollback support
- **Approval Workflow:**
  - Auto-approve by classification
  - Manual approval queue
  - Staged rollout (pilot -> production)

---

## Remediation-Engine.ps1

- **Purpose:** Automated issue remediation
- **Built-in Remediations:**
  - Clear temp files when disk low
  - Restart hung services
  - Reset Windows Update components
  - Clear print queue
  - Renew DHCP lease
  - Re-register DLLs
  - Fix WMI repository
  - Reset network stack
- **Custom Remediation:** Define in JSON with trigger conditions

---

*Next: [07-alerts.md](07-alerts.md)*

