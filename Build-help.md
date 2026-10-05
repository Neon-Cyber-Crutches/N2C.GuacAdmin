# Build & Publish Guide for N2C.GuacAdmin

This file documents how to use `build.ps1` to test, validate, version, pack, and publish the module.

## Quick Reference

```powershell
# Run default workflow (test + lint)
pwsh ./build.ps1

# Run specific tasks
pwsh ./build.ps1 test              # unit + integration tests
pwsh ./build.ps1 test_unit         # unit tests only
pwsh ./build.ps1 test_integration  # integration tests only
pwsh ./build.ps1 lint              # PSScriptAnalyzer only
pwsh ./build.ps1 pack              # create release artifact (zip)
pwsh ./build.ps1 publish_validate  # validate module for PSGallery
pwsh ./build.ps1 publish_dry_run   # test + lint + publish_validate
pwsh ./build.ps1 publish           # full publish pipeline (test + lint + validate + pack + publish)
pwsh ./build.ps1 version_bump -BumpType patch  # bump version
pwsh ./build.ps1 noop              # bootstrap dependencies only
```

## Build System Architecture

- **`build.ps1`** — Bootstrap and execution script. Downloads dependencies to `output/RequiredModules/`, prepends to `PSModulePath`, loads `build.yml` config, and runs named tasks.
- **`build.yml`** — Configuration file: build dependencies (versions), test file lists, lint settings, publish settings, pack settings, and workflow definitions.
- **`output/RequiredModules/`** — Bootstrapped build dependencies. Gitignored. Ensures reproducible builds regardless of locally installed module versions.
- **`output/N2C.GuacAdmin-<version>.zip`** — Release artifact (created by `pack` task). Gitignored.

## Full Release Process

### Step 1: Verify Tests Pass

```powershell
pwsh ./build.ps1 test
```

Run this after any code changes before proceeding with release.

### Step 2: Version Bump

```powershell
# patch: 1.0.0 → 1.0.1 (bug fixes, no new features)
pwsh ./build.ps1 version_bump -BumpType patch

# minor: 1.0.0 → 1.1.0 (new backward-compatible features)
pwsh ./build.ps1 version_bump -BumpType minor

# major: 1.0.0 → 2.0.0 (breaking changes)
pwsh ./build.ps1 version_bump -BumpType major
```

This updates `ModuleVersion` in `src/N2C.GuacAdmin/N2C.GuacAdmin.psd1`.

### Step 3: Validate Module

```powershell
pwsh ./build.ps1 publish_validate
```

Validates manifest structure, exports, PSData fields (Tags, ProjectUri, ReleaseNotes), and version format.

### Step 4: Create Release Artifact (Optional, for local use)

```powershell
pwsh ./build.ps1 pack
```

Creates `output/N2C.GuacAdmin-<version>.zip` — a zip file of the module ready for distribution. This is useful for manual testing or offline installation.

### Step 5: Commit Version Bump

```bash
git add src/N2C.GuacAdmin/N2C.GuacAdmin.psd1
git commit -m "Bump version to 1.1.0"
```

### Step 6: Publish to PSGallery

**Prerequisites for local publishing:**
- Create `.psgallerykey` file in repo root containing your PSGallery API key (gitignored)
- Or pass the key directly with `-ApiKey` parameter
- Or set `PSGALLERY_API_KEY` environment variable

```powershell
# Using .psgallerykey file (recommended for local)
pwsh ./build.ps1 publish

# Using explicit API key
pwsh ./build.ps1 publish -ApiKey "your-api-key-here"
```

The publish task runs: test → lint → publish_validate → pack → Publish-PSResource (or Publish-Module fallback).

**Publish mechanism:** The script uses `Publish-PSResource` from the PSResourceGet module when available (modern cross-platform approach that doesn't use `dotnet pack`). Falls back to `Publish-Module` from PowerShellGet if PSResourceGet is not installed.

### Step 7: Create Git Tag

```bash
git tag v1.1.0
git push origin main --tags
```

## Release Artifacts

The `pack` task creates a versioned zip artifact at `output/N2C.GuacAdmin-<version>.zip`. This artifact:
- Contains the complete module (psd1, psm1, Types.ps1, Public/, Private/, Tests/)
- Is created during the `publish` pipeline automatically
- Is uploaded as a GitHub Release asset when published via CI

**Local usage of the artifact:**
```powershell
# Download the zip from a GitHub Release
# Extract to $env:USERPROFILE\Documents\PowerShell\Modules
# Or import directly:
Import-Module .\N2C.GuacAdmin\N2C.GuacAdmin.psd1
```

## CI/CD Publishing (GitHub Actions)

The `.github/workflows/publish.yml` workflow triggers on GitHub Release publication.

**Setup:**
1. Add `PSGALLERY_API_KEY` as a GitHub repository secret (Settings → Secrets → Actions)
2. Make code changes and bump version
3. Create a GitHub Release

The workflow automatically:
1. Checks out the repository
2. Ensures PSResourceGet is installed
3. Runs `pwsh ./build.ps1 publish` (tests, lints, validates, packs, publishes)
4. Uploads the release artifact (`output/N2C.GuacAdmin-*.zip`) to the GitHub Release

**Result:** Users can download the module zip directly from the GitHub Release page.

## API Key Resolution Priority

The publish task resolves the PSGallery API key in this order:
1. `-ApiKey` parameter (CLI override)
2. `.psgallerykey` file in repo root (local development, gitignored)
3. `PSGALLERY_API_KEY` environment variable (CI environments)

## Troubleshooting

### "Failed to generate the compressed file" / dotnet pack error
This occurs with PowerShellGet 2.x which internally uses `dotnet pack` targeting the obsolete `netcoreapp2.0` framework. The build script now uses `Publish-PSResource` (PSResourceGet) which avoids this issue. Ensure PSResourceGet is installed:

```powershell
pwsh -Command "Get-Module Microsoft.PowerShell.PSResourceGet -ListAvailable"
```

### Module validation fails
Check that the manifest (`N2C.GuacAdmin.psd1`) has:
- Valid `ModuleVersion` (semver format)
- `PrivateData.PSData.Tags` (non-empty array)
- `PrivateData.PSData.ProjectUri`
- `PrivateData.PSData.ReleaseNotes`

### Tests fail in CI
CI uses the self-contained mock Guacamole server (`Tests/GuacMockServer.ps1`) — no live instance required.

### Release artifact not uploaded
Check that the GitHub Actions workflow has `contents: write` permission and the `softprops/action-gh-release@v2` step is configured correctly. The artifact pattern is `output/N2C.GuacAdmin-*.zip`.

## Standalone Runners (for quick iteration)

```powershell
# Quick test run
pwsh src/N2C.GuacAdmin/run-tests.ps1
pwsh src/N2C.GuacAdmin/run-tests.ps1 -IncludeIntegration

# Quick lint run
pwsh src/N2C.GuacAdmin/run-lint.ps1
```

These are convenient for fast feedback during development but use whatever module versions are installed locally (not the pinned versions from `build.yml`).
