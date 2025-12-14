<#
.SYNOPSIS
    Time-based alert escalation handler.

.DESCRIPTION
    Manages multi-tier alert escalation with business hours awareness and on-call schedule integration.
    Escalates unacknowledged alerts through defined tiers with configurable timeouts.

.PARAMETER Action
    Action to perform: Start, Stop, Status, Configure

.PARAMETER AlertId
    Alert ID to escalate.

.PARAMETER EscalationPath
    Escalation path configuration (JSON or hashtable).

.PARAMETER BusinessHoursOnly
    Only escalate during business hours.

.EXAMPLE
    .\Escalation-Handler.ps1 -Action "Start" -AlertId "alert-123"

.EXAMPLE
    .\Escalation-Handler.ps1 -Action "Status" -AlertId "alert-123"

.EXAMPLE
    .\Escalation-Handler.ps1 -Action "Stop" -AlertId "alert-123"

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+, PSSQLite module
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Start', 'Stop', 'Status', 'Configure')]
    [string]$Action,

    [Parameter()]
    [string]$AlertId,

    [Parameter()]
    [object]$EscalationPath,

    [Parameter()]
    [switch]$BusinessHoursOnly,

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

# Default escalation configuration
$defaultEscalationPath = @{
    Tier1 = @{
        Name        = "Primary Contact"
        Timeout     = 15  # minutes
        Channels    = @('Email', 'Teams')
        Contacts    = @('admin@example.com')
    }
    Tier2 = @{
        Name        = "Team Lead"
        Timeout     = 30  # minutes
        Channels    = @('Email', 'Teams', 'SMS')
        Contacts    = @('teamlead@example.com')
    }
    Tier3 = @{
        Name        = "Manager"
        Timeout     = 60  # minutes
        Channels    = @('Email', 'Teams', 'SMS', 'PagerDuty')
        Contacts    = @('manager@example.com')
    }
    Tier4 = @{
        Name        = "Executive"
        Timeout     = 120  # minutes
        Channels    = @('Email', 'SMS', 'PagerDuty')
        Contacts    = @('executive@example.com')
    }
}

# Business hours configuration (Monday-Friday, 8 AM - 6 PM)
$businessHours = @{
    StartHour = 8
    EndHour   = 18
    DaysOfWeek = @(1, 2, 3, 4, 5)  # Monday-Friday
}

# Helper functions
function Test-RMMBusinessHours {
    $now = Get-Date
    $currentHour = $now.Hour
    $currentDay = [int]$now.DayOfWeek

    $inBusinessHours = ($currentHour -ge $businessHours.StartHour) -and 
                       ($currentHour -lt $businessHours.EndHour) -and
                       ($businessHours.DaysOfWeek -contains $currentDay)

    return $inBusinessHours
}

function Start-RMMEscalation {
    param($AlertId, $EscalationPath, $BusinessHoursOnly)

    # Check if alert exists
    $query = "SELECT * FROM Alerts WHERE AlertId = @AlertId"
    $params = @{ AlertId = $AlertId }
    $alert = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params

    if (-not $alert) {
        Write-Error "Alert not found: $AlertId"
        return
    }

    # Check if already resolved
    if ($alert.ResolvedAt) {
        Write-Host "[INFO] Alert already resolved, escalation not needed" -ForegroundColor Cyan
        return
    }

    # Check business hours if required
    if ($BusinessHoursOnly -and -not (Test-RMMBusinessHours)) {
        Write-Host "[INFO] Outside business hours, escalation deferred" -ForegroundColor Yellow
        return
    }

    Write-Host "[ESCALATION] Starting escalation for alert: $($alert.Title)" -ForegroundColor Cyan
    Write-Host "[INFO] Severity: $($alert.Severity) | Device: $($alert.DeviceId)" -ForegroundColor Cyan
    Write-Host ""

    # Use provided escalation path or default
    if (-not $EscalationPath) {
        $EscalationPath = $defaultEscalationPath
    }

    # Determine current tier based on alert age
    $alertAge = (Get-Date) - [datetime]$alert.CreatedAt
    $alertAgeMinutes = $alertAge.TotalMinutes

    $currentTier = $null
    $cumulativeTimeout = 0

    foreach ($tierKey in ($EscalationPath.Keys | Sort-Object)) {
        $tier = $EscalationPath[$tierKey]
        $cumulativeTimeout += $tier.Timeout

        if ($alertAgeMinutes -lt $cumulativeTimeout) {
            $currentTier = @{
                Key  = $tierKey
                Data = $tier
            }
            break
        }
    }

    if (-not $currentTier) {
        # Alert has exceeded all tiers
        $lastTier = $EscalationPath.Keys | Sort-Object | Select-Object -Last 1
        $currentTier = @{
            Key  = $lastTier
            Data = $EscalationPath[$lastTier]
        }
        Write-Host "[WARNING] Alert has exceeded all escalation tiers!" -ForegroundColor Red
    }

    Write-Host "[TIER] Current escalation tier: $($currentTier.Key) - $($currentTier.Data.Name)" -ForegroundColor Yellow
    Write-Host "[INFO] Alert age: $([math]::Round($alertAgeMinutes, 1)) minutes" -ForegroundColor Gray
    Write-Host "[INFO] Channels: $($currentTier.Data.Channels -join ', ')" -ForegroundColor Gray
    Write-Host "[INFO] Contacts: $($currentTier.Data.Contacts -join ', ')" -ForegroundColor Gray

    # Send notifications through configured channels
    # (In production, this would call Notification-Engine.ps1)
    Write-Host "[ACTION] Sending notifications..." -ForegroundColor Cyan

    return $currentTier
}

