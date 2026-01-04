<#
.SYNOPSIS
    Scalability features for RMM system.

.DESCRIPTION
    Provides parallel processing, connection pooling, caching, and batch operations
    to improve performance for operations on multiple devices.

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+
#>

#Requires -Version 5.1

#region Module Variables

$script:SessionCache = @{}
$script:DataCache = @{}
$script:CacheTTL = @{
    DeviceStatus = 300      # 5 minutes
    Inventory    = 86400    # 24 hours
    Configuration = 3600    # 1 hour
}
$script:SessionTTL = 300    # 5 minutes for WinRM sessions
$script:ThrottleLimit = 50  # Max parallel operations
$script:BatchSize = 100     # Rows per database commit

#endregion

#region Parallel Processing

function Invoke-RMMParallel {
    <#
    .SYNOPSIS
        Execute operations on multiple devices in parallel.
    .DESCRIPTION
        Uses ForEach-Object -Parallel (PS7+) or RunspacePool (PS5.1) for parallel execution.
    .PARAMETER Devices
        Array of device objects to process.
    .PARAMETER ScriptBlock
        Script block to execute on each device.
    .PARAMETER ThrottleLimit
        Maximum concurrent operations. Default: 50
    .PARAMETER ArgumentList
        Additional arguments to pass to the script block.
    .EXAMPLE
        $devices | Invoke-RMMParallel -ScriptBlock { param($d) Get-Service -ComputerName $d.Hostname }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Devices,
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [int]$ThrottleLimit = $script:ThrottleLimit,
        [object[]]$ArgumentList = @()
    )

    begin { $allDevices = @() }
    process { $allDevices += $Devices }
    end {
        if ($allDevices.Count -eq 0) { return @() }
        $results = @()
        $isPSCore = $PSVersionTable.PSVersion.Major -ge 7

        if ($isPSCore) {
            $results = $allDevices | ForEach-Object -Parallel {
                $device = $_
                $sb = $using:ScriptBlock
                $args = $using:ArgumentList
                try { & $sb $device @args }
                catch { [PSCustomObject]@{ Device = $device; Error = $_.Exception.Message; Success = $false } }
            } -ThrottleLimit $ThrottleLimit
        }
        else {
            $runspacePool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit)
            $runspacePool.Open()
            $runspaces = @()

            foreach ($device in $allDevices) {
                $powershell = [PowerShell]::Create()
                $powershell.RunspacePool = $runspacePool
                [void]$powershell.AddScript($ScriptBlock).AddArgument($device)
                foreach ($arg in $ArgumentList) { [void]$powershell.AddArgument($arg) }
                $runspaces += [PSCustomObject]@{
                    PowerShell = $powershell
                    Handle     = $powershell.BeginInvoke()
                    Device     = $device
                }
            }

            foreach ($rs in $runspaces) {
                try { $results += $rs.PowerShell.EndInvoke($rs.Handle) }
                catch { $results += [PSCustomObject]@{ Device = $rs.Device; Error = $_.Exception.Message; Success = $false } }
                finally { $rs.PowerShell.Dispose() }
            }
            $runspacePool.Close()
            $runspacePool.Dispose()
        }
        return $results
    }
}

#endregion

#region Connection Pooling

function Get-RMMSession {
    <#
    .SYNOPSIS
        Get or create a cached WinRM session with automatic transport handling.
    .DESCRIPTION
        Reuses existing sessions from cache or creates new ones. Sessions expire after TTL.
        Automatically handles workgroup/non-domain environments by:
        - Preferring HTTPS transport when available (port 5986)
        - Managing TrustedHosts safely for HTTP fallback
        - Providing clear error messages for connection issues
    .PARAMETER ComputerName
        Target computer hostname.
    .PARAMETER Credential
        Optional credential for non-domain computers (required for workgroup targets).
    .PARAMETER RequireHTTPS
        Require HTTPS transport - fail if not available. Default: $false
    .PARAMETER SkipTrustedHostsManagement
        Do not automatically manage TrustedHosts. Default: $false
    .EXAMPLE
        $session = Get-RMMSession -ComputerName "SERVER01"
    .EXAMPLE
        $session = Get-RMMSession -ComputerName "WORKGROUP-PC" -Credential $cred -RequireHTTPS
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [PSCredential]$Credential,
        [switch]$RequireHTTPS,
        [switch]$SkipTrustedHostsManagement
    )

    $cacheKey = $ComputerName.ToLower()
    $now = Get-Date

    # Check for cached session
    if ($script:SessionCache.ContainsKey($cacheKey)) {
        $cached = $script:SessionCache[$cacheKey]
        $age = ($now - $cached.CreatedAt).TotalSeconds
        if ($age -lt $script:SessionTTL -and $cached.Session.State -eq 'Opened') {
            return $cached.Session
        }
        else {
            Remove-PSSession -Session $cached.Session -ErrorAction SilentlyContinue
            $script:SessionCache.Remove($cacheKey)
        }
    }

    # Create new session using secure remoting helper
    $sessionParams = @{
        ComputerName = $ComputerName
    }
    if ($Credential) { $sessionParams.Credential = $Credential }
    if ($RequireHTTPS) { $sessionParams.RequireHTTPS = $true }
    if ($SkipTrustedHostsManagement) { $sessionParams.SkipTrustedHostsManagement = $true }

    $session = New-RMMRemoteSession @sessionParams

    if ($null -eq $session) {
        throw "Failed to create session to '$ComputerName'"
    }

    $script:SessionCache[$cacheKey] = @{ Session = $session; CreatedAt = $now }
    return $session
}

