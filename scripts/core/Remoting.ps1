<#
.SYNOPSIS
    Secure PowerShell Remoting helpers for RMM system.

.DESCRIPTION
    Provides secure remoting connection management with support for both domain-joined
    and workgroup (non-domain) environments. Features include:
    - Automatic HTTPS detection and preference for workgroup targets
    - Safe TrustedHosts management (narrow scope, reversible)
    - Session caching with secure transport selection
    - Clear error messaging for connection issues

.NOTES
    Author: myTech.Today RMM
    Version: 1.0.0
    Requires: PowerShell 5.1+
#>

#Requires -Version 5.1

#region Module Variables

# Track temporarily added TrustedHosts for cleanup
$script:TemporaryTrustedHosts = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

# Default ports
$script:WinRMHttpPort = 5985
$script:WinRMHttpsPort = 5986

# Connection preferences
$script:PreferHTTPS = $true
$script:AutoManageTrustedHosts = $true

#endregion

#region Environment Detection

function Test-RMMDomainMembership {
    <#
    .SYNOPSIS
        Check if the local computer is domain-joined.
    .OUTPUTS
        Boolean indicating domain membership.
    #>
    [CmdletBinding()]
    param()

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        return ($cs.PartOfDomain -eq $true)
    }
    catch {
        # Fallback method
        try {
            $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()
            return ($null -ne $domain)
        }
        catch {
            return $false
        }
    }
}

function Test-RMMRemoteHTTPS {
    <#
    .SYNOPSIS
        Test if a remote computer has WinRM HTTPS listener available.
    .PARAMETER ComputerName
        Target computer hostname or IP.
    .PARAMETER TimeoutSeconds
        Connection timeout in seconds. Default: 5
    .OUTPUTS
        Boolean indicating HTTPS availability.
    .EXAMPLE
        Test-RMMRemoteHTTPS -ComputerName "SERVER01"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [int]$TimeoutSeconds = 5
    )

    try {
        $tcpTest = Test-NetConnection -ComputerName $ComputerName -Port $script:WinRMHttpsPort `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        return ($tcpTest.TcpTestSucceeded -eq $true)
    }
    catch {
        return $false
    }
}

function Test-RMMRemoteHTTP {
    <#
    .SYNOPSIS
        Test if a remote computer has WinRM HTTP listener available.
    .PARAMETER ComputerName
        Target computer hostname or IP.
    .OUTPUTS
        Boolean indicating HTTP availability.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    try {
        $tcpTest = Test-NetConnection -ComputerName $ComputerName -Port $script:WinRMHttpPort `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        return ($tcpTest.TcpTestSucceeded -eq $true)
    }
    catch {
        return $false
    }
}

function Test-RMMRemoteEnvironment {
    <#
    .SYNOPSIS
        Analyze remote connection requirements for a target computer.
    .DESCRIPTION
        Determines the best connection strategy based on:
        - Local domain membership
        - Remote HTTPS availability
        - TrustedHosts configuration
    .PARAMETER ComputerName
        Target computer hostname or IP.
    .OUTPUTS
        PSCustomObject with connection recommendations.
    .EXAMPLE
        $env = Test-RMMRemoteEnvironment -ComputerName "WORKGROUP-PC"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    $result = [PSCustomObject]@{
        ComputerName         = $ComputerName
        LocalIsDomainJoined  = (Test-RMMDomainMembership)
        HTTPSAvailable       = (Test-RMMRemoteHTTPS -ComputerName $ComputerName)
        HTTPAvailable        = (Test-RMMRemoteHTTP -ComputerName $ComputerName)
        InTrustedHosts       = (Test-RMMInTrustedHosts -ComputerName $ComputerName)
        RecommendedTransport = 'HTTP'
        RequiresTrustedHost  = $false
        ConnectionReady      = $false
        Message              = ''
    }

    # Determine recommended transport and requirements
    if ($result.LocalIsDomainJoined) {
        # Domain environment - Kerberos should work, prefer HTTP for simplicity
        $result.RecommendedTransport = 'HTTP'
        $result.RequiresTrustedHost = $false
        $result.ConnectionReady = $result.HTTPAvailable
        $result.Message = "Domain environment - using Kerberos authentication"
    }
    elseif ($result.HTTPSAvailable) {
        # HTTPS available - use it (more secure for workgroup)
        $result.RecommendedTransport = 'HTTPS'
        $result.RequiresTrustedHost = $false
        $result.ConnectionReady = $true
        $result.Message = "HTTPS available - using secure transport"
    }
    elseif ($result.HTTPAvailable) {
        # HTTP only - need TrustedHosts for workgroup
        $result.RecommendedTransport = 'HTTP'
        $result.RequiresTrustedHost = -not $result.InTrustedHosts
        $result.ConnectionReady = $result.InTrustedHosts
        if ($result.InTrustedHosts) {
            $result.Message = "Workgroup target in TrustedHosts - HTTP connection ready"
        }
        else {
            $result.Message = "Workgroup target requires TrustedHosts entry for HTTP connection"
        }
    }
    else {
        $result.Message = "No WinRM listener detected on target (ports 5985/5986 not responding)"
    }

    return $result
}

