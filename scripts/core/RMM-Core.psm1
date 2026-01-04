<#
.SYNOPSIS
    myTech.Today RMM Core Module

.DESCRIPTION
    Central module that provides the unified API for the RMM system.
    Provides device management, action execution, health monitoring, and configuration functions.

    Installation Paths (Microsoft Best Practices):
    - Program Files: C:\Program Files (x86)\myTech.Today\RMM\
    - Data/Config:   C:\ProgramData\myTech.Today\RMM\

.NOTES
    Author: Kyle C. Rode (myTech.Today)
    Version: 2.1
    Requires: PowerShell 5.1+, PSSQLite module
#>

#Requires -Version 5.1
#Requires -Modules PSSQLite

# Module-scoped variables
$script:ModuleRoot = $PSScriptRoot
$script:RMMInitialized = $false

# Standard installation paths following Microsoft best practices
# Program Files - read-only application binaries
$script:RMMInstallPath = "${env:ProgramFiles(x86)}\myTech.Today\RMM"

# ProgramData - writable application data (works for SYSTEM and all users)
$script:RMMDataRoot = "$env:ProgramData\myTech.Today\RMM"
$script:DataPath = "$script:RMMDataRoot\data"
$script:ConfigPath = "$script:RMMDataRoot\config"
$script:LogPath = "$script:RMMDataRoot\logs"

# Default paths for database and settings
$script:DatabasePath = Join-Path $script:DataPath "devices.db"
$script:SettingsPath = Join-Path $script:ConfigPath "settings.json"

# Legacy path support - check if old installation exists for migration
$script:LegacyInstallPath = "$env:USERPROFILE\myTech.Today\RMM"
$script:LegacyDatabasePath = "$script:LegacyInstallPath\data\devices.db"

# Import sub-modules
. "$PSScriptRoot\Config-Manager.ps1"
. "$PSScriptRoot\Logging.ps1"
. "$PSScriptRoot\Remoting.ps1"
. "$PSScriptRoot\Scalability.ps1"
. "$PSScriptRoot\Security.ps1"
. "$PSScriptRoot\Database-Maintenance.ps1"

function Initialize-RMM {
    <#
    .SYNOPSIS
        Initializes the RMM environment.

    .DESCRIPTION
        Bootstraps the RMM system by checking dependencies, connecting to the database,
        and initializing logging. This should be called before using other RMM functions.

    .PARAMETER DatabasePath
        Optional. Path to the SQLite database. Default: .\data\devices.db

    .PARAMETER Force
        Force reinitialization even if already initialized.

    .PARAMETER Quiet
        Suppress console output during initialization.

    .EXAMPLE
        Initialize-RMM
        Initializes RMM with default settings.

    .EXAMPLE
        Initialize-RMM -DatabasePath "C:\RMM\data\devices.db" -Force
        Initializes RMM with custom database path and forces reinitialization.

    .OUTPUTS
        System.Boolean
        Returns $true if initialization succeeds, $false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$DatabasePath,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$Quiet
    )

    try {
        if ($script:RMMInitialized -and -not $Force) {
            Write-Verbose "RMM already initialized. Use -Force to reinitialize."
            return $true
        }

        Write-Verbose "Initializing myTech.Today RMM..."

        # Determine database path with fallback support
        if ($DatabasePath) {
            # Explicit path provided
            $script:DatabasePath = $DatabasePath
        } elseif (Test-Path $script:DatabasePath) {
            # New standard location exists - use it
            Write-Verbose "Using standard path: $($script:DatabasePath)"
        } elseif (Test-Path $script:LegacyDatabasePath) {
            # Fall back to legacy location if it exists
            Write-Verbose "Using legacy path: $($script:LegacyDatabasePath)"
            Write-Verbose "Consider running install-server-windows.ps1 to migrate to standard paths"
            $script:DatabasePath = $script:LegacyDatabasePath
            $script:RMMDataRoot = $script:LegacyInstallPath
            $script:DataPath = "$script:LegacyInstallPath\data"
            $script:ConfigPath = "$script:LegacyInstallPath\config"
            $script:LogPath = "$script:LegacyInstallPath\logs"
            $script:SettingsPath = "$script:ConfigPath\settings.json"
        }

        # Resolve full path
        if ($script:DatabasePath -and (Test-Path $script:DatabasePath -IsValid)) {
            $script:DatabasePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($script:DatabasePath)
        }

        # Check if database exists
        if (-not (Test-Path $script:DatabasePath)) {
            if (-not $Quiet) {
                Write-Warning "Database not found at: $script:DatabasePath"
                Write-Warning "Run install-server-windows.ps1 to install RMM and create the database"
            }
            return $false
        }

        # Initialize logging (Quiet mode unless explicitly verbose)
        Initialize-RMMLogging -ScriptName "RMM-Core" -ScriptVersion "2.1" -Quiet:(-not $VerbosePreference)

        # Test database connection
        try {
            $testQuery = "SELECT COUNT(*) as Count FROM sqlite_master WHERE type='table'"
            $result = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $testQuery -ErrorAction Stop
            Write-Verbose "Database connection successful. Tables found: $($result.Count)"
        }
        catch {
            if (-not $Quiet) { Write-RMMLog "Failed to connect to database: $($_.Exception.Message)" -Level ERROR }
            return $false
        }

        # Load configuration
        $config = Get-RMMConfiguration
        if (-not $config) {
            Write-Verbose "Failed to load configuration"
        }
        else {
            Write-Verbose "Configuration loaded successfully"
        }

        # Validate configuration - only warn if it fails
        $configValid = Test-RMMConfiguration
        if (-not $configValid) {
            Write-Verbose "Configuration validation failed"
        }

        $script:RMMInitialized = $true
        Write-Verbose "RMM initialization complete"

        return $true
    }
    catch {
        if (-not $Quiet) {
            Write-Error "Failed to initialize RMM: $_"
            Write-RMMLog "RMM initialization failed: $($_.Exception.Message)" -Level ERROR
        }
        return $false
    }
}

function Get-RMMConfig {
    <#
    .SYNOPSIS
        Retrieves RMM configuration settings.

    .DESCRIPTION
        Wrapper function for Get-RMMConfiguration. Loads and returns the RMM configuration.

    .PARAMETER Section
        Optional. Specific configuration section to retrieve.

    .PARAMETER Reload
        Force reload from disk, bypassing cache.

    .EXAMPLE
        $config = Get-RMMConfig
        Returns the entire configuration.

    .EXAMPLE
        $monitoring = Get-RMMConfig -Section "Monitoring"
        Returns only the Monitoring section.

    .OUTPUTS
        PSCustomObject
        The configuration object or section.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('General', 'Connections', 'Monitoring', 'Notifications', 'Security', 'Database', 'Performance', 'UI')]
        [string]$Section,

        [Parameter()]
        [switch]$Reload
    )

    return Get-RMMConfiguration @PSBoundParameters
}

function Set-RMMConfig {
    <#
    .SYNOPSIS
        Updates RMM configuration settings.

    .DESCRIPTION
        Wrapper function for Set-RMMConfiguration. Updates a configuration value.

    .PARAMETER Section
        The configuration section.

    .PARAMETER Key
        The configuration key.

    .PARAMETER Value
        The new value.

    .EXAMPLE
        Set-RMMConfig -Section "General" -Key "LogLevel" -Value "Debug"
        Sets the log level to Debug.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('General', 'Connections', 'Monitoring', 'Notifications', 'Security', 'Database', 'Performance', 'UI')]
        [string]$Section,

        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [object]$Value
    )

    return Set-RMMConfiguration @PSBoundParameters
}

