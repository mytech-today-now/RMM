<#
.SYNOPSIS
    Unit tests for RMM-Core module.

.DESCRIPTION
    Pester tests for core framework functionality including initialization,
    device management, configuration, and logging.

.NOTES
    Author: myTech.Today RMM
    Requires: Pester 3.4+
#>

# Load module before tests
$modulePath = Join-Path $PSScriptRoot "..\..\scripts\core\RMM-Core.psm1"
Import-Module $modulePath -Force

Describe "RMM-Core Module Tests" {
    Context "Module Loading" {
        It "Should import RMM-Core module" {
            Get-Module -Name RMM-Core | Should Not BeNullOrEmpty
        }

        It "Should export Initialize-RMM function" {
            Get-Command -Name Initialize-RMM -Module RMM-Core | Should Not BeNullOrEmpty
        }

        It "Should export Get-RMMDevice function" {
            Get-Command -Name Get-RMMDevice -Module RMM-Core | Should Not BeNullOrEmpty
        }

        It "Should export Get-RMMConfig function" {
            Get-Command -Name Get-RMMConfig -Module RMM-Core | Should Not BeNullOrEmpty
        }
    }

    Context "Initialize-RMM" {
        It "Should initialize without throwing" {
            { Initialize-RMM } | Should Not Throw
        }

        It "Should create data directory" {
            $dataPath = "$env:USERPROFILE\myTech.Today\data"
            Test-Path $dataPath | Should Be $true
        }

        It "Should create database file" {
            $dbPath = "$env:USERPROFILE\myTech.Today\data\devices.db"
            Test-Path $dbPath | Should Be $true
        }
    }

    Context "Configuration Management" {
        It "Should get configuration" {
            $config = Get-RMMConfig
            $config | Should Not BeNullOrEmpty
        }

        It "Should have General section in config" {
            $config = Get-RMMConfig
            $config.General | Should Not BeNullOrEmpty
        }

        It "Should have Monitoring section in config" {
            $config = Get-RMMConfig
            $config.Monitoring | Should Not BeNullOrEmpty
        }
    }

    Context "Device Management" {
        # Use unique hostname for each test run to avoid conflicts
        $script:testHostname = "TEST-PESTER-$(Get-Random -Maximum 99999)"

        It "Should add a device" {
            # Add-RMMDevice returns the DeviceId (GUID string), not the device object
            $script:testDeviceId = Add-RMMDevice -Hostname $script:testHostname -IPAddress "192.168.99.1"
            $script:testDeviceId | Should Not BeNullOrEmpty
            # Verify device was created by retrieving it
            $device = Get-RMMDevice -Hostname $script:testHostname | Select-Object -First 1
            $device.Hostname | Should Be $script:testHostname
        }

        It "Should retrieve device by hostname" {
            $device = Get-RMMDevice -Hostname $script:testHostname | Select-Object -First 1
            $device | Should Not BeNullOrEmpty
            $device.Hostname | Should Be $script:testHostname
        }

        It "Should update device status" {
            # Update-RMMDevice requires DeviceId
            Update-RMMDevice -DeviceId $script:testDeviceId -Status "Online"
            $updatedDevice = Get-RMMDevice -Hostname $script:testHostname | Select-Object -First 1
            $updatedDevice.Status | Should Be "Online"
        }

        It "Should remove device" {
            # Remove-RMMDevice requires DeviceId
            Remove-RMMDevice -DeviceId $script:testDeviceId -Force
            $removedDevice = Get-RMMDevice -DeviceId $script:testDeviceId -ErrorAction SilentlyContinue
            $removedDevice | Should BeNullOrEmpty
        }
    }

    Context "Database Access" {
        It "Should return database path" {
            $dbPath = Get-RMMDatabase
            $dbPath | Should Not BeNullOrEmpty
            $dbPath | Should Match "devices\.db$"
        }

        It "Should connect to database" {
            $dbPath = Get-RMMDatabase
            Test-Path $dbPath | Should Be $true
        }
    }

    Context "Health Check" {
        It "Should return health summary" {
            $health = Get-RMMHealth
            $health | Should Not BeNullOrEmpty
        }
    }
}

Describe "Scalability Module Tests" {
    Context "Caching" {
        It "Should set cache value" {
            { Set-RMMCache -Key "test-key" -Type "DeviceStatus" -Data @{Status = "Online"} } | Should Not Throw
        }

        It "Should get cached value" {
            Set-RMMCache -Key "test-cache" -Type "DeviceStatus" -Data "TestValue"
            $cached = Get-RMMCache -Key "test-cache" -Type "DeviceStatus"
            $cached | Should Be "TestValue"
        }

        It "Should clear cache" {
            Set-RMMCache -Key "test-clear" -Type "DeviceStatus" -Data "ToBeCleared"
            Clear-RMMCache -Type "DeviceStatus"
            $cached = Get-RMMCache -Key "test-clear" -Type "DeviceStatus"
            $cached | Should BeNullOrEmpty
        }
    }

    Context "Error Handling" {
        It "Should categorize transient errors" {
            # Test error categorization function exists
            Get-Command -Name Get-RMMErrorCategory | Should Not BeNullOrEmpty
        }
    }
}

Describe "Security Module Tests" {
    Context "Role-Based Access Control" {
        It "Should set user role" {
            { Set-RMMUserRole -Username "TestUser" -Role "Admin" } | Should Not Throw
        }

        It "Should get user role" {
            Set-RMMUserRole -Username "TestUser" -Role "Operator"
            $role = Get-RMMUserRole
            $role.Username | Should Be "TestUser"
            $role.Role | Should Be "Operator"
        }

        It "Should test permissions for Admin" {
            Set-RMMUserRole -Username "AdminUser" -Role "Admin"
            Test-RMMPermission -Permission "Device.Write" | Should Be $true
        }

        It "Should deny permissions for Viewer" {
            Set-RMMUserRole -Username "ViewerUser" -Role "Viewer"
            Test-RMMPermission -Permission "Action.Execute" | Should Be $false
        }
    }

    Context "Audit Logging" {
        It "Should write audit log entry" {
            { Write-RMMAuditLog -Action "TestAction" -TargetDevices @("TEST-001") -Result "Success" } | Should Not Throw
        }
    }
}

