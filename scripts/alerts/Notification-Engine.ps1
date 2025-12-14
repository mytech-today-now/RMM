<#
.SYNOPSIS
    Multi-channel notification engine for RMM alerts.

.DESCRIPTION
    Sends notifications through various channels (Email, Teams, Slack, PagerDuty, SMS, Webhook, Event Log)
    based on alert severity and configured notification rules.

.PARAMETER AlertId
    Alert ID to send notification for.

.PARAMETER Channels
    Notification channels to use: Email, Teams, Slack, PagerDuty, SMS, Webhook, EventLog

.PARAMETER ConfigPath
    Path to notification configuration file (default: config/notifications.json).

.PARAMETER TestMode
    Send test notification without requiring an alert.

.EXAMPLE
    .\Notification-Engine.ps1 -AlertId "alert-123" -Channels "Email","Teams"

.EXAMPLE
    .\Notification-Engine.ps1 -TestMode -Channels "Email"

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+, PSSQLite module
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$AlertId,

    [Parameter()]
    [ValidateSet('Email', 'Teams', 'Slack', 'PagerDuty', 'SMS', 'Webhook', 'EventLog', 'All')]
    [string[]]$Channels = @('Email'),

    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [switch]$TestMode,

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

# Load notification configuration
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot "..\..\config\notifications.json"
}

$notificationConfig = @{
    Email = @{
        Enabled    = $false
        SMTPServer = "smtp.example.com"
        Port       = 587
        From       = "rmm@example.com"
        To         = @("admin@example.com")
        UseSSL     = $true
        Username   = ""
        Password   = ""
    }
    Teams = @{
        Enabled    = $false
        WebhookURL = ""
    }
    Slack = @{
        Enabled    = $false
        WebhookURL = ""
    }
    PagerDuty = @{
        Enabled        = $false
        IntegrationKey = ""
    }
    SMS = @{
        Enabled     = $false
        AccountSID  = ""
        AuthToken   = ""
        FromNumber  = ""
        ToNumbers   = @()
    }
    Webhook = @{
        Enabled = $false
        URL     = ""
        Headers = @{}
    }
    EventLog = @{
        Enabled  = $true
        LogName  = "Application"
        Source   = "RMM"
    }
}

# Load config from file if it exists
if (Test-Path $ConfigPath) {
    try {
        $loadedConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        # Merge loaded config with defaults
        foreach ($channel in $loadedConfig.PSObject.Properties.Name) {
            if ($notificationConfig.ContainsKey($channel)) {
                $notificationConfig[$channel] = $loadedConfig.$channel
            }
        }
    }
    catch {
        Write-Warning "Failed to load notification config: $_. Using defaults."
    }
}

