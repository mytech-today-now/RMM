<#
.SYNOPSIS
    Unit tests for RMM Remoting module.

.DESCRIPTION
    Pester tests for remoting functionality including TrustedHosts management,
    HTTPS detection, and session creation.

.NOTES
    Author: myTech.Today RMM
    Requires: Pester 3.4+
#>

# Load module before tests
$modulePath = Join-Path $PSScriptRoot "..\..\scripts\core\RMM-Core.psm1"
Import-Module $modulePath -Force

Describe "RMM Remoting Module Tests" {
    Context "Module Loading" {
        It "Should export Test-RMMDomainMembership function" {
            Get-Command -Name Test-RMMDomainMembership -Module RMM-Core -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }

        It "Should export Test-RMMRemoteHTTPS function" {
            Get-Command -Name Test-RMMRemoteHTTPS -Module RMM-Core -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }

        It "Should export Test-RMMRemoteEnvironment function" {
            Get-Command -Name Test-RMMRemoteEnvironment -Module RMM-Core -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }

        It "Should export Get-RMMTrustedHosts function" {
            Get-Command -Name Get-RMMTrustedHosts -Module RMM-Core -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }

        It "Should export Add-RMMTrustedHost function" {
            Get-Command -Name Add-RMMTrustedHost -Module RMM-Core -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }

        It "Should export New-RMMRemoteSession function" {
            Get-Command -Name New-RMMRemoteSession -Module RMM-Core -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }

        It "Should export Invoke-RMMRemoteCommand function" {
            Get-Command -Name Invoke-RMMRemoteCommand -Module RMM-Core -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }

        It "Should export Set-RMMRemotingPreference function" {
            Get-Command -Name Set-RMMRemotingPreference -Module RMM-Core -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }

        It "Should export Get-RMMRemotingPreference function" {
            Get-Command -Name Get-RMMRemotingPreference -Module RMM-Core -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }

        It "Should export Clear-RMMTemporaryTrustedHosts function" {
            Get-Command -Name Clear-RMMTemporaryTrustedHosts -Module RMM-Core -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
    }

    Context "Domain Membership Detection" {
        It "Should return boolean from Test-RMMDomainMembership" {
            $result = Test-RMMDomainMembership
            $result.GetType().Name | Should Be 'Boolean'
        }
    }

    Context "TrustedHosts Management" {
        It "Should return array or empty from Get-RMMTrustedHosts" {
            $result = Get-RMMTrustedHosts
            # Result should be array or null/empty - both are valid
            ($result -eq $null -or $result -is [array] -or $result -is [string]) | Should Be $true
        }

        It "Should return boolean from Test-RMMInTrustedHosts" {
            $result = Test-RMMInTrustedHosts -ComputerName "localhost"
            $result.GetType().Name | Should Be 'Boolean'
        }
    }

    Context "Remoting Preferences" {
        It "Should get remoting preferences" {
            $prefs = Get-RMMRemotingPreference
            $prefs | Should Not BeNullOrEmpty
        }

        It "Should have PreferHTTPS property" {
            $prefs = Get-RMMRemotingPreference
            $prefs.PreferHTTPS | Should Be $true
        }

        It "Should have AutoManageTrustedHosts property" {
            $prefs = Get-RMMRemotingPreference
            $prefs.AutoManageTrustedHosts | Should Be $true
        }
    }

    Context "Remote Environment Testing" {
        It "Should analyze localhost environment" {
            $result = Test-RMMRemoteEnvironment -ComputerName "localhost"
            $result | Should Not BeNullOrEmpty
            $result.ComputerName | Should Be "localhost"
        }

        It "Should return LocalIsDomainJoined for localhost" {
            $result = Test-RMMRemoteEnvironment -ComputerName "localhost"
            $result.LocalIsDomainJoined.GetType().Name | Should Be 'Boolean'
        }

        It "Should return HTTPAvailable for localhost" {
            $result = Test-RMMRemoteEnvironment -ComputerName "localhost"
            $result.HTTPAvailable.GetType().Name | Should Be 'Boolean'
        }

        It "Should return RecommendedTransport" {
            $result = Test-RMMRemoteEnvironment -ComputerName "localhost"
            ($result.RecommendedTransport -eq 'HTTP' -or $result.RecommendedTransport -eq 'HTTPS') | Should Be $true
        }
    }
}

