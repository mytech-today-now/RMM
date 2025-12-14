<#
.SYNOPSIS
    Security features for RMM system.

.DESCRIPTION
    Provides credential management, role-based access control (RBAC), and audit logging
    for secure RMM operations.

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+
#>

#Requires -Version 5.1

#region Module Variables

$script:SecretsPath = Join-Path $PSScriptRoot "..\..\secrets"
$script:CredentialCache = @{}
$script:CurrentUser = $null
$script:CurrentRole = $null

# Role definitions
$script:RolePermissions = @{
    Admin = @{
        Description = "Full access, configuration, user management"
        Permissions = @('*')
    }
    Operator = @{
        Description = "Device management, actions, alerts"
        Permissions = @('Device.Read', 'Device.Write', 'Action.Execute', 'Alert.Read', 'Alert.Write', 'Report.Read')
    }
    Viewer = @{
        Description = "Read-only access to dashboards and reports"
        Permissions = @('Device.Read', 'Alert.Read', 'Report.Read', 'Dashboard.Read')
    }
}

#endregion

#region Credential Management

function Save-RMMCredential {
    <#
    .SYNOPSIS
        Securely save a credential using DPAPI encryption.
    .DESCRIPTION
        Exports credential to XML file encrypted with Windows DPAPI.
        Only the same user on the same machine can decrypt.
    .PARAMETER Name
        Unique name for the credential.
    .PARAMETER Credential
        PSCredential object to save.
    .PARAMETER Description
        Optional description for the credential.
    .EXAMPLE
        $cred = Get-Credential
        Save-RMMCredential -Name "DomainAdmin" -Credential $cred
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [PSCredential]$Credential,
        [string]$Description = ""
    )

    if (-not (Test-Path $script:SecretsPath)) {
        New-Item -ItemType Directory -Path $script:SecretsPath -Force | Out-Null
    }

    $credPath = Join-Path $script:SecretsPath "$Name.xml"
    $metaPath = Join-Path $script:SecretsPath "$Name.meta.json"

    # Export credential (DPAPI encrypted)
    $Credential | Export-Clixml -Path $credPath -Force

    # Save metadata (not sensitive)
    $metadata = @{
        Name = $Name
        Description = $Description
        Username = $Credential.UserName
        CreatedAt = (Get-Date).ToString("o")
        CreatedBy = [Environment]::UserName
        Machine = [Environment]::MachineName
    }
    $metadata | ConvertTo-Json | Out-File -FilePath $metaPath -Encoding UTF8 -Force

    Write-RMMLog -Message "Credential saved: $Name" -Level "Info"
    return $true
}

function Get-RMMCredential {
    <#
    .SYNOPSIS
        Retrieve a saved credential.
    .PARAMETER Name
        Name of the credential to retrieve.
    .PARAMETER UseCache
        Use cached credential if available. Default: true
    .EXAMPLE
        $cred = Get-RMMCredential -Name "DomainAdmin"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [bool]$UseCache = $true
    )

    if ($UseCache -and $script:CredentialCache.ContainsKey($Name)) {
        return $script:CredentialCache[$Name]
    }

    $credPath = Join-Path $script:SecretsPath "$Name.xml"
    if (-not (Test-Path $credPath)) {
        Write-Warning "Credential not found: $Name"
        return $null
    }

    try {
        $credential = Import-Clixml -Path $credPath
        $script:CredentialCache[$Name] = $credential
        return $credential
    }
    catch {
        Write-Warning "Failed to load credential $Name : $_"
        return $null
    }
}

function Remove-RMMCredential {
    <#
    .SYNOPSIS
        Remove a saved credential.
    .PARAMETER Name
        Name of the credential to remove.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $credPath = Join-Path $script:SecretsPath "$Name.xml"
    $metaPath = Join-Path $script:SecretsPath "$Name.meta.json"

    if (Test-Path $credPath) { Remove-Item $credPath -Force }
    if (Test-Path $metaPath) { Remove-Item $metaPath -Force }
    if ($script:CredentialCache.ContainsKey($Name)) { $script:CredentialCache.Remove($Name) }

    Write-RMMLog -Message "Credential removed: $Name" -Level "Info"
}

function Get-RMMCredentialList {
    <#
    .SYNOPSIS
        List all saved credentials (metadata only, not secrets).
    #>
    [CmdletBinding()]
    param()

    $credentials = @()
    $metaFiles = Get-ChildItem -Path $script:SecretsPath -Filter "*.meta.json" -ErrorAction SilentlyContinue

    foreach ($file in $metaFiles) {
        try {
            $meta = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $credentials += $meta
        }
        catch { }
    }
    return $credentials
}

#endregion

#region Role-Based Access Control

function Set-RMMUserRole {
    <#
    .SYNOPSIS
        Set the current user role for RBAC.
    .PARAMETER Username
        Username to set.
    .PARAMETER Role
        Role to assign (Admin, Operator, Viewer).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        [Parameter(Mandatory)]
        [ValidateSet('Admin', 'Operator', 'Viewer')]
        [string]$Role
    )

    $script:CurrentUser = $Username
    $script:CurrentRole = $Role
    Write-RMMLog -Message "User role set: $Username as $Role" -Level "Info"
}

