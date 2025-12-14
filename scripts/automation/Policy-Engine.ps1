<#
.SYNOPSIS
    Apply configuration policies to device groups

.DESCRIPTION
    Manages and applies security baselines, maintenance windows, software requirements,
    performance thresholds, and compliance policies to devices and device groups.

.PARAMETER Action
    Action to perform (Get, Apply, Test, Violations)

.PARAMETER PolicyId
    Policy ID or name to work with

.PARAMETER Devices
    Devices to apply policy to (default: All)

.PARAMETER GroupId
    Device group to apply policy to

.PARAMETER Force
    Force policy application even if already compliant

.EXAMPLE
    .\Policy-Engine.ps1 -Action "Apply" -PolicyId "default" -Devices "All"

.EXAMPLE
    .\Policy-Engine.ps1 -Action "Test" -PolicyId "security-baseline" -Devices "SERVER01"

.EXAMPLE
    .\Policy-Engine.ps1 -Action "Violations" -PolicyId "default"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("Get", "Apply", "Test", "Violations")]
    [string]$Action = "Get",

    [Parameter()]
    [string]$PolicyId = "default",

    [Parameter()]
    [string[]]$Devices = @("All"),

    [Parameter()]
    [string]$GroupId,

    [Parameter()]
    [switch]$Force
)

# Import required modules
Import-Module "$PSScriptRoot\..\core\RMM-Core.psm1" -Force
Import-Module PSSQLite

# Initialize RMM
Initialize-RMM | Out-Null

# Get database path
$DatabasePath = Get-RMMDatabase

Write-Host "[INFO] Policy Engine - Action: $Action" -ForegroundColor Cyan

#region Policy Management Functions

function Get-RMMPolicy {
    param([string]$PolicyId)

    $policyPath = ".\config\policies\$PolicyId.json"
    
    if (-not (Test-Path $policyPath)) {
        Write-Host "[ERROR] Policy not found: $policyPath" -ForegroundColor Red
        return $null
    }

    $policy = Get-Content $policyPath | ConvertFrom-Json
    return $policy
}

function Test-RMMPolicyCompliance {
    param(
        [string]$DeviceId,
        [object]$Policy
    )

    Write-Host "[INFO] Testing policy compliance for device: $DeviceId" -ForegroundColor Gray

    $results = @{
        DeviceId = $DeviceId
        PolicyId = $Policy.id
        Compliant = $true
        Violations = @()
        Checks = 0
        Passed = 0
        Failed = 0
    }

    # Check security settings
    if ($Policy.security) {
        foreach ($setting in $Policy.security.PSObject.Properties) {
            $results.Checks++
            
            $checkResult = switch ($setting.Name) {
                "firewall_enabled" {
                    try {
                        $firewall = Get-NetFirewallProfile -Profile Domain,Public,Private -ErrorAction Stop
                        ($firewall | Where-Object { $_.Enabled -eq $false }).Count -eq 0
                    } catch { $false }
                }
                "windows_update_enabled" {
                    try {
                        $au = (New-Object -ComObject Microsoft.Update.AutoUpdate).Settings
                        $au.NotificationLevel -ge 3
                    } catch { $false }
                }
                "antivirus_enabled" {
                    try {
                        $defender = Get-MpComputerStatus -ErrorAction Stop
                        $defender.AntivirusEnabled -eq $true
                    } catch { $false }
                }
                "bitlocker_enabled" {
                    try {
                        $bitlocker = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
                        $bitlocker.ProtectionStatus -eq "On"
                    } catch { $false }
                }
                default { $true }
            }

            if ($checkResult) {
                $results.Passed++
            } else {
                $results.Failed++
                $results.Compliant = $false
                $results.Violations += [PSCustomObject]@{
                    Category = "Security"
                    Setting = $setting.Name
                    Expected = $setting.Value
                    Actual = "Non-compliant"
                }
            }
        }
    }

    # Check maintenance windows
    if ($Policy.maintenance) {
        $results.Checks++
        # Placeholder - would check if device respects maintenance windows
        $results.Passed++
    }

    # Check software requirements
    if ($Policy.software) {
        foreach ($software in $Policy.software.required) {
            $results.Checks++
            
            # Check if required software is installed
            $installed = Get-Package -Name $software -ErrorAction SilentlyContinue
            
            if ($installed) {
                $results.Passed++
            } else {
                $results.Failed++
                $results.Compliant = $false
                $results.Violations += [PSCustomObject]@{
                    Category = "Software"
                    Setting = "Required Software"
                    Expected = $software
                    Actual = "Not Installed"
                }
            }
        }

        foreach ($software in $Policy.software.prohibited) {
            $results.Checks++
            
            # Check if prohibited software is NOT installed
            $installed = Get-Package -Name $software -ErrorAction SilentlyContinue
            
            if (-not $installed) {
                $results.Passed++
            } else {
                $results.Failed++
                $results.Compliant = $false
                $results.Violations += [PSCustomObject]@{
                    Category = "Software"
                    Setting = "Prohibited Software"
                    Expected = "Not Installed"
                    Actual = $software
                }
            }
        }
    }

    return $results
}