function Get-LocalDeviceInfo {
    <#
    .SYNOPSIS
        Collects detailed local device information.

    .DESCRIPTION
        Cross-platform function that gathers comprehensive system information
        including OS details, hardware specs, network configuration, and more.
        Uses WMI/CIM on Windows, system_profiler on macOS, and lshw/dmidecode on Linux.

    .EXAMPLE
        Get-LocalDeviceInfo
        Returns a PSObject with all available device information.

    .OUTPUTS
        PSCustomObject with properties: Hostname, FQDN, IPAddress, MACAddress,
        OSName, OSVersion, OSBuild, DeviceType, Manufacturer, Model, SerialNumber
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Write-Verbose "Collecting local device information..."

    $info = [PSCustomObject]@{
        Hostname     = $env:COMPUTERNAME
        FQDN         = $null
        IPAddress    = $null
        MACAddress   = $null
        OSName       = $null
        OSVersion    = $null
        OSBuild      = $null
        DeviceType   = "Workstation"
        Manufacturer = $null
        Model        = $null
        SerialNumber = $null
    }

    # Get FQDN
    try {
        $info.FQDN = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
        Write-Verbose "FQDN: $($info.FQDN)"
    }
    catch {
        $info.FQDN = $env:COMPUTERNAME
        Write-Verbose "Could not resolve FQDN, using hostname: $_"
    }

    # Platform-specific collection
    if ($IsWindows -or (-not $IsLinux -and -not $IsMacOS)) {
        # Windows: Use CIM/WMI
        Write-Verbose "Collecting Windows system information via CIM..."

        # Network info
        try {
            $adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
                       Where-Object { $_.Status -eq 'Up' } |
                       Select-Object -First 1
            if ($adapter) {
                $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                            Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
                            Select-Object -First 1
                $info.IPAddress = $ipConfig.IPAddress
                $info.MACAddress = $adapter.MacAddress
                Write-Verbose "Network: IP=$($info.IPAddress), MAC=$($info.MACAddress)"
            }
        }
        catch {
            Write-Verbose "Network collection failed: $_"
        }

        # Fallback IP if above failed
        if (-not $info.IPAddress) {
            try {
                $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                      Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -ne 'WellKnown' } |
                      Select-Object -First 1
                $info.IPAddress = $ip.IPAddress
                Write-Verbose "Fallback IP: $($info.IPAddress)"
            }
            catch {
                Write-Verbose "Fallback IP collection failed: $_"
            }
        }

        # OS information
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $info.OSName = $os.Caption
            $info.OSVersion = $os.Version
            $info.OSBuild = $os.BuildNumber
            Write-Verbose "OS: $($info.OSName) v$($info.OSVersion) (Build $($info.OSBuild))"

            # Determine if server
            if ($os.ProductType -eq 2 -or $os.ProductType -eq 3) {
                $info.DeviceType = "Server"
            }
        }
        catch {
            Write-Warning "Could not retrieve OS information: $_"
        }

        # Hardware information
        try {
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            $info.Manufacturer = $cs.Manufacturer
            $info.Model = $cs.Model
            Write-Verbose "Hardware: $($info.Manufacturer) $($info.Model)"

            # Refine device type based on chassis
            if ($info.DeviceType -ne "Server") {
                switch ($cs.PCSystemType) {
                    1 { $info.DeviceType = "Desktop" }
                    2 { $info.DeviceType = "Laptop" }
                    3 { $info.DeviceType = "Workstation" }
                    4 { $info.DeviceType = "Server" }
                    5 { $info.DeviceType = "Server" }
                }
            }

            # Check for virtual machine
            if ($cs.Model -match 'Virtual|VMware|Hyper-V|VirtualBox|QEMU|KVM|Parallels') {
                $info.DeviceType = "Virtual"
                Write-Verbose "Virtual machine detected"
            }
        }
        catch {
            Write-Warning "Could not retrieve hardware information: $_"
        }

        # Serial number from BIOS
        try {
            $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
            $info.SerialNumber = $bios.SerialNumber
            Write-Verbose "Serial: $($info.SerialNumber)"
        }
        catch {
            Write-Verbose "Could not retrieve BIOS serial: $_"
        }
    }
    elseif ($IsMacOS) {
        # macOS: Use system_profiler and sw_vers
        Write-Verbose "Collecting macOS system information..."

        $info.Manufacturer = "Apple"

        # OS info
        try {
            $info.OSName = "macOS"
            $info.OSVersion = (sw_vers -productVersion 2>$null) -join ''
            $info.OSBuild = (sw_vers -buildVersion 2>$null) -join ''
            Write-Verbose "OS: macOS $($info.OSVersion) ($($info.OSBuild))"
        }
        catch {
            Write-Verbose "Could not get macOS version: $_"
        }

        # Hardware info
        try {
            $info.Model = (sysctl -n hw.model 2>$null) -join ''
            $hwInfo = system_profiler SPHardwareDataType 2>$null
            if ($hwInfo) {
                $serialMatch = $hwInfo | Select-String 'Serial Number.*:\s*(.+)$'
                if ($serialMatch) {
                    $info.SerialNumber = $serialMatch.Matches[0].Groups[1].Value.Trim()
                }
            }
            Write-Verbose "Hardware: Apple $($info.Model), Serial: $($info.SerialNumber)"
        }
        catch {
            Write-Verbose "Could not get macOS hardware info: $_"
        }

        # Network info
        try {
            $ifconfig = ifconfig 2>$null
            $ipMatch = $ifconfig | Select-String 'inet\s+(\d+\.\d+\.\d+\.\d+)' |
                       Where-Object { $_.Matches[0].Groups[1].Value -notmatch '^127\.' } |
                       Select-Object -First 1
            if ($ipMatch) {
                $info.IPAddress = $ipMatch.Matches[0].Groups[1].Value
            }
            $macMatch = $ifconfig | Select-String 'ether\s+([0-9a-f:]+)' | Select-Object -First 1
            if ($macMatch) {
                $info.MACAddress = $macMatch.Matches[0].Groups[1].Value.ToUpper()
            }
            Write-Verbose "Network: IP=$($info.IPAddress), MAC=$($info.MACAddress)"
        }
        catch {
            Write-Verbose "Could not get macOS network info: $_"
        }

        # Device type - check if laptop
        if ($info.Model -match 'MacBook') {
            $info.DeviceType = "Laptop"
        }
        elseif ($info.Model -match 'Mac Pro|Mac Studio') {
            $info.DeviceType = "Workstation"
        }
        else {
            $info.DeviceType = "Desktop"
        }
    }
    elseif ($IsLinux) {
        # Linux: Use various system commands
        Write-Verbose "Collecting Linux system information..."

        # Hostname (Linux-style)
        if (-not $info.Hostname) {
            $info.Hostname = (hostname 2>$null) -join ''
        }

        # OS info from /etc/os-release
        try {
            if (Test-Path /etc/os-release) {
                $osRelease = Get-Content /etc/os-release -ErrorAction Stop
                $prettyName = $osRelease | Select-String '^PRETTY_NAME="?([^"]+)"?$'
                if ($prettyName) {
                    $info.OSName = $prettyName.Matches[0].Groups[1].Value
                }
                else {
                    $info.OSName = "Linux"
                }
            }
            $info.OSVersion = (uname -r 2>$null) -join ''
            Write-Verbose "OS: $($info.OSName) $($info.OSVersion)"
        }
        catch {
            $info.OSName = "Linux"
            Write-Verbose "Could not get Linux OS info: $_"
        }

        # Hardware info - try dmidecode (requires root) or lshw
        try {
            if (Get-Command dmidecode -ErrorAction SilentlyContinue) {
                $dmi = sudo dmidecode -s system-manufacturer 2>$null
                if ($dmi) { $info.Manufacturer = ($dmi -join '').Trim() }

                $dmi = sudo dmidecode -s system-product-name 2>$null
                if ($dmi) { $info.Model = ($dmi -join '').Trim() }

                $dmi = sudo dmidecode -s system-serial-number 2>$null
                if ($dmi) { $info.SerialNumber = ($dmi -join '').Trim() }
            }
            elseif (Get-Command lshw -ErrorAction SilentlyContinue) {
                $lshw = sudo lshw -class system -short 2>$null
                # Parse lshw output if available
            }
            Write-Verbose "Hardware: $($info.Manufacturer) $($info.Model)"
        }
        catch {
            Write-Verbose "Could not get Linux hardware info (may need root): $_"
        }

        # Network info
        try {
            if (Get-Command ip -ErrorAction SilentlyContinue) {
                $ipAddr = ip -4 addr show 2>$null
                $ipMatch = $ipAddr | Select-String 'inet\s+(\d+\.\d+\.\d+\.\d+)' |
                           Where-Object { $_.Matches[0].Groups[1].Value -notmatch '^127\.' } |
                           Select-Object -First 1
                if ($ipMatch) {
                    $info.IPAddress = $ipMatch.Matches[0].Groups[1].Value
                }

                $linkInfo = ip link show 2>$null
                $macMatch = $linkInfo | Select-String 'link/ether\s+([0-9a-f:]+)' | Select-Object -First 1
                if ($macMatch) {
                    $info.MACAddress = $macMatch.Matches[0].Groups[1].Value.ToUpper()
                }
            }
            Write-Verbose "Network: IP=$($info.IPAddress), MAC=$($info.MACAddress)"
        }
        catch {
            Write-Verbose "Could not get Linux network info: $_"
        }

        # Check if virtual
        if (Test-Path /sys/class/dmi/id/product_name) {
            $product = Get-Content /sys/class/dmi/id/product_name -ErrorAction SilentlyContinue
            if ($product -match 'Virtual|VMware|VirtualBox|QEMU|KVM') {
                $info.DeviceType = "Virtual"
            }
        }
    }

    Write-Verbose "Device info collection complete"
    return $info
}

