<#
.SYNOPSIS
    Comprehensive device health assessment and scoring.

.DESCRIPTION
    Calculates a 0-100 health score based on weighted factors:
    - Availability: 25 points (Is device reachable?)
    - Performance: 25 points (CPU/Memory/Disk within thresholds?)
    - Security: 25 points (AV current, firewall on, updates installed?)
    - Compliance: 25 points (Matches policy requirements?)

.PARAMETER Devices
    Array of device hostnames, a group name, or "All" to monitor all devices.

.PARAMETER DatabasePath
    Path to the RMM database. If not specified, uses the default from RMM-Core.

.EXAMPLE
    .\Health-Monitor.ps1 -Devices "localhost"

.EXAMPLE
    .\Health-Monitor.ps1 -Devices "All"

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
    [string]$DatabasePath
)

# Import required modules
$ErrorActionPreference = 'Stop'

try {
    $rmmCorePath = Join-Path $PSScriptRoot "..\core\RMM-Core.psm1"
    if (-not (Get-Module -Name RMM-Core)) {
        Import-Module $rmmCorePath -Force
    }

    # Import logging module
    $loggingPath = Join-Path $PSScriptRoot "..\core\Logging.ps1"
    . $loggingPath

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

# Initialize logging for this monitor
Initialize-RMMLogging -ScriptName "Health-Monitor" -ScriptVersion "2.0"
Write-RMMLog "Health Monitor started" -Level INFO -Component "Health-Monitor"

# Get database path
if (-not $DatabasePath) {
    $DatabasePath = Get-RMMDatabase
}

# Load thresholds
$thresholdsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "..\config\thresholds.json"
$thresholds = Get-Content $thresholdsPath -Raw | ConvertFrom-Json

# Resolve devices
$targetDevices = @()
if ($Devices -contains "All") {
    $targetDevices = Get-RMMDevice
    Write-RMMLog "Monitoring all devices ($($targetDevices.Count) total)" -Level INFO -Component "Health-Monitor"
}
else {
    foreach ($device in $Devices) {
        $dev = Get-RMMDevice -Hostname $device -ErrorAction SilentlyContinue
        if ($dev) {
            $targetDevices += $dev
        }
        else {
            Write-Warning "Device not found: $device"
            Write-RMMLog "Device not found: $device" -Level WARNING -Component "Health-Monitor"
        }
    }
    Write-RMMLog "Monitoring $($targetDevices.Count) device(s): $($Devices -join ', ')" -Level INFO -Component "Health-Monitor"
}

Write-Host "[INFO] Assessing health of $($targetDevices.Count) device(s)" -ForegroundColor Cyan
Write-Host ""

# Helper function to check if hostname is localhost
function Test-IsLocalhost {
    param([string]$Hostname)
    $localNames = @('localhost', '127.0.0.1', $env:COMPUTERNAME, "$env:COMPUTERNAME.$env:USERDNSDOMAIN")
    return ($Hostname -in $localNames) -or ($Hostname -eq [System.Net.Dns]::GetHostName())
}

# Health assessment function
function Assess-Health {
    param($Device, $Thresholds, $DatabasePath)

    $healthData = @{
        DeviceId      = $Device.DeviceId
        Hostname      = $Device.Hostname
        HealthScore   = 0
        Status        = 'Unknown'
        Availability  = 0
        Performance   = 0
        Security      = 0
        Compliance    = 0
        Issues        = @()
    }

    # Determine if this is the local machine
    $isLocal = Test-IsLocalhost -Hostname $Device.Hostname

    # Availability Check (25 points)
    try {
        if ($isLocal) {
            # Local machine is always available
            $healthData.Availability = 25
        }
        else {
            $online = Test-Connection -ComputerName $Device.Hostname -Count 2 -Quiet -ErrorAction SilentlyContinue
            if ($online) {
                $healthData.Availability = 25
            }
            else {
                $healthData.Issues += "Device is offline or unreachable"
                $healthData.Status = 'Offline'
                return $healthData
            }
        }
    }
    catch {
        $healthData.Issues += "Availability check failed"
        $healthData.Status = 'Unknown'
        return $healthData
    }

    # Performance Check (25 points)
    try {
        $perfScore = 0

        # CPU check - use local commands for localhost, remote for others
        if ($isLocal) {
            $cpu = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -ErrorAction Stop |
                Where-Object { $_.Name -eq "_Total" }
        }
        else {
            $cpu = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -ComputerName $Device.Hostname -ErrorAction Stop |
                Where-Object { $_.Name -eq "_Total" }
        }

        # Use correct threshold path: $Thresholds.CPU.Warning (not performance.cpu.warning)
        $cpuWarning = if ($Thresholds.CPU.Warning) { $Thresholds.CPU.Warning } else { 80 }
        $cpuCritical = if ($Thresholds.CPU.Critical) { $Thresholds.CPU.Critical } else { 95 }

        if ($cpu.PercentProcessorTime -lt $cpuWarning) {
            $perfScore += 8
        }
        elseif ($cpu.PercentProcessorTime -lt $cpuCritical) {
            $perfScore += 4
            $healthData.Issues += "CPU usage is elevated ($([math]::Round($cpu.PercentProcessorTime, 1))%)"
        }
        else {
            $healthData.Issues += "CPU usage is critical ($([math]::Round($cpu.PercentProcessorTime, 1))%)"
        }

        # Memory check
        if ($isLocal) {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        }
        else {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Device.Hostname -ErrorAction Stop
        }
        $memUsage = (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100

        # Use correct threshold path: $Thresholds.Memory.Warning (not performance.memory.warning)
        $memWarning = if ($Thresholds.Memory.Warning) { $Thresholds.Memory.Warning } else { 85 }
        $memCritical = if ($Thresholds.Memory.Critical) { $Thresholds.Memory.Critical } else { 95 }

        if ($memUsage -lt $memWarning) {
            $perfScore += 8
        }
        elseif ($memUsage -lt $memCritical) {
            $perfScore += 4
            $healthData.Issues += "Memory usage is elevated ($([math]::Round($memUsage, 1))%)"
        }
        else {
            $healthData.Issues += "Memory usage is critical ($([math]::Round($memUsage, 1))%)"
        }

        # Disk check
        if ($isLocal) {
            $disks = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop |
                Where-Object { $_.DriveType -eq 3 }
        }
        else {
            $disks = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $Device.Hostname -ErrorAction Stop |
                Where-Object { $_.DriveType -eq 3 }
        }

        # Use correct threshold path: $Thresholds.Disk (not performance.diskSpace)
        $diskWarning = if ($Thresholds.Disk.Warning) { $Thresholds.Disk.Warning } else { 80 }
        $diskCritical = if ($Thresholds.Disk.Critical) { $Thresholds.Disk.Critical } else { 90 }

        $diskIssues = 0
        foreach ($disk in $disks) {
            $usedPercent = 100 - (($disk.FreeSpace / $disk.Size) * 100)
            if ($usedPercent -gt $diskCritical) {
                $healthData.Issues += "Disk $($disk.DeviceID) space is critical ($([math]::Round($usedPercent, 1))% used)"
                $diskIssues++
            }
            elseif ($usedPercent -gt $diskWarning) {
                $healthData.Issues += "Disk $($disk.DeviceID) space is low ($([math]::Round($usedPercent, 1))% used)"
                $diskIssues++
            }
        }

        if ($diskIssues -eq 0) { $perfScore += 9 }
        elseif ($diskIssues -le 1) { $perfScore += 4 }

        $healthData.Performance = $perfScore
    }
    catch {
        $healthData.Issues += "Performance check failed: $_"
    }

    # Security Check (25 points)
    try {
        $secScore = 0
        $avFound = $false
        $avName = ""

        # First check Windows Security Center for ANY antivirus (including third-party like Avira, Norton, etc.)
        if ($isLocal) {
            $avProducts = Get-CimInstance -Namespace "root/SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
        }
        else {
            $avProducts = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                Get-CimInstance -Namespace "root/SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
            } -ErrorAction SilentlyContinue
        }

        if ($avProducts) {
            foreach ($av in $avProducts) {
                # productState is a bitmask: bits 4-7 indicate if AV is enabled, bits 16-23 indicate if definitions are up to date
                # Common enabled states: 266240 (enabled, up to date), 262144 (enabled, out of date), 393472 (enabled)
                $state = $av.productState
                $enabled = ($state -band 0x1000) -ne 0  # Bit 12 indicates enabled
                # Alternative check: states 266240, 262144, 393472, 397568 typically indicate enabled AV
                $knownEnabledStates = @(266240, 262144, 393472, 397568, 397584, 393488)

                if ($enabled -or ($state -in $knownEnabledStates) -or ($state -gt 0)) {
                    $avFound = $true
                    $avName = $av.displayName
                    # DEBUG logging removed - use INFO for important detections only
                    break
                }
            }
        }

        # Fallback: Check Windows Defender specifically
        if (-not $avFound) {
            if ($isLocal) {
                $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
            }
            else {
                $defender = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    Get-MpComputerStatus -ErrorAction SilentlyContinue
                } -ErrorAction SilentlyContinue
            }

            if ($defender -and $defender.AntivirusEnabled) {
                $avFound = $true
                $avName = "Windows Defender"
            }
        }

        if ($avFound) {
            $secScore += 8
            # Check definition age for Windows Defender only (third-party AV doesn't expose this easily)
            if ($defender -and $defender.AntivirusSignatureAge -le 7) {
                $secScore += 5
            }
            elseif ($defender -and $defender.AntivirusSignatureAge -gt 7) {
                $healthData.Issues += "Antivirus definitions are outdated ($avName)"
            }
            else {
                # Third-party AV detected, assume definitions are OK (can't easily check)
                $secScore += 5
            }
            # Antivirus detection successful - no logging needed for normal operation
        }
        else {
            $healthData.Issues += "Antivirus is not enabled"
        }

        # Firewall
        if ($isLocal) {
            $firewall = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        }
        else {
            $firewall = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                Get-NetFirewallProfile -ErrorAction SilentlyContinue
            } -ErrorAction SilentlyContinue
        }

        if ($firewall) {
            $allEnabled = ($firewall | Where-Object { $_.Enabled -eq $false }).Count -eq 0
            if ($allEnabled) {
                $secScore += 7
            }
            else {
                $healthData.Issues += "Firewall is not fully enabled"
            }
        }

        # Windows Updates
        if ($isLocal) {
            try {
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                $updates = $searcher.Search("IsInstalled=0").Updates.Count
            }
            catch {
                $updates = -1
            }
        }
        else {
            $updates = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                try {
                    $session = New-Object -ComObject Microsoft.Update.Session
                    $searcher = $session.CreateUpdateSearcher()
                    $searcher.Search("IsInstalled=0").Updates.Count
                }
                catch {
                    return -1
                }
            } -ErrorAction SilentlyContinue
        }

        if ($updates -eq 0) {
            $secScore += 5
        }
        elseif ($updates -gt 0 -and $updates -le 5) {
            $secScore += 2
            $healthData.Issues += "$updates pending Windows updates"
        }
        elseif ($updates -gt 5) {
            $healthData.Issues += "Many pending Windows updates"
        }

        $healthData.Security = $secScore
    }
    catch {
        $healthData.Issues += "Security check failed: $_"
    }

    # Compliance Check (25 points) - Simplified for now
    try {
        # For now, give full compliance score if device is online and responding
        # In a full implementation, this would check against policy requirements
        $healthData.Compliance = 20
    }
    catch {
        $healthData.Issues += "Compliance check failed: $_"
    }

    # Calculate total health score
    $healthData.HealthScore = $healthData.Availability + $healthData.Performance + $healthData.Security + $healthData.Compliance

    # Determine status
    if ($healthData.HealthScore -ge 80) {
        $healthData.Status = 'Healthy'
    }
    elseif ($healthData.HealthScore -ge 60) {
        $healthData.Status = 'Warning'
    }
    else {
        $healthData.Status = 'Critical'
    }

    return $healthData
}

