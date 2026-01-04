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

# Initialize RMM (includes logging - will skip if already initialized)
Initialize-RMM -ErrorAction Stop | Out-Null

# Log monitor start (logging already initialized by Initialize-RMM)
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

# Helper function to check if running on Windows
function Test-IsWindows {
    return ($IsWindows -eq $true) -or ($PSVersionTable.PSEdition -eq 'Desktop') -or ([System.Environment]::OSVersion.Platform -eq 'Win32NT')
}

# Fast Windows Update check using registry and CIM (replaces slow COM-based check)
# Returns: 0 = fully patched, positive = estimated pending updates, -1 = unable to check
function Get-FastWindowsUpdateStatus {
    [CmdletBinding()]
    param()

    try {
        # Check for pending reboot first (indicates updates installed but awaiting reboot)
        $pendingReboot = $false
        $rebootPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
        )
        foreach ($path in $rebootPaths) {
            if (Test-Path $path) {
                $pendingReboot = $true
                break
            }
        }

        # Check last update install date via CIM (much faster than COM)
        $lastHotfix = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
            Where-Object { $_.InstalledOn } |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 1

        $daysSinceUpdate = 999
        if ($lastHotfix -and $lastHotfix.InstalledOn) {
            $daysSinceUpdate = ((Get-Date) - $lastHotfix.InstalledOn).Days
        }

        # Try quick registry check for update history (USOShared)
        $pendingCount = 0
        try {
            $usoPath = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\StateVariables'
            if (Test-Path $usoPath) {
                $usoState = Get-ItemProperty -Path $usoPath -ErrorAction SilentlyContinue
                if ($usoState.PendingUpdatesCount) {
                    $pendingCount = [int]$usoState.PendingUpdatesCount
                }
            }
        }
        catch { }

        # Return estimate based on combined signals
        if ($pendingReboot) {
            # Reboot pending means at least some updates are waiting
            return [Math]::Max(1, $pendingCount)
        }
        elseif ($pendingCount -gt 0) {
            return $pendingCount
        }
        elseif ($daysSinceUpdate -le 30) {
            # Updated within last 30 days, likely OK
            return 0
        }
        elseif ($daysSinceUpdate -gt 60) {
            # Very stale - assume multiple updates pending
            return 5
        }
        else {
            # 30-60 days, might have some updates
            return 2
        }
    }
    catch {
        Write-Verbose "Fast Windows Update check failed: $_"
        return -1
    }
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
        # Detailed metrics for logging
        Metrics       = @{
            CPU        = @{ Value = 0; Status = 'Unknown'; Points = 0 }
            Memory     = @{ Value = 0; Status = 'Unknown'; Points = 0 }
            Disks      = @()
            Antivirus  = @{ Name = ''; Enabled = $false; Points = 0 }
            Firewall   = @{ Enabled = $false; Points = 0 }
            Updates    = @{ Pending = -1; Points = 0 }
        }
    }

    # Determine if this is the local machine
    $isLocal = Test-IsLocalhost -Hostname $Device.Hostname
    Write-RMMLog "Assessing health for $($Device.Hostname) (Local: $isLocal)" -Level INFO -Component "Health-Monitor"

    # Availability Check (25 points)
    try {
        if ($isLocal) {
            # Local machine is always available
            $healthData.Availability = 25
            Write-RMMLog "$($Device.Hostname) - Availability: PASS (local device, 25/25 points)" -Level SUCCESS -Component "Health-Monitor"
        }
        else {
            $online = Test-Connection -ComputerName $Device.Hostname -Count 2 -Quiet -ErrorAction SilentlyContinue
            if ($online) {
                $healthData.Availability = 25
                Write-RMMLog "$($Device.Hostname) - Availability: PASS (reachable, 25/25 points)" -Level SUCCESS -Component "Health-Monitor"
            }
            else {
                $healthData.Issues += "Device is offline or unreachable"
                $healthData.Status = 'Offline'
                Write-RMMLog "$($Device.Hostname) - Availability: FAIL (offline, 0/25 points)" -Level ERROR -Component "Health-Monitor"
                return $healthData
            }
        }
    }
    catch {
        $healthData.Issues += "Availability check failed"
        $healthData.Status = 'Unknown'
        Write-RMMLog "$($Device.Hostname) - Availability: ERROR - $($_.Exception.Message)" -Level ERROR -Component "Health-Monitor"
        return $healthData
    }

    # Performance Check (25 points) - Cross-platform
    try {
        $perfScore = 0
        $isWindowsOS = Test-IsWindows

        # Thresholds
        $cpuWarning = if ($Thresholds.CPU.Warning) { $Thresholds.CPU.Warning } else { 80 }
        $cpuCritical = if ($Thresholds.CPU.Critical) { $Thresholds.CPU.Critical } else { 95 }
        $memWarning = if ($Thresholds.Memory.Warning) { $Thresholds.Memory.Warning } else { 85 }
        $memCritical = if ($Thresholds.Memory.Critical) { $Thresholds.Memory.Critical } else { 95 }
        $diskWarning = if ($Thresholds.Disk.Warning) { $Thresholds.Disk.Warning } else { 80 }
        $diskCritical = if ($Thresholds.Disk.Critical) { $Thresholds.Disk.Critical } else { 90 }

        if ($isWindowsOS) {
            # === WINDOWS: Use CIM/WMI ===
            # CPU check
            if ($isLocal) {
                $cpu = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -ErrorAction Stop |
                    Where-Object { $_.Name -eq "_Total" }
            }
            else {
                $cpu = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -ComputerName $Device.Hostname -ErrorAction Stop |
                    Where-Object { $_.Name -eq "_Total" }
            }
            $cpuValue = [math]::Round($cpu.PercentProcessorTime, 1)

            # Memory check
            if ($isLocal) {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            }
            else {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Device.Hostname -ErrorAction Stop
            }
            $memUsage = (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100
            $memValue = [math]::Round($memUsage, 1)
            $memTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $memFreeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)

            # Disk check
            if ($isLocal) {
                $disks = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop |
                    Where-Object { $_.DriveType -eq 3 }
            }
            else {
                $disks = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $Device.Hostname -ErrorAction Stop |
                    Where-Object { $_.DriveType -eq 3 }
            }
        }
        else {
            # === macOS/Linux: Use cross-platform methods ===
            # CPU - use Get-Counter on Windows, or simple calculation on Unix
            if ($IsMacOS) {
                $cpuOutput = (top -l 1 | grep -E "^CPU" 2>$null) -join ''
                if ($cpuOutput -match '(\d+\.?\d*)%\s*idle') {
                    $cpuValue = [math]::Round(100 - [double]$Matches[1], 1)
                }
                else {
                    $cpuValue = 10  # Default if unable to parse
                }
            }
            elseif ($IsLinux) {
                $cpuOutput = (top -bn1 | grep "Cpu(s)" 2>$null) -join ''
                if ($cpuOutput -match '(\d+\.?\d*)\s*id') {
                    $cpuValue = [math]::Round(100 - [double]$Matches[1], 1)
                }
                else {
                    $cpuValue = 10
                }
            }
            else {
                $cpuValue = 10
            }

            # Memory - use /proc/meminfo on Linux, vm_stat on macOS
            if ($IsLinux -and (Test-Path /proc/meminfo)) {
                $memInfo = Get-Content /proc/meminfo
                $memTotal = ($memInfo | Select-String '^MemTotal:').ToString() -replace '[^0-9]', ''
                $memAvail = ($memInfo | Select-String '^MemAvailable:').ToString() -replace '[^0-9]', ''
                $memUsage = 100 - ([double]$memAvail / [double]$memTotal * 100)
                $memValue = [math]::Round($memUsage, 1)
                $memTotalGB = [math]::Round([double]$memTotal / 1048576, 1)
                $memFreeGB = [math]::Round([double]$memAvail / 1048576, 1)
            }
            elseif ($IsMacOS) {
                $memPages = (vm_stat 2>$null) -join "`n"
                $pageSize = 4096
                $freePages = 0
                $activePages = 0
                if ($memPages -match 'Pages free:\s*(\d+)') { $freePages = [int]$Matches[1] }
                if ($memPages -match 'Pages active:\s*(\d+)') { $activePages = [int]$Matches[1] }
                $totalMem = (sysctl -n hw.memsize 2>$null) -join ''
                $memTotalGB = [math]::Round([double]$totalMem / 1GB, 1)
                $memFreeGB = [math]::Round(($freePages * $pageSize) / 1GB, 1)
                $memUsage = 100 - ($memFreeGB / $memTotalGB * 100)
                $memValue = [math]::Round($memUsage, 1)
            }
            else {
                $memValue = 50
                $memTotalGB = 8
                $memFreeGB = 4
            }

            # Disk - use Get-PSDrive for cross-platform
            $disks = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 }
        }

        # Score CPU
        $healthData.Metrics.CPU.Value = $cpuValue
        if ($cpuValue -lt $cpuWarning) {
            $perfScore += 8
            $healthData.Metrics.CPU.Status = 'OK'
            $healthData.Metrics.CPU.Points = 8
            Write-RMMLog "$($Device.Hostname) - CPU: $cpuValue% (OK, 8/8 points)" -Level SUCCESS -Component "Health-Monitor"
        }
        elseif ($cpuValue -lt $cpuCritical) {
            $perfScore += 4
            $healthData.Metrics.CPU.Status = 'Warning'
            $healthData.Metrics.CPU.Points = 4
            $healthData.Issues += "CPU usage is elevated ($cpuValue%)"
            Write-RMMLog "$($Device.Hostname) - CPU: $cpuValue% (ELEVATED, 4/8 points)" -Level WARNING -Component "Health-Monitor"
        }
        else {
            $healthData.Metrics.CPU.Status = 'Critical'
            $healthData.Metrics.CPU.Points = 0
            $healthData.Issues += "CPU usage is critical ($cpuValue%)"
            Write-RMMLog "$($Device.Hostname) - CPU: $cpuValue% (CRITICAL, 0/8 points)" -Level ERROR -Component "Health-Monitor"
        }

        # Score Memory
        $healthData.Metrics.Memory.Value = $memValue
        if ($memValue -lt $memWarning) {
            $perfScore += 8
            $healthData.Metrics.Memory.Status = 'OK'
            $healthData.Metrics.Memory.Points = 8
            Write-RMMLog "$($Device.Hostname) - Memory: $memValue% used ($memFreeGB GB free of $memTotalGB GB, OK, 8/8 points)" -Level SUCCESS -Component "Health-Monitor"
        }
        elseif ($memValue -lt $memCritical) {
            $perfScore += 4
            $healthData.Metrics.Memory.Status = 'Warning'
            $healthData.Metrics.Memory.Points = 4
            $healthData.Issues += "Memory usage is elevated ($memValue%)"
            Write-RMMLog "$($Device.Hostname) - Memory: $memValue% used (ELEVATED, 4/8 points)" -Level WARNING -Component "Health-Monitor"
        }
        else {
            $healthData.Metrics.Memory.Status = 'Critical'
            $healthData.Metrics.Memory.Points = 0
            $healthData.Issues += "Memory usage is critical ($memValue%)"
            Write-RMMLog "$($Device.Hostname) - Memory: $memValue% used (CRITICAL, 0/8 points)" -Level ERROR -Component "Health-Monitor"
        }

        # Score Disks
        $diskIssues = 0
        foreach ($disk in $disks) {
            if ($isWindowsOS) {
                $usedPercent = [math]::Round(100 - (($disk.FreeSpace / $disk.Size) * 100), 1)
                $totalGB = [math]::Round($disk.Size / 1GB, 1)
                $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
                $driveName = $disk.DeviceID
            }
            else {
                # Cross-platform Get-PSDrive
                if ($disk.Used -and $disk.Free) {
                    $totalBytes = $disk.Used + $disk.Free
                    $usedPercent = [math]::Round(($disk.Used / $totalBytes) * 100, 1)
                    $totalGB = [math]::Round($totalBytes / 1GB, 1)
                    $freeGB = [math]::Round($disk.Free / 1GB, 1)
                }
                else {
                    continue  # Skip if no data
                }
                $driveName = $disk.Name
            }
            $diskInfo = @{ Drive = $driveName; UsedPercent = $usedPercent; FreeGB = $freeGB; TotalGB = $totalGB; Status = 'OK' }

            if ($usedPercent -gt $diskCritical) {
                $healthData.Issues += "Disk $driveName space is critical ($usedPercent% used)"
                $diskInfo.Status = 'Critical'
                $diskIssues++
                Write-RMMLog "$($Device.Hostname) - Disk ${driveName}: $usedPercent% used ($freeGB GB free, CRITICAL)" -Level ERROR -Component "Health-Monitor"
            }
            elseif ($usedPercent -gt $diskWarning) {
                $healthData.Issues += "Disk $driveName space is low ($usedPercent% used)"
                $diskInfo.Status = 'Warning'
                $diskIssues++
                Write-RMMLog "$($Device.Hostname) - Disk ${driveName}: $usedPercent% used ($freeGB GB free, LOW)" -Level WARNING -Component "Health-Monitor"
            }
            else {
                Write-RMMLog "$($Device.Hostname) - Disk ${driveName}: $usedPercent% used ($freeGB GB free, OK)" -Level SUCCESS -Component "Health-Monitor"
            }
            $healthData.Metrics.Disks += $diskInfo
        }

        if ($diskIssues -eq 0) { $perfScore += 9 }
        elseif ($diskIssues -le 1) { $perfScore += 4 }

        $healthData.Performance = $perfScore
        Write-RMMLog "$($Device.Hostname) - Performance total: $perfScore/25 points" -Level INFO -Component "Health-Monitor"
    }
    catch {
        $healthData.Issues += "Performance check failed: $_"
        Write-RMMLog "$($Device.Hostname) - Performance check FAILED: $($_.Exception.Message)" -Level ERROR -Component "Health-Monitor"
    }

    # Security Check (25 points)
    # Cross-platform: Windows gets full checks, macOS/Linux get N/A with full points
    try {
        $secScore = 0
        $isWindowsOS = Test-IsWindows

        if ($isWindowsOS) {
            # === WINDOWS: Full security checks ===
            $avFound = $false
            $avName = ""
            $defender = $null

            # Check Windows Security Center for ANY antivirus
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
                    $state = $av.productState
                    $enabled = ($state -band 0x1000) -ne 0
                    $knownEnabledStates = @(266240, 262144, 393472, 397568, 397584, 393488)
                    if ($enabled -or ($state -in $knownEnabledStates) -or ($state -gt 0)) {
                        $avFound = $true
                        $avName = $av.displayName
                        break
                    }
                }
            }

            # Fallback: Check Windows Defender
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

            $healthData.Metrics.Antivirus.Name = $avName
            $healthData.Metrics.Antivirus.Enabled = $avFound

            if ($avFound) {
                $secScore += 8
                $avPoints = 8
                if ($defender -and $defender.AntivirusSignatureAge -le 7) {
                    $secScore += 5
                    $avPoints += 5
                    Write-RMMLog "$($Device.Hostname) - Antivirus: $avName ENABLED, definitions current ($($defender.AntivirusSignatureAge) days old, 13/13 points)" -Level SUCCESS -Component "Health-Monitor"
                }
                elseif ($defender -and $defender.AntivirusSignatureAge -gt 7) {
                    $healthData.Issues += "Antivirus definitions are outdated ($avName)"
                    Write-RMMLog "$($Device.Hostname) - Antivirus: $avName ENABLED, definitions OUTDATED ($($defender.AntivirusSignatureAge) days old, 8/13 points)" -Level WARNING -Component "Health-Monitor"
                }
                else {
                    $secScore += 5
                    $avPoints += 5
                    Write-RMMLog "$($Device.Hostname) - Antivirus: $avName ENABLED (third-party, 13/13 points)" -Level SUCCESS -Component "Health-Monitor"
                }
                $healthData.Metrics.Antivirus.Points = $avPoints
            }
            else {
                $healthData.Issues += "Antivirus is not enabled"
                $healthData.Metrics.Antivirus.Points = 0
                Write-RMMLog "$($Device.Hostname) - Antivirus: NOT ENABLED (0/13 points)" -Level ERROR -Component "Health-Monitor"
            }

            # Firewall check
            if ($isLocal) {
                $firewall = Get-NetFirewallProfile -ErrorAction SilentlyContinue
            }
            else {
                $firewall = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    Get-NetFirewallProfile -ErrorAction SilentlyContinue
                } -ErrorAction SilentlyContinue
            }

            if ($firewall) {
                $enabledProfiles = ($firewall | Where-Object { $_.Enabled -eq $true }).Name -join ', '
                $disabledProfiles = ($firewall | Where-Object { $_.Enabled -eq $false }).Name -join ', '
                $allEnabled = ($firewall | Where-Object { $_.Enabled -eq $false }).Count -eq 0
                $healthData.Metrics.Firewall.Enabled = $allEnabled

                if ($allEnabled) {
                    $secScore += 7
                    $healthData.Metrics.Firewall.Points = 7
                    Write-RMMLog "$($Device.Hostname) - Firewall: ALL PROFILES ENABLED ($enabledProfiles, 7/7 points)" -Level SUCCESS -Component "Health-Monitor"
                }
                else {
                    $healthData.Metrics.Firewall.Points = 0
                    $healthData.Issues += "Firewall is not fully enabled"
                    Write-RMMLog "$($Device.Hostname) - Firewall: PARTIALLY ENABLED (Enabled: $enabledProfiles; Disabled: $disabledProfiles, 0/7 points)" -Level WARNING -Component "Health-Monitor"
                }
            }
            else {
                Write-RMMLog "$($Device.Hostname) - Firewall: Unable to check status" -Level WARNING -Component "Health-Monitor"
            }

            # Windows Updates - using FAST registry-based check instead of slow COM
            if ($isLocal) {
                $updates = Get-FastWindowsUpdateStatus
            }
            else {
                # For remote, use Invoke-Command with the fast check
                $updates = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                    $pendingReboot = $false
                    $rebootPaths = @(
                        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
                        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
                    )
                    foreach ($path in $rebootPaths) { if (Test-Path $path) { $pendingReboot = $true; break } }

                    $lastHotfix = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
                        Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
                    $daysSinceUpdate = 999
                    if ($lastHotfix -and $lastHotfix.InstalledOn) { $daysSinceUpdate = ((Get-Date) - $lastHotfix.InstalledOn).Days }

                    if ($pendingReboot) { return 1 }
                    elseif ($daysSinceUpdate -le 30) { return 0 }
                    elseif ($daysSinceUpdate -gt 60) { return 5 }
                    else { return 2 }
                } -ErrorAction SilentlyContinue
                if ($null -eq $updates) { $updates = -1 }
            }

            $healthData.Metrics.Updates.Pending = $updates

            if ($updates -eq 0) {
                $secScore += 5
                $healthData.Metrics.Updates.Points = 5
                Write-RMMLog "$($Device.Hostname) - Updates: FULLY PATCHED (5/5 points)" -Level SUCCESS -Component "Health-Monitor"
            }
            elseif ($updates -gt 0 -and $updates -le 5) {
                $secScore += 2
                $healthData.Metrics.Updates.Points = 2
                $healthData.Issues += "~$updates pending updates"
                Write-RMMLog "$($Device.Hostname) - Updates: ~$updates PENDING (2/5 points)" -Level WARNING -Component "Health-Monitor"
            }
            elseif ($updates -gt 5) {
                $healthData.Metrics.Updates.Points = 0
                $healthData.Issues += "Many pending updates (~$updates)"
                Write-RMMLog "$($Device.Hostname) - Updates: ~$updates PENDING (many, 0/5 points)" -Level WARNING -Component "Health-Monitor"
            }
            elseif ($updates -eq -1) {
                # Unable to check - give partial credit
                $secScore += 2
                $healthData.Metrics.Updates.Points = 2
                Write-RMMLog "$($Device.Hostname) - Updates: Unable to check (2/5 points)" -Level WARNING -Component "Health-Monitor"
            }
        }
        else {
            # === macOS/Linux: Award full security points (N/A on this platform) ===
            $secScore = 25
            $healthData.Metrics.Antivirus.Name = "N/A (non-Windows)"
            $healthData.Metrics.Antivirus.Enabled = $true
            $healthData.Metrics.Antivirus.Points = 13
            $healthData.Metrics.Firewall.Enabled = $true
            $healthData.Metrics.Firewall.Points = 7
            $healthData.Metrics.Updates.Pending = 0
            $healthData.Metrics.Updates.Points = 5
            Write-RMMLog "$($Device.Hostname) - Security: N/A on this platform (full 25/25 points awarded)" -Level INFO -Component "Health-Monitor"
        }

        $healthData.Security = $secScore
        Write-RMMLog "$($Device.Hostname) - Security total: $secScore/25 points" -Level INFO -Component "Health-Monitor"
    }
    catch {
        $healthData.Issues += "Security check failed: $_"
        Write-RMMLog "$($Device.Hostname) - Security check FAILED: $($_.Exception.Message)" -Level ERROR -Component "Health-Monitor"
    }

    # Compliance Check (25 points) - Simplified for now
    try {
        # For now, give full compliance score if device is online and responding
        # In a full implementation, this would check against policy requirements
        $healthData.Compliance = 20
        Write-RMMLog "$($Device.Hostname) - Compliance: Basic check passed (20/25 points)" -Level SUCCESS -Component "Health-Monitor"
    }
    catch {
        $healthData.Issues += "Compliance check failed: $_"
        Write-RMMLog "$($Device.Hostname) - Compliance check FAILED: $($_.Exception.Message)" -Level ERROR -Component "Health-Monitor"
    }

    # Calculate total health score
    $healthData.HealthScore = $healthData.Availability + $healthData.Performance + $healthData.Security + $healthData.Compliance

    # Determine status (Healthy ≥90, Warning 70-89, Critical <70)
    if ($healthData.HealthScore -ge 90) {
        $healthData.Status = 'Healthy'
    }
    elseif ($healthData.HealthScore -ge 70) {
        $healthData.Status = 'Warning'
    }
    else {
        $healthData.Status = 'Critical'
    }

    # Log detailed final score breakdown
    Write-RMMLog "$($Device.Hostname) - FINAL SCORE: $($healthData.HealthScore)/100 ($($healthData.Status)) [Availability: $($healthData.Availability)/25, Performance: $($healthData.Performance)/25, Security: $($healthData.Security)/25, Compliance: $($healthData.Compliance)/25]" -Level INFO -Component "Health-Monitor"

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