function Get-RMMDevice {
    <#
    .SYNOPSIS
        Queries devices from the RMM database.

    .DESCRIPTION
        Retrieves device information with optional filtering by site, group, status, or tags.

    .PARAMETER DeviceId
        Optional. Specific device ID to retrieve.

    .PARAMETER Hostname
        Optional. Filter by hostname (supports wildcards).

    .PARAMETER SiteId
        Optional. Filter by site ID.

    .PARAMETER Status
        Optional. Filter by device status (Online, Offline, Unknown, etc.).

    .PARAMETER Tag
        Optional. Filter by tag.

    .EXAMPLE
        Get-RMMDevice
        Returns all devices.

    .EXAMPLE
        Get-RMMDevice -Status "Online"
        Returns all online devices.

    .EXAMPLE
        Get-RMMDevice -SiteId "main" -Status "Offline"
        Returns all offline devices at the main site.

    .OUTPUTS
        PSCustomObject[]
        Array of device objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$DeviceId,

        [Parameter()]
        [string]$Hostname,

        [Parameter()]
        [string]$SiteId,

        [Parameter()]
        [ValidateSet('Online', 'Offline', 'Unknown', 'Maintenance', 'Decommissioned')]
        [string]$Status,

        [Parameter()]
        [string]$Tag
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        # Build query
        $query = "SELECT * FROM Devices WHERE 1=1"
        $params = @{}

        if ($DeviceId) {
            $query += " AND DeviceId = @DeviceId"
            $params.DeviceId = $DeviceId
        }

        if ($Hostname) {
            $query += " AND Hostname LIKE @Hostname"
            $params.Hostname = $Hostname.Replace('*', '%')
        }

        if ($SiteId) {
            $query += " AND SiteId = @SiteId"
            $params.SiteId = $SiteId
        }

        if ($Status) {
            $query += " AND Status = @Status"
            $params.Status = $Status
        }

        if ($Tag) {
            $query += " AND Tags LIKE @Tag"
            $params.Tag = "%$Tag%"
        }

        $query += " ORDER BY Hostname"

        # Execute query
        if ($params.Count -gt 0) {
            $devices = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $query -SqlParameters $params
        }
        else {
            $devices = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $query
        }

        return $devices
    }
    catch {
        Write-Error "Failed to query devices: $_"
        Write-RMMLog "Failed to query devices: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Add-RMMDevice {
    <#
    .SYNOPSIS
        Registers a new device in the RMM system.

    .DESCRIPTION
        Adds a new device to the Devices table with the specified information.
        Optionally associates WinRM credentials for remote management.

    .PARAMETER Hostname
        The hostname of the device.

    .PARAMETER FQDN
        Optional. Fully Qualified Domain Name.

    .PARAMETER IPAddress
        Optional. IP address of the device.

    .PARAMETER MACAddress
        Optional. MAC address of the device.

    .PARAMETER SiteId
        Optional. Site ID (default: from configuration).

    .PARAMETER DeviceType
        Optional. Device type: Workstation, Server, Laptop, etc.

    .PARAMETER Description
        Optional. Description of the device.

    .PARAMETER Tags
        Optional. Comma-separated tags.

    .PARAMETER CredentialName
        Optional. Name of saved credential to use for WinRM connections.
        Use Save-RMMCredential to store credentials first.

    .PARAMETER Credential
        Optional. PSCredential object for WinRM connections.
        If provided with -SaveCredential, saves the credential for future use.

    .PARAMETER SaveCredential
        If specified with -Credential, saves the credential using the hostname as the name.

    .EXAMPLE
        Add-RMMDevice -Hostname "SERVER01" -IPAddress "192.168.1.10" -Tags "production,critical"
        Adds a new server device.

    .EXAMPLE
        Add-RMMDevice -Hostname "WEB01" -SiteId "datacenter" -Description "Primary web server" -Credential (Get-Credential) -SaveCredential
        Adds a device and saves WinRM credentials for it.

    .OUTPUTS
        System.String
        The DeviceId of the newly created device.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Hostname,

        [Parameter()]
        [string]$FQDN,

        [Parameter()]
        [string]$IPAddress,

        [Parameter()]
        [string]$MACAddress,

        [Parameter()]
        [string]$SiteId,

        [Parameter()]
        [ValidateSet('Workstation', 'Server', 'Laptop', 'Virtual', 'Container', 'Other')]
        [string]$DeviceType = 'Workstation',

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Tags,

        [Parameter()]
        [string]$CredentialName,

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [switch]$SaveCredential
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        # Generate DeviceId
        $deviceId = [guid]::NewGuid().ToString()

        # Get default site if not specified
        if (-not $SiteId) {
            $config = Get-RMMConfiguration
            $SiteId = $config.General.DefaultSite
        }

        # Handle credentials
        $credName = $CredentialName
        if ($Credential -and $SaveCredential) {
            $credName = "Device-$Hostname"
            Save-RMMCredential -Name $credName -Credential $Credential -Description "WinRM credential for $Hostname"
            Write-Host "[OK] Credential saved as: $credName" -ForegroundColor Green
        }

        if ($PSCmdlet.ShouldProcess($Hostname, "Add device")) {
            $query = @"
INSERT INTO Devices (DeviceId, Hostname, FQDN, IPAddress, MACAddress, SiteId, DeviceType, Description, Tags, CredentialName, Status, CreatedAt, UpdatedAt)
VALUES (@DeviceId, @Hostname, @FQDN, @IPAddress, @MACAddress, @SiteId, @DeviceType, @Description, @Tags, @CredentialName, 'Unknown', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
"@

            $params = @{
                DeviceId       = $deviceId
                Hostname       = $Hostname
                FQDN           = $FQDN
                IPAddress      = $IPAddress
                MACAddress     = $MACAddress
                SiteId         = $SiteId
                DeviceType     = $DeviceType
                Description    = $Description
                Tags           = $Tags
                CredentialName = $credName
            }

            Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $query -SqlParameters $params

            Write-Host "[OK] Device added: $Hostname ($deviceId)" -ForegroundColor Green
            Write-RMMLog "Device added: $Hostname ($deviceId)" -Level SUCCESS
            Write-RMMDeviceLog -DeviceId $deviceId -Message "Device registered in RMM system" -Level SUCCESS

            return $deviceId
        }
    }
    catch {
        Write-Error "Failed to add device: $_"
        Write-RMMLog "Failed to add device ${Hostname}: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Update-RMMDevice {
    <#
    .SYNOPSIS
        Updates device information in the RMM system.

    .DESCRIPTION
        Updates one or more fields for an existing device.

    .PARAMETER DeviceId
        The unique identifier of the device to update.

    .PARAMETER Hostname
        Optional. New hostname.

    .PARAMETER IPAddress
        Optional. New IP address.

    .PARAMETER Status
        Optional. New status.

    .PARAMETER Tags
        Optional. New tags (comma-separated).

    .EXAMPLE
        Update-RMMDevice -DeviceId "abc123" -Status "Online"
        Updates the device status to Online.

    .EXAMPLE
        Update-RMMDevice -DeviceId "abc123" -IPAddress "192.168.1.20" -Tags "production,updated"
        Updates IP address and tags.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceId,

        [Parameter()]
        [string]$Hostname,

        [Parameter()]
        [string]$IPAddress,

        [Parameter()]
        [ValidateSet('Online', 'Offline', 'Unknown', 'Maintenance', 'Decommissioned')]
        [string]$Status,

        [Parameter()]
        [string]$Tags
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        # Build update query dynamically
        $updates = @()
        $params = @{ DeviceId = $DeviceId }

        if ($Hostname) {
            $updates += "Hostname = @Hostname"
            $params.Hostname = $Hostname
        }

        if ($IPAddress) {
            $updates += "IPAddress = @IPAddress"
            $params.IPAddress = $IPAddress
        }

        if ($Status) {
            $updates += "Status = @Status"
            $params.Status = $Status
        }

        if ($Tags) {
            $updates += "Tags = @Tags"
            $params.Tags = $Tags
        }

        if ($updates.Count -eq 0) {
            Write-Warning "No updates specified"
            return
        }

        $updates += "UpdatedAt = CURRENT_TIMESTAMP"

        if ($PSCmdlet.ShouldProcess($DeviceId, "Update device")) {
            $query = "UPDATE Devices SET $($updates -join ', ') WHERE DeviceId = @DeviceId"
            Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $query -SqlParameters $params

            Write-Host "[OK] Device updated: $DeviceId" -ForegroundColor Green
            Write-RMMLog "Device updated: $DeviceId" -Level SUCCESS
            Write-RMMDeviceLog -DeviceId $DeviceId -Message "Device information updated" -Level INFO
        }
    }
    catch {
        Write-Error "Failed to update device: $_"
        Write-RMMLog "Failed to update device ${DeviceId}: $($_.Exception.Message)" -Level ERROR
    }
}

