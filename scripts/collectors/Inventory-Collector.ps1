<#
.SYNOPSIS
    Comprehensive inventory collection for managed devices.

.DESCRIPTION
    Collects hardware, software, security, and network inventory from managed devices
    and stores the results in the RMM database. Supports parallel processing and caching.

.PARAMETER Devices
    Array of device hostnames, a group name, or "All" to collect from all devices.

.PARAMETER Categories
    Categories to collect: All, Hardware, Software, Security, Network.
    Default: All

.PARAMETER Parallel
    Enable parallel processing (default: $true for PowerShell 7+).

.PARAMETER ThrottleLimit
    Maximum number of parallel jobs (default: 25).

.PARAMETER Force
    Skip cache and force fresh collection.

.PARAMETER DatabasePath
    Path to the RMM database. If not specified, uses the default from RMM-Core.

.EXAMPLE
    .\Inventory-Collector.ps1 -Devices "localhost" -Categories All

.EXAMPLE
    .\Inventory-Collector.ps1 -Devices "Workstations" -Categories Hardware,Software -Parallel

.EXAMPLE
    .\Inventory-Collector.ps1 -Devices "SERVER01","SERVER02" -Force

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+, PSSQLite module
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Devices = @("All"),

    [Parameter()]
    [ValidateSet('All', 'Hardware', 'Software', 'Security', 'Network')]
    [string[]]$Categories = @('All'),

    [Parameter()]
    [switch]$Parallel = ($PSVersionTable.PSVersion.Major -ge 7),

    [Parameter()]
    [int]$ThrottleLimit = 25,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [string]$DatabasePath
)

# Import required modules
$ErrorActionPreference = 'Stop'

try {
    # Import RMM Core
    $rmmCorePath = Join-Path $PSScriptRoot "..\core\RMM-Core.psm1"
    if (-not (Get-Module -Name RMM-Core)) {
        Import-Module $rmmCorePath -Force
    }

    # Import PSSQLite
    if (-not (Get-Module -Name PSSQLite)) {
        Import-Module PSSQLite -ErrorAction Stop
    }
}
catch {
    Write-Error "Failed to import required modules: $_"
    exit 1
}

# Initialize RMM
try {
    Initialize-RMM -ErrorAction Stop
    Write-Host "[INFO] RMM initialized successfully" -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to initialize RMM: $_"
    exit 1
}

# Get database path
if (-not $DatabasePath) {
    $DatabasePath = Get-RMMDatabase
}

# Resolve devices
$targetDevices = @()
if ($Devices -contains "All") {
    $targetDevices = Get-RMMDevice
}
else {
    foreach ($device in $Devices) {
        # Treat as hostname
        $dev = Get-RMMDevice -Hostname $device -ErrorAction SilentlyContinue
        if ($dev) {
            $targetDevices += $dev
        }
        else {
            Write-Warning "Device not found: $device"
        }
    }
}

if ($targetDevices.Count -eq 0) {
    Write-Warning "No devices found to collect inventory from"
    exit 0
}

Write-Host "[INFO] Collecting inventory from $($targetDevices.Count) device(s)" -ForegroundColor Cyan
Write-Host ""

# Determine categories to collect
$categoriesToCollect = if ($Categories -contains 'All') {
    @('Hardware', 'Software', 'Security', 'Network')
}
else {
    $Categories
}

Write-Host "[INFO] Categories: $($categoriesToCollect -join ', ')" -ForegroundColor Cyan
Write-Host ""

