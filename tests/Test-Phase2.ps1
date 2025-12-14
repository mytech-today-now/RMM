<#
.SYNOPSIS
    Phase 2 validation test script.

.DESCRIPTION
    Tests all Phase 2 core framework functionality.
#>

$ErrorActionPreference = 'Stop'
$testsPassed = 0
$testsFailed = 0

function Test-Function {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    
    Write-Host "`n[TEST] $Name" -ForegroundColor Cyan
    try {
        & $Test
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:testsPassed++
    }
    catch {
        Write-Host "[FAIL] $Name - $_" -ForegroundColor Red
        $script:testsFailed++
    }
}

# Change to RMM root
Set-Location $PSScriptRoot\..

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Phase 2 Validation Tests" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

# Test 1: Module Import
Test-Function "Import RMM-Core module" {
    Import-Module .\scripts\core\RMM-Core.psm1 -Force
    if (-not (Get-Module -Name RMM-Core)) {
        throw "Module not loaded"
    }
}

# Test 2: Initialize RMM
Test-Function "Initialize RMM" {
    $result = Initialize-RMM
    if (-not $result) {
        throw "Initialization failed"
    }
}

# Test 3: Get Configuration
Test-Function "Get RMM Configuration" {
    $config = Get-RMMConfig
    if (-not $config) {
        throw "Configuration not loaded"
    }
    if (-not $config.General) {
        throw "Configuration missing General section"
    }
}

# Test 4: Get Health
Test-Function "Get RMM Health" {
    $health = Get-RMMHealth
    if ($null -eq $health) {
        throw "Health check failed"
    }
    if ($null -eq $health.TotalDevices) {
        throw "Health missing TotalDevices"
    }
}

# Test 5: Get Devices
Test-Function "Get RMM Devices" {
    $devices = Get-RMMDevice
    # Should return array or null, not error
}

# Test 6: Add Device
Test-Function "Add RMM Device" {
    $deviceId = Add-RMMDevice -Hostname "TEST-VALIDATION" -IPAddress "10.0.0.1" -Tags "test"
    if (-not $deviceId) {
        throw "Failed to add device"
    }
}

# Test 7: Get Specific Device
Test-Function "Get Specific Device" {
    $device = Get-RMMDevice -Hostname "TEST-VALIDATION"
    if (-not $device) {
        throw "Device not found"
    }
    if ($device.Hostname -ne "TEST-VALIDATION") {
        throw "Wrong device returned"
    }
}

# Test 8: Update Device
Test-Function "Update Device" {
    $device = Get-RMMDevice -Hostname "TEST-VALIDATION"
    Update-RMMDevice -DeviceId $device.DeviceId -Status "Online" -Tags "test,updated"
    $updated = Get-RMMDevice -DeviceId $device.DeviceId
    if ($updated.Status -ne "Online") {
        throw "Device not updated"
    }
}

# Test 9: Queue Action
Test-Function "Queue Action" {
    $device = Get-RMMDevice -Hostname "TEST-VALIDATION"
    $actionId = Invoke-RMMAction -DeviceId $device.DeviceId -ActionType "HealthCheck"
    if (-not $actionId) {
        throw "Failed to queue action"
    }
}

# Test 10: Get Database Path
Test-Function "Get Database Path" {
    $dbPath = Get-RMMDatabase
    if (-not $dbPath) {
        throw "Database path not returned"
    }
    if (-not (Test-Path $dbPath)) {
        throw "Database file not found"
    }
}

# Test 11: Remove Device
Test-Function "Remove Device" {
    $device = Get-RMMDevice -Hostname "TEST-VALIDATION"
    Remove-RMMDevice -DeviceId $device.DeviceId -Force
    $removed = Get-RMMDevice -DeviceId $device.DeviceId
    if ($removed) {
        throw "Device not removed"
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Test Results" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { 'Red' } else { 'Green' })
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "[OK] All Phase 2 tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "[ERROR] Some tests failed" -ForegroundColor Red
    exit 1
}