function Update-RMMDeviceInfo {
    <#
    .SYNOPSIS
        Updates device system information from live collection.

    .DESCRIPTION
        Refreshes device hardware, OS, and network information in the database
        by collecting current system data. Useful after hardware changes,
        OS upgrades, or to fix incomplete device records.

    .PARAMETER DeviceId
        The device ID to update. If not specified, updates the local device.

    .PARAMETER Hostname
        The hostname to find and update. If not specified, uses local hostname.

    .EXAMPLE
        Update-RMMDeviceInfo
        Updates the local device's information in the database.

    .EXAMPLE
        Update-RMMDeviceInfo -Hostname "SERVER01"
        Updates system info for SERVER01 (collects from local if matching hostname).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$DeviceId,

        [Parameter()]
        [string]$Hostname
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        # Determine which device to update
        if (-not $DeviceId -and -not $Hostname) {
            $Hostname = $env:COMPUTERNAME
        }

        # Find the device
        $device = $null
        if ($DeviceId) {
            $device = Get-RMMDevice -DeviceId $DeviceId
        }
        else {
            $device = Get-RMMDevice -Hostname $Hostname
        }

        if (-not $device) {
            Write-Warning "Device not found: $(if ($DeviceId) { $DeviceId } else { $Hostname })"
            return
        }

        # Can only collect live info for the local device
        $isLocal = $device.Hostname -eq $env:COMPUTERNAME

        if (-not $isLocal) {
            Write-Warning "Cannot collect live system info for remote device '$($device.Hostname)'. Use Inventory-Collector.ps1 for remote devices."
            return
        }

        Write-Host "Collecting system information for $($device.Hostname)..." -ForegroundColor Cyan

        # Get current system info
        $info = Get-LocalDeviceInfo

        if ($PSCmdlet.ShouldProcess($device.Hostname, "Update device system information")) {
            $query = @"
UPDATE Devices SET
    FQDN = @FQDN,
    IPAddress = @IPAddress,
    MACAddress = @MACAddress,
    OSName = @OSName,
    OSVersion = @OSVersion,
    OSBuild = @OSBuild,
    DeviceType = @DeviceType,
    Manufacturer = @Manufacturer,
    Model = @Model,
    SerialNumber = @SerialNumber,
    LastSeen = CURRENT_TIMESTAMP,
    UpdatedAt = CURRENT_TIMESTAMP
WHERE DeviceId = @DeviceId
"@

            $params = @{
                DeviceId     = $device.DeviceId
                FQDN         = $info.FQDN
                IPAddress    = $info.IPAddress
                MACAddress   = $info.MACAddress
                OSName       = $info.OSName
                OSVersion    = $info.OSVersion
                OSBuild      = $info.OSBuild
                DeviceType   = $info.DeviceType
                Manufacturer = $info.Manufacturer
                Model        = $info.Model
                SerialNumber = $info.SerialNumber
            }

            Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $query -SqlParameters $params

            Write-Host "[OK] Device info updated: $($device.Hostname)" -ForegroundColor Green
            Write-Host "     OS: $($info.OSName) $($info.OSVersion)" -ForegroundColor Gray
            Write-Host "     Hardware: $($info.Manufacturer) $($info.Model)" -ForegroundColor Gray
            Write-Host "     Serial: $($info.SerialNumber)" -ForegroundColor Gray
            Write-RMMLog "Device info refreshed: $($device.Hostname)" -Level SUCCESS
            Write-RMMDeviceLog -DeviceId $device.DeviceId -Message "Device system information updated" -Level INFO

            # Return updated device
            return Get-RMMDevice -DeviceId $device.DeviceId
        }
    }
    catch {
        Write-Error "Failed to update device info: $_"
        Write-RMMLog "Failed to update device info: $($_.Exception.Message)" -Level ERROR
    }
}

