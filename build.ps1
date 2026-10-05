#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap and build script for N2C.GuacAdmin module.

.DESCRIPTION
    Downloads build dependencies to output/RequiredModules, overrides PSModulePath
    to use those versions, loads build.yml configuration, and runs build tasks
    for testing and linting.

    Usage:
        pwsh ./build.ps1                  # runs default tasks (test + lint)
        pwsh ./build.ps1 test             # runs unit + integration tests only
        pwsh ./build.ps1 lint             # runs PSScriptAnalyzer only
        pwsh ./build.ps1 test_unit        # runs unit tests only
        pwsh ./build.ps1 test_integration # runs integration tests only
        pwsh ./build.ps1 noop             # bootstraps dependencies, runs no tasks

.PARAMETER Tasks
    The task or tasks to run. The default value is '.' (runs the default task).

.PARAMETER OutputDirectory
    Specifies the folder to build the artefact into. The default value is 'output'.
#>
[CmdletBinding()]
param
(
    [Parameter(Position = 0)]
    [System.String[]]
    $Tasks = '.',

    [Parameter()]
    [System.String]
    $OutputDirectory = 'output'
)

# ============================================================================
# BOOTSTRAP: Resolve dependencies and override PSModulePath
#
# Build dependencies are saved to output/RequiredModules and that path is
# prepended to PSModulePath so they take precedence over any locally installed
# conflicting versions. This ensures reproducible builds regardless of the
# developer's local environment.
# ============================================================================

Write-Host "[bootstrap] Starting bootstrap" -ForegroundColor Green

# Resolve absolute paths
$repoRoot = $PSScriptRoot
$requiredModulesPath = Join-Path -Path $repoRoot -ChildPath (Join-Path -Path $OutputDirectory -ChildPath 'RequiredModules')
$buildConfigPath = Join-Path -Path $repoRoot -ChildPath 'build.yml'

# Create the required modules directory if it doesn't exist
if (-not (Test-Path -Path $requiredModulesPath -PathType Container))
{
    Write-Host "[bootstrap] Creating required modules directory: $requiredModulesPath" -ForegroundColor Green
    New-Item -Path $requiredModulesPath -ItemType Directory -Force | Out-Null
}

# Ensure the required modules path is FIRST in PSModulePath (single occurrence) to override local versions
$separator = [System.IO.Path]::PathSeparator
$paths = $env:PSModulePath -split [regex]::Escape($separator)
$occurrences = ($paths | Where-Object { $_ -eq $requiredModulesPath }).Count

if ($occurrences -eq 0 -or $paths[0] -ne $requiredModulesPath -or $occurrences -gt 1)
{
    # Remove any existing occurrences of requiredModulesPath (and empty strings)
    $paths = $paths | Where-Object { $_ -ne $requiredModulesPath -and $_ -ne '' }
    Write-Host "[bootstrap] Placing $requiredModulesPath first in PSModulePath" -ForegroundColor Green
    $paths = @($requiredModulesPath) + $paths
    $env:PSModulePath = $paths -join $separator
}
else
{
    Write-Host "[bootstrap] $requiredModulesPath already first in PSModulePath" -ForegroundColor DarkGreen
}

# ============================================================================
# INTERNAL DEPENDENCIES
#
# These modules are required by build.ps1 itself (e.g., to parse build.yml or
# provide the task runner) and cannot be specified in build.yml. They are
# bootstrapped before the build configuration is loaded.
# ============================================================================

$RequiredInternalModules = @(
    @{ Name = 'powershell-yaml'; Version = '0.4.12' }
    @{ Name = 'InvokeBuild';     Version = '5.14.23' }
)

foreach ($internalModule in $RequiredInternalModules)
{
    $moduleName = $internalModule.Name
    $version = $internalModule.Version

    Write-Host "[bootstrap] Ensuring internal dependency: $moduleName ($version)" -ForegroundColor Green

    # Check if the specific version already exists in RequiredModules before downloading
    # Check for the module manifest (.psd1) to verify a complete module was saved
    if ($version -eq 'latest')
    {
        $moduleBase = Join-Path -Path $requiredModulesPath -ChildPath $moduleName
        # Find any version subdirectory that has a .psd1 manifest
        $versionDirs = Get-ChildItem -Path $moduleBase -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+(\.\d+)*$' }
        $validDir = $versionDirs | ForEach-Object {
            $manifest = Join-Path -Path $_.FullName -ChildPath "$moduleName.psd1"
            if (Test-Path -Path $manifest -PathType Leaf) { $_ }
        } | Select-Object -First 1
        if (-not $validDir)
        {
            Write-Host "[bootstrap] Downloading $moduleName (latest) to $requiredModulesPath" -ForegroundColor Yellow
            Save-Module -Name $moduleName -Path $requiredModulesPath -Force -ErrorAction Stop
        }
    }
    else
    {
        $versionDir = Join-Path -Path (Join-Path -Path $requiredModulesPath -ChildPath $moduleName) -ChildPath $version
        $manifest = Join-Path -Path $versionDir -ChildPath "$moduleName.psd1"
        if (-not (Test-Path -Path $manifest -PathType Leaf))
        {
            Write-Host "[bootstrap] Downloading $moduleName ($version) to $requiredModulesPath" -ForegroundColor Yellow
            Save-Module -Name $moduleName -Path $requiredModulesPath -RequiredVersion $version -Force -ErrorAction Stop
        }
    }

    Write-Host "[bootstrap] Importing $moduleName" -ForegroundColor Green
    Import-Module -Name $moduleName -Force -ErrorAction Stop
    Write-Host "[bootstrap] $moduleName ready" -ForegroundColor DarkGreen
}

