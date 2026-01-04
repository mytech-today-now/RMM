You are an expert PowerShell developer refactoring a cross-platform PowerShell-based RMM (Remote Monitoring and Management) project that must run reliably on Windows, macOS, and Linux using PowerShell 7+ (pwsh).

The repository root is currently open in VS Code, and you have full access to all files in the project (especially under `scripts/`, `modules/`, `lib/`, and configuration files).

### Primary Goals
Refactor the Health Monitor script (`scripts/monitors/Health-Monitor.ps1`) and any supporting modules/functions to address the following critical issues:

1. **Eliminate Redundant Initialization Steps**
   - Current behavior shows logging being initialized multiple times:
     ```
     [OK] RMM logging initialized
     [OK] Configuration is valid
     [INFO] RMM already initialized. Use -Force to reinitialize.
     True
     [INFO] Initializing RMM logging...
     ```
   - This results in unnecessary repeated calls to initialization routines (e.g., core RMM init followed by health-monitor-specific logging init).
   - Refactor the initialization logic so that:
     - Core RMM logging and configuration validation occur only once per script execution.
     - If the RMM core is already initialized in the session, skip reinitialization entirely (do not print informational messages suggesting `-Force` unless explicitly requested).
     - Health-monitor-specific logging should append to or reuse existing log infrastructure without triggering full reinitialization.
     - Ensure no duplicate "Initializing RMM logging..." messages appear.

2. **Dramatically Improve Performance of Health Check Execution**
   - Current runtime: ~2–3 minutes even on a local device, with the longest delay observed between firewall check (~23:14:38) and Windows Updates check (~23:16:18) — approximately 100 seconds for what should be fast queries.
   - Target: Entire health check for a single local device should complete in under 15 seconds, even on slow hardware.
   - Specific areas to optimize:
     - **Windows Updates check**: This is the clearest bottleneck. Replace any slow methods (e.g., COM objects like `Microsoft.Update.Session`, repeated searches via `Get-HotFix` or `Get-WUList`) with faster, modern alternatives:
       - Prefer `PSWindowsUpdate` module if available, but since this must remain cross-platform and dependency-light, use efficient built-in CIM/WMI queries or `Get-CimInstance` where possible.
       - On Windows, use `Get-CimInstance -ClassName Win32_QuickFixEngineering` selectively or check pending reboots/updates via registry + USO status without full session scanning.
       - Cache results where safe and avoid unnecessary enumeration.
     - **Antivirus/Firewall checks**: Ensure they use fast native cmdlets (`Get-MpComputerStatus`, `Get-NetFirewallProfile`) and avoid loops or slow external commands.
     - **Performance metrics (CPU, Memory, Disk)**: These are already fast — retain efficient methods (e.g., `Get-CimInstance Win32_OperatingSystem`, `Get-CimInstance Win32_LogicalDisk`).
     - **Parallelize where safe**: For multiple devices, use background jobs or `ForEach-Object -Parallel` (in PW 7+), but preserve serial efficiency for single-device local runs.
     - **Avoid repeated expensive calls**: Ensure no duplicate queries for the same data across checks.

3. **Fix Incorrect Health Score Aggregation and Summary Reporting**
   - Current output shows inconsistencies:
     - Final device line: `FINAL SCORE: 71/100 [Availability: 25/25, Performance: 4/25, Security: 22/25, Compliance: 20/25]`
     - Summary section claims: `Average Health Score: 71/100` with `Healthy: 0, Warning: 1`, but category totals must always add up correctly.
   - Ensure:
     - Sub-scores (Availability, Performance, Security, Compliance) always sum precisely to the final score (e.g., 25 + 4 + 22 + 20 = 71).
     - The "Health Assessment Summary" accurately reflects counts:
       - Healthy: devices with score ≥ 90
       - Warning: 70 ≤ score < 90
       - Critical: score < 70
       - Offline: unreachable devices
     - Both the per-device final line and the overall summary must display identical category breakdowns and correct bucket counts.

### General Refactoring Guidelines
- Maintain full cross-platform compatibility:
  - Use PowerShell 7+ core features only.
  - Guard Windows-specific checks with `$IsWindows` or `-eq "Windows"` platform checks.
  - On macOS/Linux, gracefully skip or mock Windows-only checks (e.g., Windows Updates, Defender, Firewall profiles) and award neutral/maximum points where appropriate, with clear log messages indicating "N/A on this platform".
  - Disk, CPU, and memory checks should remain fully functional on all platforms using cross-platform CIM equivalents or `Get-ComputerInfo` where possible.
- Prioritize readability, maintainability, and modularity:
  - Break large functions into smaller, well-named, pure functions where possible.
  - Use descriptive variable names and add comment-based help where useful.
  - Keep backward compatibility with existing command-line usage.
- Logging:
  - Preserve structured log output but reduce verbosity during normal runs.
  - Only emit progress/timing info when `-Verbose` or `-Debug` is used.
- Error handling:
  - Gracefully handle failures in individual checks without halting the entire monitor.
  - Continue assessing remaining categories if one fails.

Implement these changes with clean, efficient, well-tested PowerShell code that results in a noticeably faster, cleaner, and more accurate health monitoring experience across Windows, macOS, and Linux.