function Remove-RMMDevice {
    <#
    .SYNOPSIS
        Removes a device from the RMM system.

    .DESCRIPTION
        Unregisters a device from the RMM database. This does not delete historical data.

    .PARAMETER DeviceId
        The unique identifier of the device to remove.

    .PARAMETER Force
        Skip confirmation prompt.

    .EXAMPLE
        Remove-RMMDevice -DeviceId "abc123"
        Removes the device with confirmation.

    .EXAMPLE
        Remove-RMMDevice -DeviceId "abc123" -Force
        Removes the device without confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$DeviceId,

        [Parameter()]
        [switch]$Force
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        # Get device info for confirmation
        $device = Get-RMMDevice -DeviceId $DeviceId

        if (-not $device) {
            Write-Warning "Device not found: $DeviceId"
            return
        }

        if ($Force -or $PSCmdlet.ShouldProcess("$($device.Hostname) ($DeviceId)", "Remove device")) {
            $query = "DELETE FROM Devices WHERE DeviceId = @DeviceId"
            Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $query -SqlParameters @{ DeviceId = $DeviceId }

            Write-Host "[OK] Device removed: $($device.Hostname)" -ForegroundColor Green
            Write-RMMLog "Device removed: $($device.Hostname) ($DeviceId)" -Level SUCCESS
            Write-RMMDeviceLog -DeviceId $DeviceId -Message "Device unregistered from RMM system" -Level WARNING
        }
    }
    catch {
        Write-Error "Failed to remove device: $_"
        Write-RMMLog "Failed to remove device ${DeviceId}: $($_.Exception.Message)" -Level ERROR
    }
}

#region Site Management Functions

function Get-RMMSite {
    <#
    .SYNOPSIS
        Retrieves site information from the RMM system.

    .DESCRIPTION
        Gets one or more sites with optional filtering by SiteId or Name.

    .PARAMETER SiteId
        Optional. Filter by specific site ID.

    .PARAMETER Name
        Optional. Filter by site name (supports wildcards).

    .EXAMPLE
        Get-RMMSite
        Returns all sites.

    .EXAMPLE
        Get-RMMSite -SiteId "main"
        Returns the site with ID "main".
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SiteId,

        [Parameter()]
        [string]$Name
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        $query = "SELECT * FROM Sites WHERE 1=1"
        $params = @{}

        if ($SiteId) {
            $query += " AND SiteId = @SiteId"
            $params['SiteId'] = $SiteId
        }

        if ($Name) {
            $query += " AND Name LIKE @Name"
            $params['Name'] = $Name -replace '\*', '%'
        }

        $query += " ORDER BY Name"

        $sites = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $query -SqlParameters $params

        # Get URLs for each site
        foreach ($site in $sites) {
            $urlQuery = "SELECT URLId, URL, Label FROM SiteURLs WHERE SiteId = @SiteId ORDER BY Label"
            $urls = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $urlQuery -SqlParameters @{ SiteId = $site.SiteId }
            $site | Add-Member -NotePropertyName 'URLs' -NotePropertyValue @($urls) -Force
        }

        return $sites
    }
    catch {
        Write-Error "Failed to get sites: $_"
    }
}

function New-RMMSite {
    <#
    .SYNOPSIS
        Creates a new site in the RMM system.

    .DESCRIPTION
        Adds a new site with contact and address information.

    .PARAMETER Name
        Required. The display name of the site.

    .PARAMETER ContactName
        Contact person's name.

    .PARAMETER ContactEmail
        Contact email address.

    .PARAMETER MainPhone
        Main phone number.

    .PARAMETER CellPhone
        Cell phone number.

    .PARAMETER StreetNumber
        Street address number.

    .PARAMETER StreetName
        Street name.

    .PARAMETER Unit
        Unit or suite number.

    .PARAMETER Building
        Building name.

    .PARAMETER City
        City name.

    .PARAMETER State
        State or province.

    .PARAMETER Zip
        Postal/ZIP code.

    .PARAMETER Country
        Country name.

    .PARAMETER Timezone
        Timezone identifier.

    .PARAMETER Notes
        Additional notes.

    .EXAMPLE
        New-RMMSite -Name "Main Office" -City "New York" -State "NY"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$ContactName,

        [Parameter()]
        [string]$ContactEmail,

        [Parameter()]
        [string]$MainPhone,

        [Parameter()]
        [string]$CellPhone,

        [Parameter()]
        [string]$StreetNumber,

        [Parameter()]
        [string]$StreetName,

        [Parameter()]
        [string]$Unit,

        [Parameter()]
        [string]$Building,

        [Parameter()]
        [string]$City,

        [Parameter()]
        [string]$State,

        [Parameter()]
        [string]$Zip,

        [Parameter()]
        [string]$Country,

        [Parameter()]
        [string]$Timezone,

        [Parameter()]
        [string]$Notes
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        # Generate SiteId from name
        $SiteId = $Name.ToLower() -replace '[^a-z0-9]', '-'

        # Check if exists
        $existing = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "SELECT SiteId FROM Sites WHERE SiteId = @SiteId" -SqlParameters @{ SiteId = $SiteId }
        if ($existing) {
            Write-Warning "Site already exists with ID: $SiteId"
            return
        }

        # Build location string
        $locationParts = @()
        if ($City) { $locationParts += $City }
        if ($State) { $locationParts += $State }
        if ($Country) { $locationParts += $Country }
        $Location = $locationParts -join ', '

        $query = @"
INSERT INTO Sites (SiteId, Name, Location, ContactName, ContactEmail, MainPhone, CellPhone,
    StreetNumber, StreetName, Unit, Building, City, State, Zip, Country, Timezone, Notes, CreatedAt)
VALUES (@SiteId, @Name, @Location, @ContactName, @ContactEmail, @MainPhone, @CellPhone,
    @StreetNumber, @StreetName, @Unit, @Building, @City, @State, @Zip, @Country, @Timezone, @Notes, CURRENT_TIMESTAMP)
"@

        $params = @{
            SiteId = $SiteId; Name = $Name; Location = $Location; ContactName = $ContactName
            ContactEmail = $ContactEmail; MainPhone = $MainPhone; CellPhone = $CellPhone
            StreetNumber = $StreetNumber; StreetName = $StreetName; Unit = $Unit; Building = $Building
            City = $City; State = $State; Zip = $Zip; Country = $Country; Timezone = $Timezone; Notes = $Notes
        }

        Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $query -SqlParameters $params

        Write-Host "[OK] Site created: $Name ($SiteId)" -ForegroundColor Green
        Write-RMMLog "Site created: $Name ($SiteId)" -Level SUCCESS

        return Get-RMMSite -SiteId $SiteId
    }
    catch {
        Write-Error "Failed to create site: $_"
        Write-RMMLog "Failed to create site ${Name}: $($_.Exception.Message)" -Level ERROR
    }
}