# Alert management functions (inline to avoid circular imports)
function New-HealthAlert {
    param($DeviceId, $AlertType, $Severity, $Title, $Message, $Source, $AutoResolve, $DbPath)

    # Check for duplicate alerts (same type + device + title that is unresolved)
    $duplicateCheck = @"
SELECT AlertId, CreatedAt FROM Alerts
WHERE DeviceId = @DeviceId
  AND AlertType = @AlertType
  AND Title = @Title
  AND ResolvedAt IS NULL
ORDER BY CreatedAt DESC
LIMIT 1
"@
    $duplicateParams = @{
        DeviceId  = $DeviceId
        AlertType = $AlertType
        Title     = $Title
    }
    $duplicate = Invoke-SqliteQuery -DataSource $DbPath -Query $duplicateCheck -SqlParameters $duplicateParams

    if ($duplicate) {
        Write-Host "[DEDUPLICATED] Alert already exists for: $Title" -ForegroundColor Yellow
        return $duplicate.AlertId
    }

    # Create new alert
    $alertId = [guid]::NewGuid().ToString()
    $query = @"
INSERT INTO Alerts (AlertId, DeviceId, AlertType, Severity, Title, Message, Source, AutoResolved, CreatedAt)
VALUES (@AlertId, @DeviceId, @AlertType, @Severity, @Title, @Message, @Source, @AutoResolved, CURRENT_TIMESTAMP)
"@
    $params = @{
        AlertId      = $alertId
        DeviceId     = $DeviceId
        AlertType    = $AlertType
        Severity     = $Severity
        Title        = $Title
        Message      = $Message
        Source       = $Source
        AutoResolved = if ($AutoResolve) { 1 } else { 0 }
    }

    Invoke-SqliteQuery -DataSource $DbPath -Query $query -SqlParameters $params
    Write-Host "[ALERT CREATED] $alertId - $Title" -ForegroundColor Magenta
    return $alertId
}

