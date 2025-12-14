<#
.SYNOPSIS
    Central alert processing and lifecycle management.

.DESCRIPTION
    Manages alert lifecycle from creation to resolution, including deduplication,
    correlation, acknowledgment, and auto-resolution.

.PARAMETER Action
    Action to perform: Create, Get, Acknowledge, Resolve, Archive, Correlate

.PARAMETER AlertId
    Alert ID for Get, Acknowledge, or Resolve actions.

.PARAMETER DeviceId
    Device ID for creating alerts or filtering.

.PARAMETER AlertType
    Type of alert (e.g., Performance, Security, Availability, Health).

.PARAMETER Severity
    Alert severity: Critical, High, Medium, Low, Info

.PARAMETER Title
    Alert title (required for Create action).

.PARAMETER Message
    Alert message/description.

.PARAMETER Source
    Source that generated the alert (e.g., script name).

.PARAMETER AutoResolve
    Automatically resolve alert when condition clears.

.EXAMPLE
    .\Alert-Manager.ps1 -Action "Create" -DeviceId "localhost" -AlertType "Performance" -Severity "High" -Title "High CPU Usage" -Message "CPU at 95%"

.EXAMPLE
    .\Alert-Manager.ps1 -Action "Get" -Severity "Critical"

.EXAMPLE
    .\Alert-Manager.ps1 -Action "Acknowledge" -AlertId "alert-123"

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+, PSSQLite module
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Create', 'Get', 'Acknowledge', 'Resolve', 'Archive', 'Correlate')]
    [string]$Action,

    [Parameter()]
    [string]$AlertId,

    [Parameter()]
    [string]$DeviceId,

    [Parameter()]
    [ValidateSet('Performance', 'Security', 'Availability', 'Health', 'Compliance', 'Update', 'Custom')]
    [string]$AlertType,

    [Parameter()]
    [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')]
    [string]$Severity,

    [Parameter()]
    [string]$Title,

    [Parameter()]
    [string]$Message,

    [Parameter()]
    [string]$Source,

    [Parameter()]
    [switch]$AutoResolve,

    [Parameter()]
    [string]$AcknowledgedBy,

    [Parameter()]
    [string]$ResolvedBy,

    [Parameter()]
    [int]$DaysToArchive = 30,

    [Parameter()]
    [string]$DatabasePath
)

# Import required modules
$ErrorActionPreference = 'Stop'

try {
    $rmmCorePath = Join-Path $PSScriptRoot "..\core\RMM-Core.psm1"
    if (-not (Get-Module -Name RMM-Core)) {
        Import-Module $rmmCorePath -Force
    }

    if (-not (Get-Module -Name PSSQLite)) {
        Import-Module PSSQLite -ErrorAction Stop
    }
}
catch {
    Write-Error "Failed to import required modules: $_"
    exit 1
}

# Initialize RMM
Initialize-RMM -ErrorAction Stop

# Get database path
if (-not $DatabasePath) {
    $DatabasePath = Get-RMMDatabase
}

