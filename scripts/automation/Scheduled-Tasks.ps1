<#
.SYNOPSIS
    Manage RMM scheduled operations

.DESCRIPTION
    Creates, manages, and monitors Windows scheduled tasks for RMM operations including
    availability checks, health metrics, inventory scans, update scans, security scans,
    report generation, and database maintenance.

.PARAMETER Action
    Action to perform (RegisterAll, Register, Unregister, List, Start, Status)

.PARAMETER TaskName
    Specific task name to work with

.PARAMETER Interval
    Interval for the task (in minutes for frequent tasks)

.EXAMPLE
    .\Scheduled-Tasks.ps1 -Action "RegisterAll"

.EXAMPLE
    .\Scheduled-Tasks.ps1 -Action "Register" -TaskName "RMM-AvailabilityCheck"

.EXAMPLE
    .\Scheduled-Tasks.ps1 -Action "List"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("RegisterAll", "Register", "Unregister", "List", "Start", "Status")]
    [string]$Action = "List",

    [Parameter()]
    [string]$TaskName,

    [Parameter()]
    [int]$Interval
)

# Import required modules
Import-Module "$PSScriptRoot\..\core\RMM-Core.psm1" -Force

# Initialize RMM
Initialize-RMM | Out-Null

Write-Host "[INFO] Scheduled Tasks Manager - Action: $Action" -ForegroundColor Cyan

#region Task Definitions

$RMMTasks = @(
    @{
        Name = "RMM-AvailabilityCheck"
        Description = "Check device availability every 5 minutes"
        ScriptPath = ".\scripts\monitors\Availability-Monitor.ps1"
        Interval = 5  # minutes
        Type = "Recurring"
    },
    @{
        Name = "RMM-HealthMetrics"
        Description = "Collect health metrics every 5 minutes"
        ScriptPath = ".\scripts\monitors\Health-Monitor.ps1"
        Interval = 5  # minutes
        Type = "Recurring"
    },
    @{
        Name = "RMM-PerformanceMetrics"
        Description = "Collect performance metrics every 5 minutes"
        ScriptPath = ".\scripts\monitors\Performance-Monitor.ps1"
        Interval = 5  # minutes
        Type = "Recurring"
    },
    @{
        Name = "RMM-FullInventory"
        Description = "Complete inventory scan daily at 2 AM"
        ScriptPath = ".\scripts\collectors\Inventory-Collector.ps1"
        Schedule = "Daily"
        Time = "02:00"
        Type = "Daily"
    },
    @{
        Name = "RMM-UpdateScan"
        Description = "Check for available updates daily at 3 AM"
        ScriptPath = ".\scripts\actions\Update-Manager.ps1"
        Arguments = "-Action Scan"
        Schedule = "Daily"
        Time = "03:00"
        Type = "Daily"
    },
    @{
        Name = "RMM-SecurityScan"
        Description = "Security posture check daily at 4 AM"
        ScriptPath = ".\scripts\collectors\Security-Scanner.ps1"
        Schedule = "Daily"
        Time = "04:00"
        Type = "Daily"
    },
    @{
        Name = "RMM-DataCleanup"
        Description = "Prune old data daily at 5 AM"
        ScriptPath = ".\scripts\maintenance\Data-Cleanup.ps1"
        Schedule = "Daily"
        Time = "05:00"
        Type = "Daily"
    },
    @{
        Name = "RMM-WeeklyReports"
        Description = "Generate weekly reports on Sunday at 6 AM"
        ScriptPath = ".\scripts\reports\Report-Generator.ps1"
        Arguments = "-ReportType ExecutiveSummary"
        Schedule = "Weekly"
        DayOfWeek = "Sunday"
        Time = "06:00"
        Type = "Weekly"
    },
    @{
        Name = "RMM-DatabaseMaintenance"
        Description = "Vacuum and optimize database weekly on Sunday at 3 AM"
        ScriptPath = ".\scripts\maintenance\Database-Maintenance.ps1"
        Schedule = "Weekly"
        DayOfWeek = "Sunday"
        Time = "03:00"
        Type = "Weekly"
    }
)

#endregion

#region Task Management Functions

