<#
.SYNOPSIS
    Uninstalls myTech.Today RMM from this computer.

.DESCRIPTION
    Removes the RMM installation including:
    - PowerShell module registration
    - Desktop and Start Menu shortcuts
    - RMM program files (from Program Files)

    By default, preserves user data (database, logs, config in ProgramData).
    Use -RemoveData to also remove all data.

    Supports both new standard paths and legacy user-profile paths.

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
    Version: 2.1.0
#>

[CmdletBinding()]
param(
    [switch]$RemoveData,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

#region Path Configuration
# New standard paths (Microsoft best practices)
$ProgramFilesRoot = "${env:ProgramFiles(x86)}\myTech.Today"
$RMMInstallPath = "$ProgramFilesRoot\RMM"
$RMMClientPath = "$ProgramFilesRoot\RMM-Client"
$ProgramDataRoot = "$env:ProgramData\myTech.Today"
$RMMDataPath = "$ProgramDataRoot\RMM"
$RMMClientDataPath = "$ProgramDataRoot\RMM-Client"
$ModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules\RMM"

# Legacy paths (for migration cleanup)
$LegacyInstallRoot = "$env:USERPROFILE\myTech.Today"
$LegacyModulePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Modules\RMM"
$LegacyModulePath2 = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "WindowsPowerShell\Modules\RMM"

# Shortcut locations
$PublicDesktop = "$env:PUBLIC\Desktop"
$StartMenuAllUsers = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\myTech.Today"
$StartMenuCurrentUser = Join-Path ([Environment]::GetFolderPath('StartMenu')) "Programs\myTech.Today"
#endregion

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

# Step 1: Stop any running dashboard and clear module cache
Write-Step "1/7" "Stopping RMM services and clearing module cache..."
Get-Process -Name pwsh, powershell -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*Start-WebDashboard*" -or $_.CommandLine -like "*RMM-Client*" } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Write-OK "Services stopped"

# Remove cached module from current PowerShell session
if (Get-Module -Name RMM -ErrorAction SilentlyContinue) {
    Remove-Module -Name RMM -Force -ErrorAction SilentlyContinue
    Write-OK "RMM module unloaded from current session"
}

# Clear PowerShell module analysis cache to prevent stale module loading
$moduleAnalysisCache = "$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\ModuleAnalysisCache"
if (Test-Path $moduleAnalysisCache) {
    Remove-Item -Path $moduleAnalysisCache -Force -ErrorAction SilentlyContinue
    Write-OK "Module analysis cache cleared"
}

# Step 2: Remove shortcuts
Write-Step "2/7" "Removing shortcuts..."

# Public Desktop shortcuts
$dashboardShortcut = Join-Path $PublicDesktop "mTT RMM Dashboard.lnk"
$clientShortcut = Join-Path $PublicDesktop "mTT RMM Client.lnk"
foreach ($shortcut in @($dashboardShortcut, $clientShortcut)) {
    if (Test-Path $shortcut) {
        Remove-Item -Path $shortcut -Force
        Write-OK "Removed: $shortcut"
    }
}

# Current user desktop (legacy)
$userDesktop = [Environment]::GetFolderPath('Desktop')
$userDashboardShortcut = Join-Path $userDesktop "mTT RMM Dashboard.lnk"
if (Test-Path $userDashboardShortcut) {
    Remove-Item -Path $userDashboardShortcut -Force
    Write-OK "Removed user desktop shortcut"
}

# Start Menu folders
if (Test-Path $StartMenuAllUsers) {
    Remove-Item -Path $StartMenuAllUsers -Recurse -Force
    Write-OK "Start Menu folder removed (All Users)"
}

if (Test-Path $StartMenuCurrentUser) {
    Remove-Item -Path $StartMenuCurrentUser -Recurse -Force
    Write-OK "Start Menu folder removed (Current User)"
}

# Step 3: Remove module registration
Write-Step "3/7" "Removing PowerShell module..."
foreach ($modPath in @($ModulePath, $LegacyModulePath, $LegacyModulePath2)) {
    if (Test-Path $modPath) {
        Remove-Item -Path $modPath -Recurse -Force
        Write-OK "Module removed: $modPath"
    }
}

# Step 4: Remove RMM program files (Program Files)
Write-Step "4/7" "Removing RMM program files..."
if (Test-Path $RMMInstallPath) {
    Remove-Item -Path $RMMInstallPath -Recurse -Force
    Write-OK "RMM removed: $RMMInstallPath"
}
if (Test-Path $RMMClientPath) {
    Remove-Item -Path $RMMClientPath -Recurse -Force
    Write-OK "RMM Client removed: $RMMClientPath"
}
# Clean up parent folder if empty
if ((Test-Path $ProgramFilesRoot) -and ((Get-ChildItem $ProgramFilesRoot -Force | Measure-Object).Count -eq 0)) {
    Remove-Item -Path $ProgramFilesRoot -Force
    Write-Info "Removed empty folder: $ProgramFilesRoot"
}

# Step 5: Remove legacy installation (user profile)
Write-Step "5/7" "Removing legacy installation..."
if (Test-Path $LegacyInstallRoot) {
    if ($RemoveData) {
        Remove-Item -Path $LegacyInstallRoot -Recurse -Force
        Write-OK "Legacy installation removed: $LegacyInstallRoot"
    } else {
        # Only remove program files, keep data
        $legacyRMM = Join-Path $LegacyInstallRoot "RMM"
        if (Test-Path $legacyRMM) {
            # Keep data folders, remove scripts
            Get-ChildItem $legacyRMM -Directory | Where-Object { $_.Name -notin @('data', 'logs', 'config') } | Remove-Item -Recurse -Force
            Write-Info "Legacy program files removed, data preserved"
        }
    }
} else {
    Write-Info "No legacy installation found"
}

# Step 6: Handle user data (ProgramData)
Write-Step "6/7" "User data..."
if ($RemoveData) {
    if (Test-Path $RMMDataPath) {
        Remove-Item -Path $RMMDataPath -Recurse -Force
        Write-OK "RMM data removed: $RMMDataPath"
    }
    if (Test-Path $RMMClientDataPath) {
        Remove-Item -Path $RMMClientDataPath -Recurse -Force
        Write-OK "Client data removed: $RMMClientDataPath"
    }
    # Clean up parent folder if empty
    if ((Test-Path $ProgramDataRoot) -and ((Get-ChildItem $ProgramDataRoot -Force | Measure-Object).Count -eq 0)) {
        Remove-Item -Path $ProgramDataRoot -Force
        Write-Info "Removed empty folder: $ProgramDataRoot"
    }
} else {
    Write-Info "Data preserved at: $ProgramDataRoot"
    Write-Host ""
    Write-Host "To completely remove all data, run:" -ForegroundColor Yellow
    Write-Host "  .\uninstall-server-windows.ps1 -RemoveData -Force" -ForegroundColor White
    Write-Host ""
    Write-Host "Or manually delete:" -ForegroundColor Gray
    Write-Host "  $ProgramDataRoot" -ForegroundColor Gray
    if (Test-Path $LegacyInstallRoot) {
        Write-Host "  $LegacyInstallRoot" -ForegroundColor Gray
    }
}

# Step 7: Final cleanup verification
Write-Step "7/7" "Verifying cleanup..."
$remainingItems = @()
if (Test-Path $RMMInstallPath) { $remainingItems += $RMMInstallPath }
if (Test-Path $ModulePath) { $remainingItems += $ModulePath }
if ($remainingItems.Count -eq 0) {
    Write-OK "All RMM server components removed successfully"
} else {
    Write-Host "  [!] Some items could not be removed:" -ForegroundColor Yellow
    $remainingItems | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Uninstall Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

