You are an expert PowerShell developer working on a cross-platform PowerShell repository that supports Windows, macOS, and Linux via PowerShell 7+. The repository contains scripts and modules related to Remote Monitoring and Management (RMM) tools, including functions like Get-RMMDevice, which retrieves detailed information about the local device from the RMM agent's perspective.

The user has reported an issue where the output of Get-RMMDevice is incomplete or missing key fields, showing many blank values:

DeviceId : fe0853e2-10b4-4830-9d5e-f8378677f493
Hostname : MYTECHTODAY-LAP
FQDN :
IPAddress : 192.168.0.101
MACAddress :
Status : Online
LastSeen :
SiteId : default
DeviceType : Workstation
OSName :
OSVersion :
OSBuild :
Manufacturer :
Model :
SerialNumber :
AgentVersion :
Tags :
Description :
Notes :
CredentialName :
AdminUsername :
AdminPasswordEncrypted :
CreatedAt : 2025-12-14 22:51:30
UpdatedAt : 2025-12-14 22:51:30

The user suspects a problem with the health check or device information gathering process on their local computer. They want a reliable solution that fetches and returns real, accurate data without relying on placeholders, mock data, or fake values.

Your task is to:

1. Diagnose the likely cause of the missing fields. Consider common issues in RMM integrations, such as:
   - Incomplete agent reporting or delayed synchronization with the RMM server.
   - Permissions issues preventing the agent from collecting certain system details.
   - API limitations or bugs in how device audit data is retrieved.
   - Differences in data availability when running locally vs. via remote RMM execution.
   - Cross-platform variations (e.g., some fields like Manufacturer/Model/SerialNumber may be harder to collect reliably on macOS/Linux).

2. Refactor the Get-RMMDevice function (and any supporting functions, such as health checks, audit collection, or API calls) to ensure it reliably populates all possible fields with real data.

Key refactoring goals:
- Prioritize accuracy and completeness: Use direct system queries where possible to supplement or replace RMM API data if the API returns incomplete info.
- Avoid any hard-coded placeholders, default empty strings, or simulated data. If a field cannot be retrieved, leave it null or add clear error logging, but never fake it.
- Make the function robust and user-friendly: Include detailed verbose output, helpful error messages, and progress indicators.
- Ensure cross-platform compatibility:
  - On Windows: Use WMI/CIM (e.g., Win32_ComputerSystem, Win32_OperatingSystem, Win32_NetworkAdapterConfiguration) for OS, manufacturer, model, serial, MAC, etc.
  - On macOS: Use system commands like system_profiler, sw_vers, networksetup.
  - On Linux: Use commands like lshw, uname, hostnamectl, dmidecode (if available), ip/ifconfig for network info.
  - Detect the platform with $IsWindows, $IsMacOS, $IsLinux and branch logic accordingly.
- If the function relies on an RMM API or module (e.g., for DeviceId, SiteId, AgentVersion), ensure proper authentication, retry logic, and fallback to local collection where API data is missing.
- Add comprehensive comment-based help, parameter validation, and output as a well-structured PSObject for easy piping and formatting.
- Include logging (Write-Verbose, Write-Warning) to explain why certain fields might be empty if retrieval fails.
- Test for edge cases: Offline agents, restricted permissions, virtual machines, containers.

3. If needed, create or update a separate local device info collector function (e.g., Get-LocalDeviceInfo) that Get-RMMDevice can merge with RMM-specific data.

4. Provide clean, modular, readable code with consistent naming, error handling (try/catch), and no redundant operations.

5. After refactoring, suggest tests the user can run locally on Windows, macOS, and Linux to verify full data population.

Produce the refactored code files/changes with clear explanations. Focus on creating the most reliable, maintainable, and easy-to-use implementation possible.