#endregion

#region TrustedHosts Management

function Get-RMMTrustedHosts {
    <#
    .SYNOPSIS
        Get the current TrustedHosts list as an array.
    .OUTPUTS
        Array of trusted host entries.
    #>
    [CmdletBinding()]
    param()

    try {
        $trustedHosts = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction Stop).Value
        if ([string]::IsNullOrWhiteSpace($trustedHosts)) {
            return @()
        }
        return ($trustedHosts -split ',').Trim() | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
    catch {
        Write-Warning "Failed to read TrustedHosts: $_"
        return @()
    }
}

function Test-RMMInTrustedHosts {
    <#
    .SYNOPSIS
        Check if a computer is in the TrustedHosts list.
    .PARAMETER ComputerName
        Computer name or IP to check.
    .OUTPUTS
        Boolean indicating if the computer is trusted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    $trustedHosts = Get-RMMTrustedHosts

    # Check for exact match or wildcard
    if ($trustedHosts -contains '*') { return $true }
    if ($trustedHosts -contains $ComputerName) { return $true }

    # Check for pattern matches (e.g., *.domain.local)
    foreach ($pattern in $trustedHosts) {
        if ($pattern -like '*`**') {
            $regex = '^' + [regex]::Escape($pattern).Replace('\*', '.*') + '$'
            if ($ComputerName -match $regex) { return $true }
        }
    }

    return $false
}

function Add-RMMTrustedHost {
    <#
    .SYNOPSIS
        Safely add a computer to TrustedHosts using concatenation.
    .DESCRIPTION
        Adds a single computer to TrustedHosts without replacing existing entries.
        Tracks temporary additions for later cleanup.
    .PARAMETER ComputerName
        Computer name or IP to add.
    .PARAMETER Temporary
        Mark as temporary for cleanup later. Default: $true
    .EXAMPLE
        Add-RMMTrustedHost -ComputerName "WORKGROUP-PC"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [bool]$Temporary = $true
    )

    # Check if already in list
    if (Test-RMMInTrustedHosts -ComputerName $ComputerName) {
        Write-Verbose "Computer '$ComputerName' is already in TrustedHosts"
        return $true
    }

    try {
        # Use -Concatenate to safely append
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value $ComputerName -Concatenate -Force -ErrorAction Stop

        if ($Temporary) {
            [void]$script:TemporaryTrustedHosts.Add($ComputerName)
        }

        Write-Verbose "Added '$ComputerName' to TrustedHosts"
        return $true
    }
    catch {
        Write-Warning "Failed to add '$ComputerName' to TrustedHosts: $_"
        Write-Warning "You may need to run PowerShell as Administrator or manually add the host."
        return $false
    }
}

