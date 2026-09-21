# N2C.GuacAdmin — Progress & Plan

> Tracking file for the PowerShell module under `src/N2C.GuacAdmin/`.
> Architecture and "do not rediscover" facts live in [`../../AGENTS.md`](../../AGENTS.md) — read that first.
> Run the full suite: `./run-tests.ps1` (add `-IncludeIntegration` for the mock-server session tests).
> Lint gate: `./run-lint.ps1` (settings: `PSScriptAnalyzerSettings.psd1`).

Status legend: `[x]` done · `[ ]` to do · `[-]` in progress

---

## Phase 1 — Scaffold, transport, auth/session lifecycle ✅ (COMPLETE)

All 58 tests green (35 unit + 23 integration vs. `Tests/GuacMockServer.ps1`).

### Public cmdlets
- [x] `New-GuacSession` — `POST /api/tokens` (form-urlencoded, optional `guac-totp`), returns `[N2C_GuacAdmin_GuacSession]`; defaults `-DataSource` from the token response and validates an override; TLS/proxy plumbing; `-TimeoutSec`.
- [x] `Get-GuacSession` — resolves the default session for a server (module session-state, case-insensitive, trailing-slash tolerant) or `$null`.
- [x] `Remove-GuacSession` — `DELETE /api/tokens/{token}`; tolerant of an already-gone token (401/404); clears local state; `SupportsShouldProcess` (ConfirmImpact High).
- [x] `Test-GuacSession` — `HEAD /api/session`; `$true`/`$false` (401/404 → `$false`), terminating otherwise.

### Private transport & helpers
- [x] `Invoke-GuacRest` — single transport; every failure → terminating `[N2C_GuacAdmin_GuacRestException]` (HTTP status, APIError `Type`, masked `Endpoint`, `Reason`, `RawBody`); token masked in URLs/messages; 5.1↔7.x `Invoke-WebRequest` capability shims.
- [x] `ConvertTo-GuacServerUrl`, `ConvertTo-GuacRestUrl`, `ConvertTo-GuacFormUrlEncoded`, `ConvertTo-GuacJson` (incl. 5.1 array-unwrapping guard), `ConvertFrom-GuacErrorBody`, `ConvertTo-GuacMaskedSecret`, `ConvertFrom-GuacSecureString`, `Get-GuacResponseDetails` (+`Get-GuacErrorCategory`, `Get-GuacResponseStatus/Body/HeaderValue`), `Get-GuacSessionState`/`Clear-GuacSessionState`.

### Types & manifest
- [x] `Types.ps1` — `[N2C_GuacAdmin_GuacSession]`, `[N2C_GuacAdmin_GuacRestException]` (loaded via `ScriptsToProcess`); module captures them once as `$script:GuacSessionType` / `$script:GuacRestExceptionType` (see AGENTS.md §6.1).
- [x] `N2C.GuacAdmin.psd1` — `PowerShellVersion 5.1`, exports exactly the four phase-1 cmdlets, PSData metadata.

### Tests
- [x] `Tests/Helpers.Tests.ps1` — unit coverage of all private helpers.
- [x] `Tests/SessionLifecycle.Tests.ps1` — auth, TOTP, revocation, `-WhatIf`, session resolution, and the full `GuacRestException` error contract (via `InModuleScope` against the private transport).
- [x] `Tests/GuacMockServer.ps1` + `Tests/GuacTestHelpers.psm1` — self-contained mock of the 1.6.0 REST surface (no live instance needed).
- [x] `run-tests.ps1` — Pester v5 runner; `-IncludeIntegration` gates the mock-server file.

### Known-good pitfalls (locked in AGENTS.md §6.1 — do not rediscover)
- [x] Runtime class-name resolution inside module scope is unreliable → construct/test via `$script:*Type` variables.
- [x] `$PSCmdlet.WriteVerboseMessage` is not available → use `Write-Verbose`/`Write-Warning`/`Write-Error` cmdlets.
- [x] `-f` with a comma list needs parentheses → `"..." -f ($a, $b)`.
- [x] Pester v5 `BeforeAll` vars need `$script:` prefix to be visible in `It` blocks.
- [x] Reach private functions from tests via `InModuleScope` (no `PSModuleInfo.GetCommand`).
- [x] Transport-failure category is `ConnectionError`, not `ConnectionFailure`.

---

## Phase 1.5 — Tidy-up before entity work ✅ (COMPLETE)

