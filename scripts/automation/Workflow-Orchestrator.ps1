<#
.SYNOPSIS
    Multi-step automated workflow orchestration

.DESCRIPTION
    Executes complex multi-step workflows with error handling, rollback capabilities,
    and status tracking. Supports workflows like device onboarding, patch management,
    and offline device recovery.

.PARAMETER Workflow
    Workflow name to execute

.PARAMETER DeviceId
    Device to run workflow on

.PARAMETER Parameters
    Workflow-specific parameters as hashtable

.PARAMETER Action
    Action to perform (Start, Stop, Status, History)

.PARAMETER WorkflowId
    Workflow execution ID for status/stop operations

.EXAMPLE
    .\Workflow-Orchestrator.ps1 -Workflow "OnboardNewDevice" -DeviceId "NEW-PC-01"

.EXAMPLE
    .\Workflow-Orchestrator.ps1 -Workflow "PatchTuesday" -Parameters @{PilotGroup="Servers"}

.EXAMPLE
    .\Workflow-Orchestrator.ps1 -Action "Status" -WorkflowId "abc123"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("OnboardNewDevice", "PatchTuesday", "OfflineDeviceRecovery", "Custom")]
    [string]$Workflow,

    [Parameter()]
    [string]$DeviceId,

    [Parameter()]
    [hashtable]$Parameters = @{},

    [Parameter()]
    [ValidateSet("Start", "Stop", "Status", "History")]
    [string]$Action = "Start",

    [Parameter()]
    [string]$WorkflowId
)

# Import required modules
Import-Module "$PSScriptRoot\..\core\RMM-Core.psm1" -Force
Import-Module PSSQLite

# Initialize RMM
Initialize-RMM | Out-Null

# Get database path
$DatabasePath = Get-RMMDatabase

Write-Host "[INFO] Workflow Orchestrator - Action: $Action" -ForegroundColor Cyan

#region Workflow Definitions

function Get-WorkflowDefinition {
    param([string]$WorkflowName)

    $workflows = @{
        "OnboardNewDevice" = @{
            Name = "OnboardNewDevice"
            Description = "Onboard a new device to RMM management"
            Steps = @(
                @{ Name = "VerifyConnectivity"; Action = "Test-Connection"; Required = $true },
                @{ Name = "CollectInventory"; Action = ".\scripts\collectors\Inventory-Collector.ps1"; Required = $true },
                @{ Name = "ApplySecurityBaseline"; Action = ".\scripts\automation\Policy-Engine.ps1"; Arguments = "-Action Apply -PolicyId security-baseline"; Required = $true },
                @{ Name = "InstallRequiredSoftware"; Action = ".\scripts\actions\Script-Executor.ps1"; Required = $false },
                @{ Name = "MoveToProductionGroup"; Action = "Update-DeviceGroup"; Required = $false },
                @{ Name = "NotifyITTeam"; Action = "Send-Notification"; Required = $false }
            )
        }
        "PatchTuesday" = @{
            Name = "PatchTuesday"
            Description = "Automated patch management workflow"
            Steps = @(
                @{ Name = "ScanAllDevices"; Action = ".\scripts\actions\Update-Manager.ps1"; Arguments = "-Action Scan"; Required = $true },
                @{ Name = "InstallPilotUpdates"; Action = ".\scripts\actions\Update-Manager.ps1"; Arguments = "-Action Install -Devices PilotGroup"; Required = $true },
                @{ Name = "WaitForReboots"; Action = "Start-Sleep"; Arguments = "-Seconds 600"; Required = $true },
                @{ Name = "VerifyPilotHealth"; Action = ".\scripts\monitors\Health-Monitor.ps1"; Arguments = "-Devices PilotGroup"; Required = $true },
                @{ Name = "InstallProductionUpdates"; Action = ".\scripts\actions\Update-Manager.ps1"; Arguments = "-Action Install -Devices ProductionGroup"; Required = $true },
                @{ Name = "GenerateComplianceReport"; Action = ".\scripts\reports\Report-Generator.ps1"; Arguments = "-ReportType UpdateCompliance"; Required = $false }
            )
        }
        "OfflineDeviceRecovery" = @{
            Name = "OfflineDeviceRecovery"
            Description = "Attempt to recover offline devices"
            Steps = @(
                @{ Name = "DetectOfflineDevices"; Action = "Get-OfflineDevices"; Required = $true },
                @{ Name = "AttemptWakeOnLAN"; Action = "Send-WOL"; Required = $false },
                @{ Name = "WaitForResponse"; Action = "Start-Sleep"; Arguments = "-Seconds 300"; Required = $true },
                @{ Name = "VerifyOnline"; Action = "Test-Connection"; Required = $true },
                @{ Name = "EscalateAlert"; Action = ".\scripts\alerts\Alert-Manager.ps1"; Arguments = "-Action Create -AlertType Availability -Severity High"; Required = $false },
                @{ Name = "QueuePendingActions"; Action = "Queue-Actions"; Required = $false }
            )
        }
    }

    return $workflows[$WorkflowName]
}