# Load build configuration
Write-Host "[bootstrap] Loading build configuration from $buildConfigPath" -ForegroundColor Green
if (-not (Test-Path -Path $buildConfigPath -PathType Leaf))
{
    throw "Build configuration file not found: $buildConfigPath"
}

$buildConfig = ConvertFrom-Yaml -Yaml (Get-Content -Path $buildConfigPath -Raw)

# Download all required modules from config to RequiredModules
$requiredModules = $buildConfig.RequiredModules
foreach ($moduleName in $requiredModules.Keys)
{
    $version = $requiredModules[$moduleName]
    Write-Host "[bootstrap] Ensuring $moduleName ($version) is available" -ForegroundColor Green

    # Check for the module manifest (.psd1) to verify a complete module was saved
    if ($version -eq 'latest')
    {
        $moduleBase = Join-Path -Path $requiredModulesPath -ChildPath $moduleName
        # Find any version subdirectory that has a .psd1 manifest
        $versionDirs = Get-ChildItem -Path $moduleBase -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+(\.\d+)*$' }
        $validDir = $versionDirs | ForEach-Object {
            $manifest = Join-Path -Path $_.FullName -ChildPath "$moduleName.psd1"
            if (Test-Path -Path $manifest -PathType Leaf) { $_ }
        } | Select-Object -First 1
        if (-not $validDir)
        {
            Write-Host "[bootstrap] Downloading $moduleName (latest) to $requiredModulesPath" -ForegroundColor Yellow
            Save-Module -Name $moduleName -Path $requiredModulesPath -Force -ErrorAction Stop
        }
    }
    else
    {
        $versionDir = Join-Path -Path (Join-Path -Path $requiredModulesPath -ChildPath $moduleName) -ChildPath $version
        $manifest = Join-Path -Path $versionDir -ChildPath "$moduleName.psd1"
        if (-not (Test-Path -Path $manifest -PathType Leaf))
        {
            Write-Host "[bootstrap] Downloading $moduleName ($version) to $requiredModulesPath" -ForegroundColor Yellow
            Save-Module -Name $moduleName -Path $requiredModulesPath -RequiredVersion $version -Force -ErrorAction Stop
        }
    }

    Write-Host "[bootstrap] $moduleName ready" -ForegroundColor DarkGreen
}

# Import required modules into the session
Write-Host "[bootstrap] Importing required modules" -ForegroundColor Green
foreach ($moduleName in $requiredModules.Keys)
{
    Import-Module -Name $moduleName -Force -ErrorAction Stop
    Write-Host "[bootstrap] Imported $moduleName" -ForegroundColor DarkGreen
}

Write-Host "[bootstrap] Bootstrap complete" -ForegroundColor Green

# ============================================================================
# TASK EXECUTION
# ============================================================================

# Helper: run unit tests via Pester
function Invoke-UnitTests {
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Running unit tests" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Cyan

    $unitFiles = @()
    foreach ($file in $buildConfig.Tests.UnitFiles)
    {
        $unitFiles += Join-Path -Path $repoRoot -ChildPath $file
    }

    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = $unitFiles
    $pesterConfig.Run.Exit = $true
    $pesterConfig.Output.Verbosity = $buildConfig.Tests.Verbosity
    Invoke-Pester -Configuration $pesterConfig
}

# Helper: run integration tests via Pester
function Invoke-IntegrationTests {
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Running integration tests" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Cyan

    $integrationFiles = @()
    foreach ($file in $buildConfig.Tests.IntegrationFiles)
    {
        $integrationFiles += Join-Path -Path $repoRoot -ChildPath $file
    }

    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = $integrationFiles
    $pesterConfig.Run.Exit = $true
    $pesterConfig.Output.Verbosity = $buildConfig.Tests.Verbosity
    Invoke-Pester -Configuration $pesterConfig
}

# Helper: run PSScriptAnalyzer lint
function Invoke-Lint {
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Running PSScriptAnalyzer lint" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Cyan

    $lintScript = Join-Path -Path $repoRoot -ChildPath (Join-Path -Path $buildConfig.ModuleSource -ChildPath 'run-lint.ps1')

    if (-not (Test-Path -Path $lintScript -PathType Leaf))
    {
        throw "Lint script not found: $lintScript"
    }

    & $lintScript
    if (-not $?)
    {
        throw "PSScriptAnalyzer found issues"
    }
    Write-Host "PSScriptAnalyzer: no blocking findings" -ForegroundColor Green
}

# Determine which tasks to run based on workflow definitions in build.yml
if ($Tasks -contains '.')
{
    # Default workflow from config
    $defaultTasks = $buildConfig.BuildWorkflow['.']
    if ($defaultTasks)
    {
        Write-Host "[build] Running default workflow: $($defaultTasks -join ', ')" -ForegroundColor Magenta
        $Tasks = $defaultTasks
    }
    else
    {
        Write-Host "[build] No default workflow defined in build.yml" -ForegroundColor Yellow
        $Tasks = @('test', 'lint')
    }
}

Write-Host "[build] Running tasks: $($Tasks -join ', ')" -ForegroundColor Magenta

foreach ($taskName in $Tasks)
{
    switch ($taskName)
    {
        'test_unit' {
            Invoke-UnitTests
        }
        'test_integration' {
            Invoke-IntegrationTests
        }
        'test' {
            Invoke-UnitTests
            Invoke-IntegrationTests
        }
        'lint_module' {
            Invoke-Lint
        }
        'lint' {
            Invoke-Lint
        }
        'noop' {
            Write-Host "" -ForegroundColor Green
            Write-Host "Noop task completed (bootstrap only)" -ForegroundColor Green
            Write-Host "" -ForegroundColor Green
        }
        default {
            throw "Unknown task: $taskName"
        }
    }
}

Write-Host "" -ForegroundColor Green
Write-Host "Build completed successfully." -ForegroundColor Green