# Get alert details
$alert = $null
if (-not $TestMode) {
    if (-not $AlertId) {
        Write-Error "AlertId is required when not in TestMode"
        exit 1
    }

    $query = "SELECT * FROM Alerts WHERE AlertId = @AlertId"
    $params = @{ AlertId = $AlertId }
    $alert = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params

    if (-not $alert) {
        Write-Error "Alert not found: $AlertId"
        exit 1
    }
}
else {
    # Create test alert
    $alert = [PSCustomObject]@{
        AlertId   = "test-alert"
        DeviceId  = "test-device"
        AlertType = "Test"
        Severity  = "Info"
        Title     = "Test Notification"
        Message   = "This is a test notification from RMM Notification Engine"
        CreatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

Write-Host "[INFO] Sending notifications for alert: $($alert.Title)" -ForegroundColor Cyan
Write-Host "[INFO] Severity: $($alert.Severity) | Type: $($alert.AlertType)" -ForegroundColor Cyan
Write-Host ""

# Notification functions
function Send-EmailNotification {
    param($Alert, $Config)

    if (-not $Config.Enabled) {
        Write-Host "[SKIPPED] Email notifications not enabled" -ForegroundColor Yellow
        return $false
    }

    try {
        $subject = "[$($Alert.Severity)] $($Alert.Title)"
        $body = @"
<html>
<body>
<h2 style='color: red;'>RMM Alert</h2>
<table>
<tr><td><strong>Severity:</strong></td><td>$($Alert.Severity)</td></tr>
<tr><td><strong>Device:</strong></td><td>$($Alert.DeviceId)</td></tr>
<tr><td><strong>Type:</strong></td><td>$($Alert.AlertType)</td></tr>
<tr><td><strong>Title:</strong></td><td>$($Alert.Title)</td></tr>
<tr><td><strong>Message:</strong></td><td>$($Alert.Message)</td></tr>
<tr><td><strong>Created:</strong></td><td>$($Alert.CreatedAt)</td></tr>
</table>
</body>
</html>
"@

        $mailParams = @{
            SmtpServer = $Config.SMTPServer
            Port       = $Config.Port
            From       = $Config.From
            To         = $Config.To
            Subject    = $subject
            Body       = $body
            BodyAsHtml = $true
        }

        if ($Config.UseSSL) {
            $mailParams.UseSsl = $true
        }

        if ($Config.Username -and $Config.Password) {
            $securePassword = ConvertTo-SecureString $Config.Password -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($Config.Username, $securePassword)
            $mailParams.Credential = $credential
        }

        Send-MailMessage @mailParams -ErrorAction Stop
        Write-Host "[SUCCESS] Email notification sent" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[FAILED] Email notification: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Send-TeamsNotification {
    param($Alert, $Config)

    if (-not $Config.Enabled -or -not $Config.WebhookURL) {
        Write-Host "[SKIPPED] Teams notifications not configured" -ForegroundColor Yellow
        return $false
    }

    try {
        $color = switch ($Alert.Severity) {
            'Critical' { 'FF0000' }
            'High' { 'FFA500' }
            'Medium' { 'FFFF00' }
            'Low' { '00FF00' }
            'Info' { '0000FF' }
        }

        $body = @{
            "@type"      = "MessageCard"
            "@context"   = "https://schema.org/extensions"
            "summary"    = $Alert.Title
            "themeColor" = $color
            "title"      = "[$($Alert.Severity)] $($Alert.Title)"
            "sections"   = @(
                @{
                    "facts" = @(
                        @{ "name" = "Device"; "value" = $Alert.DeviceId }
                        @{ "name" = "Type"; "value" = $Alert.AlertType }
                        @{ "name" = "Severity"; "value" = $Alert.Severity }
                        @{ "name" = "Message"; "value" = $Alert.Message }
                        @{ "name" = "Created"; "value" = $Alert.CreatedAt }
                    )
                }
            )
        }

        $json = $body | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri $Config.WebhookURL -Method Post -Body $json -ContentType 'application/json' -ErrorAction Stop
        Write-Host "[SUCCESS] Teams notification sent" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[FAILED] Teams notification: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Send-SlackNotification {
    param($Alert, $Config)

    if (-not $Config.Enabled -or -not $Config.WebhookURL) {
        Write-Host "[SKIPPED] Slack notifications not configured" -ForegroundColor Yellow
        return $false
    }

    try {
        $color = switch ($Alert.Severity) {
            'Critical' { 'danger' }
            'High' { 'warning' }
            default { 'good' }
        }

        $body = @{
            "text"        = "RMM Alert: $($Alert.Title)"
            "attachments" = @(
                @{
                    "color"  = $color
                    "fields" = @(
                        @{ "title" = "Severity"; "value" = $Alert.Severity; "short" = $true }
                        @{ "title" = "Device"; "value" = $Alert.DeviceId; "short" = $true }
                        @{ "title" = "Type"; "value" = $Alert.AlertType; "short" = $true }
                        @{ "title" = "Created"; "value" = $Alert.CreatedAt; "short" = $true }
                        @{ "title" = "Message"; "value" = $Alert.Message; "short" = $false }
                    )
                }
            )
        }

        $json = $body | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri $Config.WebhookURL -Method Post -Body $json -ContentType 'application/json' -ErrorAction Stop
        Write-Host "[SUCCESS] Slack notification sent" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[FAILED] Slack notification: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Write-EventLogNotification {
    param($Alert, $Config)

    if (-not $Config.Enabled) {
        Write-Host "[SKIPPED] Event Log notifications not enabled" -ForegroundColor Yellow
        return $false
    }

    try {
        # Create event source if it doesn't exist
        if (-not [System.Diagnostics.EventLog]::SourceExists($Config.Source)) {
            New-EventLog -LogName $Config.LogName -Source $Config.Source
        }

        $eventType = switch ($Alert.Severity) {
            'Critical' { 'Error' }
            'High' { 'Error' }
            'Medium' { 'Warning' }
            'Low' { 'Information' }
            'Info' { 'Information' }
        }

        $message = @"
RMM Alert: $($Alert.Title)

Device: $($Alert.DeviceId)
Type: $($Alert.AlertType)
Severity: $($Alert.Severity)
Message: $($Alert.Message)
Created: $($Alert.CreatedAt)
"@

        Write-EventLog -LogName $Config.LogName -Source $Config.Source -EntryType $eventType -EventId 1000 -Message $message
        Write-Host "[SUCCESS] Event Log notification written" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[FAILED] Event Log notification: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Send notifications
$successCount = 0
$failCount = 0

if ($Channels -contains 'All') {
    $Channels = @('Email', 'Teams', 'Slack', 'EventLog')
}

foreach ($channel in $Channels) {
    $success = $false
    switch ($channel) {
        'Email' { $success = Send-EmailNotification -Alert $alert -Config $notificationConfig.Email }
        'Teams' { $success = Send-TeamsNotification -Alert $alert -Config $notificationConfig.Teams }
        'Slack' { $success = Send-SlackNotification -Alert $alert -Config $notificationConfig.Slack }
        'EventLog' { $success = Write-EventLogNotification -Alert $alert -Config $notificationConfig.EventLog }
        default { Write-Host "[SKIPPED] Channel not implemented: $channel" -ForegroundColor Yellow }
    }

    if ($success) {
        $successCount++
    }
    else {
        $failCount++
    }
}

# Update alert with notification status
if (-not $TestMode) {
    try {
        $notificationsSent = ($Channels -join ',')
        $query = "UPDATE Alerts SET NotificationsSent = @NotificationsSent WHERE AlertId = @AlertId"
        $params = @{
            AlertId            = $AlertId
            NotificationsSent  = $notificationsSent
        }
        Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params
    }
    catch {
        Write-Warning "Failed to update alert notification status: $_"
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Notification Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Alert: $($alert.Title)" -ForegroundColor White
Write-Host "Channels Attempted: $($Channels.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Cyan
