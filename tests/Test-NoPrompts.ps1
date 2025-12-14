<#
.SYNOPSIS
    Verify that no scripts prompt for user input.

.DESCRIPTION
    Tests that all collectors and monitors can run without prompting for parameters.
#>

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Testing for Unattended Execution" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$scripts = @(
    ".\scripts\collectors\Event-Collector.ps1"
    ".\scripts\collectors\Hardware-Monitor.ps1"
    ".\scripts\collectors\Inventory-Collector.ps1"
    ".\scripts\collectors\Security-Scanner.ps1"
    ".\scripts\collectors\Software-Auditor.ps1"
    ".\scripts\monitors\Availability-Monitor.ps1"
    ".\scripts\monitors\Health-Monitor.ps1"
    ".\scripts\monitors\Performance-Monitor.ps1"
    ".\scripts\monitors\Service-Monitor.ps1"
)

$passCount = 0
$failCount = 0

foreach ($script in $scripts) {
    $scriptName = Split-Path $script -Leaf
    Write-Host "[TEST] Checking $scriptName for mandatory parameters..." -ForegroundColor Yellow
    
    # Check if script has mandatory parameters
    $content = Get-Content $script -Raw
    if ($content -match 'Parameter.*Mandatory\s*=\s*\$true') {
        Write-Host "[FAIL] $scriptName has mandatory parameters" -ForegroundColor Red
        $failCount++
    }
    elseif ($content -match '\$Devices\s*=\s*@\("All"\)') {
        Write-Host "[PASS] $scriptName has default value for Devices parameter" -ForegroundColor Green
        $passCount++
    }
    else {
        Write-Host "[WARN] $scriptName - could not verify default parameter" -ForegroundColor Yellow
        $failCount++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host ""

if ($failCount -eq 0) {
    Write-Host "[OK] All scripts can run unattended!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "[FAIL] Some scripts may prompt for input." -ForegroundColor Red
    exit 1
}