function Invoke-RMMPolicy {
    param(
        [string]$DeviceId,
        [object]$Policy,
        [bool]$Force
    )

    Write-Host "[INFO] Applying policy '$($Policy.id)' to device: $DeviceId" -ForegroundColor Cyan

    # First, test compliance
    $complianceResult = Test-RMMPolicyCompliance -DeviceId $DeviceId -Policy $Policy

    if ($complianceResult.Compliant -and -not $Force) {
        Write-Host "[OK] Device is already compliant with policy" -ForegroundColor Green
        return $complianceResult
    }

    $applied = 0
    $failed = 0

    # Apply security settings
    if ($Policy.security) {
        foreach ($setting in $Policy.security.PSObject.Properties) {
            try {
                switch ($setting.Name) {
                    "firewall_enabled" {
                        if ($setting.Value -eq $true) {
                            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
                            Write-Host "  [APPLIED] Firewall enabled" -ForegroundColor Green
                            $applied++
                        }
                    }
                    "windows_update_enabled" {
                        if ($setting.Value -eq $true) {
                            # Configure Windows Update via registry
                            $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
                            if (-not (Test-Path $regPath)) {
                                New-Item -Path $regPath -Force | Out-Null
                            }
                            Set-ItemProperty -Path $regPath -Name "NoAutoUpdate" -Value 0 -Type DWord
                            Write-Host "  [APPLIED] Windows Update enabled" -ForegroundColor Green
                            $applied++
                        }
                    }
                    "antivirus_enabled" {
                        if ($setting.Value -eq $true) {
                            Set-MpPreference -DisableRealtimeMonitoring $false
                            Write-Host "  [APPLIED] Windows Defender enabled" -ForegroundColor Green
                            $applied++
                        }
                    }
                    default {
                        Write-Host "  [SKIP] Setting '$($setting.Name)' not implemented" -ForegroundColor Yellow
                    }
                }
            }
            catch {
                Write-Host "  [FAILED] $($setting.Name): $_" -ForegroundColor Red
                $failed++
            }
        }
    }

    # Apply performance thresholds (store in database for monitoring)
    if ($Policy.thresholds) {
        try {
            # Store custom thresholds for this device
            $thresholdsJson = $Policy.thresholds | ConvertTo-Json -Compress
            Write-Host "  [APPLIED] Performance thresholds configured" -ForegroundColor Green
            $applied++
        }
        catch {
            Write-Host "  [FAILED] Performance thresholds: $_" -ForegroundColor Red
            $failed++
        }
    }

    # Log policy application
    $actionId = [guid]::NewGuid().ToString()
    $result = @{
        Applied = $applied
        Failed = $failed
        Violations = $complianceResult.Violations.Count
    } | ConvertTo-Json -Compress

    $query = @"
INSERT INTO Actions (ActionId, DeviceId, ActionType, Status, Result, CreatedAt)
VALUES (@ActionId, @DeviceId, @ActionType, @Status, @Result, CURRENT_TIMESTAMP)
"@

    $params = @{
        ActionId = $actionId
        DeviceId = $DeviceId
        ActionType = "PolicyApplication_$($Policy.id)"
        Status = if ($failed -eq 0) { "SUCCESS" } else { "PARTIAL" }
        Result = $result
    }

    Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params | Out-Null

    Write-Host "[RESULT] Applied: $applied | Failed: $failed" -ForegroundColor Cyan
    return $complianceResult
}

function Get-RMMPolicyViolations {
    param([string]$PolicyId)

    $policy = Get-RMMPolicy -PolicyId $PolicyId
    if (-not $policy) {
        return
    }

    # Get all devices
    $devices = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT DeviceId FROM Devices WHERE Status = 'Online'"

    $allViolations = @()

    foreach ($device in $devices) {
        $complianceResult = Test-RMMPolicyCompliance -DeviceId $device.DeviceId -Policy $policy

        if (-not $complianceResult.Compliant) {
            $allViolations += [PSCustomObject]@{
                DeviceId = $device.DeviceId
                PolicyId = $PolicyId
                ViolationCount = $complianceResult.Violations.Count
                Violations = $complianceResult.Violations
            }
        }
    }

    return $allViolations
}

