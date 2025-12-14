# PROMPT 00: Project Overview & Context

**READ THIS FIRST** - This provides essential context for all subsequent prompts.

---

## Project Mission

You are building the **myTech.Today RMM (Remote Monitoring and Management)** system - a complete, production-ready, enterprise-capable PowerShell-based RMM solution.

**Key Facts:**
- **Author:** Kyle C. Rode (myTech.Today)
- **Version:** 2.0
- **Initial Scale:** 150 endpoints
- **Maximum Scale:** 10,000+ endpoints
- **Feature Coverage:** ~70% of commercial RMM capabilities
- **Cost:** Free/open-source

---

## What You're Building

A comprehensive RMM system with:
- ✅ Asset inventory and hardware/software auditing
- ✅ Real-time health monitoring and alerting
- ✅ Remote actions and script execution
- ✅ Windows Update management via WinGet
- ✅ Automated remediation and policy enforcement
- ✅ Executive dashboards and compliance reporting
- ✅ Multi-site support with relay agents
- ✅ Web-based and CLI interfaces

---

## Technical Foundation

### PowerShell Requirements
- **Minimum:** PowerShell 5.1 (Windows)
- **Recommended:** PowerShell 7.4+ (for parallel processing)
- **Cross-platform:** Optional Linux/macOS support via PS7

### Target Operating Systems
- Windows 10 21H2+ (Pro/Enterprise)
- Windows 11 (all versions)
- Windows Server 2016, 2019, 2022, 2025
- Optional: Linux endpoints via SSH

### Core Dependencies (auto-install during setup)
- `PSWindowsUpdate` - Windows Update management
- `PSSQLite` - SQLite database operations
- `ThreadJob` - Parallel processing (PS5.1)
- `ImportExcel` - Excel report generation
- `PSWriteHTML` - HTML dashboard generation

### Architecture Principles
- **Hybrid Pull/Push:** Central console pulls data, pushes actions
- **Tiered Storage:** In-memory → JSON cache → SQLite → Archive
- **Scalable:** Parallel processing, connection pooling, caching
- **Secure:** DPAPI encryption, audit logging, RBAC
- **Maintainable:** Modular design, comprehensive logging

---

## Scale Targets

| Metric | Initial | Maximum |
|--------|---------|---------|
| Endpoints | 150 | 10,000+ |
| Concurrent Operations | 25 | 500 |
| Data Retention | 90 days | 2 years |
| Geographic Sites | 1 | 50+ |
| Admin Users | 1-3 | 25+ |

---

## Important Notes for AI

1. **Follow myTech.Today standards:** Reference `.augment/core-guidelines.md` for coding standards
2. **Use shared logging:** Integrate with `Q:\_kyle\temp_documents\GitHub\PowerShellScripts\scripts\logging.ps1`, which remains at `https://raw.githubusercontent.com/mytech-today-now/scripts/refs/heads/main/logging.ps1`  The logging.ps1 scripts should be updated as necessary, but remain backwards compatible with other scripts in the PowerShellScripts repo.
3. **Production quality:** Include error handling, logging, parameter validation, and help documentation
4. **No emoji:** ASCII-only output per myTech.Today standards

---

**NEXT PROMPT:** [01-project-foundation.md](01-project-foundation.md) - Create project structure and foundation files

---

*This is prompt 1 of 13 in the RMM build sequence*