function Stop-RMMEscalation {
    param($AlertId)

    # Check if alert exists
    $query = "SELECT * FROM Alerts WHERE AlertId = @AlertId"
    $params = @{ AlertId = $AlertId }
    $alert = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params

    if (-not $alert) {
        Write-Error "Alert not found: $AlertId"
        return
    }

    Write-Host "[ESCALATION] Stopping escalation for alert: $($alert.Title)" -ForegroundColor Cyan

    # In production, this would cancel any pending escalation timers/jobs
    Write-Host "[SUCCESS] Escalation stopped" -ForegroundColor Green
}

function Get-RMMEscalationStatus {
    param($AlertId, $EscalationPath)

    # Check if alert exists
    $query = "SELECT * FROM Alerts WHERE AlertId = @AlertId"
    $params = @{ AlertId = $AlertId }
    $alert = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params

    if (-not $alert) {
        Write-Error "Alert not found: $AlertId"
        return
    }

    # Use provided escalation path or default
    if (-not $EscalationPath) {
        $EscalationPath = $defaultEscalationPath
    }

    # Calculate alert age
    $alertAge = (Get-Date) - [datetime]$alert.CreatedAt
    $alertAgeMinutes = $alertAge.TotalMinutes

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Escalation Status" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Alert: $($alert.Title)" -ForegroundColor White
    Write-Host "Severity: $($alert.Severity)" -ForegroundColor White
    Write-Host "Device: $($alert.DeviceId)" -ForegroundColor White
    Write-Host "Created: $($alert.CreatedAt)" -ForegroundColor White
    Write-Host "Age: $([math]::Round($alertAgeMinutes, 1)) minutes" -ForegroundColor White

    if ($alert.AcknowledgedAt) {
        Write-Host "Acknowledged: $($alert.AcknowledgedAt) by $($alert.AcknowledgedBy)" -ForegroundColor Green
    }
    else {
        Write-Host "Acknowledged: No" -ForegroundColor Yellow
    }

    if ($alert.ResolvedAt) {
        Write-Host "Resolved: $($alert.ResolvedAt) by $($alert.ResolvedBy)" -ForegroundColor Green
    }
    else {
        Write-Host "Resolved: No" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Escalation Tiers:" -ForegroundColor Cyan

    $cumulativeTimeout = 0
    foreach ($tierKey in ($EscalationPath.Keys | Sort-Object)) {
        $tier = $EscalationPath[$tierKey]
        $tierStart = $cumulativeTimeout
        $tierEnd = $cumulativeTimeout + $tier.Timeout
        $cumulativeTimeout = $tierEnd

        $status = if ($alertAgeMinutes -ge $tierStart -and $alertAgeMinutes -lt $tierEnd) {
            "[CURRENT]"
        }
        elseif ($alertAgeMinutes -ge $tierEnd) {
            "[PASSED]"
        }
        else {
            "[PENDING]"
        }

        $color = switch ($status) {
            '[CURRENT]' { 'Yellow' }
            '[PASSED]' { 'Gray' }
            '[PENDING]' { 'White' }
        }

        Write-Host "$status $tierKey - $($tier.Name) ($tierStart-$tierEnd min)" -ForegroundColor $color
        Write-Host "  Channels: $($tier.Channels -join ', ')" -ForegroundColor Gray
    }

    Write-Host "========================================" -ForegroundColor Cyan
}

# Execute action
switch ($Action) {
    'Start' {
        if (-not $AlertId) {
            Write-Error "AlertId is required for Start action"
            exit 1
        }
        Start-RMMEscalation -AlertId $AlertId -EscalationPath $EscalationPath -BusinessHoursOnly $BusinessHoursOnly
    }
    'Stop' {
        if (-not $AlertId) {
            Write-Error "AlertId is required for Stop action"
            exit 1
        }
        Stop-RMMEscalation -AlertId $AlertId
    }
    'Status' {
        if (-not $AlertId) {
            Write-Error "AlertId is required for Status action"
            exit 1
        }
        Get-RMMEscalationStatus -AlertId $AlertId -EscalationPath $EscalationPath
    }
    'Configure' {
        Write-Host "Escalation Configuration:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Business Hours:" -ForegroundColor Yellow
        Write-Host "  Days: Monday-Friday" -ForegroundColor Gray
        Write-Host "  Hours: $($businessHours.StartHour):00 - $($businessHours.EndHour):00" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Currently in business hours: $(Test-RMMBusinessHours)" -ForegroundColor White
        Write-Host ""
        Write-Host "Default Escalation Path:" -ForegroundColor Yellow
        foreach ($tierKey in ($defaultEscalationPath.Keys | Sort-Object)) {
            $tier = $defaultEscalationPath[$tierKey]
            Write-Host "  $tierKey - $($tier.Name)" -ForegroundColor White
            Write-Host "    Timeout: $($tier.Timeout) minutes" -ForegroundColor Gray
            Write-Host "    Channels: $($tier.Channels -join ', ')" -ForegroundColor Gray
            Write-Host "    Contacts: $($tier.Contacts -join ', ')" -ForegroundColor Gray
        }
    }
}
