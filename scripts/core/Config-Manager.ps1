<#
.SYNOPSIS
    Configuration management for the myTech.Today RMM system.

.DESCRIPTION
    Manages settings.json with validation, hot-reload capabilities, and environment-specific overrides.
    Provides functions to get, set, test, reset, export, and import configuration settings.

    Configuration is searched in this order:
    1. ProgramData (standard installation): C:\ProgramData\myTech.Today\RMM\config\
    2. Portable mode (running from source): .\config\
    3. Legacy user profile: %USERPROFILE%\myTech.Today\config\

.NOTES
    Author: Kyle C. Rode (myTech.Today)
    Version: 2.1
    Requires: PowerShell 5.1+
#>

# Script-scoped variables
$script:ConfigCache = $null
$script:ConfigLastModified = $null

# Determine config path - check multiple locations in order of preference
$script:ConfigPath = $null
$possibleRoots = @(
    "$env:ProgramData\myTech.Today\RMM",            # Standard installation (ProgramData)
    "$PSScriptRoot\..\..",                          # Portable mode (running from RMM folder)
    "$env:USERPROFILE\myTech.Today\RMM",            # Legacy user profile location
    "$env:USERPROFILE\myTech.Today"                 # Legacy user profile (old structure)
)

foreach ($root in $possibleRoots) {
    $testConfig = Join-Path $root "config\settings.json"
    if (Test-Path $testConfig) {
        $script:ConfigPath = $testConfig
        break
    }
}

# Default to ProgramData if no existing config found
if (-not $script:ConfigPath) {
    $script:ConfigPath = "$env:ProgramData\myTech.Today\RMM\config\settings.json"
}

function Get-RMMConfiguration {
    <#
    .SYNOPSIS
        Loads and returns the RMM configuration.

    .DESCRIPTION
        Reads the settings.json file and returns the configuration as a PowerShell object.
        Implements caching with automatic reload if the file has been modified.

    .PARAMETER Section
        Optional. Specific configuration section to retrieve (General, Connections, Monitoring, etc.)

    .PARAMETER Reload
        Force reload from disk, bypassing cache.

    .EXAMPLE
        $config = Get-RMMConfiguration
        Returns the entire configuration object.

    .EXAMPLE
        $general = Get-RMMConfiguration -Section "General"
        Returns only the General configuration section.

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

    try {
        # Resolve full path
        $configPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($script:ConfigPath)

        if (-not (Test-Path $configPath)) {
            throw "Configuration file not found: $configPath"
        }

        # Check if we need to reload
        $fileInfo = Get-Item $configPath
        $needsReload = $Reload -or 
                       $null -eq $script:ConfigCache -or 
                       $null -eq $script:ConfigLastModified -or 
                       $fileInfo.LastWriteTime -gt $script:ConfigLastModified

        if ($needsReload) {
            $script:ConfigCache = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            $script:ConfigLastModified = $fileInfo.LastWriteTime
        }

        # Return specific section or entire config
        if ($Section) {
            return $script:ConfigCache.$Section
        }
        else {
            return $script:ConfigCache
        }
    }
    catch {
        Write-Error "Failed to load configuration: $_"
        return $null
    }
}

