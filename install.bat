@echo off
REM ============================================================================
REM  myTech.Today - RMM Client Setup
REM  Checks for PowerShell 7+, installs if needed, then runs the installer
REM ============================================================================
setlocal enabledelayedexpansion

echo.
echo ============================================================
echo   myTech.Today - RMM Client Setup
echo ============================================================
echo.

where pwsh >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [OK] PowerShell 7+ is installed
    goto :RUN_INSTALLER
)

echo [INFO] PowerShell 7+ not found. Checking for winget...

where winget >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] winget is not available on this system.
    echo.
    echo Please install PowerShell 7 manually:
    echo   https://github.com/PowerShell/PowerShell/releases
    echo.
    pause
    exit /b 1
)

echo [INFO] Installing PowerShell 7 using winget...

net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [WARN] Not running as administrator. Requesting elevation...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to install PowerShell 7.
    pause
    exit /b 1
)

echo [OK] PowerShell 7 installed successfully!

:RUN_INSTALLER
echo.
echo [INFO] Running RMM Client Installer...
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-client-windows.ps1" %*

echo.
echo [INFO] Complete.
pause