function Get-RMMUserRole {
    <#
    .SYNOPSIS
        Get the current user role.
    #>
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        Username = $script:CurrentUser
        Role = $script:CurrentRole
        Permissions = if ($script:CurrentRole) { $script:RolePermissions[$script:CurrentRole].Permissions } else { @() }
    }
}

function Test-RMMPermission {
    <#
    .SYNOPSIS
        Check if current user has a specific permission.
    .PARAMETER Permission
        Permission to check (e.g., Device.Read, Action.Execute).
    .EXAMPLE
        if (Test-RMMPermission -Permission "Action.Execute") { ... }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Permission)

    if (-not $script:CurrentRole) { return $false }
    $perms = $script:RolePermissions[$script:CurrentRole].Permissions
    return ($perms -contains '*' -or $perms -contains $Permission)
}

function Assert-RMMPermission {
    <#
    .SYNOPSIS
        Assert that current user has permission, throw if not.
    .PARAMETER Permission
        Permission required.
    .PARAMETER Action
        Description of action for error message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Permission,
        [string]$Action = "perform this action"
    )

    if (-not (Test-RMMPermission -Permission $Permission)) {
        $msg = "Access denied: User '$($script:CurrentUser)' with role '$($script:CurrentRole)' cannot $Action (requires $Permission)"
        Write-RMMLog -Message $msg -Level "Error"
        throw $msg
    }
}

#endregion

#region Audit Logging

function Write-RMMAuditLog {
    <#
    .SYNOPSIS
        Write an entry to the audit log.
    .DESCRIPTION
        Records all actions to the AuditLog table with timestamp, user, action, target, result, and details.
    .PARAMETER Action
        Action performed (e.g., DeviceAdded, ActionExecuted, CredentialAccessed).
    .PARAMETER TargetDevices
        Array of target device IDs or hostnames.
    .PARAMETER Result
        Result of the action (Success, Failure, Partial).
    .PARAMETER Details
        Additional details as hashtable.
    .EXAMPLE
        Write-RMMAuditLog -Action "ActionExecuted" -TargetDevices @("SERVER01") -Result "Success" -Details @{ActionType="Restart"}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action,
        [string[]]$TargetDevices = @(),
        [ValidateSet('Success', 'Failure', 'Partial')]
        [string]$Result = 'Success',
        [hashtable]$Details = @{}
    )

    $dbPath = Get-RMMDatabase
    $timestamp = (Get-Date).ToUniversalTime().ToString("o")
    $user = if ($script:CurrentUser) { $script:CurrentUser } else { [Environment]::UserName }
    $ipAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress
    if (-not $ipAddress) { $ipAddress = "127.0.0.1" }

    $auditEntry = @{
        Timestamp = $timestamp
        Username = $user
        Role = $script:CurrentRole
        Action = $Action
        TargetDevices = ($TargetDevices -join ',')
        Result = $Result
        IPAddress = $ipAddress
        Details = ($Details | ConvertTo-Json -Compress -Depth 5)
    }

    try {
        $query = @"
INSERT INTO AuditLog (Timestamp, Username, Role, Action, TargetDevices, Result, IPAddress, Details)
VALUES (@Timestamp, @Username, @Role, @Action, @TargetDevices, @Result, @IPAddress, @Details)
"@
        Invoke-SqliteQuery -DataSource $dbPath -Query $query -SqlParameters $auditEntry -ErrorAction Stop
    }
    catch {
        # Fallback to file-based audit log if database fails
        $logPath = Join-Path $env:USERPROFILE "myTech.Today\logs\audit.log"
        $logDir = Split-Path $logPath -Parent
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $logLine = "$timestamp | $user | $Action | $($TargetDevices -join ',') | $Result | $ipAddress | $($Details | ConvertTo-Json -Compress)"
        Add-Content -Path $logPath -Value $logLine -Encoding UTF8
    }
}

function Get-RMMAuditLog {
    <#
    .SYNOPSIS
        Retrieve audit log entries.
    .PARAMETER StartDate
        Start date for filtering.
    .PARAMETER EndDate
        End date for filtering.
    .PARAMETER Action
        Filter by action type.
    .PARAMETER Username
        Filter by username.
    .PARAMETER Limit
        Maximum entries to return. Default: 100
    #>
    [CmdletBinding()]
    param(
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string]$Action,
        [string]$Username,
        [int]$Limit = 100
    )

    $dbPath = Get-RMMDatabase
    $query = "SELECT * FROM AuditLog WHERE 1=1"
    $params = @{}

    if ($StartDate) {
        $query += " AND Timestamp >= @StartDate"
        $params.StartDate = $StartDate.ToUniversalTime().ToString("o")
    }
    if ($EndDate) {
        $query += " AND Timestamp <= @EndDate"
        $params.EndDate = $EndDate.ToUniversalTime().ToString("o")
    }
    if ($Action) {
        $query += " AND Action = @Action"
        $params.Action = $Action
    }
    if ($Username) {
        $query += " AND Username = @Username"
        $params.Username = $Username
    }

    $query += " ORDER BY Timestamp DESC LIMIT @Limit"
    $params.Limit = $Limit

    return Invoke-SqliteQuery -DataSource $dbPath -Query $query -SqlParameters $params
}

#endregion