function Resolve-HealthAlerts {
    param($DeviceId, $DbPath)

    # Find all unresolved alerts for this device that were created by Health-Monitor
    $query = @"
SELECT AlertId, Title FROM Alerts
WHERE DeviceId = @DeviceId
  AND ResolvedAt IS NULL
  AND Source = 'Health-Monitor'
"@
    $unresolvedAlerts = Invoke-SqliteQuery -DataSource $DbPath -Query $query -SqlParameters @{ DeviceId = $DeviceId }

    if ($unresolvedAlerts) {
        foreach ($alert in $unresolvedAlerts) {
            $resolveQuery = @"
UPDATE Alerts
SET ResolvedAt = CURRENT_TIMESTAMP,
    ResolvedBy = 'Health-Monitor',
    AutoResolved = 1
WHERE AlertId = @AlertId
"@
            Invoke-SqliteQuery -DataSource $DbPath -Query $resolveQuery -SqlParameters @{ AlertId = $alert.AlertId }
            Write-Host "[AUTO-RESOLVED] $($alert.AlertId) - $($alert.Title)" -ForegroundColor Green
        }
    }
}

function Resolve-ClearedAlerts {
    param($DeviceId, $CurrentIssues, $Hostname, $DbPath)

    # Find all unresolved alerts for this device that were created by Health-Monitor
    $query = @"
SELECT AlertId, Title FROM Alerts
WHERE DeviceId = @DeviceId
  AND ResolvedAt IS NULL
  AND Source = 'Health-Monitor'
"@
    $unresolvedAlerts = Invoke-SqliteQuery -DataSource $DbPath -Query $query -SqlParameters @{ DeviceId = $DeviceId }

    if ($unresolvedAlerts) {
        # Build list of current issue titles (with hostname prefix as stored in alerts)
        $currentIssueTitles = @()
        foreach ($issue in $CurrentIssues) {
            $currentIssueTitles += "$($Hostname): $issue"
        }

        foreach ($alert in $unresolvedAlerts) {
            # Check if this alert's issue is still in the current issues list
            $stillExists = $false
            foreach ($title in $currentIssueTitles) {
                if ($alert.Title -eq $title) {
                    $stillExists = $true
                    break
                }
            }

            # If the issue is no longer detected, auto-resolve the alert
            if (-not $stillExists) {
                $resolveQuery = @"
UPDATE Alerts
SET ResolvedAt = CURRENT_TIMESTAMP,
    ResolvedBy = 'Health-Monitor',
    AutoResolved = 1
WHERE AlertId = @AlertId
"@
                Invoke-SqliteQuery -DataSource $DbPath -Query $resolveQuery -SqlParameters @{ AlertId = $alert.AlertId }
                Write-Host "[AUTO-RESOLVED] $($alert.AlertId) - $($alert.Title) (issue cleared)" -ForegroundColor Green
            }
        }
    }
}