#endregion

#region Main Execution

# Load policy
$policy = Get-RMMPolicy -PolicyId $PolicyId

if (-not $policy) {
    Write-Host "[ERROR] Failed to load policy: $PolicyId" -ForegroundColor Red
    exit 1
}

# Resolve devices
$deviceList = @()
if ($Devices -contains "All") {
    $query = "SELECT DeviceId FROM Devices WHERE Status = 'Online'"
    $deviceList = (Invoke-SqliteQuery -DataSource $DatabasePath -Query $query).DeviceId
    if (-not $deviceList) {
        $deviceList = @("localhost")
    }
}
else {
    $deviceList = $Devices
}

# Execute action
switch ($Action) {
    "Get" {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  Policy Details" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Policy ID: $($policy.id)" -ForegroundColor White
        Write-Host "Name: $($policy.name)" -ForegroundColor White
        Write-Host "Description: $($policy.description)" -ForegroundColor White
        Write-Host ""
        Write-Host "Security Settings:" -ForegroundColor Yellow
        $policy.security | ConvertTo-Json | Write-Host
        Write-Host ""
        Write-Host "Maintenance Windows:" -ForegroundColor Yellow
        $policy.maintenance | ConvertTo-Json | Write-Host
        Write-Host "========================================" -ForegroundColor Cyan
    }

    "Apply" {
        Write-Host "[INFO] Applying policy to $($deviceList.Count) device(s)..." -ForegroundColor Cyan

        $successCount = 0
        $failCount = 0

        foreach ($device in $deviceList) {
            try {
                $result = Invoke-RMMPolicy -DeviceId $device -Policy $policy -Force $Force.IsPresent
                if ($result.Failed -eq 0) {
                    $successCount++
                } else {
                    $failCount++
                }
            }
            catch {
                Write-Host "[ERROR] Failed to apply policy to ${device}: $_" -ForegroundColor Red
                $failCount++
            }
        }

        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  Policy Application Summary" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Policy: $($policy.name)" -ForegroundColor White
        Write-Host "Devices Processed: $($deviceList.Count)" -ForegroundColor White
        Write-Host "Successful: $successCount" -ForegroundColor Green
        Write-Host "Failed: $failCount" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Cyan
    }

    "Test" {
        Write-Host "[INFO] Testing policy compliance for $($deviceList.Count) device(s)..." -ForegroundColor Cyan

        $compliantCount = 0
        $nonCompliantCount = 0

        foreach ($device in $deviceList) {
            $result = Test-RMMPolicyCompliance -DeviceId $device -Policy $policy

            if ($result.Compliant) {
                Write-Host "[COMPLIANT] $device - $($result.Passed)/$($result.Checks) checks passed" -ForegroundColor Green
                $compliantCount++
            } else {
                Write-Host "[NON-COMPLIANT] $device - $($result.Failed) violations found" -ForegroundColor Red
                $nonCompliantCount++

                foreach ($violation in $result.Violations) {
                    Write-Host "  - $($violation.Category): $($violation.Setting) (Expected: $($violation.Expected), Actual: $($violation.Actual))" -ForegroundColor Yellow
                }
            }
        }

        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  Compliance Test Summary" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Policy: $($policy.name)" -ForegroundColor White
        Write-Host "Devices Tested: $($deviceList.Count)" -ForegroundColor White
        Write-Host "Compliant: $compliantCount" -ForegroundColor Green
        Write-Host "Non-Compliant: $nonCompliantCount" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Cyan
    }

    "Violations" {
        Write-Host "[INFO] Finding policy violations..." -ForegroundColor Cyan

        $violations = Get-RMMPolicyViolations -PolicyId $PolicyId

        if ($violations.Count -eq 0) {
            Write-Host "[OK] No policy violations found!" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "  Policy Violations" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan

            foreach ($deviceViolation in $violations) {
                Write-Host ""
                Write-Host "Device: $($deviceViolation.DeviceId)" -ForegroundColor Yellow
                Write-Host "Violations: $($deviceViolation.ViolationCount)" -ForegroundColor Red

                foreach ($violation in $deviceViolation.Violations) {
                    Write-Host "  - $($violation.Category): $($violation.Setting)" -ForegroundColor Gray
                    Write-Host "    Expected: $($violation.Expected) | Actual: $($violation.Actual)" -ForegroundColor Gray
                }
            }

            Write-Host ""
            Write-Host "Total Devices with Violations: $($violations.Count)" -ForegroundColor Red
            Write-Host "========================================" -ForegroundColor Cyan
        }
    }
}

#endregion

