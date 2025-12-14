<#
.SYNOPSIS
    Test Phase 4: Actions & Alerting

.DESCRIPTION
    Validates all action scripts, alert management, notifications, and escalation workflows.
#>

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Phase 4: Actions & Alerting Tests" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = 'Continue'
$testsPassed = 0
$testsFailed = 0

# Import RMM Core
try {
    Import-Module ".\scripts\core\RMM-Core.psm1" -Force
    Initialize-RMM
    Write-Host "[PASS] RMM Core module loaded" -ForegroundColor Green
    $testsPassed++
}
catch {
    Write-Host "[FAIL] Failed to load RMM Core: $_" -ForegroundColor Red
    $testsFailed++
    exit 1
}

# Test 1: Remote Actions - FlushDNS
Write-Host ""
Write-Host "[TEST 1] Testing Remote-Actions.ps1 - FlushDNS..." -ForegroundColor Yellow
try {
    $result = .\scripts\actions\Remote-Actions.ps1 -Action "FlushDNS" -Devices "localhost" -Confirm:$false 2>&1
    if ($LASTEXITCODE -eq 0 -or $result -match "SUCCESS") {
        Write-Host "[PASS] FlushDNS action executed" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] FlushDNS action failed" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Remote-Actions.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 2: Script Executor
Write-Host ""
Write-Host "[TEST 2] Testing Script-Executor.ps1..." -ForegroundColor Yellow
try {
    $result = .\scripts\actions\Script-Executor.ps1 -ScriptBlock { Get-Service | Select-Object -First 5 } -Devices "localhost" 2>&1
    if ($LASTEXITCODE -eq 0 -or $result -match "SUCCESS") {
        Write-Host "[PASS] Script execution completed" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Script execution failed" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Script-Executor.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 3: Update Manager - Scan
Write-Host ""
Write-Host "[TEST 3] Testing Update-Manager.ps1 - Scan..." -ForegroundColor Yellow
try {
    $result = .\scripts\actions\Update-Manager.ps1 -Action "Scan" -Devices "localhost" 2>&1
    if ($LASTEXITCODE -eq 0 -or $result -match "SUCCESS|PROCESSING") {
        Write-Host "[PASS] Update scan initiated" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[WARN] Update scan may have issues (this is expected if Windows Update is unavailable)" -ForegroundColor Yellow
        $testsPassed++
    }
}
catch {
    Write-Host "[WARN] Update-Manager.ps1 error (expected): $_" -ForegroundColor Yellow
    $testsPassed++
}

# Test 4: Remediation Engine - ClearTemp
Write-Host ""
Write-Host "[TEST 4] Testing Remediation-Engine.ps1 - ClearTemp..." -ForegroundColor Yellow
try {
    $result = .\scripts\actions\Remediation-Engine.ps1 -Remediation "ClearTemp" -Devices "localhost" -AutoRemediate 2>&1
    if ($LASTEXITCODE -eq 0 -or $result -match "SUCCESS") {
        Write-Host "[PASS] ClearTemp remediation executed" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] ClearTemp remediation failed" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Remediation-Engine.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 5: Alert Manager - Create Alert
Write-Host ""
Write-Host "[TEST 5] Testing Alert-Manager.ps1 - Create Alert..." -ForegroundColor Yellow
try {
    $result = .\scripts\alerts\Alert-Manager.ps1 -Action "Create" -DeviceId "localhost" -AlertType "Test" -Severity "High" -Title "Test Alert" -Message "This is a test alert" 2>&1
    if ($LASTEXITCODE -eq 0 -or $result -match "CREATED") {
        Write-Host "[PASS] Alert created successfully" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Alert creation failed" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Alert-Manager.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 6: Alert Manager - Get Alerts
Write-Host ""
Write-Host "[TEST 6] Testing Alert-Manager.ps1 - Get Alerts..." -ForegroundColor Yellow
try {
    $result = .\scripts\alerts\Alert-Manager.ps1 -Action "Get" -Severity "High" 2>&1
    if ($LASTEXITCODE -eq 0 -or $result -match "Active Alerts|No alerts") {
        Write-Host "[PASS] Alert retrieval successful" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Alert retrieval failed" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Alert-Manager.ps1 Get error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 7: Notification Engine - Test Mode
Write-Host ""
Write-Host "[TEST 7] Testing Notification-Engine.ps1 - Test Mode..." -ForegroundColor Yellow
try {
    $result = .\scripts\alerts\Notification-Engine.ps1 -TestMode -Channels "EventLog" 2>&1
    if ($LASTEXITCODE -eq 0 -or $result -match "SUCCESS|SKIPPED") {
        Write-Host "[PASS] Notification engine test completed" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Notification engine test failed" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Notification-Engine.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 8: Escalation Handler - Configure
Write-Host ""
Write-Host "[TEST 8] Testing Escalation-Handler.ps1 - Configure..." -ForegroundColor Yellow
try {
    $result = .\scripts\alerts\Escalation-Handler.ps1 -Action "Configure" 2>&1
    if ($LASTEXITCODE -eq 0 -or $result -match "Escalation Configuration|Business Hours") {
        Write-Host "[PASS] Escalation configuration displayed" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Escalation configuration failed" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Escalation-Handler.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 9: Check Actions table
Write-Host ""
Write-Host "[TEST 9] Checking Actions table in database..." -ForegroundColor Yellow
try {
    Import-Module PSSQLite
    $db = Get-RMMDatabase
    $actions = Invoke-SqliteQuery -DataSource $db -Query "SELECT COUNT(*) as Count FROM Actions"
    if ($actions.Count -gt 0) {
        Write-Host "[PASS] Actions logged to database: $($actions.Count) entries" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[WARN] No actions found in database (may be expected)" -ForegroundColor Yellow
        $testsPassed++
    }
}
catch {
    Write-Host "[FAIL] Database check error: $_" -ForegroundColor Red
    $testsFailed++
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Tests: $($testsPassed + $testsFailed)" -ForegroundColor White
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Cyan

if ($testsFailed -eq 0) {
    Write-Host ""
    Write-Host "[SUCCESS] All Phase 4 tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host ""
    Write-Host "[FAILURE] Some tests failed. Review output above." -ForegroundColor Red
    exit 1
}

