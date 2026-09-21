#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the N2C.GuacAdmin Pester v5 test suite.

.DESCRIPTION
    Runs the unit tests (Helpers) and, when requested, the mock-based session
    lifecycle tests. Usage:
      pwsh -File ./run-tests.ps1                 # helpers only
      pwsh -File ./run-tests.ps1 -IncludeIntegration   # helpers + mock server
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [switch] $IncludeIntegration
)

$ErrorActionPreference = 'Stop'
$testsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$files = @()

# Always run the pure helper unit tests.
$files += (Join-Path $testsRoot 'Helpers.Tests.ps1')

# The session lifecycle tests spin up a local mock Guacamole server.
if ($IncludeIntegration) {
    $files += (Join-Path $testsRoot 'SessionLifecycle.Tests.ps1')
}

$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path = $files
$pesterConfig.Run.Exit = $true
$pesterConfig.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $pesterConfig
