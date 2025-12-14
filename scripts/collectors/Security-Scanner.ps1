<#
.SYNOPSIS
    Security posture assessment and vulnerability scanning.

.DESCRIPTION
    Performs comprehensive security checks including Windows Update status, antivirus,
    firewall, BitLocker, user accounts, and generates a security score (0-100).

.PARAMETER Devices
    Array of device hostnames, a group name, or "All" to scan all devices.

.PARAMETER DatabasePath
    Path to the RMM database. If not specified, uses the default from RMM-Core.

.EXAMPLE
    .\Security-Scanner.ps1 -Devices "localhost"

.EXAMPLE
    .\Security-Scanner.ps1 -Devices "All"

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

Write-Host "[INFO] Scanning security on $($targetDevices.Count) device(s)" -ForegroundColor Cyan
Write-Host ""

# Security scan function
function Scan-Security {
    param($Device, $DatabasePath)

    $securityData = @{
        DeviceId       = $Device.DeviceId
        Hostname       = $Device.Hostname
        SecurityScore  = 0
        Issues         = @()
        Checks         = @{}
    }

    try {
        # Test connectivity
        if (-not (Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Write-Warning "$($Device.Hostname): Device is offline"
            return $securityData
        }

        $score = 0
        $maxScore = 100

        # Check Windows Defender (20 points)
        try {
            $defender = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                Get-MpComputerStatus -ErrorAction SilentlyContinue
            } -ErrorAction SilentlyContinue

            if ($defender) {
                $securityData.Checks.DefenderEnabled = $defender.AntivirusEnabled
                $securityData.Checks.DefenderUpdated = ($defender.AntivirusSignatureAge -le 7)
                
                if ($defender.AntivirusEnabled) { $score += 10 }
                if ($defender.AntivirusSignatureAge -le 7) { $score += 10 }
                else {
                    $securityData.Issues += "Antivirus definitions are outdated ($($defender.AntivirusSignatureAge) days old)"
                }
            }
            else {
                $securityData.Issues += "Windows Defender status unavailable"
            }
        }
        catch {
            $securityData.Issues += "Failed to check Windows Defender: $_"
        }

        # Check Firewall (20 points)
        try {
            $firewall = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                Get-NetFirewallProfile -ErrorAction SilentlyContinue
            } -ErrorAction SilentlyContinue

            if ($firewall) {
                $allEnabled = ($firewall | Where-Object { $_.Enabled -eq $false }).Count -eq 0
                $securityData.Checks.FirewallEnabled = $allEnabled
                
                if ($allEnabled) { $score += 20 }
                else {
                    $securityData.Issues += "One or more firewall profiles are disabled"
                }
            }
        }
        catch {
            $securityData.Issues += "Failed to check Firewall: $_"
        }

        # Check Windows Updates (20 points)
        try {
            $updates = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                $searcher.Search("IsInstalled=0").Updates.Count
            } -ErrorAction SilentlyContinue

            $securityData.Checks.PendingUpdates = $updates

            if ($updates -eq 0) { $score += 20 }
            elseif ($updates -le 5) { $score += 10 }
            else {
                $securityData.Issues += "$updates pending Windows updates"
            }
        }
        catch {
            $securityData.Issues += "Failed to check Windows Updates: $_"
        }

        # Check BitLocker (15 points)
        try {
            $bitlocker = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                Get-BitLockerVolume -ErrorAction SilentlyContinue | Where-Object { $_.VolumeType -eq 'OperatingSystem' }
            } -ErrorAction SilentlyContinue

            if ($bitlocker) {
                $encrypted = $bitlocker.ProtectionStatus -eq 'On'
                $securityData.Checks.BitLockerEnabled = $encrypted

                if ($encrypted) { $score += 15 }
                else {
                    $securityData.Issues += "BitLocker is not enabled on OS drive"
                }
            }
        }
        catch {
            # BitLocker might not be available on all editions
        }

        # Check Local Administrators (15 points)
        try {
            $admins = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
            } -ErrorAction SilentlyContinue

            $adminCount = ($admins | Measure-Object).Count
            $securityData.Checks.LocalAdminCount = $adminCount

            if ($adminCount -le 2) { $score += 15 }
            elseif ($adminCount -le 4) { $score += 10 }
            else {
                $securityData.Issues += "Too many local administrators ($adminCount)"
            }
        }
        catch {
            $securityData.Issues += "Failed to check local administrators: $_"
        }

        # Check for pending reboot (10 points)
        try {
            $pendingReboot = Invoke-Command -ComputerName $Device.Hostname -ScriptBlock {
                $rebootPending = $false

                # Check various registry keys
                if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
                    $rebootPending = $true
                }
                if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
                    $rebootPending = $true
                }

                return $rebootPending
            } -ErrorAction SilentlyContinue

            $securityData.Checks.PendingReboot = $pendingReboot

            if (-not $pendingReboot) { $score += 10 }
            else {
                $securityData.Issues += "System has a pending reboot"
            }
        }
        catch {
            $securityData.Issues += "Failed to check pending reboot: $_"
        }

        # Calculate final score
        $securityData.SecurityScore = $score

        # Determine severity
        $severity = if ($score -ge 80) { "Healthy" }
                    elseif ($score -ge 60) { "Warning" }
                    else { "Critical" }

        Write-Host "[$severity] $($Device.Hostname): Security Score = $score/100 ($($securityData.Issues.Count) issues)" -ForegroundColor $(
            if ($severity -eq 'Healthy') { 'Green' }
            elseif ($severity -eq 'Warning') { 'Yellow' }
            else { 'Red' }
        )
    }
    catch {
        Write-Warning "$($Device.Hostname): Security scan failed: $_"
    }

    return $securityData
}

# Execute security scan
$scanResults = @()

foreach ($device in $targetDevices) {
    $result = Scan-Security -Device $device -DatabasePath $DatabasePath
    $scanResults += $result

    # Store in database
    try {
        $dataJson = @{
            SecurityScore = $result.SecurityScore
            Issues        = $result.Issues
            Checks        = $result.Checks
        } | ConvertTo-Json -Compress -Depth 10

        $query = @"
INSERT INTO Inventory (DeviceId, Category, Data, CollectedAt)
VALUES (@DeviceId, 'Security', @Data, CURRENT_TIMESTAMP)
"@

        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{
            DeviceId = $result.DeviceId
            Data     = $dataJson
        }
    }
    catch {
        Write-Warning "Failed to store security scan results: $_"
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Security Scan Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$avgScore = ($scanResults | Where-Object { $_.SecurityScore -gt 0 } | Measure-Object -Property SecurityScore -Average).Average
Write-Host "Average Security Score: $([math]::Round($avgScore, 2))/100" -ForegroundColor White
Write-Host "Devices Scanned: $($scanResults.Count)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

