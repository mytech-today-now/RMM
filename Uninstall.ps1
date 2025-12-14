<#
.SYNOPSIS
    Uninstalls myTech.Today RMM from this computer.

.DESCRIPTION
    Removes the RMM installation including:
    - PowerShell module registration
    - Desktop and Start Menu shortcuts
    - RMM program files
    
    By default, preserves user data (database, logs, config).
    Use -RemoveData to also remove all data.

.PARAMETER RemoveData
    Also removes all user data including database, logs, and configuration.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Uninstall.ps1
    Uninstalls RMM, preserving user data.

.EXAMPLE
    .\Uninstall.ps1 -RemoveData
    Completely removes RMM and all associated data.

.EXAMPLE
    .\Uninstall.ps1 -Force
    Uninstalls without confirmation prompts.

.NOTES
    Author: myTech.Today
    Version: 2.0.0
#>

[CmdletBinding()]
param(
    [switch]$RemoveData,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Paths
$InstallRoot = Join-Path $env:USERPROFILE "myTech.Today"
$RMMInstallPath = Join-Path $InstallRoot "RMM"
$ModulePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Modules\RMM"

function Write-Step { param($Step, $Message) Write-Host "[$Step] $Message" -ForegroundColor Cyan }
function Write-OK { param($Message) Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "  [i] $Message" -ForegroundColor Gray }

Write-Host ""
Write-Host "========================================" -ForegroundColor Red
Write-Host "  myTech.Today RMM - Uninstaller" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host ""

if (-not $Force) {
    $dataWarning = if ($RemoveData) { " AND ALL DATA" } else { "" }
    Write-Host "This will remove the RMM installation$dataWarning from this computer." -ForegroundColor Yellow
    $confirm = Read-Host "Are you sure you want to continue? (Y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Uninstall cancelled." -ForegroundColor Gray
        exit 0
    }
}

# Step 1: Stop any running dashboard
Write-Step "1/5" "Stopping RMM services..."
Get-Process -Name pwsh, powershell -ErrorAction SilentlyContinue | 
    Where-Object { $_.CommandLine -like "*Start-WebDashboard*" } | 
    Stop-Process -Force -ErrorAction SilentlyContinue
Write-OK "Services stopped"

# Step 2: Remove shortcuts
Write-Step "2/5" "Removing shortcuts..."
$desktopPath = [Environment]::GetFolderPath('Desktop')
$desktopShortcut = Join-Path $desktopPath "myTech.Today RMM Dashboard.lnk"
if (Test-Path $desktopShortcut) {
    Remove-Item -Path $desktopShortcut -Force
    Write-OK "Desktop shortcut removed"
} else {
    Write-Info "Desktop shortcut not found"
}

$startMenuAllUsers = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\myTech.Today"
if (Test-Path $startMenuAllUsers) {
    Remove-Item -Path $startMenuAllUsers -Recurse -Force
    Write-OK "Start Menu folder removed (All Users)"
}

$startMenuCurrentUser = Join-Path ([Environment]::GetFolderPath('StartMenu')) "Programs\myTech.Today"
if (Test-Path $startMenuCurrentUser) {
    Remove-Item -Path $startMenuCurrentUser -Recurse -Force
    Write-OK "Start Menu folder removed (Current User)"
}

# Step 3: Remove module registration
Write-Step "3/5" "Removing PowerShell module..."
if (Test-Path $ModulePath) {
    Remove-Item -Path $ModulePath -Recurse -Force
    Write-OK "Module removed from: $ModulePath"
} else {
    Write-Info "Module not found (already removed)"
}

# Step 4: Remove RMM program files
Write-Step "4/5" "Removing RMM installation..."
if (Test-Path $RMMInstallPath) {
    Remove-Item -Path $RMMInstallPath -Recurse -Force
    Write-OK "RMM removed from: $RMMInstallPath"
} else {
    Write-Info "RMM folder not found (already removed)"
}

# Step 5: Handle user data
Write-Step "5/5" "User data..."
if ($RemoveData) {
    if (Test-Path $InstallRoot) {
        Remove-Item -Path $InstallRoot -Recurse -Force
        Write-OK "All data removed from: $InstallRoot"
    }
} else {
    Write-Info "Data preserved at: $InstallRoot"
    Write-Host ""
    Write-Host "To completely remove all data, run:" -ForegroundColor Yellow
    Write-Host "  .\Uninstall.ps1 -RemoveData" -ForegroundColor White
    Write-Host ""
    Write-Host "Or manually delete: $InstallRoot" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Uninstall Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

