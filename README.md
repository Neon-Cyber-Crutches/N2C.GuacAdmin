<!-- The structure of this README.md inspired and powered by https://github.com/othneildrew/Best-README-Template -->
<a id="readme-top"></a>

# N2C.GuacAdmin

[![Contributors][contributors-shield]][contributors-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![Apache 2.0 License][license-shield]][license-url]

<!-- PROJECT LOGO -->
<div align="center">
  <a href="https://github.com/Neon-Cyber-Crutches/N2C.GuacAdmin">
    <img src="assets/images/N2C.GuacAdmin_1254x1254.png" alt="Logo" width="1280" height="1280">
  </a>
  <p align="center">
    N2C.GuacAdmin is a PowerShell module for administering a deployed **Apache Guacamole 1.6.x** instance: its configuration (users, connections, connection groups, sharing profiles, permissions, history, schemas, extensions) and its runtime state (active sessions, tunnels).
    <br />
    <br />
    <a href="https://github.com/Neon-Cyber-Crutches/N2C.GuacAdmin/issues/new?labels=bug&template=bug-report---.md">Report Bug</a>
    &middot;
    <a href="https://github.com/Neon-Cyber-Crutches/N2C.GuacAdmin/issues/new?labels=enhancement&template=feature-request---.md">Request Feature</a>
  </p>
</div>

<p align="right">(<a href="#readme-top">back to top</a>)</p>

N2C.GuacAdmin targets the Guacamole **REST API** and the **Guacamole protocol** over WebSocket tunnels.

- Compatible: Windows PowerShell 5.1 and PowerShell 7.x (Windows / Linux / macOS) ✅
- Authentication & session lifecycle ✅
- Entity CRUD (connections, users, groups, sharing profiles, permissions) ✅
- Active sessions, tunnels, languages, patches, extensions ✅
- Protocol client (interactive WebSocket sessions) ✅

## Layout

| Path | What |
|---|---|
| `N2C.GuacAdmin.psd1` | Module manifest |
| `N2C.GuacAdmin.psm1` | Loader |
| `Types.ps1` | `[N2C_GuacAdmin_GuacSession]`, `[N2C_GuacAdmin_GuacRestException]` |
| `Public/` | Exported cmdlets |
| `Private/` | Transport (`Invoke-GuacRest`) and helpers |
| `Tests/` | Pester v5 unit tests + self-contained mock Guacamole server |
| `run-tests.ps1` | Test runner |
| `run-lint.ps1` | PSScriptAnalyzer gate (settings: `PSScriptAnalyzerSettings.psd1`) |

## Install (from source)

```powershell
Import-Module .\N2C.GuacAdmin.psd1
```

## Usage

The module is built around a **session object** — authentication state is carried
by `[N2C_GuacAdmin_GuacSession]`, never by script-scope globals. A per-server
"default session" (the `-CmsSession` pattern) lets subsequent cmdlets omit `-Session`.

```powershell
# 1. Authenticate (PSCredential; optional TOTP as SecureString)
$cred    = Get-Credential
$session = New-GuacSession -Server https://guac.example.com/guacamole -Credential $cred

# Inspect what you got (the token is masked in the string representation)
$session   # N2C.GuacAdmin.GuacSession: Server=... User=guacadmin DataSource=mysql Token=abcd...wxyz

# 2. Check the session is still valid
Test-GuacSession -Session $session        # True
Test-GuacSession -Server https://guac.example.com/guacamole   # resolves the default session

# 3. The default session can also be retrieved explicitly
Get-GuacSession -Server https://guac.example.com/guacamole

# 4. Revoke the token when done (SupportsShouldProcess; ConfirmImpact High)
Remove-GuacSession -Session $session
Remove-GuacSession -Server https://guac.example.com/guacamole
```

### Multi-instance / multi-user

Because state is keyed by server URI, you can hold several sessions in one process:

```powershell
$prod  = New-GuacSession -Server https://guac.prod.example.com/guacamole  -Credential $prodCred
$stg   = New-GuacSession -Server https://guac.stg.example.com/guacamole  -Credential $stgCred

Test-GuacSession -Session $prod   # explicit -Session wins over the default
Test-GuacSession -Session $stg
```

### TOTP, TLS, proxy

```powershell
New-GuacSession -Server $server -Credential $cred `
    -TotpCode (Read-Host -Prompt 'TOTP code' -AsSecureString) `
    -CertificateThumbprint 'A1B2C3...' `
    -Proxy 'http://proxy.example.com:8080' -ProxyCredential $proxyCred `
    -TimeoutSec 60
```