# Alert management functions
function New-RMMAlert {
    param($DeviceId, $AlertType, $Severity, $Title, $Message, $Source, $AutoResolve)

    # Check for duplicate alerts (same type + device within 5 minutes)
    $duplicateCheck = @"
SELECT AlertId, CreatedAt FROM Alerts
WHERE DeviceId = @DeviceId
  AND AlertType = @AlertType
  AND Title = @Title
  AND ResolvedAt IS NULL
  AND datetime(CreatedAt) > datetime('now', '-5 minutes')
ORDER BY CreatedAt DESC
LIMIT 1
"@
    $duplicateParams = @{
        DeviceId  = $DeviceId
        AlertType = $AlertType
        Title     = $Title
    }
    $duplicate = Invoke-SqliteQuery -DataSource $DatabasePath -Query $duplicateCheck -SqlParameters $duplicateParams

    if ($duplicate) {
        Write-Host "[DEDUPLICATED] Alert already exists (created $($duplicate.CreatedAt))" -ForegroundColor Yellow
        return $duplicate.AlertId
    }

    # Create new alert
    $alertId = [guid]::NewGuid().ToString()
    $query = @"
INSERT INTO Alerts (AlertId, DeviceId, AlertType, Severity, Title, Message, Source, AutoResolved, CreatedAt)
VALUES (@AlertId, @DeviceId, @AlertType, @Severity, @Title, @Message, @Source, @AutoResolved, CURRENT_TIMESTAMP)
"@
    $params = @{
        AlertId      = $alertId
        DeviceId     = $DeviceId
        AlertType    = $AlertType
        Severity     = $Severity
        Title        = $Title
        Message      = $Message
        Source       = $Source
        AutoResolved = if ($AutoResolve) { 1 } else { 0 }
    }

    Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params

    Write-Host "[CREATED] Alert $alertId - $Title" -ForegroundColor Green
    return $alertId
}

function Get-RMMAlert {
    param($AlertId, $DeviceId, $AlertType, $Severity, $Resolved)

    $query = "SELECT * FROM Alerts WHERE 1=1"
    $params = @{}

    if ($AlertId) {
        $query += " AND AlertId = @AlertId"
        $params.AlertId = $AlertId
    }
    if ($DeviceId) {
        $query += " AND DeviceId = @DeviceId"
        $params.DeviceId = $DeviceId
    }
    if ($AlertType) {
        $query += " AND AlertType = @AlertType"
        $params.AlertType = $AlertType
    }
    if ($Severity) {
        $query += " AND Severity = @Severity"
        $params.Severity = $Severity
    }
    if ($PSBoundParameters.ContainsKey('Resolved')) {
        if ($Resolved) {
            $query += " AND ResolvedAt IS NOT NULL"
        }
        else {
            $query += " AND ResolvedAt IS NULL"
        }
    }

    $query += " ORDER BY CreatedAt DESC"

    if ($params.Count -gt 0) {
        return Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params
    }
    else {
        return Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
    }
}

function Set-RMMAlertAcknowledged {
    param($AlertId, $AcknowledgedBy)

    $query = @"
UPDATE Alerts
SET AcknowledgedAt = CURRENT_TIMESTAMP,
    AcknowledgedBy = @AcknowledgedBy
WHERE AlertId = @AlertId
"@
    $params = @{
        AlertId        = $AlertId
        AcknowledgedBy = $AcknowledgedBy
    }

    Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params
    Write-Host "[ACKNOWLEDGED] Alert $AlertId by $AcknowledgedBy" -ForegroundColor Green
}

function Set-RMMAlertResolved {
    param($AlertId, $ResolvedBy, $AutoResolved)

    $query = @"
UPDATE Alerts
SET ResolvedAt = CURRENT_TIMESTAMP,
    ResolvedBy = @ResolvedBy,
    AutoResolved = @AutoResolved
WHERE AlertId = @AlertId
"@
    $params = @{
        AlertId      = $AlertId
        ResolvedBy   = $ResolvedBy
        AutoResolved = if ($AutoResolved) { 1 } else { 0 }
    }

    Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params

    $resolveType = if ($AutoResolved) { "AUTO-RESOLVED" } else { "RESOLVED" }
    Write-Host "[$resolveType] Alert $AlertId" -ForegroundColor Green
}

function Remove-RMMAlert {
    param($DaysToArchive)

    $query = @"
DELETE FROM Alerts
WHERE ResolvedAt IS NOT NULL
  AND datetime(ResolvedAt) < datetime('now', '-$DaysToArchive days')
"@
    Invoke-SqliteQuery -DataSource $DatabasePath -Query $query | Out-Null
    Write-Host "[ARCHIVED] Removed alerts older than $DaysToArchive days" -ForegroundColor Green
}

