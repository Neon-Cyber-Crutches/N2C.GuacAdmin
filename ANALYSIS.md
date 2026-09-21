# Analysis: Administering Apache Guacamole with PowerShell

> Research results based on: the official **guacamole-client 1.6.0** source (ANALYSIS/guacamole-client-1.6.0/, downloaded from dlcdn.apache.org), the unofficial REST API documentation [`guacamole-rest-api-documentation`](ANALYSIS/guacamole-rest-api-documentation/README.md) (ridvanaltun, based on 1.1.0), and the PowerShell module [`guacamole-powershell`](ANALYSIS/guacamole-powershell/README.md) (UpperM/PSGuacamole, v1.0.4).

---

## 1. Why there is no session management in the official documentation

The page [https://guacamole.apache.org/api-documentation/](https://guacamole.apache.org/api-documentation/) (saved as [`api-documentation.html`](ANALYSIS/api-documentation.html)) is the **Java API** documentation (the `guacamole-common` / `guacamole-ext` / `protocol` libraries), **not** the REST API. It describes classes such as `GuacamoleConfiguration` and `AuthenticationProvider` — the concerns of Java extension developers, not of administrators.

But even looking at the REST API (which has no official specification — none exists in the repository), **there is no endpoint to create interactive sessions**. This is the key point:

| What | Mechanism |
|---|---|
| Authentication, token acquisition | `POST /api/tokens` (REST) |
| CRUD of users, connections, groups, sharing profiles, permissions, history, schemas | `GET/POST/PATCH/DELETE /api/session/data/{dataSource}/...` (REST) |
| Listing active sessions, terminating them | `GET` / JSON `PATCH` on `/api/session/data/{dataSource}/activeConnections` (REST) |
| **Creating an interactive session (connecting to a connection/group)** | **Guacamole protocol over WebSocket** `/websocket-tunnel` (or HTTP fallback `/tunnel`) |

### 1.1. How a session is actually created

The Guacamole frontend (Angular) creates the tunnel like this:

[`ManagedClient.js`](ANALYSIS/guacamole-client-1.6.0/guacamole/src/main/frontend/src/app/client/types/ManagedClient.js:374)
```javascript
tunnel = new Guacamole.ChainedTunnel(
    new Guacamole.WebSocketTunnel('websocket-tunnel'),
    new Guacamole.HTTPTunnel('tunnel')
);
```

The WebSocket tunnel URL is assembled in [`getConnectString()`](ANALYSIS/guacamole-client-1.6.0/guacamole/src/main/frontend/src/app/client/types/ManagedClient.js:289):

```javascript
let connectString =
      "token="             + encodeURIComponent(authenticationService.getCurrentToken())
    + "&GUAC_DATA_SOURCE=" + encodeURIComponent(identifier.dataSource)
    + "&GUAC_ID="          + encodeURIComponent(identifier.id)
    + "&GUAC_TYPE="        + encodeURIComponent(identifier.type)   // "c" = connection, "g" = group
    + "&GUAC_WIDTH="       + Math.floor(optimal_width)
    + "&GUAC_HEIGHT="      + Math.floor(optimal_height)
    + "&GUAC_DPI="         + Math.floor(optimal_dpi)
    + "&GUAC_TIMEZONE="    + encodeURIComponent(preferenceService.preferences.timezone);
// + repeated GUAC_AUDIO / GUAC_VIDEO / GUAC_IMAGE
```

The socket is opened with **WebSocket subprotocol `"guacamole"`** — [`Tunnel.js`](ANALYSIS/guacamole-client-1.6.0/guacamole-common-js/src/main/webapp/modules/Tunnel.js:991):

```javascript
socket = new WebSocket(tunnelURL + "?" + data, "guacamole");
```

The query parameter names are defined in [`TunnelRequest.java`](ANALYSIS/guacamole-client-1.6.0/guacamole/src/main/java/org/apache/guacamole/tunnel/TunnelRequest.java:43):

- `token` — `AUTH_TOKEN_PARAMETER` (the token from `POST /api/tokens`)
- `GUAC_DATA_SOURCE` — `AUTH_PROVIDER_IDENTIFIER_PARAMETER` — the **AuthenticationProvider identifier** (see section 2)
- `GUAC_TYPE` — `"c"` (connection) or `"g"` (connection group)
- `GUAC_ID` — the UUID of the connection or group
- `GUAC_WIDTH` / `GUAC_HEIGHT` / `GUAC_DPI` — display parameters
- `GUAC_AUDIO` / `GUAC_VIDEO` / `GUAC_IMAGE` — mimetypes (repeatable parameters)
- `GUAC_TIMEZONE` — client timezone

The server accepts the request in `RestrictedGuacamoleWebSocketTunnelServlet` → `TunnelRequestService.createTunnel(request)`, which validates the token, locates the object in the UserContext of the given AuthenticationProvider, and **only then** brings the connection up via guacd.

### 1.2. The Guacamole protocol handshake

After the socket is opened, the client must perform an instruction exchange. The authoritative implementation is [`ConfiguredGuacamoleSocket.java`](ANALYSIS/guacamole-client-1.6.0/guacamole-common/src/main/java/org/apache/guacamole/protocol/ConfiguredGuacamoleSocket.java:220):

```
client → select {connectionID | protocol}        // line 220
server → args {argName, ...}                     // line 223: protocol argument names (0th arg = protocol version)
client → size {width, height, dpi}               // line 262
client → audio  {mimeTypes...}                   // line 272
client → video  {mimeTypes...}                   // line 279
client → image  {mimeTypes...}                   // line 286
client → timezone {tz} (optional, per capability) // line 296
client → name     {n}   (optional, per capability) // line 303
client → connect {argValues...}                  // line 307: values collected for the arg names
server → ready {connectionId}                    // line 310: the active session identifier
```

- Instruction format on the wire: `length.opcode,length.arg1,length.arg2,...` (length prefixes, `,` and `;` separators).
- `ready` returns the **active session ID** — the same UUID later visible in the REST `activeConnections`.
- Errors arrive as `error {code, message, statusCode}` and `disconnect` instructions.
- The protocol argument set (what `connect` values are required: host, port, username, password, `guac-*` options) is defined by the **protocol schema** in `ANALYSIS/guacamole-client-1.6.0/guacamole-ext/src/main/resources/org/apache/guacamole/protocols/{ssh,vnc,rdp,telnet,kubernetes}.json` — i.e. "configuring a session" = filling in the argument values per that schema (obtainable via REST `GET /api/session/data/{ds}/schema/connectionAttributes` plus `connection.parameters`).

**Conclusion:** "creating and configuring a session" from PowerShell = opening a WebSocket to `{server}/websocket-tunnel?token=...&GUAC_DATA_SOURCE=...&GUAC_ID=...&GUAC_TYPE=c&GUAC_WIDTH=...&GUAC_HEIGHT=...&GUAC_DPI=...` (subprotocol `guacamole`), performing the handshake from 1.2, and then processing the instruction stream (`size`, `image`, `text`, `mouse`, `key`, `clipboard`, `audio`, `bell`, `disconnect`, ...). This is a full programmatic RDP/VNC/SSH client at the "data stream" level — not an administrative operation.

---

## 2. What `-DataSource mysql` means

It is **not a database name** and not a DB connection parameter. It is the **AuthenticationProvider identifier**.

Evidence:

1. [`TunnelRequest.java`](ANALYSIS/guacamole-client-1.6.0/guacamole/src/main/java/org/apache/guacamole/tunnel/TunnelRequest.java:43) — `AUTH_PROVIDER_IDENTIFIER_PARAMETER = "GUAC_DATA_SOURCE"`, documented as "identifier of the AuthenticationProvider... referred to as the data source identifier".
2. REST URL: [`SessionResource.java`](ANALYSIS/guacamole-client-1.6.0/guacamole/src/main/java/org/apache/guacamole/rest/session/SessionResource.java:111) — `@Path("data/{dataSource}")` → [`UserContextResource`](ANALYSIS/guacamole-client-1.6.0/guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java:56). **The entire UserContext (users, connections, groups, history, schema, activeConnections) lives within a single AuthenticationProvider.**
3. The `POST /api/tokens` response contains `dataSource` and `availableDataSources` — what the user received at login (see [`AUTHENTICATION.md`](ANALYSIS/guacamole-rest-api-documentation/docs/AUTHENTICATION.md)).

Historically the default AuthenticationProvider is `guacamole-auth-mysql`, whose default identifier is the string `mysql`, hence `-DataSource mysql` in all UpperM examples. With LDAP authentication it would be `ldap`, for the Postgres extension — `postgresql`, etc. Find yours in the `dataSource` field of the `POST /api/tokens` response or in your extension's `guac-manifest.json` (`"identifier": ...`).

**Implication for the new module:**
- do not hardcode `mysql`; take the value from the `New-GuacToken`/`New-GuacSession` response (the `dataSource` field) and make it the **default**;
- support multiple auth providers on one instance (UpperM technically allows it — the parameter is passed to every call — but only if the global `$Script:Server` hasn't been clobbered).

---

## 3. Problems with the UpperM/PSGuacamole module (catalog)

### 3.1. Global state in script scope

[`New-GuacToken.ps1`](ANALYSIS/guacamole-powershell/PSGuacamole/Public/APIConnection/New-GuacToken.ps1:89)
```powershell
$Script:Token  = $RestCall.authToken
$Script:Server = $Server
```
The token and server are stored in **module script-scope globals**. Consequences:
- only **one** "active" session per PowerShell process; working with two instances (or two users) in parallel is impossible;
- state does not survive re-`Import-Module`, `pwsh -File`, DSC, and other scenarios where the script scope restarts;
- other functions read `$Token`/`$Server` directly from scope (e.g. [`Stop-GuacConnection.ps1`](ANALYSIS/guacamole-powershell/PSGuacamole/Public/Connections/Stop-GuacConnection.ps1:28) uses `$Server` and `$Token` which are **not declared in its param()**) — a hidden dependency that breaks dot-sourcing and cross-module invocation;
- no explicit lifecycle: no `Disconnect-*`, no "is the token still valid" check before a call (only a bare `DELETE /api/tokens/{token}` in `Remove-GuacToken`).

**Correct architecture:** a cmdlet wrapper with `[-Server] [-Token]` parameters (or `-Session <GuacSession>` — a context object), where `New-GuacSession` returns an object holding the token, and all other cmdlets accept `-Session` with `ValueFromPipeline` plus a default from session state (the `-CmsSession` pattern from PSD).

### 3.2. Swallowed errors

The pattern in **every** function, see [`New-GuacToken.ps1`](ANALYSIS/guacamole-powershell/PSGuacamole/Public/APIConnection/New-GuacToken.ps1:79) and [`Stop-GuacConnection.ps1`](ANALYSIS/guacamole-powershell/PSGuacamole/Public/Connections/Stop-GuacConnection.ps1:36):
```powershell
catch {
    Write-Warning $_.Exception.Message
    return $False
}
```
Problems:
- `$False` as a result is **data**, not an error: `$ErrorActionPreference = 'Stop'` does not trigger, the caller's `try/catch` cannot catch it, `if (-not $result)` is not checked — scripts silently "go nowhere";
- `Write-Warning` loses the HTTP status, the API error body (Guacamole returns JSON with `status`/`reason`), and the request context;
- in `New-GuacToken`, on error the `end` block still runs with `$null` → `$Script:Token = $null` with no notification;
- the message "If TOTP is enabled, please provid -TOTP parameters" (typo + printed on any error) is stdout noise that breaks parsing.

**Correct architecture:** terminating errors via `throw` (or `Write-Error -ErrorAction Stop`) with the **parsed** Guacamole JSON error body (`status`, `reason`) and the HTTP status in the `Exception`/`ErrorRecord`; no `$False` into the pipeline.

### 3.3. PowerShell version incompatibilities

[`New-GuacToken.ps1`](ANALYSIS/guacamole-powershell/PSGuacamole/Public/APIConnection/New-GuacToken.ps1:43)
```powershell
if ($IsWindows) { ... } else {
    $Password = ConvertFrom-SecureString -SecureString $SecurePassword -AsPlaintext
}
```
- `$IsWindows` is a **PowerShell 6+** automatic variable; in Windows PowerShell 5.1 it is `$null` → the condition is false → the else branch runs;
- `-AsPlaintext` is a **PS 6+** parameter; in 5.1 `ConvertFrom-SecureString` without `-AsPlaintext` returns a reversible string representation, **not the password** → the password-prompt path is **broken on 5.1** (while the `psd1` declares `PowerShellVersion = 3.0`);
- the Windows branch (`Marshal::SecureStringToBSTR`) is a correct workaround for 5.1, but it is unreachable because of the `$IsWindows` bug.

Additionally:
- no `-Credential [PSCredential]` support — only a string password parameter (logging, console history, and autocomplete expose it);
- no `ConfirmImpact`, no `SupportsShouldProcess` (DSC/WhatIf-If), no `ParameterSetName`, no `ValueFromPipeline`, no `Aliases`.

### 3.4. Outdated API coverage

The module's last commit is **2023-12-01** and it targets the 1.0/1.1 era (the ridvanaltun docs are the same 1.1.0). Missing support for everything that appeared in 1.4–1.6:
- **Extensions REST API**: `GET /api/ext/{dataSource}` — [`SessionResource.java`](ANALYSIS/guacamole-client-1.6.0/guacamole/src/main/java/org/apache/guacamole/rest/session/SessionResource.java:140) (`@Path("ext/{dataSource}")`), vault extension, display-statistics, auth-ban, and any third-party extension with `REST` endpoints;
- **Sharing profiles** exist, but without `sharingCredentials` — [`ActiveConnectionResource.java`](ANALYSIS/guacamole-client-1.6.0/guacamole/src/main/java/org/apache/guacamole/rest/activeconnection/ActiveConnectionResource.java:128) serves `GET sharingCredentials/{sharingProfile}` → `APIUserCredentials` (credentials for sharing a session) — this is "session access/configuration" that UpperM lacks;
- **Tunnels REST** — `GET` only ([`TunnelCollectionResource.java`](ANALYSIS/guacamole-client-1.6.0/guacamole/src/main/java/org/apache/guacamole/rest/tunnel/TunnelCollectionResource.java:77)); UpperM covers it but without understanding that these are read-only metadata (activeConnection, protocol, streams), not control;
- **History** — `Get-GuacConnectionsHistory` exists, but without `startDate`/`endDate` filtering (the REST supports query parameters);
- **Schema attributes** — `userAttributes`, `userPreferenceAttributes`, `userGroupAttributes`, `sharingProfileAttributes`, `connectionGroupAttributes`, `protocols` — only partially covered in UpperM (just `connectionAttributes` and `protocols`);
- **`DELETE /api/session`** (invalidates the token/session — [`SessionResource.java`](ANALYSIS/guacamole-client-1.6.0/guacamole/src/main/java/org/apache/guacamole/rest/session/SessionResource.java:179)) — in UpperM this is `Remove-GuacToken` via `DELETE /api/tokens/{token}`, which works but is not equivalent and is undocumented;
- **`HEAD /api/session`** — token validity check — absent.

### 3.5. Miscellaneous

- **Token in the query string** (`?token=...`) is an API requirement, but there is no hygiene: no masking in `-Verbose`/`-Debug` output, no `SecureString`/`Sensitive` parameters, the token is visible in any URI logging/capture.
- **No TLS options**: `Invoke-RestMethod` without `-CertificateThumbprint`/`-Certificate`, `-Proxy`, `-NoProxy`; self-signed certs force manual `TLS12` hacks.
- **No tests, no CI, no Pester examples**; docs are script-generated but lack examples for new features.
- **`ConvertTo-Json` without `-Depth`** in PATCH bodies; the JSON patch array is built with the string trick `"[$($Body)]"` — fragile for nested data.
- **French comments** in the manifest; missing `#Requires`, `Tags`, `ReleaseNotes`.
- **Correct core to keep**: JSON Patch for killing sessions ([`Stop-GuacConnection.ps1`](ANALYSIS/guacamole-powershell/PSGuacamole/Public/Connections/Stop-GuacConnection.ps1:23)), the `-TOTP` parameter (`guac-totp`), the begin/process/end structure, and the domain-based layout (Users/Connections/Groups/Permissions/...).

---

## 4. Design recommendations for the new module

### 4.1. Core: the session as an object

```powershell
# Returns a context object
$g = New-GuacSession -Server https://guac.example.com/guacamole -Credential (Get-Credential)
# $g = [GuacSession] { Server, Token, DataSource, Username, AvailableDataSources, RawResponse }

Get-GuacConnection -Session $g -Id <uuid>
Get-GuacConnection -Id <uuid> | Stop-GuacActiveConnection   # -Session ValueFromPipeline
```
- `-Session` with `ValueFromPipeline` + default from session state (like `-CmsSession`) — solves multi-server and pipelining at once;
- `New-GuacSession` takes `DataSource` from the token response by default; `-DataSource` overrides it (for multi-provider instances);
- `Test-GuacSession` (HEAD `/api/session`) and `Remove-GuacSession` (DELETE `/api/tokens/{token}`).

### 4.2. Error handling

- all REST calls go through a single private `Invoke-GuacRest`: it parses the Guacamole JSON error (`status`/`reason`), and re-throws a terminating error carrying the HTTP status and body;
- no `return $False` anywhere;
- `SupportsShouldProcess` on all mutations, `ConfirmImpact = High` on `Remove-*`/`Stop-*`.

### 4.3. API coverage (target, based on 1.6.0)

| Group | Endpoints | Notes |
|---|---|---|
| Auth | `POST /api/tokens`, `DELETE /api/tokens/{t}`, `DELETE /api/session`, `HEAD /api/session` | + `guac-totp` |
| Self/Active | `.../self`, `.../activeConnections` (GET + PATCH-kill), `.../activeConnections/{id}/connection`, `.../activeConnections/{id}/sharingCredentials/{profile}` | **new vs UpperM** |
| Connections/Groups/SharingProfiles | CRUD + JSON Patch (`PATCH .../connections`, `.../connectionGroups`, `.../sharingProfiles`) | + `parameters`, `history`, `sharingProfiles` sub-resources |
| Users/UserGroups/Permissions | CRUD + membership | `PUT .../users/{id}/password` |
| History | `.../history` + `.../connections/{id}/history` | `startDate`/`endDate` query parameters |
| Schema | `.../schema/*` (all 6 attribute sets + `protocols`) | the key to "session configuration" — see 4.4 |
| Tunnels | `GET /api/session/tunnels`, `/api/session/tunnels/{t}` | read-only metadata |
| Extensions | `GET /api/ext/{dataSource}` + discovery | **new vs UpperM** |
| Languages/Patches | `/api/languages`, `/api/patches` | |

### 4.4. Session management (the main differentiator)

1. **`New-GuacActiveSession`** (or `Start-GuacConnection`) — does not create an "admin object" but **brings up a real tunnel**:
   - accepts `-Connection <uuid>` or `-ConnectionGroup <uuid>`, `-DataSource`, `-Session $g` (token), `-Width/-Height/-Dpi`, `-ProtocolArgs @{...}`;
   - builds the query string per [`TunnelRequest.java`](ANALYSIS/guacamole-client-1.6.0/guacamole/src/main/java/org/apache/guacamole/tunnel/TunnelRequest.java:43);
   - opens a `System.Net.WebSockets.ClientWebSocket` (or .NET `WebSocket`) with `SubProtocol "guacamole"` at `{server}/websocket-tunnel`;
   - performs the handshake from [`ConfiguredGuacamoleSocket`](ANALYSIS/guacamole-client-1.6.0/guacamole-common/src/main/java/org/apache/guacamole/protocol/ConfiguredGuacamoleSocket.java:220): `select` → `args` → `size`/`audio`/`video`/`image`/`timezone`/`name` → `connect` → `ready`;
   - returns a `[GuacActiveSession]` object with `Id` (from `ready`), the `WebSocket`, an instruction stream (Queue/Channel), and `Send-Instruction`/`Close` methods.
   - The `connect` arguments are assembled from `connection.parameters` (REST) + the protocol schema (`schema/connectionAttributes` + `protocols/{proto}.json` from `guacamole-ext` — these can be bundled with the module as data files).
2. **`Get-GuacActiveConnection`** / **`Stop-GuacActiveConnection`** / **`Get-GuacSharingCredential`** — the REST layer over already-active sessions (including other users' sessions — for administration).
3. **`Invoke-GuacInstruction`** / `Receive-GuacInstruction` — low-level protocol access for advanced scenarios (SSH/VNC scripting: sending `key`/`mouse`/`clipboard`, receiving `text`/`image`).
4. Document honestly: REST manages **entities**, WebSocket manages **sessions**; "session configuration" = tunnel parameters + protocol argument values.

### 4.5. Quality bar

- `#Requires -Version 5.1`, targeting 5.1+ and 7.x (use only compatible APIs; SecureString→string via `Marshal` on all platforms, or the `[System.Net.NetworkCredential]` pattern);
- Pester tests (mocked transport), CI (GitHub Actions: PSScriptAnalyzer lint + Pester + publish);
- `SecureString`/`Sensitive` for all passwords and TOTP; token masking in `-Verbose`/`-Debug`;
- `-CertificateThumbprint`/`-Certificate`/`-Proxy` plumbed into the REST core;
- a single cmdlet noun/verb convention (e.g. the `Guac` noun), `Aliases`, `Examples` in every help, `Tags` in the psd1.

### 4.6. What NOT to copy from UpperM

1. `$Script:` globals → session object + pipeline;
2. `catch { return $False }` → terminating errors with the parsed body;
3. `$IsWindows`/`-AsPlaintext` → cross-platform SecureString conversion;
4. hardcoded `mysql` → default from the token response's `dataSource`;
5. missing `/api/ext`, `sharingCredentials`, schema attributes, `Test-*` → full 1.6.0 coverage;
6. no protocol client → `New-GuacActiveSession` over WebSocket.

---

## 5. Short answer to the original question

"Creating and configuring sessions" is not found in the official `api-documentation` because:
1. that page documents the **Java API**, not the REST API;
2. the Guacamole REST API **does not create interactive sessions** — it manages entities and *active* sessions (list/kill/credentials);
3. a session is created by a **client connection**: WebSocket `/websocket-tunnel?token=...&GUAC_DATA_SOURCE=...&GUAC_ID=...&GUAC_TYPE=c&GUAC_WIDTH=...&GUAC_HEIGHT=...&GUAC_DPI=...` (subprotocol `guacamole`) + the `select → args → size/audio/video/image → connect → ready` handshake. "Configuring" a session = tunnel parameters + protocol argument values (per the `guacamole-ext/.../protocols/*.json` schemas).

`-DataSource mysql` in UpperM is the **AuthenticationProvider identifier** (the URL path segment `/api/session/data/{dataSource}/` and the `GUAC_DATA_SOURCE` tunnel parameter), not a database name; the new module should take it from the `POST /api/tokens` response (`dataSource`/`availableDataSources`).