### Error handling

Every transport failure raises a **terminating** `[N2C_GuacAdmin_GuacRestException]`
(no cmdlet returns `$false` on an API error). The exception carries the parsed
Guacamole `APIError` body plus request context:

```powershell
try {
    New-GuacSession -Server $server -Credential $badCred
}
catch [N2C_GuacAdmin_GuacRestException] {
    $_.StatusCode   # 401
    $_.Type         # 'INVALID_CREDENTIALS' (APIError.Type)
    $_.Reason       # human-readable reason from the APIError body
    $_.Endpoint     # request URL with the token masked
    $_.RawBody      # raw response body
}
```

## Testing

```powershell
# Unit tests (pure helpers, no network)
pwsh ./run-tests.ps1

# + mock-server integration (spins up a local mock of the 1.6.0 REST API)
pwsh ./run-tests.ps1 -IncludeIntegration

# Lint gate (fails on any finding not documented in PSScriptAnalyzerSettings.psd1)
pwsh ./run-lint.ps1
pwsh ./run-lint.ps1 -ShowInfo   # also report Info-level findings
```

## Building & publishing

The project uses a build system driven by [`build.yml`](build.yml) and executed by [`build.ps1`](build.ps1):

```powershell
pwsh ./build.ps1                    # default: test + lint
pwsh ./build.ps1 test               # unit + integration tests
pwsh ./build.ps1 lint               # PSScriptAnalyzer only
pwsh ./build.ps1 publish_validate   # validate module for PSGallery
pwsh ./build.ps1 publish_dry_run    # test + lint + publish_validate (no actual publish)
pwsh ./build.ps1 publish            # full publish: test + lint + validate + Publish-Module
pwsh ./build.ps1 version_bump -BumpType patch   # bump version (major/minor/patch)
```

### Local publishing

1. Create a file `.psgallerykey` in the repository root containing your PSGallery API key (this file is gitignored).
2. Run the publish workflow:

```powershell
pwsh ./build.ps1 publish
```

Alternatively, pass the API key directly: `pwsh ./build.ps1 publish -ApiKey <key>`.

### CI publishing (GitHub Actions)

The `.github/workflows/publish.yml` workflow triggers on GitHub Releases. To publish via CI:

1. Add your PSGallery API key as a GitHub Secret named `PSGALLERY_API_KEY` (repository settings → Secrets → Actions).
2. Create a release on GitHub; the workflow will automatically run tests, lint, validate, and publish to PSGallery.

## Design notes (short)

- **No script-scope globals.** A single module-scope dictionary maps server → default
  session (`Get-GuacSession` / `Set-GuacSessionState` / `Clear-GuacSessionState`).
- **One transport.** All REST traffic goes through `Invoke-GuacRest`, which parses
  Guacamole `APIError` bodies and converts every failure into a terminating
  `GuacRestException`. Token masking is applied to URLs, messages, and verbose output.
- **5.1/7.x compatibility.** No PS6+-only APIs. `Invoke-WebRequest` capability
  differences (`-UseBasicParsing`, `-Certificate` vs `-PfxCertificate`, `-NoProxy`)
  are detected at load time and plumbed automatically. TLS 1.2 is enforced on 5.1.
- **Secrets.** Passwords/TOTP are `SecureString`/`PSCredential` only. The token is
  masked in all string representations.

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[contributors-shield]: https://img.shields.io/github/contributors/Neon-Cyber-Crutches/N2C.GuacAdmin.svg?style=for-the-badge
[contributors-url]: https://github.com/Neon-Cyber-Crutches/N2C.GuacAdmin/graphs/contributors
[stars-shield]: https://img.shields.io/github/stars/Neon-Cyber-Crutches/N2C.GuacAdmin.svg?style=for-the-badge
[stars-url]: https://github.com/Neon-Cyber-Crutches/N2C.GuacAdmin/stargazers
[issues-shield]: https://img.shields.io/github/issues/Neon-Cyber-Crutches/N2C.GuacAdmin.svg?style=for-the-badge
[issues-url]: https://github.com/Neon-Cyber-Crutches/N2C.GuacAdmin/issues
[license-shield]: https://img.shields.io/github/license/Neon-Cyber-Crutches/N2C.GuacAdmin.svg?style=for-the-badge
[license-url]: https://github.com/Neon-Cyber-Crutches/N2C.GuacAdmin/blob/master/LICENSE