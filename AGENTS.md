# AGENTS.md — Project Guide for AI Agents

> This file describes the project for AI coding agents (Claude, Copilot, Zoo, etc.) working in this repository. Read it fully before making changes. Deep research backing for the design decisions below lives in [`ANALYSIS.md`](ANALYSIS.md).

## 1. What this project is

**Goal:** build a high-quality, production-grade **PowerShell module for administering a deployed Apache Guacamole instance** — managing its configuration (users, connections, connection groups, sharing profiles, permissions, history, schemas, extensions) and its runtime state (active sessions).

The module targets **Apache Guacamole 1.6.x** (REST API + Guacamole protocol), runs on **Windows PowerShell 5.1+ and PowerShell 7.x**, and is cross-platform.

### Non-goals (for now)
- Reimplementing the Guacamole web UI or a full remote-desktop rendering client.
- Supporting Guacamole < 1.4 (design against the 1.6 REST surface).

## 2. Repository layout (current state)

The workspace contains **research material** (cloned/downloaded during design) plus the module itself under [`src/N2C.GuacAdmin/`](src/N2C.GuacAdmin/) (Phase 1 complete: scaffold, private transport, and the auth/session lifecycle cmdlets).

| Path | What it is |
|---|---|
| [`ANALYSIS.md`](ANALYSIS.md) | Research findings: how Guacamole sessions actually work, full problem catalog of the legacy module, architecture recommendations |
| [`ANALYSIS/guacamole-client-1.6.0/`](ANALYSIS/guacamole-client-1.6.0/) | **Official** Apache Guacamole 1.6.0 source (authoritative reference for REST endpoints and the protocol). Key files: `guacamole/src/main/java/org/apache/guacamole/rest/**` (REST), `guacamole/src/main/java/org/apache/guacamole/tunnel/**` (tunnel params), `guacamole-common/src/main/java/org/apache/guacamole/protocol/ConfiguredGuacamoleSocket.java` (handshake), `guacamole-ext/src/main/resources/org/apache/guacamole/protocols/*.json` (protocol schemas) |
| [`ANALYSIS/guacamole-rest-api-documentation/`](ANALYSIS/guacamole-rest-api-documentation/README.md) | Unofficial REST API docs (ridvanaltun, based on 1.1.0) — useful as a starting sketch, **must be verified against 1.6.0 source** before relying on it |
| [`ANALYSIS/guacamole-powershell/`](ANALYSIS/guacamole-powershell/README.md) | Legacy UpperM/PSGuacamole module (v1.0.4) — **anti-reference**: study its problems (see §4), reuse only its correct patterns |
| [`api-documentation.html`](ANALYSIS/api-documentation.html) | Saved copy of guacamole.apache.org/api-documentation — this is the **Java API** docs, not REST |

### Restoring the ANALYSIS/ research material

The whole `ANALYSIS/` directory is research material, **not** part of the
module: it is listed in the repository `.gitignore` and is never committed or
published. It can be deleted at any time without affecting the build or the
tests. If it is gone, restore each piece from its upstream source:

| Path | Source | How to restore |
|---|---|---|
| `ANALYSIS/guacamole-client-1.6.0/` | [Apache Guacamole 1.6.0 source release](https://guacamole.apache.org/download/1.6.0/) (the authoritative reference) | The original distribution archive is kept alongside the extracted source as `ANALYSIS/guacamole-client-1.6.0.tar.gz`; extract it into `ANALYSIS/` (`tar -xzf ANALYSIS/guacamole-client-1.6.0.tar.gz -C ANALYSIS/`). If the archive itself is missing, download it again from the Apache archive: `https://archive.apache.org/dist/guacamole/1.6.0/source/guacamole-client-1.6.0.tar.gz` |
| `ANALYSIS/guacamole-rest-api-documentation/` | [ridvanaltun/guacamole-rest-api-documentation](https://github.com/ridvanaltun/guacamole-rest-api-documentation) (unofficial, based on 1.1.0) | `git clone https://github.com/ridvanaltun/guacamole-rest-api-documentation ANALYSIS/guacamole-rest-api-documentation` |
| `ANALYSIS/guacamole-powershell/` | [UpperM/guacamole-powershell](https://github.com/UpperM/guacamole-powershell) (legacy PSGuacamole v1.0.4, anti-reference) | `git clone https://github.com/UpperM/guacamole-powershell ANALYSIS/guacamole-powershell` (checkout tag `v1.0.4`) |
| `ANALYSIS/api-documentation.html` | https://guacamole.apache.org/api-documentation/ | Save the page again from the browser (it is the Java API docs, not REST) |

When restoring, re-verify that the extracted tree contains the key files cited
above (the `rest/**` package, `ConfiguredGuacamoleSocket.java`, and the
`guacamole-ext/.../protocols/*.json` schemas) — the module's verification rule
(§6) depends on them.

### Module layout (Phase 1, current)

[`src/N2C.GuacAdmin/`](src/N2C.GuacAdmin/) follows the standard PowerShell module layout: `N2C.GuacAdmin.psd1` (manifest; `ScriptsToProcess = @('Types.ps1')` defines the two classes in caller-visible scope), `N2C.GuacAdmin.psm1` (loader), `Types.ps1`, `Public/`, `Private/`, and `Tests/` (Pester v5 + a self-contained mock Guacamole server, `Tests/GuacMockServer.ps1`, so integration tests run with no live instance). Run the suite with `src/N2C.GuacAdmin/run-tests.ps1` (`-IncludeIntegration` adds the mock-server session-lifecycle tests).

## 3. Critical technical facts (do not rediscover, do not contradict)

These facts were verified against the 1.6.0 source; they shape the entire module design.

### 3.1. REST API does NOT create interactive sessions
- The REST API (`/api/...`) manages **entities**: auth tokens, users, connection groups, connections, sharing profiles, permissions, history, schemas, active-connection metadata, tunnels (read-only), languages, patches, extensions.
- **Interactive sessions are created only by the Guacamole protocol over a tunnel**:
  - WebSocket: `{server}/websocket-tunnel?token=...&GUAC_DATA_SOURCE=...&GUAC_ID=...&GUAC_TYPE=c|g&GUAC_WIDTH=...&GUAC_HEIGHT=...&GUAC_DPI=...&GUAC_TIMEZONE=...&GUAC_AUDIO=...&GUAC_VIDEO=...&GUAC_IMAGE=...` — opened with **WebSocket subprotocol `"guacamole"`**.
  - HTTP fallback: `{server}/tunnel` (same parameters; `Guacamole.ChainedTunnel` tries WebSocket first, then HTTP).
- Parameter names are defined in `TunnelRequest.java`: `token`, `GUAC_DATA_SOURCE`, `GUAC_TYPE` (`c`=connection, `g`=group), `GUAC_ID`, `GUAC_WIDTH`, `GUAC_HEIGHT`, `GUAC_DPI`, `GUAC_AUDIO`, `GUAC_VIDEO`, `GUAC_IMAGE` (repeatable), `GUAC_TIMEZONE`.
- Protocol handshake (per `ConfiguredGuacamoleSocket.java`), wire format is `length.opcode,length.arg1,...` with `,`/`;` separators:
  `select {connectionID|protocol}` → `args {names...}` → `size {w,h,dpi}` → `audio|video|image {mimetypes...}` → optional `timezone`, `name` (only if advertised) → `connect {values...}` → `ready {sessionId}`.
  Errors arrive as `error {code, message, statusCode}` / `disconnect` instructions.
- "Configuring a session" = tunnel parameters + **protocol argument values** (host, port, credentials, `guac-*` options). The set of required arguments comes from the protocol schema (`guacamole-ext/.../protocols/{ssh,vnc,rdp,telnet,kubernetes}.json`) and can be read at runtime via REST `.../schema/connectionAttributes` + `connection.parameters`.

### 3.2. `dataSource` is an AuthenticationProvider identifier
- `{dataSource}` in `/api/session/data/{dataSource}/...` and `GUAC_DATA_SOURCE` in tunnel URLs is the **AuthenticationProvider identifier** (e.g. `mysql` for `guacamole-auth-mysql`, `ldap`, `postgresql`), **not a database name**.
- The whole UserContext (users, connections, groups, activeConnections, history, schema) is scoped per AuthenticationProvider; one instance can host several.
- The identifier is returned by `POST /api/tokens` in `dataSource` / `availableDataSources`. **Default it from the auth response; expose `-DataSource` as an override.** Never hardcode `mysql`.

### 3.3. Authentication & session lifecycle (REST)
- `POST /api/tokens` with `application/x-www-form-urlencoded` (`username`, `password`, optional `guac-totp`) → `{ authToken, username, dataSource, availableDataSources }`.
- Token is passed as the `token` query parameter on every request.
- `DELETE /api/tokens/{token}` revokes the token; `DELETE /api/session` invalidates the whole session; `HEAD /api/session` checks validity.

### 3.4. Active sessions (REST view)
- `GET .../activeConnections` → collection of `APIActiveConnection` `{ identifier, connectionIdentifier, startDate, remoteHost, username, connectable }`.
- Killing a session = **JSON Patch** (RFC 6902): `PATCH .../activeConnections` with body `[{"op":"remove","path":"/<uuid>"}]`.
- Sub-resources: `.../activeConnections/{id}/connection` (underlying connection) and `GET .../activeConnections/{id}/sharingCredentials/{sharingProfile}` → `APIUserCredentials`.
- `GET /api/session/tunnels` (and `/tunnels/{uuid}`) is **read-only metadata** (activeConnection, protocol, streams) — never a control plane.

### 3.5. Mutation model
- Collection mutation uses **JSON Patch** (`PATCH`) — do not invent PUT/POST bodies for directory objects.
- Extensions REST: `GET /api/ext/{dataSource}` exposes installed extensions and their resources (vault, display-statistics, auth-ban, third-party).

## 4. Legacy module (UpperM/PSGuacamole) — what to avoid

Full catalog with file/line references in [`ANALYSIS.md` §3](ANALYSIS.md). Summary of mandatory anti-patterns to avoid:

1. **Script-scope globals** (`$Script:Token`, `$Script:Server` set by `New-GuacToken`, read implicitly by other cmdlets) → single-server-per-process, breaks on re-import, hidden dependencies.
2. **Silent failure**: `catch { Write-Warning ...; return $False }` in every cmdlet → errors become pipeline data; caller can't catch; API error body (JSON `status`/`reason`) is lost.
3. **Version bugs**: `$IsWindows` is `$null` in PS 5.1 → falls into the `ConvertFrom-SecureString -AsPlaintext` branch, which doesn't exist in 5.1 → password prompt broken on 5.1.
4. **Hardcoded assumptions** (`mysql` everywhere), string-password-only auth (no `PSCredential`/`SecureString`), no TLS/proxy options, no `ShouldProcess`, no tests/CI, French manifest comments.

**Correct patterns worth reusing:** JSON Patch for killing sessions, the `guac-totp` form field, domain-based cmdlet grouping, begin/process/end where streaming semantics are real.

## 5. Module architecture (agreed design)

### 5.1. Session object instead of globals
```powershell
$g = New-GuacSession -Server https://guac.example.com/guacamole -Credential (Get-Credential)
# $g : [GuacSession] { Server, Token, DataSource, Username, AvailableDataSources }
Get-GuacConnection -Session $g -Id <uuid>
Get-GuacConnection | Stop-GuacActiveConnection -Session $g   # -Session via ValueFromPipeline + session-state default
```
- `New-GuacSession` → returns `[GuacSession]` (PSCustomObject or typed class); `DataSource` defaults from the token response.
- All cmdlets accept `-Session` (`ValueFromPipelineByPropertyName` / by value) with a default resolved from session state (the `-CmsSession` pattern). No `$Script:` globals.
- `Remove-GuacSession` (DELETE token), `Test-GuacSession` (HEAD `/api/session`).

### 5.2. Error handling
- Single private transport (`Invoke-GuacRest` / `Invoke-GuacTunnel`) in `Private/`.
- Non-2xx → parse the Guacamole JSON error body (`status`, `reason`) → throw a **terminating** error carrying HTTP status, endpoint, and reason. Never `return $False`, never bare `Write-Warning` for API failures.
- `SupportsShouldProcess` on all mutating cmdlets; `ConfirmImpact = High` for `Remove-*`/`Stop-*`.

### 5.3. Cmdlet surface (target, verb-noun convention with noun `Guac*`)
- **Auth:** `New-GuacSession`, `Remove-GuacSession`, `Test-GuacSession`
- **Entities:** `Get/New/Update/Remove-GuacConnection`, `-GuacConnectionGroup`, `-GuacUser`, `-GuacUserGroup`, `-GuacSharingProfile` (+ permission/membership cmdlets), `Get-GuacHistory`, `Get-GuacSchema*` (all attribute sets + protocols)
- **Active sessions (REST):** `Get-GuacActiveConnection`, `Stop-GuacActiveConnection`, `Get-GuacSharingCredential`
- **Tunnels (read-only):** `Get-GuacTunnel`
- **Extensions:** `Get-GuacExtension` + per-extension resources as they are discovered
- **Protocol (sessions):** `New-GuacActiveSession` (opens WebSocket tunnel + handshake, returns `[GuacActiveSession]` with Id + instruction channel), `Remove-GuacActiveSession` (graceful `disconnect`), low-level `Send-GuacInstruction` / `Receive-GuacInstruction`
- `Update-*` cmdlets accept a JSON Patch operations array (`-Patch [ordered]@{op=...; path=...}`) as the canonical mutation input, mirroring the API.

### 5.4. Protocol client notes
- Use `System.Net.WebSockets.ClientWebSocket` with `SubProtocol = "guacamole"` (works in PS 5.1 and 7.x).
- Frame handling: messages are UTF-8 text, may be split across frames; buffer until a complete `len.opcode,len.arg,...;`-terminated instruction is parsed.
- `ready` carries the session ID; correlate it with the REST `activeConnections` list.
- Bundle the protocol JSON schemas (`guacamole-ext/.../protocols/*.json`) with the module as data for offline argument validation, but prefer runtime `schema/connectionAttributes` for the actual argument set.

## 6. Engineering standards

- **Manifest:** `PowerShellVersion = 5.1`, `#Requires -Version 5.1`, English comments, proper `Tags`, `ReleaseNotes`, `Author`, `ProjectUri`.
- **Compatibility:** must work unchanged on Windows PowerShell 5.1 and PowerShell 7.x on Windows/Linux/macOS. No PS6+-only APIs (`-AsPlaintext`, `$IsWindows`, `[System.Text.Json]`). SecureString→plaintext via `Marshal::SecureStringToBSTR` (all platforms) or `NetworkCredential`-style handling.
- **Secrets:** passwords/TOTP only as `SecureString`/`PSCredential` parameters (`ParameterType` secure); never plaintext strings in the public surface. Mask the token in all `-Verbose`/`-Debug` output.
- **TLS:** plumb `-CertificateThumbprint` / `-Certificate` / `-Proxy` / `-NoProxy` into the transport.
- **Tests:** Pester v5 in `Tests/` (unit with mocked transport; integration tests gated by a live-instance env var). Run with `src/N2C.GuacAdmin/run-tests.ps1` (`-IncludeIntegration` adds the self-contained mock-server lifecycle tests). CI via GitHub Actions: PSScriptAnalyzer (strict ruleset) + Pester + module publish dry-run.
- **Lint:** `src/N2C.GuacAdmin/run-lint.ps1` is the lint gate (PSScriptAnalyzer, full default ruleset at Warning/Error). The only allowed deviations are the documented `ExcludeRules` entries in `src/N2C.GuacAdmin/PSScriptAnalyzerSettings.psd1` — each with a rationale. Note (verified on PSScriptAnalyzer 1.24.0): per-rule `Enable = $false` inside a `Rules` hashtable is NOT honored for default rules; `ExcludeRules` is the supported mechanism.
- **Style:** approved verbs only, `-Force` for destructive overrides, `ValueFromPipeline`/`ValueFromPipelineByPropertyName` where the noun supports identity matching, help with `Examples` on every exported cmdlet, no French/other-language comments.
- **Verification rule:** any REST endpoint or parameter added to the module must be traceable to `ANALYSIS/guacamole-client-1.6.0/` source (cite the Java/JS file in the cmdlet header comment). The 1.1.0-based unofficial docs are a sketch only.

### 6.1. Empirically-verified PowerShell pitfalls (Phase 1, verified on this machine's pwsh 7.x / Pester 5.7.1 — do not rediscover)

These all bit Phase 1 and are non-obvious. The module is built to work around them:

- **Runtime class-name resolution inside a module is unreliable under some hosts.** `New-Object N2C_GuacAdmin_GuacRestException` and `catch [N2C_GuacAdmin_GuacRestException]` fail with `TypeNotFound`/`PSArgumentException` *inside module functions* under Pester 5.7.1 even though `Import-Module` succeeded and the same statement works in a plain `pwsh` script. **Rule:** never reference the module's own classes by name at runtime inside module code. The loader captures them once at load time (`$script:GuacSessionType`, `$script:GuacRestExceptionType` in `N2C.GuacAdmin.psm1`) and all construction (`$script:GuacRestExceptionType::new(...)`) and type tests (`$_ -is $script:GuacSessionType`) go through those variables. `[TypeName]` type *literals* in `param()`/`[OutputType()]` are fine (they resolve at parse time, not runtime).
- **`$PSCmdlet.WriteVerboseMessage` is not a valid method on the `PSScriptCmdlet`** exposed to a dot-sourced advanced function — it throws `RuntimeException`. Use the `Write-Verbose`/`Write-Warning`/`Write-Error` *cmdlets* instead (works on 5.1 and 7.x).
- **`$PSCmdlet.ShouldProcess` IS available** and works; `SupportsShouldProcess` in `[CmdletBinding()]` is the correct mechanism for `-WhatIf`/`-Confirm`.
- **`-f` with a single string arg is fine, but the comma list is not a single argument.** `"a {0} {1}" -f $x, $y` parses as `("a {0} {1}" -f $x), $y` — only `$x` binds and the result is an array, not a formatted string. Always parenthesize: `"a {0} {1}" -f ($x, $y)`. (PSScriptAnalyzer flags this as `PSUseCommaOperatorForArrayConstructor`-adjacent; we hit it by hand.)
- **Pester v5 variable scoping:** variables set in `BeforeAll` are NOT automatically visible in `It` blocks unless written to the container scope. Use `$script:`-prefixed variables in the test file (or set them in `BeforeAll` and reference via the same `$script:` prefix). File-scope `$var = ...` outside any block is the most portable.
- **`PSModuleInfo` has no `.GetCommand()` method** on this Pester/PowerShell combination. To reach a private function from a test, use Pester's `InModuleScope -ModuleName 'N2C.GuacAdmin' { Get-Command -Name 'Invoke-GuacRest' }` and invoke the returned command object.
- **`Import-Module ... -Force` of a module that defines classes re-runs `ScriptsToProcess`** and redefines the class types. Under Pester this destabilizes type resolution. Import the module once; if a test helper already imports it, the test's `BeforeAll` re-import is safe only because the module's class references are load-time variables.
- **`Get-GuacErrorCategory` uses `ConnectionError`, not `ConnectionFailure`** — `ErrorCategory.ConnectionFailure` does not exist; `ConnectionError` is the correct member for transport-level failures.

## 7. Suggested work phases

1. **Scaffold:** module layout, manifest, loader, private transport (`Invoke-GuacRest` with error parsing, TLS/proxy options), `New/Remove/Test-GuacSession`.
2. **Entity CRUD:** connections, connection groups, users, user groups, sharing profiles, permissions (JSON Patch core), history, schemas.
3. **Active sessions (REST):** list/kill/sharing-credentials; tunnels read-only; languages/patches; extensions discovery.
4. **Protocol client:** WebSocket tunnel + handshake + instruction pump; `New-GuacActiveSession`; low-level send/receive cmdlets.
5. **Hardening & release:** PSScriptAnalyzer strict, Pester suite, CI, docs/examples, signing/publishing.

## 8. How agents should work in this repo

- Update this file whenever an architectural decision changes; keep §3 and §5 in sync with implementation.
- When implementing a cmdlet: (1) confirm the endpoint in `ANALYSIS/guacamole-client-1.6.0/` source, (2) implement via the shared transport, (3) add Pester unit tests, (4) add `Examples` help.
- Do not treat `ANALYSIS/guacamole-powershell/` as a codebase to edit — it is a read-only reference.
- Do not treat `ANALYSIS/guacamole-rest-api-documentation/` as authoritative — cross-check against 1.6.0 source.
- Keep the module directory name/structure consistent with §2 once phase 1 starts; if renamed, update this file.
