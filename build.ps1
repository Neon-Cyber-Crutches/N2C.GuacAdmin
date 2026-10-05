#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap and build script for N2C.GuacAdmin module.

.DESCRIPTION
    Downloads build dependencies to output/RequiredModules, overrides PSModulePath
    to use those versions, loads build.yml configuration, and runs build tasks
    for testing, linting, and publishing.

    Usage:
        pwsh ./build.ps1                  # runs default tasks (test + lint)
        pwsh ./build.ps1 test             # runs unit + integration tests only
        pwsh ./build.ps1 lint             # runs PSScriptAnalyzer only
        pwsh ./build.ps1 test_unit        # runs unit tests only
        pwsh ./build.ps1 test_integration # runs integration tests only
        pwsh ./build.ps1 noop             # bootstraps dependencies, runs no tasks
        pwsh ./build.ps1 publish_validate # validates module for PSGallery publishing
        pwsh ./build.ps1 publish_dry_run  # test + lint + publish_validate
        pwsh ./build.ps1 publish          # full publish pipeline (test + lint + validate + publish)
        pwsh ./build.ps1 version_bump -BumpType patch # bumps version in manifest

.PARAMETER Tasks
    The task or tasks to run. The default value is '.' (runs the default task).

.PARAMETER OutputDirectory
    Specifies the folder to build the artefact into. The default value is 'output'.

.PARAMETER ApiKey
    PSGallery API key for publishing. If not provided, the script will look for:
    1. The .psgallerykey file in the repository root (local development)
    2. The PSGALLERY_API_KEY environment variable (CI environments)

.PARAMETER BumpType
    Version bump type for the version_bump task. One of: major, minor, patch.
    Required when running the version_bump task.
