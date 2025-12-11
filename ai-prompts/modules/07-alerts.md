# Alerting System (scripts/alerts/)

*Previous: [06-actions.md](06-actions.md)*

---

## Alert-Manager.ps1

- **Purpose:** Central alert processing
- **Alert Lifecycle:**

```
Triggered -> Active -> [Acknowledged] -> Resolved -> Archived
```

- **Alert Deduplication:** Same alert type + device within 5 minutes = increment count
- **Alert Correlation:** Group related alerts (e.g., disk + performance = "Resource Exhaustion")
- **Auto-Resolution:** Automatically resolve when condition clears

---

## Notification-Engine.ps1

### Channels Supported

| Channel | Configuration | Features |
|---------|---------------|----------|
| Email (SMTP) | Server, port, credentials | HTML templates, attachments |
| Microsoft Teams | Webhook URL | Adaptive cards, action buttons |
| Slack | Webhook URL | Rich formatting, threads |
| PagerDuty | Integration key | Escalation, on-call routing |
| SMS (Twilio) | Account SID, Auth token | Critical alerts only |
| Webhook (Generic) | URL, headers | JSON payload, custom format |
| Windows Event Log | Local/remote | For SIEM integration |

### Notification Rules

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

---

## Escalation-Handler.ps1

- **Purpose:** Time-based alert escalation
- **Features:**
  - Multi-tier escalation paths
  - Business hours awareness
  - On-call schedule integration
  - Escalation timeout (no response)
  - Manager override notifications

---

*Next: [08-reports.md](08-reports.md)*

