# myTech.Today RMM - Architecture

## High-Level System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         myTech.Today RMM Central Console                     │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │  Web Dashboard │ │ CLI Console  │ │  Scheduler   │ │   Alerting   │        │
│  └───────┬──────┘ └───────┬──────┘ └───────┬──────┘ └───────┬──────┘        │
│          └────────────────┴────────────────┴────────────────┘                │
│                                    │                                         │
│  ┌─────────────────────────────────┴─────────────────────────────────────┐  │
│  │                           RMM-Core.psm1                                │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐          │  │
│  │  │Collectors│ │Monitors │ │ Actions │ │ Alerts  │ │ Reports │          │  │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘          │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│  ┌─────────────────────────────────┴─────────────────────────────────────┐  │
│  │                         SQLite Database                                │  │
│  │  Devices │ Metrics │ Inventory │ Alerts │ Actions │ AuditLog          │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
         │                    │                    │
    ┌────┴────┐          ┌────┴────┐          ┌────┴────┐
    │ WinRM   │          │  SSH    │          │  SMB    │
    │ (5985)  │          │  (22)   │          │ (445)   │
    └────┬────┘          └────┬────┘          └────┬────┘
         │                    │                    │
┌────────┴────────────────────┴────────────────────┴────────┐
│                    Managed Endpoints                       │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐          │
│  │ Servers │ │Workstations│ │ Laptops │ │ Linux   │          │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘          │
└───────────────────────────────────────────────────────────┘
```

## Hybrid Pull/Push Communication Model

The RMM uses a **hybrid model** combining pull and push mechanisms:

| Method | Direction | Use Case |
|--------|-----------|----------|
| **Push (WinRM)** | Console → Endpoint | Real-time commands, immediate actions |
| **Pull (Scheduled)** | Console ← Endpoint | Bulk data collection, inventory scans |
| **Event-Driven** | Endpoint → Console | Critical alerts, threshold breaches |

## Component Overview

### Core Components (`scripts/core/`)
| Component | Purpose |
|-----------|---------|
| RMM-Core.psm1 | Main module exporting all functions |
| Initialize-RMM.ps1 | Bootstrap and installation |
| Initialize-Database.ps1 | Database schema creation |
| Config-Manager.ps1 | Configuration handling |
| Logging.ps1 | Centralized logging |
| Scalability.ps1 | Parallel processing, caching |
| Security.ps1 | Credentials, RBAC, audit |
| Database-Maintenance.ps1 | VACUUM, archival, backup |

### Collectors (`scripts/collectors/`)
| Script | Data Collected |
|--------|----------------|
| Inventory-Collector.ps1 | Hardware, software, network |
| Hardware-Monitor.ps1 | CPU, memory, disk, temperature |
| Software-Auditor.ps1 | Installed applications, licenses |
| Security-Scanner.ps1 | Vulnerabilities, compliance |
| Event-Collector.ps1 | Windows Event Logs |

### Monitors (`scripts/monitors/`)
| Script | Monitoring Target |
|--------|-------------------|
| Health-Monitor.ps1 | Overall device health score |
| Performance-Monitor.ps1 | CPU, memory, disk metrics |
| Availability-Monitor.ps1 | Uptime, connectivity |
| Service-Monitor.ps1 | Windows services status |

### Actions (`scripts/actions/`)
| Script | Capability |
|--------|------------|
| Remote-Actions.ps1 | Restart, shutdown, commands |
| Script-Executor.ps1 | Run custom scripts |
| Update-Manager.ps1 | Windows Update management |
| Remediation-Engine.ps1 | Auto-fix common issues |

### Alerts (`scripts/alerts/`)
| Script | Function |
|--------|----------|
| Alert-Manager.ps1 | Create, manage, resolve alerts |
| Notification-Engine.ps1 | Email, Teams, Slack notifications |
| Escalation-Handler.ps1 | Tiered escalation rules |

### Reports (`scripts/reports/`)
| Script | Output |
|--------|--------|
| Report-Generator.ps1 | HTML/Excel reports |
| Executive-Dashboard.ps1 | Summary dashboards |
| Compliance-Reporter.ps1 | Compliance status |

### Automation (`scripts/automation/`)
| Script | Purpose |
|--------|---------|
| Policy-Engine.ps1 | Policy enforcement |
| Workflow-Orchestrator.ps1 | Multi-step workflows |
| Scheduled-Tasks.ps1 | Task scheduling |

## Data Flow

```
[Endpoint] ──WinRM──► [Collector] ──► [Database] ──► [Monitor] ──► [Alert]
                                           │                          │
                                           ▼                          ▼
                                      [Reports]              [Notification]
                                           │                          │
                                           ▼                          ▼
                                    [Web Dashboard]           [Email/Teams]
```

## Tiered Storage Model

| Tier | Data Age | Storage | Query Speed |
|------|----------|---------|-------------|
| **Hot** | 0-24 hours | Memory Cache | < 10ms |
| **Warm** | 1-7 days | SQLite (indexed) | < 100ms |
| **Cold** | 7-90 days | SQLite (archived) | < 1s |
| **Archive** | 90+ days | Compressed files | > 1s |

## Database Schema (8 Tables)

| Table | Purpose | Key Fields |
|-------|---------|------------|
| Devices | Managed endpoints | DeviceId, Hostname, Status |
| Metrics | Performance data | DeviceId, MetricType, Value |
| Inventory | Hardware/software | DeviceId, Category, Data |
| Alerts | Alert records | AlertId, Severity, Status |
| Actions | Action history | ActionId, Type, Result |
| AuditLog | Security audit | Username, Action, Timestamp |
| Policies | Policy definitions | PolicyId, Rules |
| Sites | Site definitions | SiteId, Name, RelayAgent |

## Multi-Site Architecture

```
┌─────────────────────┐
│   Central Console   │
│   (Headquarters)    │
└──────────┬──────────┘
           │
    ┌──────┴──────┐
    │             │
┌───┴───┐   ┌────┴────┐
│Site A │   │ Site B  │
│ Relay │   │  Relay  │
└───┬───┘   └────┬────┘
    │            │
┌───┴───┐   ┌────┴────┐
│ 500   │   │  300    │
│Devices│   │ Devices │
└───────┘   └─────────┘
```

---

*myTech.Today RMM - Architecture v1.0*