- [x] Lint gate: `run-lint.ps1` + `PSScriptAnalyzerSettings.psd1` (full default ruleset; the only deviations are documented per-rule exclusions with rationale — note: `Rules.<Rule>.Enable=$false` is NOT honored for default rules in PSScriptAnalyzer 1.24.0, `ExcludeRules` is the supported mechanism).
- [x] Fixed real findings: removed unused `-Force` from `Remove-GuacSession` (it was advertised in help but had no effect); removed three unused `$session` vars in `SessionLifecycle.Tests.ps1`.
- [x] Confirmed `.EXAMPLE` help on all four public cmdlets and PSData metadata in the manifest.
- [x] `README.md` added (usage, multi-instance, TOTP/TLS/proxy, error contract, test/lint instructions).
- [x] Final verification (58/58 tests, lint clean) and initial git commit (`3a57cad`).

---

## Phase 2 — Entity CRUD (next)

Manage Guacamole entities via the per-`DataSource` UserContext REST surface. Every endpoint must be traced to `ANALYSIS/guacamole-client-1.6.0/` source (AGENTS.md §6 verification rule). All new cmdlets: accept `-Session` (`ValueFromPipelineByPropertyName` where identity-based) with module-state default; `SupportsShouldProcess` on mutators; `ConfirmImpact = High` on `Remove-*`; `Update-*` take a JSON Patch operations array (`-Patch`) as the canonical mutation input.

Shared building blocks (build once, reuse):
- [ ] **`Private/Resolve-GuacContextUrl`** — builds the per-datasource UserContext base: `{server}/api/session/data/{dataSource}/...` from a `[N2C_GuacAdmin_GuacSession]` (defaults `-DataSource` to `$session.DataSource`; never hardcode `mysql`). Cite: `guacamole/src/main/java/org/apache/guacamole/rest/SessionResource.java` (`getUserContextResource`).
- [ ] **`Private/Invoke-GuacPatch`** — JSON Patch (RFC 6902) wrapper over `Invoke-GuacRest` for collection mutations (`PATCH` with an operations array); returns the resulting collection.
- [ ] **`Private/ConvertTo-GuacJsonPatch`** — normalizes `-Patch` (ordered hashtable / array of hashtables) into the RFC 6902 wire form; guards single-element array unwrapping (5.1).
- [ ] **Pipeline plumbing** — add `Identifier`-carrying `OutputType` on entity `Get-*` so `Get-* | Stop-/Remove-/Update-*` works via `ValueFromPipelineByPropertyName`; confirm identity field names against the 1.6.0 DTOs.

### 2a. Connections
- [ ] `Get-GuacConnection` — `GET .../userContext/connections/{identifier}` (+ list overload `.../connections`). Cite: `ConnectionResource.java`.
- [ ] `New-GuacConnection` — create via `PUT .../connections` (JSON body: `name`, `protocol`, `parameters`, `maximumSessions`, `comment`, `parent` group). Verify the exact create verb/body against `ConnectionResource.java` before implementing (AGENTS.md §4 anti-pattern: do not invent bodies).
- [ ] `Update-GuacConnection` — `PUT .../connections/{id}` (full) and/or JSON Patch; `-Patch` canonical.
- [ ] `Remove-GuacConnection` — `DELETE .../connections/{id}`.
- [ ] `Get-GuacConnectionParameter` / attribute accessors if the schema calls for them (optional; prefer exposing `parameters` on the object).

### 2b. Connection groups
- [ ] `Get-GuacConnectionGroup` — `.../connectionGroups/{id}` (+ list, `.../connections/{id}` for children).
- [ ] `New-GuacConnectionGroup`, `Update-GuacConnectionGroup` (incl. reparenting via `parent`), `Remove-GuacConnectionGroup`. Cite: `ConnectionGroupResource.java`.

### 2c. Users & user groups
- [ ] `Get-GuacUser` (`.../users/{id}`, `.../users/{id}/permissions`, `/password` presence flag), `New-GuacUser`, `Update-GuacUser`, `Remove-GuacUser`, `Set-GuacUserPassword` (or `Update-GuacUserPassword`). Cite: `UserResource.java`.
- [ ] `Get-GuacUserGroup`, `New-GuacUserGroup`, `Update-GuacUserGroup` (incl. reparent), `Remove-GuacUserGroup`. Cite: `UserGroupResource.java`.

### 2d. Sharing profiles
- [ ] `Get-GuacSharingProfile`, `New-GuacSharingProfile`, `Update-GuacSharingProfile`, `Remove-GuacSharingProfile`. Cite: `SharingProfileResource.java`.

