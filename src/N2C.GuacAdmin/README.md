# N2C.GuacAdmin

PowerShell module for administering a deployed **Apache Guacamole 1.6.x** instance: its configuration (users, connections, connection groups, sharing profiles, permissions, history, schemas, extensions) and its runtime state (active sessions, tunnels).

Targets the Guacamole **REST API** and (in later phases) the **Guacamole protocol** over WebSocket tunnels.

- **Compatible:** Windows PowerShell 5.1 and PowerShell 7.x (Windows / Linux / macOS)
- **Phase 1:** authentication & session lifecycle ✅
- **Phase 2:** entity CRUD (connections, users, groups, sharing profiles, permissions) ✅
- **Phase 3:** active sessions, tunnels, languages, patches, extensions ✅
- **Phase 4 (next):** protocol client (interactive WebSocket sessions)
- Roadmap: [TODO.md](TODO.md) · Design & architecture: [AGENTS.md](../../AGENTS.md)

## Layout

| Path | What |
|---|---|
| `N2C.GuacAdmin.psd1` | Module manifest |
| `N2C.GuacAdmin.psm1` | Loader (no script-scope globals) |
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

See [AGENTS.md](../../AGENTS.md) §3–§6 for the full technical facts and engineering
standards, and [TODO.md](TODO.md) for the phase-by-phase roadmap.