function Close-RMMSession {
    <#
    .SYNOPSIS
        Close a cached WinRM session.
    .PARAMETER ComputerName
        Target computer hostname. If omitted, closes all sessions.
    #>
    [CmdletBinding()]
    param([string]$ComputerName)

    if ($ComputerName) {
        $cacheKey = $ComputerName.ToLower()
        if ($script:SessionCache.ContainsKey($cacheKey)) {
            Remove-PSSession -Session $script:SessionCache[$cacheKey].Session -ErrorAction SilentlyContinue
            $script:SessionCache.Remove($cacheKey)
        }
    }
    else {
        foreach ($key in @($script:SessionCache.Keys)) {
            Remove-PSSession -Session $script:SessionCache[$key].Session -ErrorAction SilentlyContinue
        }
        $script:SessionCache.Clear()
    }
}

function Clear-ExpiredSessions {
    <#
    .SYNOPSIS
        Remove expired sessions from the cache.
    #>
    [CmdletBinding()]
    param()

    $now = Get-Date
    $expiredKeys = @()
    foreach ($key in $script:SessionCache.Keys) {
        $cached = $script:SessionCache[$key]
        $age = ($now - $cached.CreatedAt).TotalSeconds
        if ($age -ge $script:SessionTTL -or $cached.Session.State -ne 'Opened') {
            Remove-PSSession -Session $cached.Session -ErrorAction SilentlyContinue
            $expiredKeys += $key
        }
    }
    foreach ($key in $expiredKeys) { $script:SessionCache.Remove($key) }
}

#endregion

#region Caching

function Get-RMMCache {
    <#
    .SYNOPSIS
        Get a cached value.
    .PARAMETER Key
        Cache key.
    .PARAMETER Type
        Cache type (DeviceStatus, Inventory, Configuration).
    .EXAMPLE
        $status = Get-RMMCache -Key "device123" -Type "DeviceStatus"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [Parameter(Mandatory)]
        [ValidateSet('DeviceStatus', 'Inventory', 'Configuration')]
        [string]$Type
    )

    $cacheKey = "${Type}:${Key}"
    if ($script:DataCache.ContainsKey($cacheKey)) {
        $cached = $script:DataCache[$cacheKey]
        $ttl = $script:CacheTTL[$Type]
        $age = ((Get-Date) - $cached.Timestamp).TotalSeconds
        if ($age -lt $ttl) { return $cached.Data }
        $script:DataCache.Remove($cacheKey)
    }
    return $null
}

function Set-RMMCache {
    <#
    .SYNOPSIS
        Set a cached value.
    .PARAMETER Key
        Cache key.
    .PARAMETER Type
        Cache type (DeviceStatus, Inventory, Configuration).
    .PARAMETER Data
        Data to cache.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [Parameter(Mandatory)]
        [ValidateSet('DeviceStatus', 'Inventory', 'Configuration')]
        [string]$Type,
        [Parameter(Mandatory)]
        $Data
    )

    $cacheKey = "${Type}:${Key}"
    $script:DataCache[$cacheKey] = @{ Data = $Data; Timestamp = Get-Date }
}

function Clear-RMMCache {
    <#
    .SYNOPSIS
        Clear cache entries.
    .PARAMETER Type
        Optional type to clear. Clears all if omitted.
    #>
    [CmdletBinding()]
    param([string]$Type)

    if ($Type) {
        $keysToRemove = @($script:DataCache.Keys | Where-Object { $_ -like "${Type}:*" })
        foreach ($k in $keysToRemove) { $script:DataCache.Remove($k) }
    }
    else {
        $script:DataCache.Clear()
    }
}

#endregion

#region Batch Operations