### 2e. Permissions (JSON Patch core)
- [ ] `Add-GuacUserConnection` / `Remove-GuacUserConnection` — `PATCH .../permissions/users/{user}` add/remove `{type: CONNECTION, identifier}`.
- [ ] `Add-GuacUserConnectionGroup` / `Remove-GuacUserConnectionGroup`.
- [ ] `Add-GuacUserGroupMember` / `Remove-GuacUserGroupMember` — `PATCH .../permissions/userGroups/{group}`.
- [ ] `Add-GuacUserGroupConnection` / `Remove-GuacUserGroupConnection`, `Add-GuacUserGroupConnectionGroup` / `Remove-...`.
- [ ] `Add-GuacUserSystemPermission` / `Remove-GuacUserSystemPermission` (`CREATE_USER`, `CREATE_USER_GROUP`, `CREATE_CONNECTION`, `CREATE_CONNECTION_GROUP`, `CREATE_SHARING_PROFILE`, `DELETE_USER`, … per `APIPermission.Type`). Cite: `PermissionResource.java`, `APIPermission.java`.

### 2f. History & schemas (read-only)
- [ ] `Get-GuacHistory` — `.../history` (per-user, paginated). Cite: `HistoryResource.java`.
- [ ] `Get-GuacSchemaConnection` / `Get-GuacSchemaConnectionGroup` / `Get-GuacSchemaUser` / `Get-GuacSchemaSharingProfile` — attribute/parameter metadata. Cite: `SchemaResource.java` + `*Schema.java`.
- [ ] `Get-GuacProtocol` — available protocols (`.../protocols` or the bundled `guacamole-ext/.../protocols/*.json` for offline validation). Cite: `ProtocolResource.java`.

### Phase 2 cross-cutting
- [ ] Extend `Tests/GuacMockServer.ps1` with UserContext routes (connections, groups, users, permissions, schemas) so phase-2 cmdlets are integration-tested with no live instance.
- [ ] Add a Pester file per entity area (mirroring phase-1 structure): `Connections.Tests.ps1`, `ConnectionGroups.Tests.ps1`, `Users.Tests.ps1`, `Permissions.Tests.ps1`, `Schemas.Tests.ps1`, `SharingProfiles.Tests.ps1`.
- [ ] Update `N2C.GuacAdmin.psd1` `FunctionsToExport` / manifest as cmdlets land; keep the phase-1 export-set test updated (compare as a set, per AGENTS.md §6.1).
- [ ] Help with `Examples` on every exported cmdlet (AGENTS.md §6 style).
- [ ] Update `../../AGENTS.md` §5.3 as cmdlet names/verbs are finalized, and §2 if the layout changes.

---

## Phase 3 — Active sessions, tunnels, extensions (REST)
- [ ] `Get-GuacActiveConnection` — `.../activeConnections` (list + by id), incl. `.../connection` and `.../sharingCredentials/{profile}`. Cite: `ActiveConnectionResource.java`, `APIActiveConnection.java`.
- [ ] `Stop-GuacActiveConnection` — `PATCH .../activeConnections` with `[{"op":"remove","path":"/{uuid}"}]` (ConfirmImpact High).
- [ ] `Get-GuacSharingCredential`.
- [ ] `Get-GuacTunnel` / `Get-GuacTunnels` — read-only `GET /api/session/tunnels`.
- [ ] `Get-GuacLanguage`, `Get-GuacPatches` (extension/patch discovery), `Get-GuacExtension` (`/api/ext/{dataSource}`). Cite: `TunnelResource.java`, `LanguageResource.java`, `ExtensionResource.java`.

## Phase 4 — Protocol (interactive sessions)
- [ ] `New-GuacActiveSession` — open WebSocket tunnel (`SubProtocol "guacamole"`) + `select/args/size/.../connect → ready` handshake; return `[N2C_GuacActiveSession]` (id + instruction channel). Cite: `ConfiguredGuacamoleSocket.java`, `TunnelRequest.java`.
- [ ] `Send-GuacInstruction` / `Receive-GuacInstruction` — low-level instruction pump (frame buffering to `len.opcode,...;` terminators).
- [ ] `Remove-GuacActiveSession` — graceful `disconnect`.
- [ ] Bundle `guacamole-ext/.../protocols/*.json` as module data for offline argument validation.

## Phase 5 — Hardening & release
- [ ] PSScriptAnalyzer with a strict ruleset (CI); fix all findings.
- [ ] GitHub Actions: PSScriptAnalyzer + Pester (unit + integration) + module publish dry-run.
- [ ] Complete comment-based help + `Examples` on every public cmdlet.
- [ ] Signing/publishing; finalize `ReleaseNotes`, `Tags`, `Author`, `ProjectUri`.
- [ ] Optional: real-instance integration test gated by an env var (`GUAC_ADMIN_INTEGRATION=1` + `-Server`/`-Credential`).
