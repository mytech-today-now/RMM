# Implementation Guidelines

*Previous: [12-security.md](12-security.md)*

---

## Coding Standards

- Follow myTech.Today PowerShell guidelines (see .augment/core-guidelines.md)
- Verb-Noun naming convention
- Comprehensive comment-based help
- Parameter validation on all functions
- ASCII-only output (no emoji)
- Centralized logging to `%USERPROFILE%\myTech.Today\logs\`

### Function Template

```powershell
function Verb-Noun {
    <#
    .SYNOPSIS
        Brief description of function.
    
    .DESCRIPTION
        Detailed description of function behavior.
    
    .PARAMETER ParameterName
        Description of the parameter.
    
    .EXAMPLE
        Verb-Noun -ParameterName "Value"
        Description of what this example does.
    
    .OUTPUTS
        [Type] Description of output.
    
    .NOTES
        Author: Kyle C. Rode
        Company: myTech.Today
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ParameterName
    )
    
    begin {
        # Initialization
    }
    
    process {
        try {
            # Main logic
        }
        catch {
            Write-LogError "Error in Verb-Noun: $_"
            throw
        }
    }
    
    end {
        # Cleanup
    }
}
```

---

## Error Handling

```powershell
try {
    $result = Invoke-Command -ComputerName $target -ScriptBlock $sb -ErrorAction Stop
}
catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
    Write-LogWarning "Device unreachable: $target"
    Set-DeviceStatus -DeviceId $deviceId -Status "Offline"
    Add-OfflineQueue -DeviceId $deviceId -Action $pendingAction
}
catch {
    Write-LogError "Unexpected error on $target : $_"
    throw
}
```

### Error Categories
- **Transient:** Network issues, timeouts - retry with backoff
- **Device:** Device offline, WinRM disabled - queue for later
- **Configuration:** Invalid settings - log and alert admin
- **Fatal:** Database corruption, critical failure - stop and notify

---

## Testing Requirements

- Unit tests for all core functions (Pester 5.x)
- Integration tests with mock devices
- Performance tests for scale validation
- Target: 80% code coverage

### Test Structure

```
tests/
├── Unit/
│   ├── Core.Tests.ps1
│   ├── Collectors.Tests.ps1
│   └── Actions.Tests.ps1
├── Integration/
│   ├── WinRM.Tests.ps1
│   └── Database.Tests.ps1
└── Performance/
    ├── Parallel.Tests.ps1
    └── Scale.Tests.ps1
```

---

## Documentation

- README.md: Quick start, feature matrix, screenshots
- docs/Setup-Guide.md: Detailed installation
- docs/Architecture.md: System design
- docs/API-Reference.md: Function documentation
- docs/Scaling-Guide.md: Performance tuning
- docs/Troubleshooting.md: Common issues

---

*Next: [14-comparison.md](14-comparison.md)*