function Set-RMMSite {
    <#
    .SYNOPSIS
        Updates an existing site in the RMM system.

    .DESCRIPTION
        Modifies site properties. Only specified parameters are updated.

    .PARAMETER SiteId
        Required. The ID of the site to update.

    .EXAMPLE
        Set-RMMSite -SiteId "main" -MainPhone "555-1234" -City "Los Angeles"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SiteId,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$ContactName,

        [Parameter()]
        [string]$ContactEmail,

        [Parameter()]
        [string]$MainPhone,

        [Parameter()]
        [string]$CellPhone,

        [Parameter()]
        [string]$StreetNumber,

        [Parameter()]
        [string]$StreetName,

        [Parameter()]
        [string]$Unit,

        [Parameter()]
        [string]$Building,

        [Parameter()]
        [string]$City,

        [Parameter()]
        [string]$State,

        [Parameter()]
        [string]$Zip,

        [Parameter()]
        [string]$Country,

        [Parameter()]
        [string]$Timezone,

        [Parameter()]
        [string]$Notes
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        # Check site exists
        $existing = Get-RMMSite -SiteId $SiteId
        if (-not $existing) {
            Write-Warning "Site not found: $SiteId"
            return
        }

        # Build dynamic update
        $updates = @()
        $params = @{ SiteId = $SiteId }
        $fields = @('Name','ContactName','ContactEmail','MainPhone','CellPhone','StreetNumber','StreetName','Unit','Building','City','State','Zip','Country','Timezone','Notes')

        foreach ($field in $fields) {
            $value = Get-Variable -Name $field -ValueOnly -ErrorAction SilentlyContinue
            if ($PSBoundParameters.ContainsKey($field)) {
                $updates += "$field = @$field"
                $params[$field] = $value
            }
        }

        if ($updates.Count -eq 0) {
            Write-Warning "No updates specified"
            return
        }

        # Update Location if address fields changed
        if ($PSBoundParameters.ContainsKey('City') -or $PSBoundParameters.ContainsKey('State') -or $PSBoundParameters.ContainsKey('Country')) {
            $newCity = if ($PSBoundParameters.ContainsKey('City')) { $City } else { $existing.City }
            $newState = if ($PSBoundParameters.ContainsKey('State')) { $State } else { $existing.State }
            $newCountry = if ($PSBoundParameters.ContainsKey('Country')) { $Country } else { $existing.Country }
            $locationParts = @($newCity, $newState, $newCountry) | Where-Object { $_ }
            $params['Location'] = $locationParts -join ', '
            $updates += "Location = @Location"
        }

        $query = "UPDATE Sites SET " + ($updates -join ', ') + " WHERE SiteId = @SiteId"
        Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $query -SqlParameters $params

        Write-Host "[OK] Site updated: $SiteId" -ForegroundColor Green
        Write-RMMLog "Site updated: $SiteId" -Level SUCCESS

        return Get-RMMSite -SiteId $SiteId
    }
    catch {
        Write-Error "Failed to update site: $_"
        Write-RMMLog "Failed to update site ${SiteId}: $($_.Exception.Message)" -Level ERROR
    }
}

function Remove-RMMSite {
    <#
    .SYNOPSIS
        Removes a site from the RMM system.

    .PARAMETER SiteId
        The ID of the site to remove.

    .PARAMETER Force
        Skip confirmation prompt.

    .EXAMPLE
        Remove-RMMSite -SiteId "old-site" -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$SiteId,

        [Parameter()]
        [switch]$Force
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        $site = Get-RMMSite -SiteId $SiteId
        if (-not $site) {
            Write-Warning "Site not found: $SiteId"
            return
        }

        # Check for devices using this site
        $deviceCount = (Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "SELECT COUNT(*) as Count FROM Devices WHERE SiteId = @SiteId" -SqlParameters @{ SiteId = $SiteId }).Count
        if ($deviceCount -gt 0) {
            Write-Warning "Cannot remove site '$($site.Name)': $deviceCount devices are assigned to it"
            return
        }

        if ($Force -or $PSCmdlet.ShouldProcess("$($site.Name) ($SiteId)", "Remove site")) {
            Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "DELETE FROM SiteURLs WHERE SiteId = @SiteId" -SqlParameters @{ SiteId = $SiteId }
            Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "DELETE FROM Sites WHERE SiteId = @SiteId" -SqlParameters @{ SiteId = $SiteId }

            Write-Host "[OK] Site removed: $($site.Name)" -ForegroundColor Green
            Write-RMMLog "Site removed: $($site.Name) ($SiteId)" -Level SUCCESS
        }
    }
    catch {
        Write-Error "Failed to remove site: $_"
        Write-RMMLog "Failed to remove site ${SiteId}: $($_.Exception.Message)" -Level ERROR
    }
}

function Add-RMMSiteURL {
    <#
    .SYNOPSIS
        Adds a URL to a site.

    .PARAMETER SiteId
        The site ID.

    .PARAMETER URL
        The URL to add.

    .PARAMETER Label
        Optional label for the URL (e.g., "Website", "Portal", "Documentation").

    .EXAMPLE
        Add-RMMSiteURL -SiteId "main" -URL "https://example.com" -Label "Website"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SiteId,

        [Parameter(Mandatory)]
        [string]$URL,

        [Parameter()]
        [string]$Label
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        $site = Get-RMMSite -SiteId $SiteId
        if (-not $site) {
            Write-Warning "Site not found: $SiteId"
            return
        }

        $query = "INSERT INTO SiteURLs (SiteId, URL, Label, CreatedAt) VALUES (@SiteId, @URL, @Label, CURRENT_TIMESTAMP)"
        Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $query -SqlParameters @{ SiteId = $SiteId; URL = $URL; Label = $Label }

        Write-Host "[OK] URL added to site $SiteId" -ForegroundColor Green
        return Get-RMMSite -SiteId $SiteId
    }
    catch {
        Write-Error "Failed to add URL: $_"
    }
}

function Remove-RMMSiteURL {
    <#
    .SYNOPSIS
        Removes a URL from a site.

    .PARAMETER URLId
        The URL ID to remove.

    .EXAMPLE
        Remove-RMMSiteURL -URLId 1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$URLId
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        Invoke-SqliteQuery -DataSource $script:DatabasePath -Query "DELETE FROM SiteURLs WHERE URLId = @URLId" -SqlParameters @{ URLId = $URLId }
        Write-Host "[OK] URL removed" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to remove URL: $_"
    }
}

#endregion

