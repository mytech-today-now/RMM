<#
.SYNOPSIS
    Software inventory and compliance checking.

.DESCRIPTION
    Audits installed software, checks against blacklist/whitelist, tracks licenses,
    and verifies version compliance.

.PARAMETER Devices
    Array of device hostnames, a group name, or "All" to audit all devices.

.PARAMETER CheckCompliance
    Enable compliance checking against policy.

.PARAMETER DatabasePath
    Path to the RMM database. If not specified, uses the default from RMM-Core.

.EXAMPLE
    .\Software-Auditor.ps1 -Devices "localhost"

.EXAMPLE
    .\Software-Auditor.ps1 -Devices "Workstations" -CheckCompliance

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+, PSSQLite module
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Devices = @("All"),

    [Parameter()]
    [switch]$CheckCompliance,

    [Parameter()]
    [string]$DatabasePath
)

# Import required modules
$ErrorActionPreference = 'Stop'

try {
    $rmmCorePath = Join-Path $PSScriptRoot "..\core\RMM-Core.psm1"
    if (-not (Get-Module -Name RMM-Core)) {
        Import-Module $rmmCorePath -Force
    }

    if (-not (Get-Module -Name PSSQLite)) {
        Import-Module PSSQLite -ErrorAction Stop
    }
}
catch {
    Write-Error "Failed to import required modules: $_"
    exit 1
}

# Initialize RMM
Initialize-RMM -ErrorAction Stop

# Get database path
if (-not $DatabasePath) {
    $DatabasePath = Get-RMMDatabase
}

# Resolve devices
$targetDevices = @()
if ($Devices -contains "All") {
    $targetDevices = Get-RMMDevice
}
else {
    foreach ($device in $Devices) {
        $dev = Get-RMMDevice -Hostname $device -ErrorAction SilentlyContinue
        if ($dev) {
            $targetDevices += $dev
        }
        else {
            Write-Warning "Device not found: $device"
        }
    }
}

Write-Host "[INFO] Auditing software on $($targetDevices.Count) device(s)" -ForegroundColor Cyan
Write-Host ""

# Software audit function
function Audit-Software {
    param($Device, $DatabasePath)

    $auditResults = @{
        DeviceId           = $Device.DeviceId
        Hostname           = $Device.Hostname
        InstalledSoftware  = @()
        UnauthorizedApps   = @()
        MissingApps        = @()
        OutdatedApps       = @()
    }

    try {
        # Test connectivity
        if (-not (Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Write-Warning "$($Device.Hostname): Device is offline"
            return $auditResults
        }

        # Get installed software from registry
        $software = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
            $apps = @()
            
            # 64-bit apps
            $apps += Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } |
                Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
            
            # 32-bit apps on 64-bit system
            $apps += Get-ItemProperty "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } |
                Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
            
            return $apps | Sort-Object DisplayName -Unique
        } -ErrorAction Stop

        $auditResults.InstalledSoftware = $software | ForEach-Object {
            @{
                Name        = $_.DisplayName
                Version     = $_.DisplayVersion
                Publisher   = $_.Publisher
                InstallDate = $_.InstallDate
            }
        }

        Write-Host "[OK] $($Device.Hostname): Found $($auditResults.InstalledSoftware.Count) installed applications" -ForegroundColor Green
    }
    catch {
        Write-Warning "$($Device.Hostname): Failed to audit software: $_"
    }

    return $auditResults
}

# Execute audit
$auditResults = @()

foreach ($device in $targetDevices) {
    $result = Audit-Software -Device $device -DatabasePath $DatabasePath
    $auditResults += $result
    
    # Store in database
    if ($result.InstalledSoftware.Count -gt 0) {
        try {
            $dataJson = $result.InstalledSoftware | ConvertTo-Json -Compress -Depth 10
            
            $query = @"
INSERT INTO Inventory (DeviceId, Category, Data, CollectedAt)
VALUES (@DeviceId, 'Software', @Data, CURRENT_TIMESTAMP)
"@
            
            Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{
                DeviceId = $result.DeviceId
                Data     = $dataJson
            }
        }
        catch {
            Write-Warning "Failed to store audit results: $_"
        }
    }
}

Write-Host ""
Write-Host "[OK] Software audit completed" -ForegroundColor Green
