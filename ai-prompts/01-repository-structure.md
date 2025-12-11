# Repository Structure

*Previous: [00-overview.md](00-overview.md)*

---

## Complete Folder and File Structure

```
RMM/
├── README.md                    # Quick start, feature matrix, screenshots
├── LICENSE                      # Private License
├── .gitignore                   # Exclude data/, logs/, *.log, secrets/
├── config/
│   ├── settings.json            # Global configuration
│   ├── thresholds.json          # Alert thresholds
│   ├── groups.json              # Device groups/tags
│   └── policies/                # Automation policies
│       ├── default.json
│       └── servers.json
├── scripts/
│   ├── core/                    # Core framework
│   │   ├── RMM-Core.psm1        # Main module (import all)
│   │   ├── Initialize-RMM.ps1   # Bootstrap/setup
│   │   ├── Config-Manager.ps1   # Configuration handling
│   │   └── Logging.ps1          # Centralized logging via 'Q:\_kyle\temp_documents\GitHub\PowerShellScripts\scripts\logging.ps1', which is located at 'https://raw.githubusercontent.com/mytech-today-now/scripts/refs/heads/main/logging.ps1', update as necessary, but remain backwards compatible, with the rest of the dependent scripts in the './powershellscripts/' repo.
│   ├── collectors/              # Data collection
│   │   ├── Inventory-Collector.ps1
│   │   ├── Hardware-Monitor.ps1
│   │   ├── Software-Auditor.ps1
│   │   ├── Security-Scanner.ps1
│   │   └── Event-Collector.ps1
│   ├── monitors/                # Health monitoring
│   │   ├── Health-Monitor.ps1
│   │   ├── Service-Monitor.ps1
│   │   ├── Performance-Monitor.ps1
│   │   └── Availability-Monitor.ps1
│   ├── actions/                 # Remote actions
│   │   ├── Remote-Actions.ps1
│   │   ├── Script-Executor.ps1
│   │   ├── Update-Manager.ps1
│   │   └── Remediation-Engine.ps1
│   ├── alerts/                  # Alerting system
│   │   ├── Alert-Manager.ps1
│   │   ├── Notification-Engine.ps1
│   │   └── Escalation-Handler.ps1
│   ├── reports/                 # Reporting
│   │   ├── Report-Generator.ps1
│   │   ├── Compliance-Reporter.ps1
│   │   └── Executive-Dashboard.ps1
│   ├── automation/              # Automation
│   │   ├── Policy-Engine.ps1
│   │   ├── Scheduled-Tasks.ps1
│   │   └── Workflow-Orchestrator.ps1
│   └── ui/                      # User interfaces
│       ├── Start-Console.ps1    # CLI dashboard
│       ├── Start-WebDashboard.ps1
│       └── web/                 # HTML/CSS/JS assets
├── data/                        # Runtime data (gitignored)
│   ├── devices.db               # SQLite device database
│   ├── cache/                   # Hot data cache (JSON)
│   ├── queue/                   # Action queue
│   └── archive/                 # Historical data
├── logs/                        # Log files (gitignored)
│   ├── rmm.md                   # Main log
│   └── devices/                 # Per-device logs
├── secrets/                     # Credentials (gitignored)
│   └── credentials.xml          # Encrypted credentials
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

---

*Next: [02-architecture.md](02-architecture.md)*

