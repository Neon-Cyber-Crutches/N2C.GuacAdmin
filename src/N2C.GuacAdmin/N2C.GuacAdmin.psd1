@{
    # Identity
    RootModule        = 'N2C.GuacAdmin.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'd9c1a2b3-4e5f-4a6b-8c7d-9e0f1a2b3c4d'
    Author            = 'N2C'
    CompanyName       = 'N2C'
    Copyright         = '(c) N2C. All rights reserved.'

    Description       = 'Administrative PowerShell module for Apache Guacamole 1.6.x: authentication sessions, connections, connection groups, users, user groups, sharing profiles, permissions, history, schemas, active sessions and tunnels via the Guacamole REST API, plus a Guacamole protocol (WebSocket) client.'

    # Compatibility: Windows PowerShell 5.1 and PowerShell 7.x (Desktop + Core)
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Public surface (phase 1: authentication/session lifecycle; phase 2:
    # entity CRUD, permissions/membership, history, schemas; phase 3: active
    # sessions, tunnels, languages, patches, extensions)
    FunctionsToExport = @(
        'New-GuacSession', 'Get-GuacSession', 'Remove-GuacSession', 'Test-GuacSession',
        'Get-GuacConnection', 'New-GuacConnection', 'Update-GuacConnection', 'Remove-GuacConnection',
        'Get-GuacConnectionGroup', 'Get-GuacConnectionGroupTree', 'New-GuacConnectionGroup', 'Update-GuacConnectionGroup', 'Remove-GuacConnectionGroup',
        'Get-GuacUser', 'New-GuacUser', 'Update-GuacUser', 'Remove-GuacUser', 'Set-GuacUserPassword',
        'Get-GuacUserGroup', 'New-GuacUserGroup', 'Update-GuacUserGroup', 'Remove-GuacUserGroup',
        'Get-GuacSharingProfile', 'New-GuacSharingProfile', 'Update-GuacSharingProfile', 'Remove-GuacSharingProfile',
        'Add-GuacPermission', 'Remove-GuacPermission',
        'Add-GuacUserGroupMember', 'Remove-GuacUserGroupMember', 'Add-GuacUserGroupChildGroup', 'Remove-GuacUserGroupChildGroup',
        'Get-GuacHistory', 'Get-GuacSchema', 'Get-GuacProtocol',
        'Get-GuacActiveConnection', 'Stop-GuacActiveConnection', 'Get-GuacSharingCredential',
        'Get-GuacTunnel', 'Get-GuacLanguage', 'Get-GuacPatches', 'Get-GuacExtension',
        'New-GuacActiveSession', 'Send-GuacInstruction', 'Receive-GuacInstruction', 'Remove-GuacActiveSession'
    )

    # Class definitions (N2C_GuacAdmin_GuacSession, N2C_GuacAdmin_GuacRestException).
    # ScriptsToProcess runs the script in a caller-visible scope, making the
    # classes the same type in the module and the caller. (TypesToProcess is
    # for .ps1xml format files, not class definitions.)
    ScriptsToProcess  = @('Types.ps1')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    DscResourcesToExport = @()

    # Private data to pass to the module. Contains the PSData metadata hashtable.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for online gallery discovery
            Tags = @('guacamole', 'apache', 'remote-desktop', 'rdp', 'ssh', 'vnc', 'rest', 'administration', 'powershell')

            ProjectUri = 'https://github.com/N2C/N2C.GuacAdmin'
            LicenseUri = 'https://github.com/N2C/N2C.GuacAdmin/blob/main/LICENSE'

            ReleaseNotes = @'
0.1.0
- Initial scaffold: module layout, manifest, loader (PS 5.1 / 7.x compatible).
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
- Pester v5 unit tests (transport, helpers, session lifecycle, manifest).
'@
        }
    }
}
