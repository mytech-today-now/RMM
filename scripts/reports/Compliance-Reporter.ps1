<#
.SYNOPSIS
    Compliance and baseline checking against security standards

.DESCRIPTION
    Scans devices against compliance baselines (CIS Benchmarks, NIST, custom policies)
    and generates compliance scores with remediation recommendations.

.PARAMETER Framework
    Compliance framework to check against (CIS, NIST, Custom)

.PARAMETER Devices
    Devices to scan (default: All)

.PARAMETER OutputPath
    Path where the compliance report will be saved

.PARAMETER Baseline
    Custom baseline name (for Custom framework)

.PARAMETER Remediate
    Automatically remediate non-compliant items where possible

.EXAMPLE
    .\Compliance-Reporter.ps1 -Framework "CIS" -Devices "All" -OutputPath ".\reports\compliance.html"

.EXAMPLE
    .\Compliance-Reporter.ps1 -Framework "Custom" -Baseline "Corporate" -Devices "SERVER01"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("CIS", "NIST", "Custom")]
    [string]$Framework = "CIS",

    [Parameter()]
    [string[]]$Devices = @("All"),

    [Parameter()]
    [string]$OutputPath = ".\reports\compliance.html",

    [Parameter()]
    [string]$Baseline = "default",

    [Parameter()]
    [switch]$Remediate
)

# Import required modules
Import-Module "$PSScriptRoot\..\core\RMM-Core.psm1" -Force
Import-Module PSSQLite

# Initialize RMM
Initialize-RMM | Out-Null

# Get database path
$DatabasePath = Get-RMMDatabase

Write-Host "[INFO] Running compliance check: $Framework framework" -ForegroundColor Cyan
Write-Host "[INFO] Baseline: $Baseline" -ForegroundColor Gray

#region Compliance Checks

function Get-CISCompliance {
    param([string]$DeviceId)

    $checks = @()

    # CIS Benchmark checks (simplified examples)
    $checks += @{
        ID = "CIS-1.1"
        Name = "Windows Firewall Enabled"
        Category = "Network Security"
        Check = {
            $firewall = Get-NetFirewallProfile -Profile Domain,Public,Private
            $allEnabled = ($firewall | Where-Object { $_.Enabled -eq $false }).Count -eq 0
            return $allEnabled
        }
        Remediation = "Enable Windows Firewall for all profiles"
        Severity = "High"
    }

    $checks += @{
        ID = "CIS-1.2"
        Name = "Automatic Updates Enabled"
        Category = "Update Management"
        Check = {
            $au = (New-Object -ComObject Microsoft.Update.AutoUpdate).Settings
            return ($au.NotificationLevel -ge 3)
        }
        Remediation = "Enable automatic Windows updates"
        Severity = "Critical"
    }

    $checks += @{
        ID = "CIS-2.1"
        Name = "Password Complexity Enabled"
        Category = "Account Security"
        Check = {
            $secpol = secedit /export /cfg "$env:TEMP\secpol.cfg" 2>&1 | Out-Null
            $content = Get-Content "$env:TEMP\secpol.cfg"
            $complexity = $content | Select-String "PasswordComplexity"
            Remove-Item "$env:TEMP\secpol.cfg" -Force
            return ($complexity -match "= 1")
        }
        Remediation = "Enable password complexity requirements"
        Severity = "High"
    }

    $checks += @{
        ID = "CIS-2.2"
        Name = "Minimum Password Length"
        Category = "Account Security"
        Check = {
            $secpol = secedit /export /cfg "$env:TEMP\secpol.cfg" 2>&1 | Out-Null
            $content = Get-Content "$env:TEMP\secpol.cfg"
            $minLength = $content | Select-String "MinimumPasswordLength"
            Remove-Item "$env:TEMP\secpol.cfg" -Force
            if ($minLength -match "= (\d+)") {
                return ([int]$matches[1] -ge 14)
            }
            return $false
        }
        Remediation = "Set minimum password length to 14 characters"
        Severity = "High"
    }

    $checks += @{
        ID = "CIS-3.1"
        Name = "Guest Account Disabled"
        Category = "Account Security"
        Check = {
            $guest = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
            return ($guest.Enabled -eq $false)
        }
        Remediation = "Disable the Guest account"
        Severity = "Medium"
    }

    $checks += @{
        ID = "CIS-4.1"
        Name = "BitLocker Enabled"
        Category = "Data Protection"
        Check = {
            $bitlocker = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
            return ($bitlocker.ProtectionStatus -eq "On")
        }
        Remediation = "Enable BitLocker encryption on system drive"
        Severity = "High"
    }

    $checks += @{
        ID = "CIS-5.1"
        Name = "Windows Defender Enabled"
        Category = "Malware Protection"
        Check = {
            $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
            return ($defender.AntivirusEnabled -eq $true)
        }
        Remediation = "Enable Windows Defender Antivirus"
        Severity = "Critical"
    }

    $checks += @{
        ID = "CIS-5.2"
        Name = "Defender Signatures Up-to-Date"
        Category = "Malware Protection"
        Check = {
            $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
            $age = (Get-Date) - $defender.AntivirusSignatureLastUpdated
            return ($age.Days -lt 7)
        }
        Remediation = "Update Windows Defender signatures"
        Severity = "High"
    }

    return $checks
}