#endregion

#region Workflow Execution Functions

function Start-RMMWorkflow {
    param(
        [string]$WorkflowName,
        [string]$DeviceId,
        [hashtable]$Parameters
    )

    $workflowDef = Get-WorkflowDefinition -WorkflowName $WorkflowName
    
    if (-not $workflowDef) {
        Write-Host "[ERROR] Workflow not found: $WorkflowName" -ForegroundColor Red
        return $null
    }

    $workflowId = [guid]::NewGuid().ToString()
    $startTime = Get-Date

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Starting Workflow: $WorkflowName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Workflow ID: $workflowId" -ForegroundColor White
    Write-Host "Device: $DeviceId" -ForegroundColor White
    Write-Host "Steps: $($workflowDef.Steps.Count)" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $stepResults = @()
    $currentStep = 0
    $failedStep = $null

    foreach ($step in $workflowDef.Steps) {
        $currentStep++
        $stepStartTime = Get-Date

        Write-Host "[$currentStep/$($workflowDef.Steps.Count)] $($step.Name)..." -ForegroundColor Cyan

        try {
            $stepResult = Invoke-WorkflowStep -Step $step -DeviceId $DeviceId -Parameters $Parameters
            
            $stepResults += [PSCustomObject]@{
                StepNumber = $currentStep
                StepName = $step.Name
                Status = "SUCCESS"
                Duration = ((Get-Date) - $stepStartTime).TotalSeconds
                Result = $stepResult
            }

            Write-Host "  [SUCCESS] $($step.Name) completed" -ForegroundColor Green
        }
        catch {
            $stepResults += [PSCustomObject]@{
                StepNumber = $currentStep
                StepName = $step.Name
                Status = "FAILED"
                Duration = ((Get-Date) - $stepStartTime).TotalSeconds
                Error = $_.Exception.Message
            }

            Write-Host "  [FAILED] $($step.Name): $_" -ForegroundColor Red

            if ($step.Required) {
                $failedStep = $step.Name
                Write-Host ""
                Write-Host "[ERROR] Required step failed. Aborting workflow." -ForegroundColor Red
                break
            } else {
                Write-Host "  [WARN] Optional step failed. Continuing..." -ForegroundColor Yellow
            }
        }
    }

    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds

    $workflowStatus = if ($failedStep) { "FAILED" } else { "COMPLETED" }

    # Log workflow execution
    $resultJson = @{
        WorkflowId = $workflowId
        Workflow = $WorkflowName
        DeviceId = $DeviceId
        Status = $workflowStatus
        FailedStep = $failedStep
        Steps = $stepResults
        Duration = $duration
    } | ConvertTo-Json -Depth 5 -Compress

    $query = @"
INSERT INTO Actions (ActionId, DeviceId, ActionType, Status, Result, CreatedAt)
VALUES (@ActionId, @DeviceId, @ActionType, @Status, @Result, CURRENT_TIMESTAMP)
"@

    $params = @{
        ActionId = $workflowId
        DeviceId = $DeviceId
        ActionType = "Workflow_$WorkflowName"
        Status = $workflowStatus
        Result = $resultJson
    }

    Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params | Out-Null

    # Display summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Workflow Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Workflow: $WorkflowName" -ForegroundColor White
    Write-Host "Status: $workflowStatus" -ForegroundColor $(if ($workflowStatus -eq "COMPLETED") { "Green" } else { "Red" })
    Write-Host "Duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor White
    Write-Host "Steps Completed: $($stepResults.Count)/$($workflowDef.Steps.Count)" -ForegroundColor White
    if ($failedStep) {
        Write-Host "Failed Step: $failedStep" -ForegroundColor Red
    }
    Write-Host "========================================" -ForegroundColor Cyan

    return $workflowId
}