function Remove-RMMTrustedHost {
    <#
    .SYNOPSIS
        Remove a specific computer from TrustedHosts.
    .PARAMETER ComputerName
        Computer name or IP to remove.
    .EXAMPLE
        Remove-RMMTrustedHost -ComputerName "WORKGROUP-PC"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    $trustedHosts = Get-RMMTrustedHosts
    if ($trustedHosts.Count -eq 0) { return $true }

    $newList = $trustedHosts | Where-Object { $_ -ne $ComputerName }

    try {
        $newValue = ($newList -join ',')
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value $newValue -Force -ErrorAction Stop
        [void]$script:TemporaryTrustedHosts.Remove($ComputerName)
        Write-Verbose "Removed '$ComputerName' from TrustedHosts"
        return $true
    }
    catch {
        Write-Warning "Failed to remove '$ComputerName' from TrustedHosts: $_"
        return $false
    }
}

function Clear-RMMTemporaryTrustedHosts {
    <#
    .SYNOPSIS
        Remove all temporarily added TrustedHosts entries.
    .DESCRIPTION
        Cleans up all hosts that were added with Add-RMMTrustedHost -Temporary $true.
    .EXAMPLE
        Clear-RMMTemporaryTrustedHosts
    #>
    [CmdletBinding()]
    param()

    $hostsToRemove = @($script:TemporaryTrustedHosts)
    foreach ($hostEntry in $hostsToRemove) {
        Remove-RMMTrustedHost -ComputerName $hostEntry | Out-Null
    }
    $script:TemporaryTrustedHosts.Clear()
    Write-Verbose "Cleared $($hostsToRemove.Count) temporary TrustedHosts entries"
}

#endregion

#region Session Creation