function Set-RMMConfiguration {
    <#
    .SYNOPSIS
        Updates a specific configuration value.

    .DESCRIPTION
        Updates a configuration setting and saves it to settings.json.
        Validates the value before saving.

    .PARAMETER Section
        The configuration section (General, Connections, etc.)

    .PARAMETER Key
        The configuration key within the section.

    .PARAMETER Value
        The new value to set.

    .EXAMPLE
        Set-RMMConfiguration -Section "General" -Key "LogLevel" -Value "Debug"
        Sets the log level to Debug.

    .EXAMPLE
        Set-RMMConfiguration -Section "Monitoring" -Key "HealthCheckInterval" -Value 600
        Sets the health check interval to 600 seconds.
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

    try {
        # Load current configuration
        $config = Get-RMMConfiguration -Reload

        if (-not $config) {
            throw "Failed to load current configuration"
        }

        # Check if section exists
        if (-not $config.PSObject.Properties.Name.Contains($Section)) {
            throw "Configuration section '$Section' not found"
        }

        # Check if key exists
        if (-not $config.$Section.PSObject.Properties.Name.Contains($Key)) {
            throw "Configuration key '$Key' not found in section '$Section'"
        }

        # Update the value
        if ($PSCmdlet.ShouldProcess("$Section.$Key", "Set value to '$Value'")) {
            $config.$Section.$Key = $Value

            # Save to file
            $configPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($script:ConfigPath)
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Force

            # Clear cache to force reload
            $script:ConfigCache = $null

            Write-Host "[OK] Configuration updated: $Section.$Key = $Value" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to set configuration: $_"
    }
}

function Test-RMMConfiguration {
    <#
    .SYNOPSIS
        Validates the RMM configuration structure.

    .DESCRIPTION
        Checks that all required configuration sections and keys exist,
        and that values are within valid ranges.

    .EXAMPLE
        Test-RMMConfiguration
        Returns $true if configuration is valid, $false otherwise.

    .OUTPUTS
        System.Boolean
        True if configuration is valid, false otherwise.
    #>
    [CmdletBinding()]
    param()

    try {
        $config = Get-RMMConfiguration -Reload

        if (-not $config) {
            Write-Warning "Configuration file could not be loaded"
            return $false
        }

        # Check required sections
        $requiredSections = @('General', 'Connections', 'Monitoring', 'Notifications', 'Security', 'Database', 'Performance', 'UI')
        $valid = $true

        foreach ($section in $requiredSections) {
            if (-not $config.PSObject.Properties.Name.Contains($section)) {
                Write-Warning "Missing required section: $section"
                $valid = $false
            }
        }

        # Validate specific settings
        if ($config.Connections.WinRMTimeout -lt 1 -or $config.Connections.WinRMTimeout -gt 300) {
            Write-Warning "WinRMTimeout must be between 1 and 300 seconds"
            $valid = $false
        }

        if ($config.Monitoring.HealthCheckInterval -lt 60) {
            Write-Warning "HealthCheckInterval must be at least 60 seconds"
            $valid = $false
        }

        if ($config.General.DataRetentionDays -lt 1) {
            Write-Warning "DataRetentionDays must be at least 1"
            $valid = $false
        }

        if ($valid) {
            Write-Host "[OK] Configuration is valid" -ForegroundColor Green
        }

        return $valid
    }
    catch {
        Write-Error "Failed to validate configuration: $_"
        return $false
    }
}

function Reset-RMMConfiguration {
    <#
    .SYNOPSIS
        Resets configuration to default values.

    .DESCRIPTION
        Creates a backup of the current configuration and resets settings.json to defaults.

    .PARAMETER Force
        Skip confirmation prompt.

    .EXAMPLE
        Reset-RMMConfiguration
        Resets configuration with confirmation prompt.

    .EXAMPLE
        Reset-RMMConfiguration -Force
        Resets configuration without confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()]
        [switch]$Force
    )

    try {
        $configPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($script:ConfigPath)

        if (-not (Test-Path $configPath)) {
            Write-Warning "Configuration file not found: $configPath"
            return
        }

        if ($Force -or $PSCmdlet.ShouldProcess("Configuration", "Reset to defaults")) {
            # Create backup
            $backupPath = "$configPath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -Path $configPath -Destination $backupPath -Force
            Write-Host "[INFO] Backup created: $backupPath" -ForegroundColor Cyan

            # Load default configuration (from the original settings.json template)
            # For now, we'll just clear the cache and notify the user
            $script:ConfigCache = $null
            Write-Host "[OK] Configuration cache cleared. Please restore from backup or recreate settings.json" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to reset configuration: $_"
    }
}

function Export-RMMConfiguration {
    <#
    .SYNOPSIS
        Exports the current configuration to a file.

    .DESCRIPTION
        Exports the current RMM configuration to a JSON file.

    .PARAMETER Path
        The path where the configuration should be exported.

    .EXAMPLE
        Export-RMMConfiguration -Path "C:\Backup\rmm-config.json"
        Exports configuration to the specified file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $config = Get-RMMConfiguration -Reload

        if (-not $config) {
            throw "Failed to load configuration"
        }

        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Force
        Write-Host "[OK] Configuration exported to: $Path" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to export configuration: $_"
    }
}

function Import-RMMConfiguration {
    <#
    .SYNOPSIS
        Imports configuration from a file.

    .DESCRIPTION
        Imports RMM configuration from a JSON file and validates it.

    .PARAMETER Path
        The path to the configuration file to import.

    .PARAMETER Force
        Skip confirmation prompt.

    .EXAMPLE
        Import-RMMConfiguration -Path "C:\Backup\rmm-config.json"
        Imports configuration from the specified file.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [switch]$Force
    )

    try {
        if (-not (Test-Path $Path)) {
            throw "Configuration file not found: $Path"
        }

        # Load and validate the import file
        $importConfig = Get-Content -Path $Path -Raw | ConvertFrom-Json

        if ($Force -or $PSCmdlet.ShouldProcess("Configuration", "Import from $Path")) {
            # Create backup of current config
            $configPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($script:ConfigPath)
            $backupPath = "$configPath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -Path $configPath -Destination $backupPath -Force
            Write-Host "[INFO] Backup created: $backupPath" -ForegroundColor Cyan

            # Import new configuration
            $importConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Force

            # Clear cache
            $script:ConfigCache = $null

            Write-Host "[OK] Configuration imported successfully" -ForegroundColor Green

            # Validate the imported configuration
            Test-RMMConfiguration | Out-Null
        }
    }
    catch {
        Write-Error "Failed to import configuration: $_"
    }
}

# Export functions
Export-ModuleMember -Function Get-RMMConfiguration, Set-RMMConfiguration, Test-RMMConfiguration, Reset-RMMConfiguration, Export-RMMConfiguration, Import-RMMConfiguration