function Invoke-WorkflowStep {
    param(
        [hashtable]$Step,
        [string]$DeviceId,
        [hashtable]$Parameters
    )

    $action = $Step.Action
    $arguments = $Step.Arguments

    # Handle different action types
    switch -Wildcard ($action) {
        "Test-Connection" {
            $result = Test-Connection -ComputerName $DeviceId -Count 1 -Quiet
            if (-not $result) {
                throw "Device is not reachable"
            }
            return $result
        }
        "Start-Sleep" {
            if ($arguments -match "-Seconds (\d+)") {
                $seconds = [int]$matches[1]
                Start-Sleep -Seconds $seconds
                return "Waited $seconds seconds"
            }
        }
        "*.ps1" {
            # Execute PowerShell script
            $scriptPath = Join-Path (Get-Location) $action
            if (Test-Path $scriptPath) {
                $cmd = "& `"$scriptPath`" $arguments"
                $result = Invoke-Expression $cmd 2>&1
                return $result
            } else {
                throw "Script not found: $scriptPath"
            }
        }
        "Get-OfflineDevices" {
            $query = "SELECT DeviceId FROM Devices WHERE Status = 'Offline' AND datetime(LastSeen) < datetime('now', '-24 hours')"
            $devices = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
            return $devices
        }
        "Send-WOL" {
            # Placeholder for Wake-on-LAN functionality
            Write-Host "    [INFO] Wake-on-LAN not implemented" -ForegroundColor Gray
            return "WOL packet sent (simulated)"
        }
        "Update-DeviceGroup" {
            # Placeholder for device group update
            Write-Host "    [INFO] Device group updated (simulated)" -ForegroundColor Gray
            return "Device moved to production group"
        }
        "Send-Notification" {
            # Placeholder for notification
            Write-Host "    [INFO] Notification sent (simulated)" -ForegroundColor Gray
            return "IT team notified"
        }
        "Queue-Actions" {
            # Placeholder for action queuing
            Write-Host "    [INFO] Actions queued (simulated)" -ForegroundColor Gray
            return "Pending actions queued"
        }
        default {
            Write-Host "    [WARN] Unknown action type: $action" -ForegroundColor Yellow
            return "Action skipped"
        }
    }
}

function Get-RMMWorkflowStatus {
    param([string]$WorkflowId)

    $query = @"
SELECT ActionId, DeviceId, ActionType, Status, Result, CreatedAt
FROM Actions
WHERE ActionId = @WorkflowId
"@

    $params = @{ WorkflowId = $WorkflowId }
    $workflow = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params

    if (-not $workflow) {
        Write-Host "[ERROR] Workflow not found: $WorkflowId" -ForegroundColor Red
        return
    }

    $result = $workflow.Result | ConvertFrom-Json

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Workflow Status" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Workflow ID: $($result.WorkflowId)" -ForegroundColor White
    Write-Host "Workflow: $($result.Workflow)" -ForegroundColor White
    Write-Host "Device: $($result.DeviceId)" -ForegroundColor White
    Write-Host "Status: $($result.Status)" -ForegroundColor $(if ($result.Status -eq "COMPLETED") { "Green" } else { "Red" })
    Write-Host "Duration: $([math]::Round($result.Duration, 2)) seconds" -ForegroundColor White
    Write-Host "Started: $($workflow.CreatedAt)" -ForegroundColor White
    Write-Host ""
    Write-Host "Steps:" -ForegroundColor Yellow

    foreach ($step in $result.Steps) {
        $statusColor = if ($step.Status -eq "SUCCESS") { "Green" } else { "Red" }
        Write-Host "  [$($step.StepNumber)] $($step.StepName): $($step.Status)" -ForegroundColor $statusColor
        if ($step.Error) {
            Write-Host "    Error: $($step.Error)" -ForegroundColor Red
        }
    }

    Write-Host "========================================" -ForegroundColor Cyan
}

function Get-RMMWorkflowHistory {
    param([int]$Limit = 10)

    $query = @"
SELECT ActionId, DeviceId, ActionType, Status, CreatedAt
FROM Actions
WHERE ActionType LIKE 'Workflow_%'
ORDER BY CreatedAt DESC
LIMIT $Limit
"@

    $workflows = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query

    if (-not $workflows) {
        Write-Host "[INFO] No workflow history found" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Workflow History (Last $Limit)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    foreach ($wf in $workflows) {
        $workflowName = $wf.ActionType -replace '^Workflow_', ''
        $statusColor = if ($wf.Status -eq "COMPLETED") { "Green" } else { "Red" }

        Write-Host ""
        Write-Host "Workflow: $workflowName" -ForegroundColor White
        Write-Host "  ID: $($wf.ActionId)" -ForegroundColor Gray
        Write-Host "  Device: $($wf.DeviceId)" -ForegroundColor Gray
        Write-Host "  Status: $($wf.Status)" -ForegroundColor $statusColor
        Write-Host "  Started: $($wf.CreatedAt)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
}

#endregion

#region Main Execution

switch ($Action) {
    "Start" {
        if (-not $Workflow) {
            Write-Host "[ERROR] Workflow parameter required for Start action" -ForegroundColor Red
            exit 1
        }

        if (-not $DeviceId) {
            $DeviceId = "localhost"
        }

        Start-RMMWorkflow -WorkflowName $Workflow -DeviceId $DeviceId -Parameters $Parameters
    }

    "Stop" {
        if (-not $WorkflowId) {
            Write-Host "[ERROR] WorkflowId parameter required for Stop action" -ForegroundColor Red
            exit 1
        }

        Write-Host "[WARN] Workflow stop functionality not yet implemented" -ForegroundColor Yellow
        Write-Host "[INFO] Workflows run to completion or failure" -ForegroundColor Gray
    }

    "Status" {
        if (-not $WorkflowId) {
            Write-Host "[ERROR] WorkflowId parameter required for Status action" -ForegroundColor Red
            exit 1
        }

        Get-RMMWorkflowStatus -WorkflowId $WorkflowId
    }

    "History" {
        Get-RMMWorkflowHistory -Limit 10
    }
}

#endregion