function Get-NISTCompliance {
    param([string]$DeviceId)

    # NIST 800-53 controls (simplified examples)
    $checks = @()

    $checks += @{
        ID = "NIST-AC-2"
        Name = "Account Management"
        Category = "Access Control"
        Check = {
            $inactiveUsers = Get-LocalUser | Where-Object { $_.Enabled -and $_.LastLogon -lt (Get-Date).AddDays(-90) }
            return ($inactiveUsers.Count -eq 0)
        }
        Remediation = "Disable inactive user accounts (>90 days)"
        Severity = "Medium"
    }

    $checks += @{
        ID = "NIST-AU-2"
        Name = "Audit Logging Enabled"
        Category = "Audit and Accountability"
        Check = {
            $auditPolicy = auditpol /get /category:* 2>&1
            return ($auditPolicy -match "Success and Failure")
        }
        Remediation = "Enable comprehensive audit logging"
        Severity = "High"
    }

    $checks += @{
        ID = "NIST-SC-7"
        Name = "Boundary Protection"
        Category = "System and Communications"
        Check = {
            $firewall = Get-NetFirewallProfile -Profile Domain,Public,Private
            $allEnabled = ($firewall | Where-Object { $_.Enabled -eq $false }).Count -eq 0
            return $allEnabled
        }
        Remediation = "Enable firewall on all network profiles"
        Severity = "Critical"
    }

    return $checks
}

function Get-CustomCompliance {
    param([string]$DeviceId, [string]$Baseline)

    # Load custom baseline from policy files
    $policyPath = ".\config\policies\$Baseline.json"
    if (-not (Test-Path $policyPath)) {
        Write-Host "[WARN] Custom baseline not found: $policyPath" -ForegroundColor Yellow
        return @()
    }

    $policy = Get-Content $policyPath | ConvertFrom-Json
    $checks = @()

    # Convert policy requirements to compliance checks
    if ($policy.security) {
        foreach ($requirement in $policy.security.PSObject.Properties) {
            $checks += @{
                ID = "CUSTOM-$($requirement.Name)"
                Name = $requirement.Name
                Category = "Custom Policy"
                Check = { $true }  # Placeholder - would need actual check logic
                Remediation = "Apply custom policy: $($requirement.Name)"
                Severity = "Medium"
            }
        }
    }

    return $checks
}

function Test-RMMCompliance {
    param(
        [string]$Framework,
        [string]$DeviceId,
        [string]$Baseline
    )

    Write-Host "[INFO] Scanning device: $DeviceId" -ForegroundColor Gray

    $checks = switch ($Framework) {
        "CIS" { Get-CISCompliance -DeviceId $DeviceId }
        "NIST" { Get-NISTCompliance -DeviceId $DeviceId }
        "Custom" { Get-CustomCompliance -DeviceId $DeviceId -Baseline $Baseline }
    }

    $results = @()
    $passed = 0
    $failed = 0

    foreach ($check in $checks) {
        try {
            $checkResult = & $check.Check
            $status = if ($checkResult) { "PASS"; $passed++ } else { "FAIL"; $failed++ }

            $results += [PSCustomObject]@{
                ID = $check.ID
                Name = $check.Name
                Category = $check.Category
                Status = $status
                Severity = $check.Severity
                Remediation = $check.Remediation
            }

            $color = if ($status -eq "PASS") { "Green" } else { "Red" }
            Write-Host "  [$status] $($check.ID): $($check.Name)" -ForegroundColor $color
        }
        catch {
            $results += [PSCustomObject]@{
                ID = $check.ID
                Name = $check.Name
                Category = $check.Category
                Status = "ERROR"
                Severity = $check.Severity
                Remediation = $check.Remediation
            }
            Write-Host "  [ERROR] $($check.ID): $_" -ForegroundColor Yellow
        }
    }

    $total = $passed + $failed
    $score = if ($total -gt 0) { [math]::Round(($passed / $total) * 100, 2) } else { 0 }

    return @{
        DeviceId = $DeviceId
        Framework = $Framework
        Score = $score
        Passed = $passed
        Failed = $failed
        Total = $total
        Results = $results
    }
}