function Import-RMMDevices {
    <#
    .SYNOPSIS
        Imports devices from a file into the RMM system.

    .DESCRIPTION
        Imports device records from CSV, JSON, XLS, or XLSX files.
        Validates required fields and skips duplicate hostnames.

    .PARAMETER Path
        Path to the import file (.csv, .json, .xls, .xlsx).

    .PARAMETER SiteId
        Optional. Default site ID for imported devices.

    .PARAMETER OverwriteExisting
        If specified, removes and reimports devices that already exist (by hostname).
        By default, existing devices are skipped.

    .EXAMPLE
        Import-RMMDevices -Path "devices.csv"
        Imports devices from a CSV file.

    .EXAMPLE
        Import-RMMDevices -Path "inventory.xlsx" -SiteId "branch-office"
        Imports devices from Excel with a specific site.

    .OUTPUTS
        PSCustomObject with import statistics.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$Path,

        [Parameter()]
        [string]$SiteId,

        [Parameter()]
        [switch]$OverwriteExisting
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        $extension = [System.IO.Path]::GetExtension($Path).ToLower()
        $devices = @()

        # Parse file based on extension
        switch ($extension) {
            ".csv" {
                $devices = Import-Csv -Path $Path -ErrorAction Stop
            }
            ".json" {
                $devices = Get-Content -Path $Path -Raw | ConvertFrom-Json -ErrorAction Stop
            }
            { $_ -in ".xls", ".xlsx" } {
                if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
                    throw "ImportExcel module required for Excel files. Install with: Install-Module ImportExcel"
                }
                Import-Module ImportExcel -ErrorAction Stop
                $devices = Import-Excel -Path $Path -ErrorAction Stop
            }
            default {
                throw "Unsupported file format: $extension. Supported: .csv, .json, .xls, .xlsx"
            }
        }

        if (-not $devices -or $devices.Count -eq 0) {
            Write-Warning "No devices found in file: $Path"
            return @{ Imported = 0; Skipped = 0; Failed = 0; Total = 0 }
        }

        $imported = 0
        $skipped = 0
        $failed = 0

        foreach ($device in $devices) {
            try {
                # Validate required field
                if (-not $device.Hostname) {
                    Write-Warning "Skipping device with missing hostname"
                    $failed++
                    continue
                }

                # Check for existing device
                $existing = Get-RMMDevice -Hostname $device.Hostname -ErrorAction SilentlyContinue
                if ($existing -and -not $OverwriteExisting) {
                    Write-Host "[SKIP] Device already exists: $($device.Hostname)" -ForegroundColor Yellow
                    $skipped++
                    continue
                }
                elseif ($existing -and $OverwriteExisting) {
                    # Remove existing device to allow reimport
                    Remove-RMMDevice -DeviceId $existing.DeviceId -Force -ErrorAction SilentlyContinue
                }

                # Determine site
                $deviceSite = if ($device.SiteId) { $device.SiteId } elseif ($SiteId) { $SiteId } else { "default" }

                # Add device
                $params = @{
                    Hostname = $device.Hostname
                    SiteId   = $deviceSite
                }
                if ($device.FQDN) { $params.FQDN = $device.FQDN }
                if ($device.IPAddress) { $params.IPAddress = $device.IPAddress }
                if ($device.MACAddress) { $params.MACAddress = $device.MACAddress }
                if ($device.DeviceType) { $params.DeviceType = $device.DeviceType }
                if ($device.Description) { $params.Description = $device.Description }
                if ($device.Tags) { $params.Tags = $device.Tags }

                if ($PSCmdlet.ShouldProcess($device.Hostname, "Import device")) {
                    Add-RMMDevice @params -ErrorAction Stop | Out-Null
                    $imported++
                }
            }
            catch {
                Write-Warning "Failed to import device $($device.Hostname): $_"
                $failed++
            }
        }

        $result = @{
            Imported = $imported
            Skipped  = $skipped
            Failed   = $failed
            Total    = $devices.Count
        }

        Write-Host ""
        Write-Host "[IMPORT COMPLETE]" -ForegroundColor Cyan
        Write-Host "  Total:    $($result.Total)" -ForegroundColor White
        Write-Host "  Imported: $($result.Imported)" -ForegroundColor Green
        Write-Host "  Skipped:  $($result.Skipped)" -ForegroundColor Yellow
        Write-Host "  Failed:   $($result.Failed)" -ForegroundColor Red

        Write-RMMLog "Imported $imported devices from $Path (skipped: $skipped, failed: $failed)" -Level INFO
        return $result
    }
    catch {
        Write-Error "Failed to import devices: $_"
        Write-RMMLog "Failed to import devices from ${Path}: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Export-RMMDevices {
    <#
    .SYNOPSIS
        Exports devices from the RMM system to a file.

    .DESCRIPTION
        Exports device records to CSV, JSON, XLS, or XLSX format.

    .PARAMETER Path
        Path for the export file (.csv, .json, .xls, .xlsx).

    .PARAMETER SiteId
        Optional. Filter devices by site ID.

    .PARAMETER Status
        Optional. Filter devices by status (Online, Offline, Unknown).

    .PARAMETER Tags
        Optional. Filter devices by tag.

    .PARAMETER IncludeCredentials
        If specified, includes credential names in export (not the actual credentials).

    .EXAMPLE
        Export-RMMDevices -Path "devices.csv"
        Exports all devices to CSV.

    .EXAMPLE
        Export-RMMDevices -Path "servers.xlsx" -Tags "server"
        Exports server devices to Excel.

    .OUTPUTS
        System.String - Path to the exported file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$SiteId,

        [Parameter()]
        [ValidateSet('Online', 'Offline', 'Unknown')]
        [string]$Status,

        [Parameter()]
        [string]$Tags,

        [Parameter()]
        [switch]$IncludeCredentials
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        # Get devices with filters
        $params = @{}
        if ($SiteId) { $params.SiteId = $SiteId }
        if ($Status) { $params.Status = $Status }
        if ($Tags) { $params.Tags = $Tags }

        $devices = Get-RMMDevice @params

        if (-not $devices -or $devices.Count -eq 0) {
            Write-Warning "No devices found matching the criteria"
            return $null
        }

        # Select columns for export
        $exportColumns = @('DeviceId', 'Hostname', 'FQDN', 'IPAddress', 'MACAddress', 'Status', 'SiteId', 'DeviceType', 'OSName', 'OSVersion', 'Description', 'Tags', 'LastSeen', 'CreatedAt')
        if ($IncludeCredentials) {
            $exportColumns += 'CredentialName'
        }

        $exportData = $devices | Select-Object $exportColumns

        $extension = [System.IO.Path]::GetExtension($Path).ToLower()

        # Ensure directory exists
        $directory = Split-Path -Parent $Path
        if ($directory -and -not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        # Export based on extension
        switch ($extension) {
            ".csv" {
                $exportData | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 -Force
            }
            ".json" {
                $exportData | ConvertTo-Json -Depth 5 | Out-File -FilePath $Path -Encoding UTF8 -Force
            }
            { $_ -in ".xls", ".xlsx" } {
                if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
                    throw "ImportExcel module required for Excel files. Install with: Install-Module ImportExcel"
                }
                Import-Module ImportExcel -ErrorAction Stop
                $exportData | Export-Excel -Path $Path -AutoSize -TableName "Devices" -WorksheetName "Devices"
            }
            default {
                throw "Unsupported file format: $extension. Supported: .csv, .json, .xls, .xlsx"
            }
        }

        Write-Host "[OK] Exported $($devices.Count) devices to: $Path" -ForegroundColor Green
        Write-RMMLog "Exported $($devices.Count) devices to $Path" -Level INFO
        return $Path
    }
    catch {
        Write-Error "Failed to export devices: $_"
        Write-RMMLog "Failed to export devices to ${Path}: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Invoke-RMMAction {
    <#
    .SYNOPSIS
        Executes an action on one or more devices.

    .DESCRIPTION
        Queues and executes actions on devices with retry logic and logging.
        Actions are logged to the Actions table and device logs.

    .PARAMETER DeviceId
        The device ID(s) to execute the action on.

    .PARAMETER ActionType
        The type of action to execute (e.g., "HealthCheck", "Restart", "RunScript").

    .PARAMETER Payload
        Optional. Action-specific payload data (as hashtable).

    .PARAMETER Priority
        Optional. Action priority (1-10, default: 5).

    .PARAMETER ScheduledAt
        Optional. Schedule the action for a future time.

    .EXAMPLE
        Invoke-RMMAction -DeviceId "abc123" -ActionType "HealthCheck"
        Executes a health check on the device.

    .EXAMPLE
        Invoke-RMMAction -DeviceId "abc123" -ActionType "RunScript" -Payload @{ Script = "Get-Service" }
        Executes a PowerShell script on the device.

    .OUTPUTS
        System.String
        The ActionId of the queued action.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]]$DeviceId,

        [Parameter(Mandatory)]
        [string]$ActionType,

        [Parameter()]
        [hashtable]$Payload,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$Priority = 5,

        [Parameter()]
        [datetime]$ScheduledAt
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        $actionIds = @()

        foreach ($device in $DeviceId) {
            if ($PSCmdlet.ShouldProcess($device, "Execute action: $ActionType")) {
                # Generate ActionId
                $actionId = [guid]::NewGuid().ToString()

                # Convert payload to JSON
                $payloadJson = if ($Payload) { $Payload | ConvertTo-Json -Compress } else { $null }

                # Determine scheduled time
                $scheduledTime = if ($ScheduledAt) { $ScheduledAt.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }

                # Insert action into queue
                $query = @"
INSERT INTO Actions (ActionId, DeviceId, ActionType, Status, Priority, Payload, ScheduledAt, CreatedAt)
VALUES (@ActionId, @DeviceId, @ActionType, 'Pending', @Priority, @Payload, @ScheduledAt, CURRENT_TIMESTAMP)
"@

                $params = @{
                    ActionId    = $actionId
                    DeviceId    = $device
                    ActionType  = $ActionType
                    Priority    = $Priority
                    Payload     = $payloadJson
                    ScheduledAt = $scheduledTime
                }

                Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $query -SqlParameters $params

                Write-Host "[OK] Action queued: $ActionType for device $device" -ForegroundColor Green
                Write-RMMLog "Action queued: $ActionType for device $device (ActionId: $actionId)" -Level SUCCESS
                Write-RMMDeviceLog -DeviceId $device -Message "Action queued: $ActionType (Priority: $Priority)" -Level INFO

                $actionIds += $actionId
            }
        }

        return $actionIds
    }
    catch {
        Write-Error "Failed to queue action: $_"
        Write-RMMLog "Failed to queue action ${ActionType}: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Get-RMMHealth {
    <#
    .SYNOPSIS
        Gets system health summary across all endpoints.

    .DESCRIPTION
        Retrieves a summary of device health status, including counts by status,
        recent alerts, and overall system health metrics.

    .PARAMETER Detailed
        Include detailed health information for each device.

    .EXAMPLE
        Get-RMMHealth
        Returns a summary of system health.

    .EXAMPLE
        Get-RMMHealth -Detailed
        Returns detailed health information for all devices.

    .OUTPUTS
        PSCustomObject
        Health summary object.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Detailed
    )

    try {
        if (-not $script:RMMInitialized) {
            Write-Warning "RMM not initialized. Call Initialize-RMM first."
            return
        }

        # Get device counts by status
        $statusQuery = @"
SELECT Status, COUNT(*) as Count
FROM Devices
GROUP BY Status
"@
        $statusCounts = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $statusQuery

        # Get recent alerts
        $alertQuery = @"
SELECT COUNT(*) as Count, Severity
FROM Alerts
WHERE ResolvedAt IS NULL
GROUP BY Severity
"@
        $alertCounts = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $alertQuery

        # Get total device count
        $totalQuery = "SELECT COUNT(*) as Total FROM Devices"
        $total = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $totalQuery

        # Build health summary
        $health = [PSCustomObject]@{
            TotalDevices    = $total.Total
            DevicesByStatus = $statusCounts
            ActiveAlerts    = $alertCounts
            Timestamp       = Get-Date
        }

        if ($Detailed) {
            # Get detailed device health
            $devicesQuery = "SELECT DeviceId, Hostname, Status, LastSeen FROM Devices ORDER BY Hostname"
            $devices = Invoke-SqliteQuery -DataSource $script:DatabasePath -Query $devicesQuery
            $health | Add-Member -MemberType NoteProperty -Name "Devices" -Value $devices
        }

        return $health
    }
    catch {
        Write-Error "Failed to get health summary: $_"
        Write-RMMLog "Failed to get health summary: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Get-RMMDatabase {
    <#
    .SYNOPSIS
        Gets the database connection path.

    .DESCRIPTION
        Returns the path to the SQLite database file currently in use.

    .EXAMPLE
        Get-RMMDatabase
        Returns the database path.

    .OUTPUTS
        System.String
        The database file path.
    #>
    [CmdletBinding()]
    param()

    return $script:DatabasePath
}