#>
[CmdletBinding()]
param
(
    [Parameter(Position = 0)]
    [System.String[]]
    $Tasks = '.',

    [Parameter()]
    [System.String]
    $OutputDirectory = 'output',

    [Parameter()]
    [System.String]
    $ApiKey,

    [Parameter()]
    [ValidateSet('major', 'minor', 'patch')]
    [System.String]
    $BumpType
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

# Helper: resolve PSGallery API key
function Resolve-PublishApiKey {
    param(
        [System.String] $ApiKeyParam
    )

    # Priority 1: explicit parameter
    if ($ApiKeyParam)
    {
        Write-Host "[publish] Using API key from parameter" -ForegroundColor DarkGreen
        return $ApiKeyParam
    }

    # Priority 2: .psgallerykey file
    $keyFile = Join-Path -Path $repoRoot -ChildPath $buildConfig.Publish.ApiKeyFile
    if (Test-Path -Path $keyFile -PathType Leaf)
    {
        $fileKey = (Get-Content -Path $keyFile -Raw).Trim()
        if ($fileKey)
        {
            Write-Host "[publish] Using API key from $keyFile" -ForegroundColor DarkGreen
            return $fileKey
        }
    }

    # Priority 3: environment variable
    if ($env:PSGALLERY_API_KEY)
    {
        Write-Host "[publish] Using API key from PSGALLERY_API_KEY environment variable" -ForegroundColor DarkGreen
        return $env:PSGALLERY_API_KEY
    }

    throw "No PSGallery API key found. Provide one via: -ApiKey parameter, .psgallerykey file, or PSGALLERY_API_KEY environment variable."
}

# Helper: validate module for PSGallery
function Invoke-PublishValidate {
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Validating module for PSGallery publishing" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Cyan

    $modulePath = Join-Path -Path $repoRoot -ChildPath $buildConfig.ModuleSource

    # Import the manifest to get module info
    $manifestPath = Join-Path -Path $modulePath -ChildPath 'N2C.GuacAdmin.psd1'
    $manifest = Import-PowerShellDataFile -Path $manifestPath

    Write-Host "Module: N2C.GuacAdmin v$($manifest.ModuleVersion)" -ForegroundColor White
    Write-Host "Repository: $($buildConfig.Publish.Repository)" -ForegroundColor White

    # Manual cross-platform validation (Validate-Module is Windows-only)
    $validationErrors = @()

    # Check RootModule exists
    $rootModule = Join-Path -Path $modulePath -ChildPath $manifest.RootModule
    if (-not (Test-Path -Path $rootModule -PathType Leaf))
    {
        $validationErrors += "RootModule not found: $($manifest.RootModule)"
    }

    # Check ScriptsToProcess exist
    if ($manifest.ScriptsToProcess)
    {
        foreach ($script in $manifest.ScriptsToProcess)
        {
            $scriptPath = Join-Path -Path $modulePath -ChildPath $script
            if (-not (Test-Path -Path $scriptPath -PathType Leaf))
            {
                $validationErrors += "ScriptsToProcess file not found: $script"
            }
        }
    }

    # Check FormatsToProcess exist
    if ($manifest.FormatsToProcess)
    {
        foreach ($format in $manifest.FormatsToProcess)
        {
            $formatPath = Join-Path -Path $modulePath -ChildPath $format
            if (-not (Test-Path -Path $formatPath -PathType Leaf))
            {
                $validationErrors += "FormatsToProcess file not found: $format"
            }
        }
    }

    # Check all exported functions exist in Public/
    if ($manifest.FunctionsToExport)
    {
        foreach ($fn in $manifest.FunctionsToExport)
        {
            $fnPath = Join-Path -Path (Join-Path -Path $modulePath -ChildPath 'Public') -ChildPath "$fn.ps1"
            if (-not (Test-Path -Path $fnPath -PathType Leaf))
            {
                $validationErrors += "Exported function script not found: Public/$fn.ps1"
            }
        }
    }

    # Verify required PSData fields
    $psData = $manifest.PrivateData.PSData
    if (-not $psData.Tags -or @($psData.Tags).Count -eq 0)
    {
        $validationErrors += "Missing or empty Tags in PrivateData.PSData"
    }
    if (-not $psData.ProjectUri)
    {
        $validationErrors += "Missing ProjectUri in PrivateData.PSData"
    }
    if (-not $psData.ReleaseNotes)
    {
        $validationErrors += "Missing ReleaseNotes in PrivateData.PSData"
    }

    # Check version format
    try
    {
        [System.Version]::Parse($manifest.ModuleVersion) | Out-Null
    }
    catch
    {
        $validationErrors += "Invalid ModuleVersion format: $($manifest.ModuleVersion)"
    }

    if ($validationErrors.Count -gt 0)
    {
        Write-Host "" -ForegroundColor Red
        Write-Host "Validation errors:" -ForegroundColor Red
        foreach ($e in $validationErrors)
        {
            Write-Host "  - $e" -ForegroundColor Red
        }
        throw "Module validation failed with $($validationErrors.Count) error(s)"
    }

    Write-Host "" -ForegroundColor Green
    Write-Host "Module validation passed (manifest structure, exports, PSData fields)" -ForegroundColor Green
}

# Helper: package module as a zip artifact for GitHub Releases
# Includes only runtime-essential files, excluding tests, dev tools, and docs.
function Invoke-PackModule {
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Packaging module as release artifact" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Cyan

    $modulePath = Join-Path -Path $repoRoot -ChildPath $buildConfig.ModuleSource
    $outputPath = Join-Path -Path $repoRoot -ChildPath $OutputDirectory

    # Import manifest for version display
    $manifestPath = Join-Path -Path $modulePath -ChildPath 'N2C.GuacAdmin.psd1'
    $manifest = Import-PowerShellDataFile -Path $manifestPath
    $version = $manifest.ModuleVersion

    # Create output directory if it doesn't exist
    if (-not (Test-Path -Path $outputPath -PathType Container))
    {
        New-Item -Path $outputPath -ItemType Directory -Force | Out-Null
    }

    $zipName = "N2C.GuacAdmin-$version.zip"
    $zipPath = Join-Path -Path $outputPath -ChildPath $zipName

    # Remove existing zip if present
    if (Test-Path -Path $zipPath -PathType Leaf)
    {
        Remove-Item -Path $zipPath -Force
    }

    Write-Host "Creating $zipName" -ForegroundColor White

    # Create a temporary staging directory for the release artifact
    $stagingDir = Join-Path -Path $env:TEMP -ChildPath "N2C.GuacAdmin-pack-$(Get-Random)"
    New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null

    try
    {
        # Read include patterns from build configuration (build.yml).
        # These are the runtime-essential module files; all others
        # (tests, dev tooling, docs, linter settings, runner scripts)
        # are excluded from the release artifact.
        $includePatterns = @($buildConfig.Pack.Include)

        foreach ($pattern in $includePatterns)
        {
            $itemPath = Join-Path -Path $modulePath -ChildPath $pattern
            if (Test-Path -Path $itemPath)
            {
                Copy-Item -Path $itemPath -Destination $stagingDir -Recurse -Force
            }
        }

        # Use Compress-Archive for simplicity and cross-platform compatibility
        Compress-Archive -Path (Join-Path -Path $stagingDir -ChildPath '*') -DestinationPath $zipPath -Force
    }
    finally
    {
        # Clean up staging directory
        if (Test-Path -Path $stagingDir)
        {
            Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Artifact created: $zipPath" -ForegroundColor Green
    Write-Host "Artifact size: $((Get-Item $zipPath).Length / 1KB) KB" -ForegroundColor Green

    # Store the zip path for use by other tasks
    $script:PackArtifactPath = $zipPath
    $script:PackArtifactName = $zipName
}

# Helper: publish module to PSGallery
# Uses Publish-PSResource (PSResourceGet) when available — the modern cross-platform
# approach that doesn't rely on dotnet pack. Falls back to Publish-Module (PowerShellGet).
function Invoke-PublishModule {
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Publishing module to PSGallery" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Cyan

    $modulePath = Join-Path -Path $repoRoot -ChildPath $buildConfig.ModuleSource
    $apiKey = Resolve-PublishApiKey -ApiKeyParam $ApiKey
    $repository = $buildConfig.Publish.Repository

    # Import manifest for version display
    $manifestPath = Join-Path -Path $modulePath -ChildPath 'N2C.GuacAdmin.psd1'
    $manifest = Import-PowerShellDataFile -Path $manifestPath

    Write-Host "Module: N2C.GuacAdmin v$($manifest.ModuleVersion)" -ForegroundColor White
    Write-Host "Repository: $repository" -ForegroundColor White
    Write-Host "API Key: ***" -ForegroundColor White

    # Check for PSResourceGet (modern) or fall back to PowerShellGet (legacy)
    $hasPSResourceGet = $false
    try
    {
        Import-Module -Name 'Microsoft.PowerShell.PSResourceGet' -Force -ErrorAction Stop
        $hasPSResourceGet = $true
        Write-Host "Using Publish-PSResource (PSResourceGet)" -ForegroundColor DarkGreen
    }
    catch
    {
        Write-Host "PSResourceGet not available, falling back to Publish-Module (PowerShellGet)" -ForegroundColor Yellow
    }

    if ($hasPSResourceGet)
    {
        Publish-PSResource -Path $modulePath -Repository $repository -ApiKey $apiKey -ErrorAction Stop
    }
    else
    {
        Import-Module -Name PowerShellGet -Force -ErrorAction Stop
        Publish-Module -Path $modulePath -Repository $repository -NuGetApiKey $apiKey -Force -ErrorAction Stop
    }

    Write-Host "" -ForegroundColor Green
    Write-Host "Module published successfully to $repository" -ForegroundColor Green
}

# Helper: publish module to GitHub Packages (NuGet protocol)
# GitHub Packages for PowerShell uses NuGet feeds. The module is packaged as a .nupkg
# and pushed to the repository's NuGet feed using the GITHUB_TOKEN.
function Invoke-PublishGitHubPackages {
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Publishing module to GitHub Packages" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Cyan

    $modulePath = Join-Path -Path $repoRoot -ChildPath $buildConfig.ModuleSource
    $ghToken = $env:GITHUB_TOKEN

    if (-not $ghToken)
    {
        throw "GITHUB_TOKEN environment variable not set. Required for GitHub Packages publishing."
    }

    # Import manifest for version and metadata
    $manifestPath = Join-Path -Path $modulePath -ChildPath 'N2C.GuacAdmin.psd1'
    $manifest = Import-PowerShellDataFile -Path $manifestPath
    $version = $manifest.ModuleVersion
    $description = $manifest.Description
    $authors = $manifest.Authors -join ', '
    $projectUri = $manifest.PrivateData.PSData.ProjectUri

    Write-Host "Module: N2C.GuacAdmin v$version" -ForegroundColor White
    Write-Host "GitHub Packages (NuGet feed)" -ForegroundColor White

    # Get the GitHub repository owner and name from the GITHUB_REPOSITORY env var (CI)
    # or default to the known values
    $ghRepo = $env:GITHUB_REPOSITORY
    if (-not $ghRepo)
    {
        $ghRepo = 'Neon-Cyber-Crutches/N2C.GuacAdmin'
    }
    $ghOwner = ($ghRepo -split '/')[0]
    $ghRepoName = ($ghRepo -split '/')[1]

    $nugetFeed = "https://nuget.pkg.github.com/$ghOwner/index.json"
    Write-Host "NuGet feed: $nugetFeed" -ForegroundColor DarkGreen

    # Create a temporary directory for NuGet packaging
    $tempDir = Join-Path -Path $env:TEMP -ChildPath "N2C.GuacAdmin-nuget-$(Get-Random)"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    try
    {
        # Create a .nuspec file
        $nuspecPath = Join-Path -Path $tempDir -ChildPath 'N2C.GuacAdmin.nuspec'
        $nuspecContent = @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
  <metadata>
    <id>N2C.GuacAdmin</id>
    <version>$version</version>
    <title>N2C.GuacAdmin</title>
    <authors>$authors</authors>
    <description>$description</description>
    <projectUrl>$projectUri</projectUrl>
    <license type="expression">MIT</license>
    <tags>guacamole;remote-desktop;ssh;rdp;vnc;admin;apache</tags>
  </metadata>
  <files>
    <file src="$modulePath/N2C.GuacAdmin.psd1" target="tools" />
    <file src="$modulePath/N2C.GuacAdmin.psm1" target="tools" />
    <file src="$modulePath/N2C.GuacAdmin.Format.ps1xml" target="tools" />
    <file src="$modulePath/Types.ps1" target="tools" />
    <file src="$modulePath/Public/**/*" target="tools/Public" />
    <file src="$modulePath/Private/**/*" target="tools/Private" />
  </files>
</package>
"@
        Set-Content -Path $nuspecPath -Value $nuspecContent -Encoding UTF8

        # Use dotnet to pack and push (available on GitHub Actions runners)
        Write-Host "Creating NuGet package..." -ForegroundColor White

        # Add GitHub Packages as a NuGet source
        & dotnet nuget add source $nugetFeed --name github-packages --username "$ghOwner" --password "$ghToken" --store-password-in-clear-text 2>&1 | Out-Null

        # Pack the module
        $nupkgPath = Join-Path -Path $tempDir -ChildPath "N2C.GuacAdmin.$version.nupkg"
        & dotnet pack $nuspecPath -o $tempDir 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

        # Find the generated nupkg
        $generatedNupkg = Get-ChildItem -Path $tempDir -Filter "*.nupkg" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $generatedNupkg)
        {
            throw "NuGet package creation failed - no .nupkg file found"
        }

        Write-Host "Package created: $($generatedNupkg.Name)" -ForegroundColor DarkGreen

        # Push to GitHub Packages
        Write-Host "Pushing to GitHub Packages..." -ForegroundColor White
        & dotnet nuget push $generatedNupkg.FullName --source github-packages --api-key $ghToken --no-symbols true 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

        Write-Host "" -ForegroundColor Green
        Write-Host "Module published successfully to GitHub Packages" -ForegroundColor Green
        Write-Host "Package: N2C.GuacAdmin v$version" -ForegroundColor Green
        Write-Host "URL: https://github.com/orgs/$ghOwner/packages or https://github.com/$ghOwner/packages" -ForegroundColor DarkGreen
    }
    finally
    {
        if (Test-Path -Path $tempDir)
        {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Helper: bump module version
function Invoke-VersionBump {
    if (-not $BumpType)
    {
        throw "version_bump task requires -BumpType parameter (major, minor, or patch)"
    }

    Write-Host "" -ForegroundColor Cyan
    Write-Host "Bumping module version ($BumpType)" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Cyan

    $manifestPath = Join-Path -Path $repoRoot -ChildPath (Join-Path -Path $buildConfig.ModuleSource -ChildPath 'N2C.GuacAdmin.psd1')

    if (-not (Test-Path -Path $manifestPath -PathType Leaf))
    {
        throw "Manifest not found: $manifestPath"
    }

    # Parse current version
    $manifest = Import-PowerShellDataFile -Path $manifestPath
    $currentVersion = [System.Version]$manifest.ModuleVersion
    Write-Host "Current version: $currentVersion" -ForegroundColor White

    # Calculate new version
    switch ($BumpType)
    {
        'major' { $newVersion = "($($currentVersion.Major + 1)).0.0" }
        'minor' { $newVersion = "$($currentVersion.Major).$($currentVersion.Minor + 1).0" }
        'patch' { $newVersion = "$($currentVersion.Major).$($currentVersion.Minor).$($currentVersion.Build + 1)" }
    }

    Write-Host "New version: $newVersion" -ForegroundColor White

    # Update manifest file
    $content = Get-Content -Path $manifestPath -Raw
    $pattern = "ModuleVersion\s*=\s*'[^']+'"
    $replacement = "ModuleVersion     = '$newVersion'"
    $newContent = [regex]::Replace($content, $pattern, $replacement, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    if ($newContent -eq $content)
    {
        throw "Failed to find ModuleVersion in manifest"
    }

    Set-Content -Path $manifestPath -Value $newContent -NoNewline

    # Verify the update
    $verifyManifest = Import-PowerShellDataFile -Path $manifestPath
    if ([System.Version]$verifyManifest.ModuleVersion -ne [System.Version]$newVersion)
    {
        throw "Version update verification failed"
    }

    Write-Host "Version bumped to $newVersion in $manifestPath" -ForegroundColor Green
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
        'publish_validate' {
            Invoke-PublishValidate
        }
        'publish_dry_run' {
            Invoke-UnitTests
            Invoke-IntegrationTests
            Invoke-Lint
            Invoke-PublishValidate
        }
        'pack' {
            Invoke-PackModule
        }
        'publish' {
            Invoke-UnitTests
            Invoke-IntegrationTests
            Invoke-Lint
            Invoke-PublishValidate
            Invoke-PackModule
            Invoke-PublishModule
        }
        'publish_ghp' {
            Invoke-PublishGitHubPackages
        }
        'version_bump' {
            Invoke-VersionBump
        }
        default {
            throw "Unknown task: $taskName"
        }
    }
}

Write-Host "" -ForegroundColor Green
Write-Host "Build completed successfully." -ForegroundColor Green
