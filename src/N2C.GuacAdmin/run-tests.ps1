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
$moduleRoot = $PSScriptRoot
$testsDir = Join-Path $moduleRoot 'Tests'
$files = @()

# Always run the pure helper unit tests.
$files += (Join-Path $testsDir 'Helpers.Tests.ps1')

# The integration tests spin up a local mock Guacamole server
# (Tests/GuacMockServer.ps1); every other *.Tests.ps1 in Tests/ is integration.
if ($IncludeIntegration) {
    $integrationFiles = Get-ChildItem -Path $testsDir -Filter '*.Tests.ps1' -File |
        Where-Object { $_.Name -ne 'Helpers.Tests.ps1' }
    $files += @($integrationFiles | ForEach-Object { $_.FullName })
}

$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path = $files
$pesterConfig.Run.Exit = $true
$pesterConfig.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $pesterConfig
