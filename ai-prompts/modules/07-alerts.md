# PROMPT 07: Alerting System

**Previous:** [06-actions.md](06-actions.md) - Complete that first

---

## Your Task

Implement the alerting system that processes alerts, sends notifications through multiple channels, and handles escalation workflows.

---

## Step 1: Create Alert-Manager.ps1

Create `RMM/scripts/alerts/Alert-Manager.ps1`:

**Purpose:** Central alert processing and lifecycle management

**Alert Lifecycle:**
```
Triggered -> Active -> [Acknowledged] -> Resolved -> Archived
```

**Features:**
- Alert deduplication (same type + device within 5 minutes = increment count)
- Alert correlation (group related alerts, e.g., disk + performance = "Resource Exhaustion")
- Auto-resolution (automatically resolve when condition clears)
- Alert severity levels (Critical, High, Medium, Low, Info)
- Alert history tracking

**Functions to Implement:**
1. `New-RMMAlert` - Create new alert
2. `Get-RMMAlert` - Query alerts with filtering
3. `Set-RMMAlertAcknowledged` - Acknowledge alert
4. `Set-RMMAlertResolved` - Resolve alert
5. `Remove-RMMAlert` - Archive old alerts
6. `Test-RMMAlertDuplicate` - Check for duplicates
7. `Get-RMMAlertCorrelation` - Find related alerts

---

## Step 2: Create Notification-Engine.ps1

Create `RMM/scripts/alerts/Notification-Engine.ps1`:

**Purpose:** Send notifications through multiple channels

**Channels to Support:**

| Channel | Configuration | Features |
|---------|---------------|----------|
| Email (SMTP) | Server, port, credentials | HTML templates, attachments |
| Microsoft Teams | Webhook URL | Adaptive cards, action buttons |
| Slack | Webhook URL | Rich formatting, threads |
| PagerDuty | Integration key | Escalation, on-call routing |
| SMS (Twilio) | Account SID, Auth token | Critical alerts only |
| Webhook (Generic) | URL, headers | JSON payload, custom format |
| Windows Event Log | Local/remote | For SIEM integration |

**Notification Rules:**

Support rules defined in configuration:
```json
{
    "rules": [
        {
            "name": "Critical to On-Call",
            "condition": { "severity": "Critical" },
            "channels": ["PagerDuty", "SMS"],
            "delay": 0
        },
        {
            "name": "High to Team",
            "condition": { "severity": "High" },
            "channels": ["Teams", "Email"],
            "delay": 300,
            "suppressDuplicates": true
        }
    ]
}
```

**Functions to Implement:**
1. `Send-RMMNotification` - Send notification to channel(s)
2. `Send-EmailNotification` - Email via SMTP
3. `Send-TeamsNotification` - Microsoft Teams webhook
4. `Send-SlackNotification` - Slack webhook
5. `Send-PagerDutyNotification` - PagerDuty API
6. `Send-SMSNotification` - Twilio SMS
7. `Send-WebhookNotification` - Generic webhook
8. `Write-EventLogNotification` - Windows Event Log

---

## Step 3: Create Escalation-Handler.ps1

Create `RMM/scripts/alerts/Escalation-Handler.ps1`:

**Purpose:** Time-based alert escalation

**Features:**
- Multi-tier escalation paths
- Business hours awareness
- On-call schedule integration
- Escalation timeout (no response)
- Manager override notifications
- Escalation history tracking

**Escalation Tiers:**
1. Tier 1: Initial notification to primary contact
2. Tier 2: Escalate to team lead after X minutes
3. Tier 3: Escalate to manager after Y minutes
4. Tier 4: Escalate to executive after Z minutes

**Functions to Implement:**
1. `Start-RMMEscalation` - Begin escalation process
2. `Stop-RMMEscalation` - Stop escalation (alert resolved)
3. `Get-RMMEscalationStatus` - Check escalation status
4. `Set-RMMEscalationSchedule` - Configure on-call schedule
5. `Test-RMMBusinessHours` - Check if within business hours

---

## Validation

After completing this prompt, verify:

- [ ] All 3 alert scripts are created
- [ ] Each script has comment-based help
- [ ] Alert-Manager.ps1 manages alert lifecycle
- [ ] Notification-Engine.ps1 supports all channels
- [ ] Escalation-Handler.ps1 implements escalation tiers
- [ ] Alerts are stored in database
- [ ] Notifications are sent correctly
- [ ] Escalation works with timeouts
- [ ] All scripts use centralized logging

Test the alerting system:

```powershell
# Create a test alert
Import-Module .\scripts\core\RMM-Core.psm1
.\scripts\alerts\Alert-Manager.ps1 -Action "Create" -DeviceId "localhost" -AlertType "Test" -Severity "High" -Title "Test Alert" -Message "This is a test"

# Send notification
.\scripts\alerts\Notification-Engine.ps1 -AlertId "test-alert-id" -Channels "Email"

# Test escalation
.\scripts\alerts\Escalation-Handler.ps1 -AlertId "test-alert-id" -Start

# Check alerts in database
Import-Module PSSQLite
Invoke-SqliteQuery -DataSource ".\data\devices.db" -Query "SELECT * FROM Alerts ORDER BY CreatedAt DESC LIMIT 10;"
```

---

**NEXT PROMPT:** [08-reports.md](08-reports.md) - Implement reporting system

---

*This is prompt 8 of 13 in the RMM build sequence*