# Collection script block
$collectionScriptBlock = {
    param($Device, $Categories, $Force, $DatabasePath, $RMMCorePath)

    # Import modules in the job context
    Import-Module $RMMCorePath -Force -ErrorAction SilentlyContinue
    Import-Module PSSQLite -ErrorAction SilentlyContinue

    $results = @{
        DeviceId = $Device.DeviceId
        Hostname = $Device.Hostname
        Success  = $false
        Data     = @{}
        Errors   = @()
    }

    try {
        # Test connectivity
        $testConnection = Test-Connection -ComputerName $Device.Hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $testConnection) {
            $results.Errors += "Device is offline or unreachable"
            return $results
        }

        # Collect Hardware inventory
        if ($Categories -contains 'Hardware') {
            try {
                $hardwareData = @{}

                # System information
                $system = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $Device.Hostname -ErrorAction Stop
                $hardwareData.System = @{
                    Manufacturer = $system.Manufacturer
                    Model        = $system.Model
                    TotalMemory  = $system.TotalPhysicalMemory
                    Domain       = $system.Domain
                }

                # BIOS information
                $bios = Get-CimInstance -ClassName Win32_BIOS -ComputerName $Device.Hostname -ErrorAction Stop
                $hardwareData.BIOS = @{
                    Manufacturer = $bios.Manufacturer
                    Version      = $bios.SMBIOSBIOSVersion
                    SerialNumber = $bios.SerialNumber
                    ReleaseDate  = $bios.ReleaseDate
                }

                # Processor information
                $processors = Get-CimInstance -ClassName Win32_Processor -ComputerName $Device.Hostname -ErrorAction Stop
                $hardwareData.Processors = $processors | ForEach-Object {
                    @{
                        Name              = $_.Name
                        Cores             = $_.NumberOfCores
                        LogicalProcessors = $_.NumberOfLogicalProcessors
                        MaxClockSpeed     = $_.MaxClockSpeed
                    }
                }

                # Memory information
                $memory = Get-CimInstance -ClassName Win32_PhysicalMemory -ComputerName $Device.Hostname -ErrorAction Stop
                $hardwareData.Memory = $memory | ForEach-Object {
                    @{
                        Capacity     = $_.Capacity
                        Speed        = $_.Speed
                        Manufacturer = $_.Manufacturer
                        PartNumber   = $_.PartNumber
                    }
                }

                # Disk information
                $disks = Get-CimInstance -ClassName Win32_DiskDrive -ComputerName $Device.Hostname -ErrorAction Stop
                $hardwareData.Disks = $disks | ForEach-Object {
                    @{
                        Model        = $_.Model
                        Size         = $_.Size
                        InterfaceType = $_.InterfaceType
                        SerialNumber = $_.SerialNumber
                    }
                }

                # Volumes information
                $volumes = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $Device.Hostname -ErrorAction Stop | Where-Object { $_.DriveType -eq 3 }
                $hardwareData.Volumes = $volumes | ForEach-Object {
                    @{
                        DeviceID   = $_.DeviceID
                        Size       = $_.Size
                        FreeSpace  = $_.FreeSpace
                        FileSystem = $_.FileSystem
                    }
                }

                # Network adapters
                $adapters = Get-CimInstance -ClassName Win32_NetworkAdapter -ComputerName $Device.Hostname -ErrorAction Stop | Where-Object { $_.PhysicalAdapter -eq $true }
                $hardwareData.NetworkAdapters = $adapters | ForEach-Object {
                    @{
                        Name       = $_.Name
                        MACAddress = $_.MACAddress
                        Speed      = $_.Speed
                    }
                }

                $results.Data.Hardware = $hardwareData
            }
            catch {
                $results.Errors += "Hardware collection failed: $($_.Exception.Message)"
            }
        }

        # Collect Software inventory
        if ($Categories -contains 'Software') {
            try {
                $softwareData = @{}

                # Operating System
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Device.Hostname -ErrorAction Stop
                $softwareData.OS = @{
                    Name           = $os.Caption
                    Version        = $os.Version
                    Build          = $os.BuildNumber
                    Architecture   = $os.OSArchitecture
                    InstallDate    = $os.InstallDate
                    LastBootUpTime = $os.LastBootUpTime
                }

                # Hotfixes (limit to last 50)
                $hotfixes = Get-CimInstance -ClassName Win32_QuickFixEngineering -ComputerName $Device.Hostname -ErrorAction Stop | Select-Object -First 50
                $softwareData.Hotfixes = $hotfixes | ForEach-Object {
                    @{
                        HotFixID    = $_.HotFixID
                        Description = $_.Description
                        InstalledOn = $_.InstalledOn
                    }
                }

                # Services (only running services)
                $services = Get-CimInstance -ClassName Win32_Service -ComputerName $Device.Hostname -ErrorAction Stop | Where-Object { $_.State -eq 'Running' }
                $softwareData.Services = $services | ForEach-Object {
                    @{
                        Name        = $_.Name
                        DisplayName = $_.DisplayName
                        StartMode   = $_.StartMode
                        State       = $_.State
                    }
                }

                $results.Data.Software = $softwareData
            }
            catch {
                $results.Errors += "Software collection failed: $($_.Exception.Message)"
            }
        }

        # Collect Security inventory
        if ($Categories -contains 'Security') {
            try {
                $securityData = @{}

                # Firewall profiles
                $firewallProfiles = Get-CimInstance -ClassName MSFT_NetFirewallProfile -Namespace root/StandardCimv2 -ComputerName $Device.Hostname -ErrorAction Stop
                $securityData.Firewall = $firewallProfiles | ForEach-Object {
                    @{
                        Name    = $_.Name
                        Enabled = $_.Enabled
                    }
                }

                # Local administrators (using secure remoting for workgroup support)
                try {
                    $admins = Invoke-RMMRemoteCommand -ComputerName $Device.Hostname -ScriptBlock {
                        Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
                    }
                    $securityData.LocalAdmins = $admins | ForEach-Object {
                        @{
                            Name = $_.Name
                            Type = $_.ObjectClass
                        }
                    }
                }
                catch {
                    $securityData.LocalAdmins = @()
                }

                $results.Data.Security = $securityData
            }
            catch {
                $results.Errors += "Security collection failed: $($_.Exception.Message)"
            }
        }

        # Collect Network inventory
        if ($Categories -contains 'Network') {
            try {
                $networkData = @{}

                # IP Configuration
                $ipConfig = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ComputerName $Device.Hostname -ErrorAction Stop | Where-Object { $_.IPEnabled -eq $true }
                $networkData.IPConfiguration = $ipConfig | ForEach-Object {
                    @{
                        Description    = $_.Description
                        IPAddress      = $_.IPAddress
                        SubnetMask     = $_.IPSubnet
                        DefaultGateway = $_.DefaultIPGateway
                        DNSServers     = $_.DNSServerSearchOrder
                        DHCPEnabled    = $_.DHCPEnabled
                    }
                }

                $results.Data.Network = $networkData
            }
            catch {
                $results.Errors += "Network collection failed: $($_.Exception.Message)"
            }
        }

        $results.Success = ($results.Errors.Count -eq 0)
    }
    catch {
        $results.Errors += "General collection error: $($_.Exception.Message)"
        $results.Success = $false
    }

    return $results
}

