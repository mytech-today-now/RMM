<#
.SYNOPSIS
    Phase 3 validation tests for Data Collection System.

.DESCRIPTION
    Tests all collectors and monitors to ensure they work correctly.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Phase 3 Validation Tests" -ForegroundColor Cyan
Write-Host "  Data Collection System" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Change to RMM directory
$rmmRoot = Split-Path $PSScriptRoot -Parent
Set-Location $rmmRoot

# Import RMM Core
Import-Module ".\scripts\core\RMM-Core.psm1" -Force
Import-Module PSSQLite

# Initialize RMM
Write-Host "[TEST] Initialize RMM" -ForegroundColor Yellow
try {
    Initialize-RMM -ErrorAction Stop
    Write-Host "[PASS] Initialize RMM" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Initialize RMM: $_" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test counters
$passCount = 1
$failCount = 0

# Test 1: Inventory Collector
Write-Host "[TEST] Inventory Collector" -ForegroundColor Yellow
try {
    & ".\scripts\collectors\Inventory-Collector.ps1" -Devices "localhost" -Categories "Hardware" -ErrorAction Stop
    Write-Host "[PASS] Inventory Collector" -ForegroundColor Green
    $passCount++
}
catch {
    Write-Host "[FAIL] Inventory Collector: $_" -ForegroundColor Red
    $failCount++
}
Write-Host ""

# Test 2: Hardware Monitor
Write-Host "[TEST] Hardware Monitor" -ForegroundColor Yellow
try {
    & ".\scripts\collectors\Hardware-Monitor.ps1" -Devices "localhost" -ErrorAction Stop
    Write-Host "[PASS] Hardware Monitor" -ForegroundColor Green
    $passCount++
}
catch {
    Write-Host "[FAIL] Hardware Monitor: $_" -ForegroundColor Red
    $failCount++
}
Write-Host ""

# Test 3: Software Auditor
Write-Host "[TEST] Software Auditor" -ForegroundColor Yellow
try {
    & ".\scripts\collectors\Software-Auditor.ps1" -Devices "localhost" -ErrorAction Stop
    Write-Host "[PASS] Software Auditor" -ForegroundColor Green
    $passCount++
}
catch {
    Write-Host "[FAIL] Software Auditor: $_" -ForegroundColor Red
    $failCount++
}
Write-Host ""

# Test 4: Security Scanner
Write-Host "[TEST] Security Scanner" -ForegroundColor Yellow
try {
    & ".\scripts\collectors\Security-Scanner.ps1" -Devices "localhost" -ErrorAction Stop
    Write-Host "[PASS] Security Scanner" -ForegroundColor Green
    $passCount++
}
catch {
    Write-Host "[FAIL] Security Scanner: $_" -ForegroundColor Red
    $failCount++
}
Write-Host ""

# Test 5: Event Collector
Write-Host "[TEST] Event Collector" -ForegroundColor Yellow
try {
    & ".\scripts\collectors\Event-Collector.ps1" -Devices "localhost" -Hours 1 -MinimumLevel "Error" -ErrorAction Stop
    Write-Host "[PASS] Event Collector" -ForegroundColor Green
    $passCount++
}
catch {
    Write-Host "[FAIL] Event Collector: $_" -ForegroundColor Red
    $failCount++
}
Write-Host ""

# Test 6: Health Monitor
Write-Host "[TEST] Health Monitor" -ForegroundColor Yellow
try {
    & ".\scripts\monitors\Health-Monitor.ps1" -Devices "localhost" -ErrorAction Stop
    Write-Host "[PASS] Health Monitor" -ForegroundColor Green
    $passCount++
}
catch {
    Write-Host "[FAIL] Health Monitor: $_" -ForegroundColor Red
    $failCount++
}
Write-Host ""

# Test 7: Service Monitor
Write-Host "[TEST] Service Monitor" -ForegroundColor Yellow
try {
    & ".\scripts\monitors\Service-Monitor.ps1" -Devices "localhost" -Services "Spooler","W32Time" -ErrorAction Stop
    Write-Host "[PASS] Service Monitor" -ForegroundColor Green
    $passCount++
}
catch {
    Write-Host "[FAIL] Service Monitor: $_" -ForegroundColor Red
    $failCount++
}
Write-Host ""

# Test 8: Performance Monitor
Write-Host "[TEST] Performance Monitor" -ForegroundColor Yellow
try {
    & ".\scripts\monitors\Performance-Monitor.ps1" -Devices "localhost" -ErrorAction Stop
    Write-Host "[PASS] Performance Monitor" -ForegroundColor Green
    $passCount++
}
catch {
    Write-Host "[FAIL] Performance Monitor: $_" -ForegroundColor Red
    $failCount++
}
Write-Host ""

# Test 9: Availability Monitor
Write-Host "[TEST] Availability Monitor" -ForegroundColor Yellow
try {
    & ".\scripts\monitors\Availability-Monitor.ps1" -Devices "localhost" -ErrorAction Stop
    Write-Host "[PASS] Availability Monitor" -ForegroundColor Green
    $passCount++
}
catch {
    Write-Host "[FAIL] Availability Monitor: $_" -ForegroundColor Red
    $failCount++
}
Write-Host ""

# Test 10: Verify database has inventory data
Write-Host "[TEST] Verify Inventory Data in Database" -ForegroundColor Yellow
try {
    $dbPath = ".\data\devices.db"
    $inventoryCount = Invoke-SqliteQuery -DataSource $dbPath -Query "SELECT COUNT(*) as Count FROM Inventory" -ErrorAction Stop
    if ($inventoryCount.Count -gt 0) {
        Write-Host "[PASS] Verify Inventory Data in Database (Found $($inventoryCount.Count) records)" -ForegroundColor Green
        $passCount++
    }
    else {
        Write-Host "[FAIL] Verify Inventory Data in Database (No records found)" -ForegroundColor Red
        $failCount++
    }
}
catch {
    Write-Host "[FAIL] Verify Inventory Data in Database: $_" -ForegroundColor Red
    $failCount++
}
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host ""

if ($failCount -eq 0) {
    Write-Host "[OK] All Phase 3 tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "[FAIL] Some tests failed. Please review the output above." -ForegroundColor Red
    exit 1
}
