# PROMPT 01: Project Foundation & Setup

**Previous:** [00-overview.md](00-overview.md) - Read that first for context

---

## Your Task

Create the complete folder structure and foundation files for the myTech.Today RMM system. This establishes the project skeleton that all subsequent prompts will build upon.

---

## Step 1: Create Folder Structure

Create this exact folder structure in the RMM directory:

```plaintext
RMM/
├── README.md
├── LICENSE
├── .gitignore
├── config/
│   ├── settings.json
│   ├── thresholds.json
│   ├── groups.json
│   └── policies/
│       ├── default.json
│       └── servers.json
├── scripts/
│   ├── core/
│   │   ├── RMM-Core.psm1
│   │   ├── Initialize-RMM.ps1
│   │   ├── Config-Manager.ps1
│   │   └── Logging.ps1
│   ├── collectors/
│   │   ├── Inventory-Collector.ps1
│   │   ├── Hardware-Monitor.ps1
│   │   ├── Software-Auditor.ps1
│   │   ├── Security-Scanner.ps1
│   │   └── Event-Collector.ps1
│   ├── monitors/
│   │   ├── Health-Monitor.ps1
│   │   ├── Service-Monitor.ps1
│   │   ├── Performance-Monitor.ps1
│   │   └── Availability-Monitor.ps1
│   ├── actions/
│   │   ├── Remote-Actions.ps1
│   │   ├── Script-Executor.ps1
│   │   ├── Update-Manager.ps1
│   │   └── Remediation-Engine.ps1
│   ├── alerts/
│   │   ├── Alert-Manager.ps1
│   │   ├── Notification-Engine.ps1
│   │   └── Escalation-Handler.ps1
│   ├── reports/
│   │   ├── Report-Generator.ps1
│   │   ├── Compliance-Reporter.ps1
│   │   └── Executive-Dashboard.ps1
│   ├── automation/
│   │   ├── Policy-Engine.ps1
│   │   ├── Scheduled-Tasks.ps1
│   │   └── Workflow-Orchestrator.ps1
│   └── ui/
│       ├── Start-Console.ps1
│       ├── Start-WebDashboard.ps1
│       └── web/
│           ├── index.html
│           ├── styles.css
│           └── app.js
├── data/
│   ├── cache/
│   ├── queue/
│   └── archive/
├── logs/
│   └── devices/
├── secrets/
├── docs/
│   ├── Setup-Guide.md
│   ├── Architecture.md
│   ├── API-Reference.md
│   ├── Scaling-Guide.md
│   └── Troubleshooting.md
└── tests/
    ├── Unit/
    ├── Integration/
    └── Performance/
```

**Action:** Create all folders listed above. Do NOT create the files yet - just the directory structure.

---

## Step 2: Create .gitignore

Create standard `RMM/.gitignore` also with this content:

```gitignore
# Runtime data
data/
!data/cache/.gitkeep
!data/queue/.gitkeep
!data/archive/.gitkeep

# Logs
logs/
*.log
*.md.log

# Secrets and credentials
secrets/
*.xml
*.pfx
*.key

# PowerShell artifacts
*.ps1xml
*.psd1.bak

# IDE
.vscode/
.idea/
*.code-workspace

# OS
Thumbs.db
.DS_Store
```

---

## Step 3: Create LICENSE

Create `RMM/LICENSE` with this content:

```text
Private License

Copyright (c) 2025 Kyle C. Rode / myTech.Today

All rights reserved.

This software is proprietary and confidential. Unauthorized copying, distribution,
modification, or use of this software, via any medium, is strictly prohibited.

For licensing inquiries, contact: sales@mytech.today
```

---

## Step 4: Create Configuration Files

### config/settings.json

Create `RMM/config/settings.json`:

```json
{
  "General": {
    "OrganizationName": "myTech.Today",
    "DefaultSite": "Main",
    "DataRetentionDays": 90,
    "LogLevel": "Info"
  },
  "Connections": {
    "WinRMTimeout": 30,
    "WinRMMaxConcurrent": 25,
    "SSHEnabled": false,
    "RelayEnabled": false
  },
  "Monitoring": {
    "InventoryInterval": "Daily",
    "HealthCheckInterval": 300,
    "MetricsRetention": 7
  },
  "Notifications": {
    "EmailEnabled": false,
    "SmtpServer": "",
    "SlackWebhook": "",
    "TeamsWebhook": "",
    "PagerDutyKey": ""
  },
  "Security": {
    "RequireHttps": false,
    "CredentialCacheTTL": 3600,
    "AuditAllActions": true
  }
}
```

### config/thresholds.json

Create `RMM/config/thresholds.json`:

```json
{
  "CPU": {
    "Warning": 80,
    "Critical": 95
  },
  "Memory": {
    "Warning": 85,
    "Critical": 95
  },
  "DiskSpace": {
    "Warning": 20,
    "Critical": 10
  },
  "DiskLatency": {
    "Warning": 20,
    "Critical": 50
  },
  "NetworkErrors": {
    "Warning": 100,
    "Critical": 1000
  }
}
```

### config/groups.json

Create `RMM/config/groups.json`:

```json
{
  "groups": [
    {
      "id": "servers",
      "name": "Servers",
      "description": "All server endpoints",
      "tags": ["production", "critical"]
    },
    {
      "id": "workstations",
      "name": "Workstations",
      "description": "User workstations",
      "tags": ["users"]
    }
  ]
}
```

### config/policies/default.json

Create `RMM/config/policies/default.json`:

```json
{
  "policyId": "default",
  "name": "Default Policy",
  "description": "Default automation policy for all devices",
  "enabled": true,
  "rules": [
    {
      "trigger": "DiskSpaceLow",
      "condition": "DiskSpace < 10",
      "action": "ClearTempFiles",
      "autoRemediate": true
    },
    {
      "trigger": "ServiceStopped",
      "condition": "Service in CriticalServices",
      "action": "RestartService",
      "autoRemediate": true
    }
  ]
}
```

### config/policies/servers.json

Create `RMM/config/policies/servers.json`:

```json
{
  "policyId": "servers",
  "name": "Server Policy",
  "description": "Automation policy for server endpoints",
  "enabled": true,
  "appliesTo": ["servers"],
  "rules": [
    {
      "trigger": "HighCPU",
      "condition": "CPU > 95 for 5 minutes",
      "action": "AlertOnly",
      "autoRemediate": false
    },
    {
      "trigger": "UpdatesAvailable",
      "condition": "CriticalUpdates > 0",
      "action": "InstallUpdates",
      "autoRemediate": false,
      "requireApproval": true
    }
  ]
}
```

---

## Step 5: Create Placeholder .gitkeep Files

Create empty `.gitkeep` files in these directories to preserve them in git:

- `RMM/data/cache/.gitkeep`
- `RMM/data/queue/.gitkeep`
- `RMM/data/archive/.gitkeep`
- `RMM/logs/devices/.gitkeep`
- `RMM/secrets/.gitkeep`

---

## Validation

After completing this prompt, verify:

- [ ] All folders exist
- [ ] .gitignore is created
- [ ] LICENSE is created
- [ ] All 6 configuration JSON files are created and valid
- [ ] .gitkeep files are in place

---

**NEXT PROMPT:** [02-architecture.md](02-architecture.md) - Database schema and architecture setup

---

*This is prompt 2 of 13 in the RMM build sequence*