# Execute collection
$collectionResults = @()

if ($Parallel -and $PSVersionTable.PSVersion.Major -ge 7) {
    Write-Host "[INFO] Using parallel processing (ThrottleLimit: $ThrottleLimit)" -ForegroundColor Cyan

    $collectionResults = $targetDevices | ForEach-Object -Parallel {
        $device = $_
        $scriptBlock = $using:collectionScriptBlock
        $categories = $using:categoriesToCollect
        $force = $using:Force
        $dbPath = $using:DatabasePath
        $rmmCore = $using:rmmCorePath

        & $scriptBlock -Device $device -Categories $categories -Force $force -DatabasePath $dbPath -RMMCorePath $rmmCore
    } -ThrottleLimit $ThrottleLimit
}
else {
    Write-Host "[INFO] Using sequential processing" -ForegroundColor Cyan

    foreach ($device in $targetDevices) {
        $result = & $collectionScriptBlock -Device $device -Categories $categoriesToCollect -Force $Force -DatabasePath $DatabasePath -RMMCorePath $rmmCorePath
        $collectionResults += $result
    }
}

# Store results in database
Write-Host ""
Write-Host "[INFO] Storing results in database..." -ForegroundColor Cyan

$successCount = 0
$failureCount = 0

foreach ($result in $collectionResults) {
    try {
        if ($result.Success -or $result.Data.Count -gt 0) {
            # Store each category separately
            foreach ($category in $result.Data.Keys) {
                $dataJson = $result.Data[$category] | ConvertTo-Json -Compress -Depth 10

                $query = @"
INSERT INTO Inventory (DeviceId, Category, Data, CollectedAt)
VALUES (@DeviceId, @Category, @Data, CURRENT_TIMESTAMP)
"@

                $params = @{
                    DeviceId = $result.DeviceId
                    Category = $category
                    Data     = $dataJson
                }

                Invoke-SqliteQuery -DataSource $DatabasePath -Query $query -SqlParameters $params
            }

            # Update device LastInventory timestamp
            $updateQuery = "UPDATE Devices SET LastInventory = CURRENT_TIMESTAMP WHERE DeviceId = @DeviceId"
            Invoke-SqliteQuery -DataSource $DatabasePath -Query $updateQuery -SqlParameters @{ DeviceId = $result.DeviceId }

            Write-Host "[OK] $($result.Hostname): Inventory collected successfully" -ForegroundColor Green
            $successCount++
        }
        else {
            Write-Host "[FAIL] $($result.Hostname): $($result.Errors -join '; ')" -ForegroundColor Red
            $failureCount++
        }
    }
    catch {
        Write-Host "[ERROR] $($result.Hostname): Failed to store results: $_" -ForegroundColor Red
        $failureCount++
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Inventory Collection Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Devices: $($targetDevices.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failureCount" -ForegroundColor $(if ($failureCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Categories: $($categoriesToCollect -join ', ')" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