function Register-RMMScheduledTask {
    param(
        [hashtable]$TaskDefinition
    )

    $taskName = $TaskDefinition.Name
    $scriptPath = Join-Path (Get-Location) $TaskDefinition.ScriptPath
    
    # Check if script exists
    if (-not (Test-Path $scriptPath)) {
        Write-Host "[WARN] Script not found: $scriptPath - Skipping task registration" -ForegroundColor Yellow
        return $false
    }

    # Check if task already exists
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "[INFO] Task '$taskName' already exists. Unregistering..." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    try {
        # Build PowerShell command
        $arguments = if ($TaskDefinition.Arguments) {
            $TaskDefinition.Arguments
        } else {
            ""
        }
        
        $command = "powershell.exe"
        $commandArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments"

        # Create action
        $taskAction = New-ScheduledTaskAction -Execute $command -Argument $commandArgs -WorkingDirectory (Get-Location)

        # Create trigger based on type
        $taskTrigger = switch ($TaskDefinition.Type) {
            "Recurring" {
                $interval = New-TimeSpan -Minutes $TaskDefinition.Interval
                New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval $interval -RepetitionDuration ([TimeSpan]::MaxValue)
            }
            "Daily" {
                New-ScheduledTaskTrigger -Daily -At $TaskDefinition.Time
            }
            "Weekly" {
                New-ScheduledTaskTrigger -Weekly -DaysOfWeek $TaskDefinition.DayOfWeek -At $TaskDefinition.Time
            }
        }

        # Create settings
        $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        # Register task
        Register-ScheduledTask -TaskName $taskName `
                               -Action $taskAction `
                               -Trigger $taskTrigger `
                               -Settings $taskSettings `
                               -Description $TaskDefinition.Description `
                               -User "SYSTEM" `
                               -RunLevel Highest `
                               -Force | Out-Null

        Write-Host "[SUCCESS] Registered task: $taskName" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[ERROR] Failed to register task '$taskName': $_" -ForegroundColor Red
        return $false
    }
}

function Unregister-RMMScheduledTask {
    param([string]$TaskName)

    try {
        Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[SUCCESS] Unregistered task: $TaskName" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[ERROR] Failed to unregister task '$TaskName': $_" -ForegroundColor Red
        return $false
    }
}

function Get-RMMScheduledTask {
    param([string]$TaskName)

    if ($TaskName) {
        $tasks = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    } else {
        $tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "RMM-*" }
    }

    return $tasks
}

function Start-RMMScheduledTask {
    param([string]$TaskName)

    try {
        Start-ScheduledTask -TaskName $TaskName
        Write-Host "[SUCCESS] Started task: $TaskName" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[ERROR] Failed to start task '$TaskName': $_" -ForegroundColor Red
        return $false
    }
}

function Get-RMMScheduledTaskStatus {
    param([string]$TaskName)

    $tasks = if ($TaskName) {
        Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    } else {
        Get-ScheduledTask | Where-Object { $_.TaskName -like "RMM-*" }
    }

    if (-not $tasks) {
        Write-Host "[WARN] No RMM tasks found" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  RMM Scheduled Tasks Status" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    foreach ($task in $tasks) {
        $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName

        $statusColor = switch ($task.State) {
            "Ready" { "Green" }
            "Running" { "Cyan" }
            "Disabled" { "Yellow" }
            default { "Red" }
        }

        Write-Host ""
        Write-Host "Task: $($task.TaskName)" -ForegroundColor White
        Write-Host "  State: $($task.State)" -ForegroundColor $statusColor
        Write-Host "  Last Run: $($taskInfo.LastRunTime)" -ForegroundColor Gray
        Write-Host "  Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
        Write-Host "  Next Run: $($taskInfo.NextRunTime)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
}

#endregion

#region Main Execution

switch ($Action) {
    "RegisterAll" {
        Write-Host "[INFO] Registering all RMM scheduled tasks..." -ForegroundColor Cyan

        $successCount = 0
        $failCount = 0

        foreach ($taskDef in $RMMTasks) {
            if (Register-RMMScheduledTask -TaskDefinition $taskDef) {
                $successCount++
            } else {
                $failCount++
            }
        }

        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  Registration Summary" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Total Tasks: $($RMMTasks.Count)" -ForegroundColor White
        Write-Host "Registered: $successCount" -ForegroundColor Green
        Write-Host "Failed: $failCount" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Cyan
    }

    "Register" {
        if (-not $TaskName) {
            Write-Host "[ERROR] TaskName parameter required for Register action" -ForegroundColor Red
            exit 1
        }

        $taskDef = $RMMTasks | Where-Object { $_.Name -eq $TaskName } | Select-Object -First 1

        if (-not $taskDef) {
            Write-Host "[ERROR] Task definition not found: $TaskName" -ForegroundColor Red
            Write-Host "[INFO] Available tasks:" -ForegroundColor Gray
            $RMMTasks | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
            exit 1
        }

        Register-RMMScheduledTask -TaskDefinition $taskDef
    }

    "Unregister" {
        if (-not $TaskName) {
            Write-Host "[ERROR] TaskName parameter required for Unregister action" -ForegroundColor Red
            exit 1
        }

        Unregister-RMMScheduledTask -TaskName $TaskName
    }

    "List" {
        $tasks = Get-RMMScheduledTask

        if (-not $tasks) {
            Write-Host "[INFO] No RMM scheduled tasks found" -ForegroundColor Yellow
            Write-Host "[INFO] Run with -Action RegisterAll to create default tasks" -ForegroundColor Gray
        } else {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "  RMM Scheduled Tasks" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan

            foreach ($task in $tasks) {
                Write-Host "$($task.TaskName) - $($task.State)" -ForegroundColor White
            }

            Write-Host ""
            Write-Host "Total: $($tasks.Count) tasks" -ForegroundColor Gray
            Write-Host "========================================" -ForegroundColor Cyan
        }
    }

    "Start" {
        if (-not $TaskName) {
            Write-Host "[ERROR] TaskName parameter required for Start action" -ForegroundColor Red
            exit 1
        }

        Start-RMMScheduledTask -TaskName $TaskName
    }

    "Status" {
        Get-RMMScheduledTaskStatus -TaskName $TaskName
    }
}

#endregion

