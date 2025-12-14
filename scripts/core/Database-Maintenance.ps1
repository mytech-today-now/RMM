<#
.SYNOPSIS
    Database maintenance and optimization for RMM system.

.DESCRIPTION
    Provides database archival, VACUUM operations, and optimization functions
    for SQLite database maintenance.

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+, PSSQLite module
#>

#Requires -Version 5.1

#region Database Maintenance

function Invoke-RMMDatabaseVacuum {
    <#
    .SYNOPSIS
        Run VACUUM on the SQLite database to reclaim space.
    .DESCRIPTION
        Rebuilds the database file, repacking it into minimal space.
        Should be run weekly for optimal performance.
    .PARAMETER DatabasePath
        Path to the database. Uses default if not specified.
    .EXAMPLE
        Invoke-RMMDatabaseVacuum
    #>
    [CmdletBinding()]
    param([string]$DatabasePath)

    if (-not $DatabasePath) { $DatabasePath = Get-RMMDatabase }

    Write-RMMLog -Message "Starting database VACUUM operation" -Level "Info"
    $startSize = (Get-Item $DatabasePath).Length

    try {
        Invoke-SqliteQuery -DataSource $DatabasePath -Query "VACUUM;" -ErrorAction Stop
        $endSize = (Get-Item $DatabasePath).Length
        $savedMB = [math]::Round(($startSize - $endSize) / 1MB, 2)
        Write-RMMLog -Message "VACUUM complete. Space reclaimed: $savedMB MB" -Level "Info"
        return @{ Success = $true; SpaceReclaimed = $savedMB }
    }
    catch {
        Write-RMMLog -Message "VACUUM failed: $_" -Level "Error"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Invoke-RMMDatabaseArchive {
    <#
    .SYNOPSIS
        Archive old data based on retention policy.
    .DESCRIPTION
        Moves old metrics, logs, and events to archive tables or deletes them
        based on the configured retention policy.
    .PARAMETER DatabasePath
        Path to the database.
    .PARAMETER MetricsRetentionDays
        Days to retain metrics. Default: 90
    .PARAMETER AlertsRetentionDays
        Days to retain resolved alerts. Default: 365
    .PARAMETER AuditRetentionDays
        Days to retain audit logs. Default: 730 (2 years)
    .EXAMPLE
        Invoke-RMMDatabaseArchive -MetricsRetentionDays 30
    #>
    [CmdletBinding()]
    param(
        [string]$DatabasePath,
        [int]$MetricsRetentionDays = 90,
        [int]$AlertsRetentionDays = 365,
        [int]$AuditRetentionDays = 730
    )

    if (-not $DatabasePath) { $DatabasePath = Get-RMMDatabase }

    Write-RMMLog -Message "Starting database archival process" -Level "Info"
    $results = @{ Metrics = 0; Alerts = 0; Audit = 0 }

    try {
        # Archive old metrics
        $metricsDate = (Get-Date).AddDays(-$MetricsRetentionDays).ToString("yyyy-MM-dd HH:mm:ss")
        $query = "DELETE FROM Metrics WHERE CollectedAt < @CutoffDate"
        $deleted = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ CutoffDate = $metricsDate }
        $results.Metrics = $deleted.Count

        # Archive resolved alerts
        $alertsDate = (Get-Date).AddDays(-$AlertsRetentionDays).ToString("yyyy-MM-dd HH:mm:ss")
        $query = "DELETE FROM Alerts WHERE Status = 'Resolved' AND ResolvedAt < @CutoffDate"
        $deleted = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ CutoffDate = $alertsDate }
        $results.Alerts = $deleted.Count

        # Archive old audit logs
        $auditDate = (Get-Date).AddDays(-$AuditRetentionDays).ToString("yyyy-MM-dd HH:mm:ss")
        $query = "DELETE FROM AuditLog WHERE Timestamp < @CutoffDate"
        $deleted = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters @{ CutoffDate = $auditDate }
        $results.Audit = $deleted.Count

        Write-RMMLog -Message "Archival complete. Deleted: Metrics=$($results.Metrics), Alerts=$($results.Alerts), Audit=$($results.Audit)" -Level "Info"
        return @{ Success = $true; Deleted = $results }
    }
    catch {
        Write-RMMLog -Message "Archival failed: $_" -Level "Error"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Invoke-RMMDatabaseBackup {
    <#
    .SYNOPSIS
        Create a backup of the database.
    .PARAMETER DatabasePath
        Path to the database.
    .PARAMETER BackupPath
        Path for the backup file. Auto-generated if not specified.
    .EXAMPLE
        Invoke-RMMDatabaseBackup
    #>
    [CmdletBinding()]
    param(
        [string]$DatabasePath,
        [string]$BackupPath
    )

    if (-not $DatabasePath) { $DatabasePath = Get-RMMDatabase }
    if (-not $BackupPath) {
        $backupDir = Join-Path (Split-Path $DatabasePath -Parent) "backups"
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $BackupPath = Join-Path $backupDir "devices_$timestamp.db"
    }

    Write-RMMLog -Message "Creating database backup: $BackupPath" -Level "Info"

    try {
        Copy-Item -Path $DatabasePath -Destination $BackupPath -Force
        $size = [math]::Round((Get-Item $BackupPath).Length / 1MB, 2)
        Write-RMMLog -Message "Backup complete: $size MB" -Level "Info"
        return @{ Success = $true; BackupPath = $BackupPath; SizeMB = $size }
    }
    catch {
        Write-RMMLog -Message "Backup failed: $_" -Level "Error"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Get-RMMDatabaseStats {
    <#
    .SYNOPSIS
        Get database statistics and health information.
    .PARAMETER DatabasePath
        Path to the database.
    #>
    [CmdletBinding()]
    param([string]$DatabasePath)

    if (-not $DatabasePath) { $DatabasePath = Get-RMMDatabase }

    $stats = @{
        Path = $DatabasePath
        SizeMB = [math]::Round((Get-Item $DatabasePath).Length / 1MB, 2)
        Tables = @{}
    }

    $tables = @('Devices', 'Metrics', 'Alerts', 'Actions', 'Inventory', 'AuditLog')
    foreach ($table in $tables) {
        try {
            $count = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT COUNT(*) as Count FROM $table" -ErrorAction SilentlyContinue
            $stats.Tables[$table] = $count.Count
        }
        catch {
            $stats.Tables[$table] = 0
        }
    }

    return $stats
}

#endregion

#region Scheduled Maintenance

function Register-RMMMaintenanceTask {
    <#
    .SYNOPSIS
        Register a Windows scheduled task for weekly database maintenance.
    .PARAMETER TaskName
        Name for the scheduled task.
    .PARAMETER Time
        Time to run (e.g., "02:00"). Default: 02:00
    .PARAMETER DayOfWeek
        Day to run. Default: Sunday
    #>
    [CmdletBinding()]
    param(
        [string]$TaskName = "RMM-DatabaseMaintenance",
        [string]$Time = "02:00",
        [string]$DayOfWeek = "Sunday"
    )

    $scriptPath = Join-Path $PSScriptRoot "..\..\scripts\core\Database-Maintenance.ps1"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -RunMaintenance"
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd

    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force
        Write-RMMLog -Message "Maintenance task registered: $TaskName" -Level "Info"
        return $true
    }
    catch {
        Write-RMMLog -Message "Failed to register maintenance task: $_" -Level "Error"
        return $false
    }
}

#endregion

# Script execution for scheduled task
if ($args -contains "-RunMaintenance") {
    Write-Host "[$(Get-Date)] Starting scheduled maintenance..."
    $dbPath = Get-RMMDatabase
    Invoke-RMMDatabaseBackup -DatabasePath $dbPath
    Invoke-RMMDatabaseArchive -DatabasePath $dbPath
    Invoke-RMMDatabaseVacuum -DatabasePath $dbPath
    Write-Host "[$(Get-Date)] Maintenance complete."
}
