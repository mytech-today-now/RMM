<#
.SYNOPSIS
    Test Phase 5: Reporting & Automation

.DESCRIPTION
    Validates all reporting scripts, compliance checking, executive dashboard,
    policy engine, scheduled tasks, and workflow orchestration.
#>

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Phase 5: Reporting & Automation Tests" -ForegroundColor Cyan
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

# Test 1: Report Generator - Executive Summary
Write-Host ""
Write-Host "[TEST 1] Testing Report-Generator.ps1 - Executive Summary..." -ForegroundColor Yellow
try {
    $result = .\scripts\reports\Report-Generator.ps1 -ReportType "ExecutiveSummary" -OutputPath ".\reports\test-executive.html" 2>&1
    if (Test-Path ".\reports\test-executive.html") {
        Write-Host "[PASS] Executive summary report generated" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Executive summary report not created" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Report-Generator.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 2: Report Generator - Device Inventory
Write-Host ""
Write-Host "[TEST 2] Testing Report-Generator.ps1 - Device Inventory..." -ForegroundColor Yellow
try {
    $result = .\scripts\reports\Report-Generator.ps1 -ReportType "DeviceInventory" -OutputPath ".\reports\test-inventory.html" 2>&1
    if (Test-Path ".\reports\test-inventory.html") {
        Write-Host "[PASS] Device inventory report generated" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Device inventory report not created" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Report-Generator.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 3: Compliance Reporter
Write-Host ""
Write-Host "[TEST 3] Testing Compliance-Reporter.ps1..." -ForegroundColor Yellow
try {
    $result = .\scripts\reports\Compliance-Reporter.ps1 -Framework "CIS" -Devices "localhost" -OutputPath ".\reports\test-compliance.html" 2>&1
    if (Test-Path ".\reports\test-compliance.html") {
        Write-Host "[PASS] Compliance report generated" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Compliance report not created" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Compliance-Reporter.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 4: Executive Dashboard
Write-Host ""
Write-Host "[TEST 4] Testing Executive-Dashboard.ps1..." -ForegroundColor Yellow
try {
    $result = .\scripts\reports\Executive-Dashboard.ps1 -OutputPath ".\reports\test-dashboard.html" 2>&1
    if (Test-Path ".\reports\test-dashboard.html") {
        Write-Host "[PASS] Executive dashboard generated" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Executive dashboard not created" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Executive-Dashboard.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 5: Policy Engine - Get Policy
Write-Host ""
Write-Host "[TEST 5] Testing Policy-Engine.ps1 - Get Policy..." -ForegroundColor Yellow
try {
    $result = .\scripts\automation\Policy-Engine.ps1 -Action "Get" -PolicyId "default" 2>&1
    if ($LASTEXITCODE -eq 0 -or $result -match "Policy Details|Policy ID") {
        Write-Host "[PASS] Policy retrieved successfully" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Policy retrieval failed" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Policy-Engine.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 6: Policy Engine - Test Compliance
Write-Host ""
Write-Host "[TEST 6] Testing Policy-Engine.ps1 - Test Compliance..." -ForegroundColor Yellow
try {
    $result = .\scripts\automation\Policy-Engine.ps1 -Action "Test" -PolicyId "default" -Devices "localhost" 2>&1
    if ($LASTEXITCODE -eq 0 -or $result -match "Compliance Test|COMPLIANT|NON-COMPLIANT") {
        Write-Host "[PASS] Compliance test completed" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Compliance test failed" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Policy-Engine.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 7: Scheduled Tasks - List
Write-Host ""
Write-Host "[TEST 7] Testing Scheduled-Tasks.ps1 - List..." -ForegroundColor Yellow
try {
    $result = .\scripts\automation\Scheduled-Tasks.ps1 -Action "List" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[PASS] Scheduled tasks listed" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Scheduled tasks list failed" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Scheduled-Tasks.ps1 error: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 8: Workflow Orchestrator - History
Write-Host ""
Write-Host "[TEST 8] Testing Workflow-Orchestrator.ps1 - History..." -ForegroundColor Yellow
try {
    $result = .\scripts\automation\Workflow-Orchestrator.ps1 -Action "History" 2>&1
    if ($LASTEXITCODE -eq 0 -or $result -match "Workflow History|No workflow history") {
        Write-Host "[PASS] Workflow history retrieved" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "[FAIL] Workflow history failed" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "[FAIL] Workflow-Orchestrator.ps1 error: $_" -ForegroundColor Red
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
    Write-Host "[SUCCESS] All Phase 5 tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host ""
    Write-Host "[FAILURE] Some tests failed. Review output above." -ForegroundColor Red
    exit 1
}