# Execute health assessment
$healthResults = @()

foreach ($device in $targetDevices) {
    $result = Assess-Health -Device $device -Thresholds $thresholds -DatabasePath $DatabasePath
    $healthResults += $result

    # Display result
    $color = switch ($result.Status) {
        'Healthy' { 'Green' }
        'Warning' { 'Yellow' }
        'Critical' { 'Red' }
        'Offline' { 'Gray' }
        default { 'White' }
    }

    Write-Host "[$($result.Status.ToUpper())] $($result.Hostname): Health Score = $($result.HealthScore)/100" -ForegroundColor $color
    if ($result.Issues.Count -gt 0) {
        foreach ($issue in $result.Issues) {
            Write-Host "  - $issue" -ForegroundColor Gray
        }
    }

    # Log the health assessment result
    $logLevel = switch ($result.Status) {
        'Healthy' { 'SUCCESS' }
        'Warning' { 'WARNING' }
        'Critical' { 'ERROR' }
        'Offline' { 'WARNING' }
        default { 'INFO' }
    }
    $issuesSummary = if ($result.Issues.Count -gt 0) { " Issues: $($result.Issues -join '; ')" } else { "" }
    Write-RMMLog "$($result.Hostname): Health Score = $($result.HealthScore)/100 ($($result.Status))$issuesSummary" -Level $logLevel -Component "Health-Monitor"

    # Write device-specific log
    if ($result.DeviceId) {
        Write-RMMDeviceLog -DeviceId $result.DeviceId -Message "Health check: Score $($result.HealthScore)/100 - $($result.Status)" -Level $logLevel
    }

    # Create alerts for each issue detected (regardless of overall device status)
    # This ensures individual issues like high RAM or low disk space always create alerts
    if ($result.DeviceId -and $result.Issues.Count -gt 0) {
        foreach ($issue in $result.Issues) {
            # Determine alert type based on issue content
            $alertType = 'Health'
            if ($issue -match 'CPU|Memory|Disk|performance') { $alertType = 'Performance' }
            elseif ($issue -match 'antivirus|firewall|security|defender') { $alertType = 'Security' }
            elseif ($issue -match 'offline|unreachable|availability') { $alertType = 'Availability' }
            elseif ($issue -match 'update|patch|Windows Update') { $alertType = 'Update' }
            elseif ($issue -match 'compliance|policy') { $alertType = 'Compliance' }

            # Determine severity based on issue content (critical vs warning keywords)
            $alertSeverity = 'Medium'  # Default for warning-level issues
            if ($issue -match 'critical') {
                $alertSeverity = 'Critical'
            }
            elseif ($issue -match 'elevated|low|outdated|pending') {
                $alertSeverity = 'Medium'
            }

            New-HealthAlert -DeviceId $result.DeviceId `
                -AlertType $alertType `
                -Severity $alertSeverity `
                -Title "$($result.Hostname): $issue" `
                -Message "Health Score: $($result.HealthScore)/100. Issue detected during health assessment." `
                -Source 'Health-Monitor' `
                -AutoResolve $true `
                -DbPath $DatabasePath
        }
    }

    # Auto-resolve alerts when specific issues are no longer detected
    # We need to resolve alerts for issues that are no longer in the Issues list
    if ($result.DeviceId) {
        Resolve-ClearedAlerts -DeviceId $result.DeviceId -CurrentIssues $result.Issues -Hostname $result.Hostname -DbPath $DatabasePath
    }

    # Update device status in database
    try {
        $query = "UPDATE Devices SET Status = @Status, LastSeen = CURRENT_TIMESTAMP WHERE DeviceId = @DeviceId"
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{
            DeviceId = $result.DeviceId
            Status   = $result.Status
        }
    }
    catch {
        Write-Warning "Failed to update device status: $_"
        Write-RMMLog "Failed to update device status for $($result.Hostname): $_" -Level ERROR -Component "Health-Monitor"
    }
}

# Summary calculations (with null checks - handle hashtables)
$healthScores = @()
$healthyCount = 0
$warningCount = 0
$criticalCount = 0
$offlineCount = 0

foreach ($r in $healthResults) {
    if ($null -ne $r -and $null -ne $r.HealthScore -and $r.HealthScore -gt 0) {
        $healthScores += $r.HealthScore
    }
    if ($null -ne $r -and $null -ne $r.Status) {
        switch ($r.Status) {
            'Healthy' { $healthyCount++ }
            'Warning' { $warningCount++ }
            'Critical' { $criticalCount++ }
            'Offline' { $offlineCount++ }
        }
    }
}

$avgScore = if ($healthScores.Count -gt 0) {
    ($healthScores | Measure-Object -Average).Average
} else { 0 }

# Display summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Health Assessment Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Average Health Score: $([math]::Round($avgScore, 2))/100" -ForegroundColor White
Write-Host "Healthy: $healthyCount" -ForegroundColor Green
Write-Host "Warning: $warningCount" -ForegroundColor Yellow
Write-Host "Critical: $criticalCount" -ForegroundColor Red
Write-Host "Offline: $offlineCount" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan

# Log summary
Write-RMMLog "Health assessment complete. Average: $([math]::Round($avgScore, 2))/100, Healthy: $healthyCount, Warning: $warningCount, Critical: $criticalCount, Offline: $offlineCount" -Level INFO -Component "Health-Monitor"