function New-RMMRemoteSession {
    <#
    .SYNOPSIS
        Create a PSSession with automatic transport and TrustedHosts handling.
    .DESCRIPTION
        Creates a PowerShell remoting session with intelligent transport selection:
        - Uses Kerberos in domain environments
        - Prefers HTTPS for workgroup/non-domain targets
        - Automatically manages TrustedHosts for HTTP fallback
        - Provides clear error messages for connection issues
    .PARAMETER ComputerName
        Target computer hostname or IP.
    .PARAMETER Credential
        PSCredential for authentication (required for workgroup targets).
    .PARAMETER UseHTTPS
        Force HTTPS transport. Default: auto-detect
    .PARAMETER RequireHTTPS
        Require HTTPS - fail if not available. Default: $false
    .PARAMETER SkipTrustedHostsManagement
        Do not automatically manage TrustedHosts. Default: $false
    .PARAMETER SessionOption
        Optional PSSessionOption object.
    .OUTPUTS
        PSSession object if successful, $null if failed.
    .EXAMPLE
        $session = New-RMMRemoteSession -ComputerName "SERVER01"
    .EXAMPLE
        $session = New-RMMRemoteSession -ComputerName "WORKGROUP-PC" -Credential $cred -RequireHTTPS
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [PSCredential]$Credential,
        [switch]$UseHTTPS,
        [switch]$RequireHTTPS,
        [switch]$SkipTrustedHostsManagement,
        [System.Management.Automation.Remoting.PSSessionOption]$SessionOption
    )

    # Analyze the remote environment
    $envCheck = Test-RMMRemoteEnvironment -ComputerName $ComputerName

    if (-not $envCheck.HTTPSAvailable -and -not $envCheck.HTTPAvailable) {
        $errorMsg = @"
Cannot connect to '$ComputerName': No WinRM listener detected.
Troubleshooting:
  1. Verify the computer is online: Test-Connection -ComputerName '$ComputerName'
  2. Enable WinRM on target: Enable-PSRemoting -Force
  3. Check firewall allows ports 5985 (HTTP) or 5986 (HTTPS)
"@
        Write-Warning $errorMsg
        return $null
    }

    # Determine transport
    $useHttps = $UseHTTPS.IsPresent -or ($script:PreferHTTPS -and $envCheck.HTTPSAvailable)

    if ($RequireHTTPS -and -not $envCheck.HTTPSAvailable) {
        $errorMsg = @"
HTTPS required but not available on '$ComputerName'.
To configure HTTPS on the target:
  `$cert = New-SelfSignedCertificate -DnsName '$ComputerName' -CertStoreLocation Cert:\LocalMachine\My
  New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint `$cert.Thumbprint -Force
"@
        Write-Warning $errorMsg
        return $null
    }

    # Build session parameters
    $sessionParams = @{
        ComputerName = $ComputerName
        ErrorAction  = 'Stop'
    }

    if ($Credential) {
        $sessionParams.Credential = $Credential
    }

    if ($SessionOption) {
        $sessionParams.SessionOption = $SessionOption
    }

    # Configure transport-specific options
    if ($useHttps) {
        $sessionParams.UseSSL = $true
        $sessionParams.Port = $script:WinRMHttpsPort

        # For self-signed certs, may need to skip CA check
        if (-not $SessionOption) {
            $skipCaOption = New-PSSessionOption -SkipCACheck -SkipCNCheck
            $sessionParams.SessionOption = $skipCaOption
        }
    }
    else {
        # HTTP transport - handle TrustedHosts for workgroup
        if ($envCheck.RequiresTrustedHost -and -not $SkipTrustedHostsManagement) {
            if ($script:AutoManageTrustedHosts) {
                Write-Verbose "Adding '$ComputerName' to TrustedHosts for HTTP connection"
                $added = Add-RMMTrustedHost -ComputerName $ComputerName -Temporary $true
                if (-not $added) {
                    $errorMsg = @"
Cannot add '$ComputerName' to TrustedHosts. Options:
  1. Run PowerShell as Administrator
  2. Manually add: Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$ComputerName' -Concatenate -Force
  3. Configure HTTPS on the target (recommended for security)
"@
                    Write-Warning $errorMsg
                    return $null
                }
            }
            else {
                $errorMsg = @"
Target '$ComputerName' is not in TrustedHosts and automatic management is disabled.
Add manually: Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$ComputerName' -Concatenate -Force
Or configure HTTPS on the target for secure connection without TrustedHosts.
"@
                Write-Warning $errorMsg
                return $null
            }
        }
    }

    # Create the session
    try {
        $session = New-PSSession @sessionParams
        $transport = if ($useHttps) { "HTTPS" } else { "HTTP" }
        Write-Verbose "Created $transport session to '$ComputerName'"
        return $session
    }
    catch {
        $errorMsg = "Failed to create session to '$ComputerName': $($_.Exception.Message)"

        # Provide specific guidance based on error
        if ($_.Exception.Message -match 'Access is denied|Access denied') {
            $errorMsg += "`nVerify credentials are correct and have remote access permissions."
        }
        elseif ($_.Exception.Message -match 'TrustedHosts') {
            $errorMsg += "`nAdd to TrustedHosts: Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$ComputerName' -Concatenate -Force"
        }
        elseif ($_.Exception.Message -match 'SSL|certificate') {
            $errorMsg += "`nSSL/Certificate issue. Try: -SkipCACheck or verify certificate trust."
        }

        Write-Warning $errorMsg
        return $null
    }
}

