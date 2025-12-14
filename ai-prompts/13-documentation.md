# PROMPT 13: Documentation Files

**Previous:** [12-testing-validation.md](12-testing-validation.md) - Complete that first

---

## Your Task

Create the 5 missing documentation files in the `docs/` folder. These provide essential guidance for users deploying, configuring, and troubleshooting the RMM system.

---

## Step 1: Create docs/Setup-Guide.md

Create `RMM/docs/Setup-Guide.md` with:

**Content Requirements:**
- Prerequisites (PowerShell version, admin rights, network requirements)
- Quick start installation steps using `Initialize-RMM.ps1 -Mode Install`
- Required PowerShell modules (PSSQLite, PSWindowsUpdate, ThreadJob, ImportExcel, PSWriteHTML)
- WinRM configuration for remote endpoints
- First device onboarding walkthrough
- Importing devices from CSV
- Verifying installation success
- Common installation issues and solutions

---

## Step 2: Create docs/Architecture.md

Create `RMM/docs/Architecture.md` with:

**Content Requirements:**
- High-level system architecture diagram (ASCII art)
- Hybrid Pull/Push communication model explanation
- Component overview (Core, Collectors, Monitors, Actions, Alerts, Reports, Automation, UI)
- Data flow between components
- Tiered storage model (Hot/Warm/Cold/Archive)
- Database schema summary (8 tables, their purposes)
- Communication methods (WinRM HTTP/HTTPS, SSH, SMB fallback, Relay agents)
- Multi-site architecture with relay agents

Reference the diagrams from `02-architecture.md` for ASCII art.

---

## Step 3: Create docs/API-Reference.md

Create `RMM/docs/API-Reference.md` with:

**Content Requirements:**
- RMM-Core.psm1 exported functions reference:
  - `Initialize-RMM` - Bootstrap environment
  - `Get-RMMConfig` / `Set-RMMConfig` - Configuration management
  - `Get-RMMDevice` / `Add-RMMDevice` / `Update-RMMDevice` / `Remove-RMMDevice` - Device CRUD
  - `Invoke-RMMAction` - Action execution
  - `Get-RMMHealth` - Health summary
  - `Get-RMMDatabase` - Database connection
- Parameter documentation for each function
- Example usage for common scenarios
- Return value descriptions
- Error codes and meanings

---

## Step 4: Create docs/Scaling-Guide.md

Create `RMM/docs/Scaling-Guide.md` with:

**Content Requirements:**
- Scale targets table (150 initial → 10,000+ maximum)
- Parallel processing configuration (ThrottleLimit settings)
- Connection pooling and session management
- Database optimization (indexing, VACUUM schedule, batch operations)
- Caching strategies (device status, inventory, configuration)
- Multi-site deployment with relay agents
- Performance tuning recommendations by endpoint count:
  - 1-150 endpoints: Default settings
  - 150-500 endpoints: Increase ThrottleLimit, enable caching
  - 500-2000 endpoints: Add relay agents, batch operations
  - 2000-10000+ endpoints: Full multi-site with local caches
- Hardware recommendations for central console

---

## Step 5: Create docs/Troubleshooting.md

Create `RMM/docs/Troubleshooting.md` with:

**Content Requirements:**
- Common issues and solutions:
  - WinRM connection failures
  - Database locked errors
  - Module import failures
  - Credential/authentication issues
  - Firewall blocking connections
  - Device appearing offline incorrectly
  - Reports not generating
  - Web dashboard not loading
- Log file locations (`%USERPROFILE%\myTech.Today\logs\`)
- Diagnostic commands for each component
- How to enable debug logging
- Database repair procedures
- Resetting the RMM installation
- Getting support / reporting issues

---

## Validation

After completing this prompt, verify:

- [ ] `docs/Setup-Guide.md` exists and covers installation
- [ ] `docs/Architecture.md` exists with diagrams
- [ ] `docs/API-Reference.md` documents all core functions
- [ ] `docs/Scaling-Guide.md` covers scaling strategies
- [ ] `docs/Troubleshooting.md` addresses common issues
- [ ] All files use consistent markdown formatting
- [ ] All files include myTech.Today branding
- [ ] Cross-references between docs are correct

```powershell
# Verify all documentation files exist
$docs = @(
    ".\docs\Setup-Guide.md",
    ".\docs\Architecture.md", 
    ".\docs\API-Reference.md",
    ".\docs\Scaling-Guide.md",
    ".\docs\Troubleshooting.md"
)
$docs | ForEach-Object {
    if (Test-Path $_) {
        Write-Host "[PASS] $_ exists" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $_ missing" -ForegroundColor Red
    }
}
```

---

**PREVIOUS PROMPT:** [12-testing-validation.md](12-testing-validation.md)

**NEXT PROMPT:** [14-web-assets.md](14-web-assets.md) - Create web dashboard UI files (if needed)

---

*This is a supplementary prompt to complete documentation gaps*

*Return to: [README.md](README.md) for overview*