function Invoke-RMMBatchInsert {
    <#
    .SYNOPSIS
        Batch insert rows into a database table.
    .PARAMETER DataSource
        Path to SQLite database.
    .PARAMETER TableName
        Target table name.
    .PARAMETER Rows
        Array of hashtables with column-value pairs.
    .PARAMETER BatchSize
        Rows per commit. Default: 100
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DataSource,
        [Parameter(Mandatory)]
        [string]$TableName,
        [Parameter(Mandatory)]
        [hashtable[]]$Rows,
        [int]$BatchSize = $script:BatchSize
    )

    if ($Rows.Count -eq 0) { return }

    $columns = $Rows[0].Keys -join ', '
    $paramNames = $Rows[0].Keys | ForEach-Object { "@$_" }
    $paramList = $paramNames -join ', '
    $insertQuery = "INSERT INTO $TableName ($columns) VALUES ($paramList)"

    for ($i = 0; $i -lt $Rows.Count; $i += $BatchSize) {
        $batch = $Rows[$i..[Math]::Min($i + $BatchSize - 1, $Rows.Count - 1)]
        foreach ($row in $batch) {
            try {
                Invoke-SqliteQuery -DataSource $DataSource -Query $insertQuery -SqlParameters $row -ErrorAction Stop
            }
            catch {
                Write-Warning "Batch insert error: $_"
            }
        }
    }
}

function Group-RMMDevicesBySite {
    <#
    .SYNOPSIS
        Group devices by site for network-efficient batch operations.
    .PARAMETER Devices
        Array of device objects with Site property.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Devices)

    $grouped = @{}
    foreach ($device in $Devices) {
        $site = if ($device.Site) { $device.Site } else { 'Default' }
        if (-not $grouped.ContainsKey($site)) { $grouped[$site] = @() }
        $grouped[$site] += $device
    }
    return $grouped
}

#endregion

#region Error Handling

function Invoke-RMMWithRetry {
    <#
    .SYNOPSIS
        Execute a script block with retry logic for transient errors.
    .DESCRIPTION
        Implements exponential backoff retry for transient errors like network issues.
    .PARAMETER ScriptBlock
        Script block to execute.
    .PARAMETER MaxRetries
        Maximum retry attempts. Default: 3
    .PARAMETER InitialDelaySeconds
        Initial delay between retries. Default: 2
    .PARAMETER DeviceId
        Optional device ID for status updates on failure.
    .EXAMPLE
        Invoke-RMMWithRetry -ScriptBlock { Invoke-Command -ComputerName "SERVER01" -ScriptBlock { Get-Service } }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$InitialDelaySeconds = 2,
        [string]$DeviceId
    )

    $attempt = 0
    $delay = $InitialDelaySeconds

    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            return & $ScriptBlock
        }
        catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
            # Transient network/remoting error - retry
            Write-RMMLog -Message "Transient error (attempt $attempt/$MaxRetries): $($_.Exception.Message)" -Level "Warning"
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds $delay
                $delay = $delay * 2  # Exponential backoff
            }
            else {
                if ($DeviceId) {
                    Update-RMMDevice -DeviceId $DeviceId -Status "Offline" -ErrorAction SilentlyContinue
                }
                throw
            }
        }
        catch [System.Net.Sockets.SocketException] {
            # Network connectivity issue - retry
            Write-RMMLog -Message "Network error (attempt $attempt/$MaxRetries): $($_.Exception.Message)" -Level "Warning"
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds $delay
                $delay = $delay * 2
            }
            else {
                throw
            }
        }
        catch {
            # Non-transient error - don't retry
            Write-RMMLog -Message "Non-transient error: $($_.Exception.Message)" -Level "Error"
            throw
        }
    }
}

function Get-RMMErrorCategory {
    <#
    .SYNOPSIS
        Categorize an error for appropriate handling.
    .PARAMETER ErrorRecord
        The error record to categorize.
    .OUTPUTS
        String: Transient, Device, Configuration, or Fatal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    $exception = $ErrorRecord.Exception

    # Transient errors - retry with backoff
    if ($exception -is [System.Management.Automation.Remoting.PSRemotingTransportException] -or
        $exception -is [System.Net.Sockets.SocketException] -or
        $exception -is [System.TimeoutException]) {
        return 'Transient'
    }

    # Device errors - queue for later
    if ($exception.Message -match 'WinRM|offline|unreachable|access denied') {
        return 'Device'
    }

    # Configuration errors - log and alert admin
    if ($exception.Message -match 'invalid|configuration|setting|parameter') {
        return 'Configuration'
    }

    # Fatal errors - stop and notify
    if ($exception.Message -match 'database|corruption|critical|fatal') {
        return 'Fatal'
    }

    return 'Unknown'
}

#endregion