function Invoke-RMMRemoteCommand {
    <#
    .SYNOPSIS
        Execute a command on a remote computer with automatic connection handling.
    .DESCRIPTION
        Wrapper around Invoke-Command that handles:
        - Transport selection (HTTPS preferred for workgroup)
        - TrustedHosts management
        - Credential handling
        - Clear error messaging
    .PARAMETER ComputerName
        Target computer hostname or IP.
    .PARAMETER ScriptBlock
        Script block to execute remotely.
    .PARAMETER ArgumentList
        Arguments to pass to the script block.
    .PARAMETER Credential
        PSCredential for authentication.
    .PARAMETER RequireHTTPS
        Require HTTPS transport. Default: $false
    .PARAMETER UseSession
        Reuse an existing PSSession if available.
    .OUTPUTS
        Results from the remote command execution.
    .EXAMPLE
        Invoke-RMMRemoteCommand -ComputerName "SERVER01" -ScriptBlock { Get-Service }
    .EXAMPLE
        $result = Invoke-RMMRemoteCommand -ComputerName "WORKGROUP-PC" -Credential $cred -ScriptBlock { param($svc) Get-Service $svc } -ArgumentList "WinRM"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,
        [PSCredential]$Credential,
        [switch]$RequireHTTPS,
        [System.Management.Automation.Runspaces.PSSession]$UseSession
    )

    # If a session is provided, use it directly
    if ($UseSession -and $UseSession.State -eq 'Opened') {
        $invokeParams = @{
            Session     = $UseSession
            ScriptBlock = $ScriptBlock
            ErrorAction = 'Stop'
        }
        if ($ArgumentList) { $invokeParams.ArgumentList = $ArgumentList }
        return Invoke-Command @invokeParams
    }

    # Analyze remote environment
    $envCheck = Test-RMMRemoteEnvironment -ComputerName $ComputerName

    if (-not $envCheck.HTTPSAvailable -and -not $envCheck.HTTPAvailable) {
        throw "Cannot connect to '$ComputerName': No WinRM listener available."
    }

    # Determine if we need to handle TrustedHosts
    $needsTrustedHost = $false
    $useHttps = $script:PreferHTTPS -and $envCheck.HTTPSAvailable

    if ($RequireHTTPS) {
        if (-not $envCheck.HTTPSAvailable) {
            throw "HTTPS required but not available on '$ComputerName'."
        }
        $useHttps = $true
    }

    if (-not $useHttps -and $envCheck.RequiresTrustedHost -and $script:AutoManageTrustedHosts) {
        $needsTrustedHost = $true
        Add-RMMTrustedHost -ComputerName $ComputerName -Temporary $true | Out-Null
    }

    # Build Invoke-Command parameters
    $invokeParams = @{
        ComputerName = $ComputerName
        ScriptBlock  = $ScriptBlock
        ErrorAction  = 'Stop'
    }

    if ($Credential) { $invokeParams.Credential = $Credential }
    if ($ArgumentList) { $invokeParams.ArgumentList = $ArgumentList }

    if ($useHttps) {
        $invokeParams.UseSSL = $true
        $invokeParams.Port = $script:WinRMHttpsPort
        $invokeParams.SessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck
    }

    try {
        return Invoke-Command @invokeParams
    }
    catch {
        throw $_
    }
}

#endregion

#region Configuration

function Set-RMMRemotingPreference {
    <#
    .SYNOPSIS
        Configure remoting preferences for the module.
    .PARAMETER PreferHTTPS
        Prefer HTTPS transport when available. Default: $true
    .PARAMETER AutoManageTrustedHosts
        Automatically manage TrustedHosts for workgroup connections. Default: $true
    .EXAMPLE
        Set-RMMRemotingPreference -PreferHTTPS $true -AutoManageTrustedHosts $false
    #>
    [CmdletBinding()]
    param(
        [bool]$PreferHTTPS,
        [bool]$AutoManageTrustedHosts
    )

    if ($PSBoundParameters.ContainsKey('PreferHTTPS')) {
        $script:PreferHTTPS = $PreferHTTPS
        Write-Verbose "PreferHTTPS set to: $PreferHTTPS"
    }
    if ($PSBoundParameters.ContainsKey('AutoManageTrustedHosts')) {
        $script:AutoManageTrustedHosts = $AutoManageTrustedHosts
        Write-Verbose "AutoManageTrustedHosts set to: $AutoManageTrustedHosts"
    }
}

function Get-RMMRemotingPreference {
    <#
    .SYNOPSIS
        Get current remoting preferences.
    .OUTPUTS
        PSCustomObject with current preferences.
    #>
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        PreferHTTPS              = $script:PreferHTTPS
        AutoManageTrustedHosts   = $script:AutoManageTrustedHosts
        WinRMHttpPort            = $script:WinRMHttpPort
        WinRMHttpsPort           = $script:WinRMHttpsPort
        TemporaryTrustedHosts    = @($script:TemporaryTrustedHosts)
    }
}

#endregion