function Get-RMMInstallPath {
    <#
    .SYNOPSIS
        Returns the RMM installation path.
    .DESCRIPTION
        Returns the path where RMM scripts and UI files are installed.
    .OUTPUTS
        System.String - The RMM installation path
    .EXAMPLE
        Get-RMMInstallPath
        Returns "C:\Users\username\myTech.Today\RMM"
    #>
    [CmdletBinding()]
    param()

    if (Test-Path $script:RMMInstallPath) {
        return $script:RMMInstallPath
    }
    # Fallback to module root parent if not installed
    return (Split-Path (Split-Path $script:ModuleRoot -Parent) -Parent)
}

# Export public functions
Export-ModuleMember -Function @(
    # Core functions
    'Initialize-RMM',
    'Get-RMMConfig',
    'Set-RMMConfig',
    'Get-LocalDeviceInfo',
    'Get-RMMDevice',
    'Add-RMMDevice',
    'Update-RMMDevice',
    'Update-RMMDeviceInfo',
    'Remove-RMMDevice',
    'Invoke-RMMAction',
    'Get-RMMHealth',
    'Get-RMMDatabase',
    'Get-RMMInstallPath',
    # Site management functions
    'Get-RMMSite',
    'New-RMMSite',
    'Set-RMMSite',
    'Remove-RMMSite',
    'Add-RMMSiteURL',
    'Remove-RMMSiteURL',
    # Import/Export functions
    'Import-RMMDevices',
    'Export-RMMDevices',
    # Remoting functions
    'Test-RMMDomainMembership',
    'Test-RMMRemoteHTTPS',
    'Test-RMMRemoteHTTP',
    'Test-RMMRemoteEnvironment',
    'Get-RMMTrustedHosts',
    'Test-RMMInTrustedHosts',
    'Add-RMMTrustedHost',
    'Remove-RMMTrustedHost',
    'Clear-RMMTemporaryTrustedHosts',
    'New-RMMRemoteSession',
    'Invoke-RMMRemoteCommand',
    'Set-RMMRemotingPreference',
    'Get-RMMRemotingPreference',
    # Scalability functions
    'Invoke-RMMParallel',
    'Get-RMMSession',
    'Close-RMMSession',
    'Clear-ExpiredSessions',
    'Get-RMMCache',
    'Set-RMMCache',
    'Clear-RMMCache',
    'Invoke-RMMBatchInsert',
    'Group-RMMDevicesBySite',
    # Security functions
    'Save-RMMCredential',
    'Get-RMMCredential',
    'Remove-RMMCredential',
    'Get-RMMCredentialList',
    'Protect-RMMString',
    'Unprotect-RMMString',
    'Set-RMMUserRole',
    'Get-RMMUserRole',
    'Test-RMMPermission',
    'Assert-RMMPermission',
    'Write-RMMAuditLog',
    'Get-RMMAuditLog',
    # Database maintenance functions
    'Invoke-RMMDatabaseVacuum',
    'Invoke-RMMDatabaseArchive',
    'Invoke-RMMDatabaseBackup',
    'Get-RMMDatabaseStats',
    'Register-RMMMaintenanceTask',
    # Error handling functions
    'Invoke-RMMWithRetry',
    'Get-RMMErrorCategory'
)

# Auto-initialize RMM when module is imported (silent mode)
# This allows Get-RMMDevice etc. to work immediately after Import-Module RMM
if (-not $script:RMMInitialized) {
    # Check if database exists at standard or legacy location
    $dbExists = (Test-Path $script:DatabasePath) -or (Test-Path $script:LegacyDatabasePath)
    if ($dbExists) {
        # Silent initialization - no console output
        $null = Initialize-RMM -Quiet
    }
}
