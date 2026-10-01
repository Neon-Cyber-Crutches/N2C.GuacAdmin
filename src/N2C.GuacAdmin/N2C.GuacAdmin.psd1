@{
    # Identity
    RootModule        = 'N2C.GuacAdmin.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'd9c1a2b3-4e5f-4a6b-8c7d-9e0f1a2b3c4d'
    Author            = 'ahpooch'
    CompanyName       = 'Neon Cyber Crutches'
    Copyright         = '(c) 2026 Neon Cyber Crutches'

    Description       = 'Administrative PowerShell module for Apache Guacamole 1.6.x: authentication sessions, connections, connection groups, users, user groups, sharing profiles, permissions, history, schemas, active sessions and tunnels via the Guacamole REST API, plus a Guacamole protocol (WebSocket) client.'

    # Compatibility: Windows PowerShell 5.1 and PowerShell 7.x (Desktop + Core)
    PowerShellVersion = '5.1'
    RequiredModules = @()
    RequiredAssemblies = @()
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
        'New-GuacSession', 'Get-GuacSession', 'Remove-GuacSession', 'Test-GuacSession', 'Set-GuacDataSource',
        'Get-GuacConnection', 'New-GuacConnection', 'Update-GuacConnection', 'Remove-GuacConnection',
        'Get-GuacConnectionGroup', 'Get-GuacConnectionGroupTree', 'New-GuacConnectionGroup', 'Update-GuacConnectionGroup', 'Remove-GuacConnectionGroup',
        'Get-GuacUser', 'New-GuacUser', 'Update-GuacUser', 'Remove-GuacUser', 'Set-GuacUserPassword',
        'Get-GuacUserGroup', 'New-GuacUserGroup', 'Update-GuacUserGroup', 'Remove-GuacUserGroup',
        'Get-GuacSharingProfile', 'New-GuacSharingProfile', 'Update-GuacSharingProfile', 'Remove-GuacSharingProfile',
        'Add-GuacPermission', 'Remove-GuacPermission',
        'Add-GuacUserGroupMember', 'Remove-GuacUserGroupMember', 'Add-GuacUserGroupChildGroup', 'Remove-GuacUserGroupChildGroup',
        'Get-GuacHistoryConnections', 'Get-GuacHistoryUsers', 'Get-GuacSchema', 'Get-GuacProtocol',
        'Get-GuacActiveConnection', 'Stop-GuacActiveConnection', 'Get-GuacSharingCredential',
        'Get-GuacTunnel', 'Get-GuacLanguage', 'Get-GuacPatches', 'Get-GuacExtension',
        'New-GuacActiveSession', 'Send-GuacInstruction', 'Receive-GuacInstruction', 'Remove-GuacActiveSession'
    )

    # Class definitions (N2C_GuacAdmin_GuacSession, N2C_GuacAdmin_GuacRestException).
    # ScriptsToProcess runs the script in a caller-visible scope, making the
    # classes the same type in the module and the caller.
    ScriptsToProcess  = @('Types.ps1')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    FormatsToProcess = @('N2C.GuacAdmin.Format.ps1xml')
    DscResourcesToExport = @()

    # Private data to pass to the module. Contains the PSData metadata hashtable.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for online gallery discovery
            Tags = @('guacamole', 'apache', 'remote-desktop', 'rdp', 'ssh', 'vnc', 'rest', 'administration', 'powershell')

            ProjectUri = 'https://github.com/Neon-Cyber-Crutches/N2C.GuacAdmin'
            LicenseUri = 'https://github.com/Neon-Cyber-Crutches/N2C.GuacAdmin/blob/main/LICENSE'

            ReleaseNotes = @'
1.0.0 — first stable release, all 5 phases complete (163 tests green)

Phase 1 — Scaffold, transport, auth/session lifecycle
- Module layout, manifest, loader (PS 5.1 / 7.x compatible).
- Private REST transport (Invoke-GuacRest): APIError parsing, terminating
  GuacRestException on every failure, TLS 1.2 enforcement on Windows PowerShell
  5.1, proxy and client certificate plumbing, token masking in verbose output.
- New-GuacSession: POST /api/tokens with PSCredential, optional TOTP
  (SecureString), data source defaulting from the token response.
- Remove-GuacSession: DELETE /api/tokens/{token} (SupportsShouldProcess,
  ConfirmImpact High), clears module session state.
- Test-GuacSession: HEAD /api/session token validity check.
- Module session state providing a default -Session resolution
  (the -CmsSession pattern); no script-scope globals.

Phase 2 — Entity CRUD
- Connections: Get/New/Update/Remove-GuacConnection (-Name, -Protocol filters;
  ParentGroupName resolution).
- Connection groups: Get/New/Update/Remove-GuacConnectionGroup +
  Get-GuacConnectionGroupTree (hierarchical tree with Permission filtering).
- Users: Get/New/Update/Remove-GuacUser, Set-GuacUserPassword
  (-Permissions, -EffectivePermissions flags).
- User groups: Get/New/Update/Remove-GuacUserGroup + Add/Remove-GuacUserGroupMember
  + Add/Remove-GuacUserGroupChildGroup.
- Sharing profiles: Get/New/Update/Remove-GuacSharingProfile
  (PrimaryConnectionName resolution).
- Permissions: Add-GuacPermission / Remove-GuacPermission (JSON Patch RFC 6902;
  user/user-group subjects, all target kinds).
- History & schemas: Get-GuacHistoryConnections, Get-GuacHistoryUsers,
  Get-GuacSchema, Get-GuacProtocol.

Phase 3 — Active sessions, tunnels, extensions (REST)
- Get-GuacActiveConnection (ConnectionName resolution), Stop-GuacActiveConnection,
  Get-GuacSharingCredential.
- Get-GuacTunnel (read-only tunnel UUID listing).
- Get-GuacLanguage, Get-GuacPatches, Get-GuacExtension.

Phase 4 — Protocol client (interactive sessions)
- New-GuacActiveSession: opens WebSocket tunnel (guacamole subprotocol) + full
  handshake (select/args/size/audio/video/image/timezone/connect → ready).
- Send-GuacInstruction / Receive-GuacInstruction (low-level instruction pump).
- Remove-GuacActiveSession (graceful disconnect).

Phase 4.5 — Get-GuacConnectionGroupTree split (Issue #1)
- Tree retrieval extracted into dedicated Get-GuacConnectionGroupTree cmdlet;
  Get-GuacConnectionGroup simplified to flat list/get semantics.

Phase 5 — Hardening & release
- PSScriptAnalyzer strict ruleset as CI lint gate (run-lint.ps1).
- Pester v5 suite: unit tests + self-contained mock Guacamole server integration
  tests (Tests/GuacMockServer.ps1).
- Multi-data-source support (-DataSource All, per-object DataSource property,
  Set-GuacDataSource).
- Name resolution (ParentGroupName, PrimaryConnectionName, ConnectionName).
- GitHub Actions CI (lint + test + publish dry-run).
'@
        }
    }
}
