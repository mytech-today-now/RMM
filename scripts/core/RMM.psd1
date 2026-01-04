@{
    # Module manifest for myTech.Today RMM
    RootModule = 'RMM-Core.psm1'
    ModuleVersion = '2.1.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'myTech.Today'
    CompanyName = 'myTech.Today'
    Copyright = '(c) 2024 myTech.Today. All rights reserved.'
    Description = 'Remote Monitoring and Management System - Device management, health monitoring, alerting, and automation. Installs to Program Files with data in ProgramData.'
    
    # Minimum PowerShell version
    PowerShellVersion = '5.1'
    
    # Required modules
    RequiredModules = @('PSSQLite')
    
    # Functions to export
    FunctionsToExport = @(
        # Core
        'Initialize-RMM',
        'Get-RMMDatabase',
        'Get-RMMInstallPath',

        # Configuration
        'Get-RMMConfig',
        'Set-RMMConfig',

        # Device Management
        'Get-LocalDeviceInfo',
        'Get-RMMDevice',
        'Add-RMMDevice',
        'Update-RMMDevice',
        'Update-RMMDeviceInfo',
        'Remove-RMMDevice',
        'Import-RMMDevices',
        'Export-RMMDevices',

        # Site Management
        'Get-RMMSite',
        'New-RMMSite',
        'Set-RMMSite',
        'Remove-RMMSite',
        'Add-RMMSiteURL',
        'Remove-RMMSiteURL',

        # Actions
        'Invoke-RMMAction',

        # Health
        'Get-RMMHealth',

        # Logging
        'Write-RMMLog',

        # Remoting (Workgroup/Non-Domain Support)
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

        # Security
        'Get-RMMCredential',
        'Save-RMMCredential',
        'Remove-RMMCredential',
        'Get-RMMCredentialList',
        'Protect-RMMString',
        'Unprotect-RMMString',
        'Set-RMMUserRole',
        'Get-RMMUserRole',
        'Test-RMMPermission',
        'Write-RMMAuditLog',
        'Get-RMMAuditLog',

        # Scalability
        'Invoke-RMMParallel',
        'Get-RMMSession',
        'Close-RMMSession',
        'Get-RMMCache',
        'Set-RMMCache',
        'Clear-RMMCache',

        # Database Maintenance
        'Invoke-RMMDatabaseVacuum',
        'Invoke-RMMDatabaseArchive',
        'Invoke-RMMDatabaseBackup',
        'Get-RMMDatabaseStats'
    )
    
    # Cmdlets to export (none - this is a script module)
    CmdletsToExport = @()
    
    # Variables to export (none)
    VariablesToExport = @()
    
    # Aliases to export (none)
    AliasesToExport = @()
    
    # Private data
    PrivateData = @{
        PSData = @{
            Tags = @('RMM', 'Monitoring', 'Management', 'Devices', 'Automation')
            ProjectUri = 'https://github.com/mytech-today/rmm'
            LicenseUri = 'https://github.com/mytech-today/rmm/blob/main/LICENSE'
        }
    }
}

