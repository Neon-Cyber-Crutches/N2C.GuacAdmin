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

## Phase 2 — Entity CRUD ✅ (COMPLETE)

All 127 tests green (35 unit + 92 integration vs. `Tests/GuacMockServer.ps1`). Every endpoint traced to `ANALYSIS/guacamole-client-1.6.0/` source (cite in each cmdlet's header comment). All cmdlets: `-Session` (pipeline by property name where identity-based) with module-state default; `SupportsShouldProcess` on mutators; `ConfirmImpact = High` on `Remove-*`; `Update-*` take `-Patch` (RFC 6902 ops array) or `-Replace`.

Shared building blocks:
- [x] **`Private/Resolve-GuacSessionContext`** (+ `Resolve-GuacContextUrl`) — per-`DataSource` UserContext base from a `[N2C_GuacAdmin_GuacSession]`; `-DataSource` defaults to `$session.DataSource`, validated against `availableDataSources`; falls back to the single registered default session when neither `-Session` nor `-Server` is bound. Cite: `rest/session/SessionResource.java` (`getUserContextResource`).
- [x] **`Private/Invoke-GuacPatch`** — JSON Patch (RFC 6902) over `Invoke-GuacRest`; **`Private/Invoke-GuacDirectory`** — Get/List/Create/Update/Delete/Replace against a directory collection with `Identifier` wrapping; **`Private/Invoke-GuacRelatedSetPatch`** — add/remove string-set members (`memberUsers`, `memberUserGroups`, `permissions`).
- [x] **`Private/Get-GuacEntityResponse`** — wraps decoded bodies in `Identifier`-carrying `PSCustomObject`s; **`Private/Get-GuacIdentifier`** extracts the identity (`Identifier` → `identifier` → `username`) for pipeline plumbing; **`Private/ConvertTo-GuacMapValue`** normalizes nested JSON maps to string-indexable hashtables (5.1/7.x parity).
- [x] **`Private/Get-GuacUserPermissions`** — attaches `permissions` / `effectivePermissions` sets onto a copy of a user object.

### 2a. Connections
- [x] `Get-GuacConnection` (list + by id), `New-GuacConnection` (`PUT .../connections`), `Update-GuacConnection` (`-Patch`/`-Replace`, re-fetch), `Remove-GuacConnection`. Cite: `ConnectionResource.java`.

### 2b. Connection groups
- [x] `Get-GuacConnectionGroup` (list + by id, `-Tree` via `.../{id}/tree`), `New-GuacConnectionGroup`, `Update-GuacConnectionGroup` (incl. reparent), `Remove-GuacConnectionGroup`. Cite: `ConnectionGroupResource.java`.

### 2c. Users & user groups
- [x] `Get-GuacUser` (list + by id; `-Permissions` / `-EffectivePermissions`), `New-GuacUser` (`-Credential`/`-Username`+`-Password`), `Update-GuacUser` (password preserved unless in body; self-password change via update rejected by the server → 403), `Remove-GuacUser`, `Set-GuacUserPassword` (`PUT .../users/{id}/password`, old+new). Cite: `UserResource.java`, `UserPasswordResource.java`.
- [x] `Get-GuacUserGroup`, `New-GuacUserGroup`, `Update-GuacUserGroup`, `Remove-GuacUserGroup`. Cite: `UserGroupResource.java`.
- [x] `Add-GuacUserGroupMember` / `Remove-GuacUserGroupMember` — `PATCH .../userGroups/{id}/memberUsers` add/remove.
- [x] `Add-GuacUserGroupChildGroup` / `Remove-GuacUserGroupChildGroup` — `PATCH .../userGroups/{id}/memberUserGroups` add/remove.

### 2d. Sharing profiles
- [x] `Get-GuacSharingProfile` (list + by id), `New-GuacSharingProfile`, `Update-GuacSharingProfile` (`-Patch`/`-Replace`), `Remove-GuacSharingProfile`. Cite: `SharingProfileResource.java`.

### 2e. Permissions (JSON Patch core)
- [x] `Add-GuacPermission` / `Remove-GuacPermission` — `PATCH .../{users|userGroups}/{id}/permissions` with `[{"op":"add|remove","path":"/{category}/{identifier}","value":"{TYPE}"}]`; subject via `-User`/`-UserGroup` or a piped entity object; targets `-Connection`, `-ConnectionGroup`, `-SharingProfile`, `-ActiveConnection`, `-System`. Cite: `PermissionSetResource.java`, `APIPermissionSet.java`.

### 2f. History & schemas (read-only)
- [x] `Get-GuacHistory` — `.../history/connections` / `.../history/users` (filterable, `-First` limit). Cite: `HistoryResource.java`.
- [x] `Get-GuacSchema` — `.../schema/connectionAttributes`, `connectionParameters`, `connectionGroupAttributes`, `userAttributes`, `userGroupAttributes`, `sharingProfileAttributes/Parameters`. Cite: `SchemaResource.java`.
- [x] `Get-GuacProtocol` — `GET /api/session/protocols` (server-side protocol list + forms). Cite: `ProtocolResource.java`.

### Phase 2 cross-cutting
- [x] `Tests/GuacMockServer.ps1` extended with the full UserContext surface (directories, permissions, related sets, password, history, schema, protocols) — integration-tested with no live instance.
- [x] Pester file per entity area: `Connections.Tests.ps1`, `ConnectionGroups.Tests.ps1`, `Users.Tests.ps1`, `UserGroups.Tests.ps1`, `SharingProfiles.Tests.ps1`, `Permissions.Tests.ps1`, `HistorySchema.Tests.ps1`.
- [x] Manifest `FunctionsToExport` updated; export-set test asserts phase-1 + phase-2 as a set.
- [x] Help with `Examples` on every exported cmdlet.
- [x] `../../AGENTS.md` §5.3 / §6.1 updated with the final cmdlet surface and the phase-2 pitfalls.

### Phase 2 pitfalls (new; locked in AGENTS.md §6.1 — do not rediscover)
- [x] Passing a `[switch]` by value to another `[switch]` parameter (`-Direct $flag`) throws `PositionalParameterNotFound`; the colon syntax (`-Direct:$flag`) is required.
- [x] `$obj.PSObject.Properties` is a `PSMemberInfoIntegratingCollection` — integer indexing performs a name-match query and returns an empty `PSPropertyInfo`; always iterate and match by name.
- [x] PS 7.x `Invoke-WebRequest` decodes JSON objects to `PSCustomObject` (5.1: `OrderedDictionary`); `PSCustomObject` has no string indexer, so `Get-GuacEntityResponse` normalizes nested maps to hashtables before exposing them.
- [x] `ConfirmImpact = 'High'` cmdlets auto-prompt under the default `$ConfirmPreference` and NRE on `ShouldProcess` in non-interactive hosts (Pester) — tests must pass `-Confirm:$false`.
- [x] Functions defined at Pester test file scope are not visible in `It` execution scope; define test helpers inside `BeforeAll`.

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
