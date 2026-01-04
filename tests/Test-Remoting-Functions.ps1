# Quick test to verify remoting functions are exported
Import-Module .\scripts\core\RMM-Core.psm1 -Force

$remotingFunctions = @(
    'Test-RMMDomainMembership',
    'Test-RMMRemoteHTTPS',
    'Test-RMMRemoteHTTP',
    'Test-RMMRemoteEnvironment',
    'Get-RMMTrustedHosts',
    'Test-RMMInTrustedHosts',
    'Add-RMMTrustedHost',
    'Remove-RMMTrustedHost',
    'Clear-RMMTemporaryTrustedHosts',
    'New-RMMRemoteSession',
    'Invoke-RMMRemoteCommand',
    'Set-RMMRemotingPreference',
    'Get-RMMRemotingPreference'
)

Write-Host "=== RMM Remoting Functions Export Test ===" -ForegroundColor Cyan
$allPassed = $true

foreach ($funcName in $remotingFunctions) {
    $cmd = Get-Command -Name $funcName -Module RMM-Core -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "[PASS] $funcName" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $funcName - NOT FOUND" -ForegroundColor Red
        $allPassed = $false
    }
}

Write-Host ""
if ($allPassed) {
    Write-Host "All remoting functions are exported correctly!" -ForegroundColor Green
} else {
    Write-Host "Some functions are missing!" -ForegroundColor Red
}

# Quick functional test
Write-Host ""
Write-Host "=== Quick Functional Tests ===" -ForegroundColor Cyan

# Test 1: Domain membership detection
$isDomain = Test-RMMDomainMembership
Write-Host "[INFO] Local computer domain-joined: $isDomain"

# Test 2: Get preferences
$prefs = Get-RMMRemotingPreference
Write-Host "[INFO] PreferHTTPS: $($prefs.PreferHTTPS)"
Write-Host "[INFO] AutoManageTrustedHosts: $($prefs.AutoManageTrustedHosts)"

# Test 3: Get TrustedHosts
$trustedHosts = Get-RMMTrustedHosts
Write-Host "[INFO] Current TrustedHosts count: $($trustedHosts.Count)"

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Cyan

