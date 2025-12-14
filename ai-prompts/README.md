# myTech.Today RMM System - Augment AI Prompt Sequence

This folder contains a **sequential series of Augment AI prompts** for building the myTech.Today RMM (Remote Monitoring and Management) system from scratch.

## How to Use These Prompts

**Feed these prompts to Augment AI one after another in order.** Each prompt builds on the previous one and includes validation steps to ensure correctness before proceeding.

---

## Prompt Sequence (13 Total)

Execute these prompts in Augment AI in this exact order:

### Foundation (Prompts 0-2)

**PROMPT 00:** [00-overview.md](00-overview.md) - Project Overview & Context
- Understand the mission, scope, and technical foundation
- Review key facts and feature coverage

**PROMPT 01:** [01-repository-structure.md](01-repository-structure.md) - Project Foundation & Setup
- Create complete folder structure
- Generate .gitignore, LICENSE, and all configuration files

**PROMPT 02:** [02-architecture.md](02-architecture.md) - Database Schema & Architecture Setup
- Create Initialize-Database.ps1 script
- Set up SQLite database with all tables and indexes

### Core Modules (Prompts 3-10)

**PROMPT 03:** [modules/03-core-framework.md](modules/03-core-framework.md) - Core Framework Implementation
- Build RMM-Core.psm1 module
- Create Initialize-RMM.ps1, Config-Manager.ps1, Logging.ps1

**PROMPT 04:** [modules/04-collectors.md](modules/04-collectors.md) - Data Collection System
- Implement 5 collector scripts (Inventory, Hardware, Software, Security, Events)

**PROMPT 05:** [modules/05-monitors.md](modules/05-monitors.md) - Health Monitoring System
- Implement 4 monitor scripts (Health, Service, Performance, Availability)

**PROMPT 06:** [modules/06-actions.md](modules/06-actions.md) - Remote Actions System
- Implement 4 action scripts (Remote-Actions, Script-Executor, Update-Manager, Remediation-Engine)

**PROMPT 07:** [modules/07-alerts.md](modules/07-alerts.md) - Alerting System
- Implement 3 alert scripts (Alert-Manager, Notification-Engine, Escalation-Handler)

**PROMPT 08:** [modules/08-reports.md](modules/08-reports.md) - Reporting System
- Implement 3 report scripts (Report-Generator, Compliance-Reporter, Executive-Dashboard)

**PROMPT 09:** [modules/09-automation.md](modules/09-automation.md) - Automation System
- Implement 3 automation scripts (Policy-Engine, Scheduled-Tasks, Workflow-Orchestrator)

**PROMPT 10:** [modules/10-ui.md](modules/10-ui.md) - User Interfaces
- Implement CLI console (Start-Console.ps1)
- Implement web dashboard (Start-WebDashboard.ps1)
- Create web assets (HTML/CSS/JS)

### Finalization (Prompts 11-12)

**PROMPT 11:** [11-scalability-security-implementation.md](11-scalability-security-implementation.md) - Scalability, Security & Implementation
- Add parallel processing and caching
- Implement security hardening (DPAPI, audit logging)
- Ensure all code follows standards

**PROMPT 12:** [12-testing-validation.md](12-testing-validation.md) - Testing & Validation
- Create Pester tests
- Generate sample data
- Validate entire system
- Verify performance targets

### Supplementary (Prompts 13+)

**PROMPT 13:** [13-documentation.md](13-documentation.md) - Documentation Files
- Create Setup-Guide.md, Architecture.md, API-Reference.md
- Create Scaling-Guide.md, Troubleshooting.md
- Complete the docs/ folder

**PROMPT 14:** [14-web-assets.md](14-web-assets.md) - Web Dashboard Assets *(if needed)*
- Create index.html, styles.css, app.js
- Complete the scripts/ui/web/ folder

---

## What You'll Build

By completing all prompts, you will have:

- **Complete RMM system** with ~70% of commercial RMM features
- **30+ PowerShell scripts** across 11 functional areas
- **SQLite database** with 8 tables and 11 indexes
- **CLI console** and **web dashboard** interfaces
- **Comprehensive monitoring** (inventory, health, performance, security)
- **Remote management** (actions, scripts, updates, remediation)
- **Alerting system** (multi-channel notifications, escalation)
- **Reporting** (executive dashboards, compliance reports)
- **Automation** (policies, scheduled tasks, workflows)
- **Scalability** for 150-10,000+ endpoints
- **Security hardening** (DPAPI encryption, audit logging)
- **Pester tests** for validation

---

## Project Summary

| Attribute | Value |
|-----------|-------|
| **Project** | myTech.Today Remote Monitoring and Management (RMM) |
| **Version** | 2.0 |
| **Author** | Kyle C. Rode |
| **Company** | myTech.Today |
| **Initial Target** | 150 endpoints |
| **Maximum Scale** | 10,000+ endpoints |
| **Commercial Coverage** | ~70% of commercial RMM features |
| **Cost** | Free (open-source) |

---

## Key Technologies

- **PowerShell 5.1+** (7.4+ recommended for parallel processing)
- **WinRM** for remote execution
- **SQLite** for data storage (via PSSQLite module)
- **PSWriteHTML** for dashboards and reports
- **PSWindowsUpdate** for patch management

### Required PowerShell Modules

- PSWindowsUpdate
- PSSQLite
- ThreadJob
- ImportExcel
- PSWriteHTML

---

## Tips for Success

1. **Execute prompts in order** - Each builds on the previous
2. **Complete validation steps** - Don't skip testing between prompts
3. **Review generated code** - Ensure it meets your requirements
4. **Test incrementally** - Validate each component before moving on
5. **Customize as needed** - Adapt thresholds, policies, and configurations

---

## Archive

The original consolidated specification is preserved as:
- **[RMM-start-ARCHIVE.md](RMM-start-ARCHIVE.md)** - Original 1,048-line specification (for reference)

---

*Last Updated: 2025-12-11*

*Total Prompts: 13 sequential prompts across 2 directories*

*Estimated Build Time: 4-8 hours (depending on AI speed and validation thoroughness)*