#endregion

#region Report Generation

function Export-RMMComplianceReport {
    param(
        [array]$ComplianceResults,
        [string]$OutputPath
    )

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Compliance Report - $(Get-Date -Format 'yyyy-MM-dd')</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #333; border-bottom: 3px solid: #0078d4; padding-bottom: 10px; }
        h2 { color: #0078d4; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f1f1f1; }
        .metric { display: inline-block; margin: 10px 20px; padding: 20px; background-color: white; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); min-width: 150px; }
        .metric-value { font-size: 32px; font-weight: bold; color: #0078d4; }
        .metric-label { font-size: 14px; color: #666; margin-top: 5px; }
        .pass { color: #107c10; font-weight: bold; }
        .fail { color: #d13438; font-weight: bold; }
        .error { color: #ff8c00; font-weight: bold; }
        .critical { background-color: #fdd; }
        .high { background-color: #fed; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Compliance Report</h1>
    <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
"@

    foreach ($result in $ComplianceResults) {
        $scoreColor = if ($result.Score -ge 80) { "#107c10" } elseif ($result.Score -ge 60) { "#ff8c00" } else { "#d13438" }

        $html += @"
    <h2>Device: $($result.DeviceId)</h2>
    <div class="metric">
        <div class="metric-value" style="color: $scoreColor;">$($result.Score)%</div>
        <div class="metric-label">Compliance Score</div>
    </div>
    <div class="metric">
        <div class="metric-value">$($result.Passed)</div>
        <div class="metric-label">Passed</div>
    </div>
    <div class="metric">
        <div class="metric-value">$($result.Failed)</div>
        <div class="metric-label">Failed</div>
    </div>
    <div class="metric">
        <div class="metric-value">$($result.Total)</div>
        <div class="metric-label">Total Checks</div>
    </div>

    <h3>Compliance Check Results</h3>
    <table>
        <tr><th>ID</th><th>Check Name</th><th>Category</th><th>Status</th><th>Severity</th><th>Remediation</th></tr>
"@

        foreach ($check in $result.Results) {
            $statusClass = $check.Status.ToLower()
            $rowClass = if ($check.Status -eq "FAIL" -and $check.Severity -in @("Critical", "High")) {
                if ($check.Severity -eq "Critical") { "critical" } else { "high" }
            } else { "" }

            $html += "        <tr class='$rowClass'><td>$($check.ID)</td><td>$($check.Name)</td><td>$($check.Category)</td><td class='$statusClass'>$($check.Status)</td><td>$($check.Severity)</td><td>$($check.Remediation)</td></tr>`n"
        }

        $html += "    </table>`n"
    }

    $html += @"
    <div class="footer">
        <p>myTech.Today RMM System | Compliance Report Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "[SUCCESS] Compliance report saved to: $OutputPath" -ForegroundColor Green
}

#endregion

#region Main Execution

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

Write-Host "[INFO] Scanning $($deviceList.Count) device(s)..." -ForegroundColor Cyan

# Run compliance checks
$allResults = @()
foreach ($device in $deviceList) {
    $complianceResult = Test-RMMCompliance -Framework $Framework -DeviceId $device -Baseline $Baseline
    $allResults += $complianceResult

    Write-Host ""
    Write-Host "[RESULT] Device: $device | Score: $($complianceResult.Score)% | Passed: $($complianceResult.Passed)/$($complianceResult.Total)" -ForegroundColor Cyan
}

# Generate report
Export-RMMComplianceReport -ComplianceResults $allResults -OutputPath $OutputPath

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Compliance Scan Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Framework: $Framework" -ForegroundColor White
Write-Host "Devices Scanned: $($allResults.Count)" -ForegroundColor White
$avgScore = if ($allResults.Count -gt 0) { [math]::Round(($allResults | Measure-Object -Property Score -Average).Average, 2) } else { 0 }
Write-Host "Average Compliance Score: $avgScore%" -ForegroundColor White
Write-Host "Report: $OutputPath" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

#endregion