function Get-RMMAlertCorrelation {
    param($DeviceId, $TimeWindow = 15)

    # Find related alerts on the same device within time window
    $query = @"
SELECT AlertType, COUNT(*) as Count, MAX(Severity) as MaxSeverity
FROM Alerts
WHERE DeviceId = @DeviceId
  AND ResolvedAt IS NULL
  AND datetime(CreatedAt) > datetime('now', '-$TimeWindow minutes')
GROUP BY AlertType
HAVING Count > 1
"@
    $params = @{ DeviceId = $DeviceId }

    $correlations = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params

    if ($correlations) {
        Write-Host "[CORRELATION] Found related alerts on device ${DeviceId}:" -ForegroundColor Yellow
        foreach ($corr in $correlations) {
            Write-Host "  - $($corr.AlertType): $($corr.Count) alerts (Max: $($corr.MaxSeverity))" -ForegroundColor Gray
        }
    }

    return $correlations
}

# Execute action
switch ($Action) {
    'Create' {
        if (-not $DeviceId -or -not $AlertType -or -not $Severity -or -not $Title) {
            Write-Error "DeviceId, AlertType, Severity, and Title are required for Create action"
            exit 1
        }
        $alertId = New-RMMAlert -DeviceId $DeviceId -AlertType $AlertType -Severity $Severity -Title $Title -Message $Message -Source $Source -AutoResolve $AutoResolve

        # Check for correlations
        Get-RMMAlertCorrelation -DeviceId $DeviceId | Out-Null
    }
    'Get' {
        $alerts = Get-RMMAlert -AlertId $AlertId -DeviceId $DeviceId -AlertType $AlertType -Severity $Severity -Resolved:$false

        if ($alerts) {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "  Active Alerts" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            foreach ($alert in $alerts) {
                $color = switch ($alert.Severity) {
                    'Critical' { 'Red' }
                    'High' { 'Yellow' }
                    'Medium' { 'White' }
                    'Low' { 'Gray' }
                    'Info' { 'Cyan' }
                }
                Write-Host "[$($alert.Severity)] $($alert.Title)" -ForegroundColor $color
                Write-Host "  Device: $($alert.DeviceId) | Type: $($alert.AlertType) | Created: $($alert.CreatedAt)" -ForegroundColor Gray
                if ($alert.Message) {
                    Write-Host "  Message: $($alert.Message)" -ForegroundColor Gray
                }
                if ($alert.AcknowledgedAt) {
                    Write-Host "  Acknowledged: $($alert.AcknowledgedAt) by $($alert.AcknowledgedBy)" -ForegroundColor Green
                }
                Write-Host ""
            }
            Write-Host "Total Alerts: $($alerts.Count)" -ForegroundColor Cyan
        }
        else {
            Write-Host "[INFO] No alerts found matching criteria" -ForegroundColor Cyan
        }
    }
    'Acknowledge' {
        if (-not $AlertId) {
            Write-Error "AlertId is required for Acknowledge action"
            exit 1
        }
        if (-not $AcknowledgedBy) {
            $AcknowledgedBy = $env:USERNAME
        }
        Set-RMMAlertAcknowledged -AlertId $AlertId -AcknowledgedBy $AcknowledgedBy
    }
    'Resolve' {
        if (-not $AlertId) {
            Write-Error "AlertId is required for Resolve action"
            exit 1
        }
        if (-not $ResolvedBy) {
            $ResolvedBy = $env:USERNAME
        }
        Set-RMMAlertResolved -AlertId $AlertId -ResolvedBy $ResolvedBy -AutoResolved:$AutoResolve
    }
    'Archive' {
        Remove-RMMAlert -DaysToArchive $DaysToArchive
    }
    'Correlate' {
        if (-not $DeviceId) {
            Write-Error "DeviceId is required for Correlate action"
            exit 1
        }
        Get-RMMAlertCorrelation -DeviceId $DeviceId
    }
}
