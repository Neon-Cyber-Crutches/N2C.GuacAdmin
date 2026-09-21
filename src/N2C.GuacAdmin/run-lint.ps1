#Requires -Version 5.1
<#
.SYNOPSIS
    Runs PSScriptAnalyzer over the N2C.GuacAdmin module with the documented
    settings (PSScriptAnalyzerSettings.psd1). Exits non-zero when any finding
    remains, so it can gate CI.

.DESCRIPTION
    Every intentional rule deviation lives in PSScriptAnalyzerSettings.psd1
    with a rationale. Any finding not covered there is a real issue and fails
    the build. The module is linted at Error/Warning severity; -ShowInfo also
    reports Info-level findings without failing on them.

.EXAMPLE
    pwsh ./run-lint.ps1
    pwsh ./run-lint.ps1 -ShowInfo
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [switch] $ShowInfo
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $root 'PSScriptAnalyzerSettings.psd1'

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    throw 'PSScriptAnalyzer is required to run this script (Install-Module PSScriptAnalyzer).'
}

$settings = Import-PowerShellDataFile -LiteralPath $settingsPath
$settings['Severity'] = @('Warning', 'Error')
if ($ShowInfo) {
    $settings['Severity'] = @('Info', 'Warning', 'Error')
}

$report = Invoke-ScriptAnalyzer -Path $root -Recurse -Settings $settings

if ($null -ne $report -and @($report).Count -gt 0) {
    @($report) | Format-Table -AutoSize RuleName, Severity, ScriptName, Line | Out-String -Width 200 | Write-Output
    if ($ShowInfo) {
        # Info-level findings are informational only; fail on Warning/Error.
        $blocking = @($report) | Where-Object { $_.Severity -ne 'Info' }
        if ($blocking.Count -eq 0) {
            Write-Output 'PSScriptAnalyzer: no blocking findings (Info shown above).'
            return
        }
    }
    Write-Error ('PSScriptAnalyzer found {0} issue(s); see PSScriptAnalyzerSettings.psd1 for documented suppressions.' -f (@($report)).Count)
    exit 1
}
Write-Output 'PSScriptAnalyzer: no findings (settings: PSScriptAnalyzerSettings.psd1).'
