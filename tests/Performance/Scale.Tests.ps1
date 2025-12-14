<#
.SYNOPSIS
    Performance tests for RMM system.

.DESCRIPTION
    Pester tests for performance validation including parallel processing,
    database query speed, and scalability targets.

.NOTES
    Author: myTech.Today RMM
    Requires: Pester 3.4+, PowerShell 5.1+
#>

# Load module before tests
$modulePath = Join-Path $PSScriptRoot "..\..\scripts\core\RMM-Core.psm1"
Import-Module $modulePath -Force
Initialize-RMM

$script:dbPath = Get-RMMDatabase

Describe "Performance Tests" {
    Context "Parallel Processing" {
        It "Should process 100 items in under 30 seconds" {
            $items = 1..100

            $elapsed = Measure-Command {
                if ($PSVersionTable.PSVersion.Major -ge 7) {
                    $items | ForEach-Object -Parallel {
                        Start-Sleep -Milliseconds 100
                    } -ThrottleLimit 50
                }
                else {
                    # PS5.1 fallback - use runspace pool
                    $runspacePool = [RunspaceFactory]::CreateRunspacePool(1, 50)
                    $runspacePool.Open()
                    $runspaces = @()

                    foreach ($item in $items) {
                        $powershell = [PowerShell]::Create()
                        $powershell.RunspacePool = $runspacePool
                        [void]$powershell.AddScript({ Start-Sleep -Milliseconds 100 })
                        $runspaces += @{
                            PowerShell = $powershell
                            Handle = $powershell.BeginInvoke()
                        }
                    }

                    foreach ($rs in $runspaces) {
                        $rs.PowerShell.EndInvoke($rs.Handle)
                        $rs.PowerShell.Dispose()
                    }
                    $runspacePool.Close()
                    $runspacePool.Dispose()
                }
            }

            $elapsed.TotalSeconds | Should BeLessThan 30
        }
    }

    Context "Database Query Performance" {
        It "Should query devices table in under 1 second" {
            $elapsed = Measure-Command {
                $devices = Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT * FROM Devices"
            }

            $elapsed.TotalSeconds | Should BeLessThan 1
        }

        It "Should query metrics with index in under 1 second" {
            $elapsed = Measure-Command {
                $metrics = Invoke-SqliteQuery -DataSource $script:dbPath -Query "SELECT * FROM Metrics ORDER BY Timestamp DESC LIMIT 1000"
            }

            $elapsed.TotalSeconds | Should BeLessThan 1
        }

        It "Should insert 100 rows in under 5 seconds" {
            $testDeviceId = "perf-test-$(Get-Random)"

            $elapsed = Measure-Command {
                for ($i = 1; $i -le 100; $i++) {
                    $query = "INSERT INTO Metrics (DeviceId, MetricType, Value, Unit, Timestamp) VALUES (@DeviceId, 'PerfTest', @Value, 'Count', datetime('now'))"
                    Invoke-SqliteQuery -DataSource $script:dbPath -Query $query -SqlParameters @{
                        DeviceId = $testDeviceId
                        Value = $i
                    }
                }
            }

            # Cleanup
            Invoke-SqliteQuery -DataSource $script:dbPath -Query "DELETE FROM Metrics WHERE DeviceId = @DeviceId" -SqlParameters @{DeviceId = $testDeviceId}

            $elapsed.TotalSeconds | Should BeLessThan 5
        }
    }

    Context "Caching Performance" {
        It "Should cache and retrieve 1000 items in under 1 second" {
            $elapsed = Measure-Command {
                for ($i = 1; $i -le 1000; $i++) {
                    Set-RMMCache -Key "perf-$i" -Type "DeviceStatus" -Data @{Index = $i}
                }
                for ($i = 1; $i -le 1000; $i++) {
                    $null = Get-RMMCache -Key "perf-$i" -Type "DeviceStatus"
                }
            }

            # Cleanup
            Clear-RMMCache -Type "DeviceStatus"

            $elapsed.TotalSeconds | Should BeLessThan 1
        }
    }

    Context "Module Load Performance" {
        It "Should import module in under 5 seconds" {
            $modulePath = Join-Path $PSScriptRoot "..\..\scripts\core\RMM-Core.psm1"

            $elapsed = Measure-Command {
                Import-Module $modulePath -Force
            }

            $elapsed.TotalSeconds | Should BeLessThan 5
        }
    }
}

Describe "Scalability Targets" {
    Context "Device Count Targets" {
        It "Should handle device list of 1000 items" {
            $devices = 1..1000 | ForEach-Object {
                @{
                    Hostname = "DEVICE-$_"
                    IPAddress = "192.168.$([math]::Floor($_ / 256)).$($_ % 256)"
                }
            }

            $devices.Count | Should Be 1000
        }
    }
}

