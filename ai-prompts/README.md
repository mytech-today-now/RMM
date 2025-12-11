# myTech.Today RMM System - AI Prompt Documentation

This folder contains comprehensive AI prompts for generating the myTech.Today RMM (Remote Monitoring and Management) system. The documentation has been split into logical modules for easier maintenance and consumption.

## Reading Order

For AI systems generating the RMM codebase, read files in this order:

1. **[00-overview.md](00-overview.md)** - Executive summary, target environment, technical requirements
2. **[01-repository-structure.md](01-repository-structure.md)** - Complete folder and file structure
3. **[02-architecture.md](02-architecture.md)** - Core architecture, communication, storage, database schema

### Feature Modules (in `modules/` folder)

4. **[modules/03-core-framework.md](modules/03-core-framework.md)** - Core framework (RMM-Core.psm1, Initialize, Config)
5. **[modules/04-collectors.md](modules/04-collectors.md)** - Data collection (Inventory, Hardware, Software, Security, Events)
6. **[modules/05-monitors.md](modules/05-monitors.md)** - Health monitoring (Health, Service, Performance, Availability)
7. **[modules/06-actions.md](modules/06-actions.md)** - Remote actions (Actions, Scripts, Updates, Remediation)
8. **[modules/07-alerts.md](modules/07-alerts.md)** - Alerting system (Alerts, Notifications, Escalation)
9. **[modules/08-reports.md](modules/08-reports.md)** - Reporting (Reports, Compliance, Executive Dashboard)
10. **[modules/09-automation.md](modules/09-automation.md)** - Automation (Policy Engine, Scheduled Tasks, Workflows)
11. **[modules/10-ui.md](modules/10-ui.md)** - User interfaces (CLI Console, Web Dashboard)

### Operational Documentation

12. **[11-scalability.md](11-scalability.md)** - Scaling architecture for 1000+ endpoints
13. **[12-security.md](12-security.md)** - Security model, authentication, audit logging
14. **[13-implementation.md](13-implementation.md)** - Coding standards, error handling, testing
15. **[14-comparison.md](14-comparison.md)** - Feature comparison with commercial RMM tools
16. **[15-quickstart.md](15-quickstart.md)** - Quick start guide and generation instructions

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

## Quick Reference

### Key Technologies
- PowerShell 5.1+ (7.4+ recommended)
- WinRM for remote execution
- SQLite for data storage
- PSWriteHTML for dashboards

### Core Modules Required
- PSWindowsUpdate
- PSSQLite
- ThreadJob
- ImportExcel
- PSWriteHTML

---

## Archive

The original consolidated file is preserved as:
- **[RMM-start-ARCHIVE.md](RMM-start-ARCHIVE.md)** - Original 1,048-line specification (for reference)

---

*Generated: 2025-12-11*
*Total Documentation: 16 files across 2 directories*

