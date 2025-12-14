<#
.SYNOPSIS
    Integration tests for RMM database operations.

.DESCRIPTION
    Pester tests for database connectivity, table operations, and data integrity.

.NOTES
    Author: myTech.Today RMM
    Requires: Pester 3.4+, PSSQLite module
#>

# Load modules before tests
Import-Module PSSQLite -ErrorAction Stop
$modulePath = Join-Path $PSScriptRoot "..\..\scripts\core\RMM-Core.psm1"
Import-Module $modulePath -Force
Initialize-RMM
$script:dbPath = Get-RMMDatabase

$script:testDeviceId = "test-device-$(Get-Random)"
$script:testAlertId = "alert-$(Get-Random)"

Describe "Database Integration Tests" {
    Context "Database Connection" {
        It "Should have valid database path" {
            $script:dbPath | Should Not BeNullOrEmpty
        }

        It "Should connect to database" {
            Test-Path $script:dbPath | Should Be $true
        }

        It "Should query database without error" {
            { Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT 1" } | Should Not Throw
        }
    }

    Context "Core Tables Exist" {
        It "Should have Devices table" {
            $tables = Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='Devices'"
            $tables | Should Not BeNullOrEmpty
        }

        It "Should have Alerts table" {
            $tables = Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='Alerts'"
            $tables | Should Not BeNullOrEmpty
        }

        It "Should have Actions table" {
            $tables = Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='Actions'"
            $tables | Should Not BeNullOrEmpty
        }

        It "Should have Metrics table" {
            $tables = Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='Metrics'"
            $tables | Should Not BeNullOrEmpty
        }

        It "Should have Inventory table" {
            $tables = Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='Inventory'"
            $tables | Should Not BeNullOrEmpty
        }

        It "Should have AuditLog table" {
            $tables = Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='AuditLog'"
            $tables | Should Not BeNullOrEmpty
        }
    }

    Context "Metrics Operations" {
        It "Should insert metrics" {
            $query = @"
INSERT INTO Metrics (DeviceId, MetricType, Value, Unit, Timestamp)
VALUES (@DeviceId, 'CPU', 45.5, 'Percent', datetime('now'))
"@
            { Invoke-SqliteQuery -DataSource $script:dbPath -Query $query -SqlParameters @{DeviceId = $script:testDeviceId} } | Should Not Throw
        }

        It "Should retrieve inserted metrics" {
            $metrics = Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT * FROM Metrics WHERE DeviceId = @DeviceId" -SqlParameters @{DeviceId = $script:testDeviceId}
            $metrics | Should Not BeNullOrEmpty
            $metrics.MetricType | Should Be "CPU"
        }
    }

    Context "Alert Operations" {
        It "Should insert alert" {
            # Actual Alerts table schema: AlertId, DeviceId, AlertType, Severity, Title, Message, Source, CreatedAt, etc.
            $query = @"
INSERT INTO Alerts (AlertId, DeviceId, AlertType, Severity, Title, Message, Source, CreatedAt)
VALUES (@AlertId, 'test-device', 'Test', 'Warning', 'Test Alert', 'Test message', 'Pester', datetime('now'))
"@
            { Invoke-SqliteQuery -DataSource $script:dbPath -Query $query -SqlParameters @{AlertId = $script:testAlertId} } | Should Not Throw
        }

        It "Should retrieve alert" {
            $alert = Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT * FROM Alerts WHERE AlertId = @AlertId" -SqlParameters @{AlertId = $script:testAlertId}
            $alert | Should Not BeNullOrEmpty
            $alert.Title | Should Be "Test Alert"
        }

        It "Should update alert" {
            # Update ResolvedAt instead of Status (no Status column in actual schema)
            $query = "UPDATE Alerts SET ResolvedAt = datetime('now'), ResolvedBy = 'Pester' WHERE AlertId = @AlertId"
            { Invoke-SqliteQuery -DataSource $script:dbPath -Query $query -SqlParameters @{AlertId = $script:testAlertId} } | Should Not Throw

            $alert = Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT * FROM Alerts WHERE AlertId = @AlertId" -SqlParameters @{AlertId = $script:testAlertId}
            $alert.ResolvedBy | Should Be "Pester"
        }
    }

    Context "Audit Log Operations" {
        It "Should insert audit log entry" {
            # Actual AuditLog schema: LogId, Timestamp, User, Action, Target, Details, IPAddress, Success
            $query = @"
INSERT INTO AuditLog (Timestamp, User, Action, Target, Details, IPAddress, Success)
VALUES (datetime('now'), 'TestUser', 'TestAction', 'TEST-001', '{}', '127.0.0.1', 1)
"@
            { Invoke-SqliteQuery -DataSource $script:dbPath -Query $query } | Should Not Throw
        }

        It "Should retrieve audit log entries" {
            $logs = Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT * FROM AuditLog ORDER BY Timestamp DESC LIMIT 10"
            $logs | Should Not BeNullOrEmpty
        }
    }
}

Describe "Database Maintenance Tests" {
    Context "Backup and Maintenance" {
        It "Should get database stats" {
            $stats = Get-RMMDatabaseStats
            $stats | Should Not BeNullOrEmpty
            # Pester v3 doesn't have BeGreaterOrEqual, use BeGreaterThan with -1
            $stats.SizeMB | Should BeGreaterThan -1
        }
    }
}

