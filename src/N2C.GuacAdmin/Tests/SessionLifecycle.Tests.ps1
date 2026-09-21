#Requires -Version 5.1
# Pester v5 tests for the N2C.GuacAdmin public session lifecycle cmdlets.
# These run against a local mock of the Guacamole 1.6.0 REST API
# (Tests/GuacMockServer.ps1), so no real Guacamole instance is required.

# Shared state for this test container. $script: prefix is required: in Pester
# v5 a plain $var assigned in BeforeAll is scoped to that block and is NOT
# visible from It blocks (only file-scope and $script:-prefixed variables are).
$script:mock = $null
$script:credential = $null
$script:totpSecure = $null

BeforeAll {
    $script:moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:moduleRoot 'Tests/GuacTestHelpers.psm1') -Force
    $script:mock = Start-GuacTestMock -WorkDir $PSScriptRoot
    # The helper module imported N2C.GuacAdmin inside its own scope; import it
    # here as well so the exported cmdlets resolve in Pester's test scope.
    # Safe to repeat: the module captures its class types in module-scope
    # variables at load time, so each import instance is self-consistent.
    Import-Module (Join-Path $script:moduleRoot 'N2C.GuacAdmin.psd1') -Force
    $script:credential = [PSCredential]::new(
        'guacadmin',
        (ConvertTo-SecureString 'secret' -AsPlainText -Force)
    )
    $script:totpSecure = ConvertTo-SecureString '123456' -AsPlainText -Force
}

AfterAll {
    if ($null -ne $script:mock) {
        Stop-GuacTestMock
    }
}

Describe 'New-GuacSession' {
    It 'creates a session from the token response' {
        $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential

        # Compare the type by the instance's runtime name rather than a
        # [TypeName] literal: the module is imported by the test helper (a
        # separate function scope), so script-defined class names are not
        # resolvable by name inside Pester's It scope, but the instances the
        # module returns carry the real type.
        $session.GetType().Name | Should -Be 'N2C_GuacAdmin_GuacSession'
        $session.Server | Should -Be $mock.BaseUrl
        $session.Username | Should -Be 'guacadmin'
        $session.Token | Should -Not -BeNullOrEmpty
        $session.Token | Should -Not -Be 'secret'
        $session.DataSource | Should -Be 'mysql'
        $session.AvailableDataSources | Should -Be @('mysql', 'ldap')
        $session.TimeoutSec | Should -Be 30
    }

    It 'sends the login as a form-urlencoded POST to /api/tokens' {
        New-GuacSession -Server $mock.BaseUrl -Credential $credential | Out-Null
        $loginRequests = Get-GuacMockLog -FilterPath '/api/tokens'
        $loginRequests.Count | Should -BeGreaterThan 0
        $last = $loginRequests[-1]
        $last.method | Should -Be 'POST'
        $last.contentType | Should -Be 'application/x-www-form-urlencoded'
        $last.body | Should -BeLike 'username=guacadmin*'
        $last.body | Should -BeLike '*password=secret*'
        $last.body | Should -Not -BeLike '*guac-totp*'
    }

    It 'defaults the data source from the token response and validates an override' {
        $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential -DataSource ldap
        $session.DataSource | Should -Be 'ldap'

        { New-GuacSession -Server $mock.BaseUrl -Credential $credential -DataSource postgresql } | Should -Throw
    }

    It 'throws a terminating error with the parsed API reason on bad credentials' {
        $badCredential = [PSCredential]::new(
            'guacadmin',
            (ConvertTo-SecureString 'wrong' -AsPlainText -Force)
        )
        $thrown = $null
        try {
            New-GuacSession -Server $mock.BaseUrl -Credential $badCredential -ErrorAction Stop
        }
        catch { $thrown = $_ }

        $thrown | Should -Not -BeNullOrEmpty
        $inner = $thrown.Exception
        $inner.GetType().Name | Should -Be 'N2C_GuacAdmin_GuacRestException'
        $inner.StatusCode | Should -Be 401
        $inner.Type | Should -Be 'INVALID_CREDENTIALS'
        $inner.Reason | Should -Be 'Invalid credentials.'
        $inner.Endpoint | Should -BeLike ('*{0}/api/tokens' -f $mock.BaseUrl)
    }

    It 'does not register a default session on failure' {
        $badCredential = [PSCredential]::new(
            'guacadmin',
            (ConvertTo-SecureString 'wrong' -AsPlainText -Force)
        )
        $serverBefore = 'https://nowhere.example.com'
        { New-GuacSession -Server $serverBefore -Credential $badCredential -ErrorAction Stop } | Should -Throw
        Get-GuacSession -Server $serverBefore | Should -BeNullOrEmpty
    }

    It 'sends the guac-totp form field when -TotpCode is supplied' {
        Invoke-GuacMockControl -Path '/_control/totp-enable'
        try {
            $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential -TotpCode $totpSecure
            $session.Token | Should -Not -BeNullOrEmpty

            $loginRequests = Get-GuacMockLog -FilterPath '/api/tokens'
            $loginRequests[-1].body | Should -BeLike '*guac-totp=123456*'
        }
        finally {
            Invoke-GuacMockControl -Path '/_control/totp-disable'
        }
    }

    It 'fails when TOTP is required but not provided' {
        Invoke-GuacMockControl -Path '/_control/totp-enable'
        try {
            $thrown = $null
            try {
                New-GuacSession -Server $mock.BaseUrl -Credential $credential -ErrorAction Stop
            }
            catch { $thrown = $_ }
            $thrown.Exception.GetType().Name | Should -Be 'N2C_GuacAdmin_GuacRestException'
            $thrown.Exception.StatusCode | Should -Be 401
            $thrown.Exception.Type | Should -Be 'INSUFFICIENT_CREDENTIALS'
        }
        finally {
            Invoke-GuacMockControl -Path '/_control/totp-disable'
        }
    }

    It 'masks the token in the session ToString()' {
        $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential
        $text = $session.ToString()
        $text | Should -Not -BeLike "*$($session.Token)*"
        $text | Should -BeLike '*Token=mock*' -Because 'the masking keeps the first 4 characters'
    }
}

Describe 'Test-GuacSession' {
    It 'returns $true for a live session' {
        $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential
        Test-GuacSession -Session $session | Should -BeTrue
    }

    It 'returns $false for a revoked token' {
        $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential
        # Revoke directly on the server side, bypassing Remove-GuacSession.
        $revoke = Invoke-WebRequest -Method DELETE -Uri ($mock.BaseUrl + '/api/tokens/' + $session.Token) `
            -Headers @{ 'Guacamole-Token' = $session.Token } -UseBasicParsing
        $revoke.StatusCode | Should -Be 204
        Test-GuacSession -Session $session | Should -BeFalse
    }

    It 'resolves the session from -Server via module state' {
        New-GuacSession -Server $mock.BaseUrl -Credential $credential | Out-Null
        Test-GuacSession -Server $mock.BaseUrl | Should -BeTrue
    }

    It 'throws when there is no session to check' {
        { Test-GuacSession -Server 'https://nowhere.example.com' } | Should -Throw
    }
}

Describe 'Remove-GuacSession' {
    It 'revokes the token and clears the module state' {
        $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential
        $sessionBefore = Get-GuacSession -Server $mock.BaseUrl
        $sessionBefore | Should -Not -BeNullOrEmpty

        Remove-GuacSession -Session $session -Confirm:$false

        Get-GuacSession -Server $mock.BaseUrl | Should -BeNullOrEmpty
        # The token must now be rejected by the server.
        Test-GuacSession -Session $session | Should -BeFalse
        # The DELETE must have been sent with the token in the URL path.
        $deleteRequests = Get-GuacMockLog -FilterPath '/api/tokens/*'
        $deleteRequests | Should -Not -BeNullOrEmpty
        $deleteRequests[-1].method | Should -Be 'DELETE'
        $deleteRequests[-1].path | Should -BeLike ('*/api/tokens/{0}' -f $session.Token)
    }

    It 'succeeds when the token is already gone (server returns 401)' {
        $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential
        # Revoke server-side directly, leaving stale local state.
        Invoke-WebRequest -Method DELETE -Uri ($mock.BaseUrl + '/api/tokens/' + $session.Token) `
            -Headers @{ 'Guacamole-Token' = $session.Token } -UseBasicParsing | Out-Null

        Remove-GuacSession -Session $session -Confirm:$false
        Get-GuacSession -Server $mock.BaseUrl | Should -BeNullOrEmpty
    }

    It 'honors -WhatIf (no server call, state retained)' {
        $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential
        $deleteCountBefore = (Get-GuacMockLog -FilterPath '/api/tokens/*').Count
        Remove-GuacSession -Session $session -WhatIf -Confirm:$false
        $deleteCountAfter = (Get-GuacMockLog -FilterPath '/api/tokens/*').Count
        $deleteCountAfter | Should -Be $deleteCountBefore
        Get-GuacSession -Server $mock.BaseUrl | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-GuacSession' {
    It 'returns the registered default for the server' {
        $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential
        $default = Get-GuacSession -Server $mock.BaseUrl
        $default | Should -Not -BeNullOrEmpty
        $default.Token | Should -Be $session.Token
    }

    It 'returns $null when no default is registered' {
        Get-GuacSession -Server 'https://unknown.example.com' | Should -BeNullOrEmpty
    }

    It 'matches the server case-insensitively and ignores a trailing slash' {
        $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential
        $alt = $mock.BaseUrl.TrimEnd('/').ToUpperInvariant() + '/'
        $default = Get-GuacSession -Server $alt
        $default | Should -Not -BeNullOrEmpty
        $default.Token | Should -Be $session.Token
    }
}

Describe 'GuacRestException error contract (via mock server)' {
    It 'maps a 404 APIError to a terminating exception with parsed fields' {
        # Reach the private transport through Pester's InModuleScope (this
        # PowerShell build's PSModuleInfo has no GetCommand method).
        $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential
        $invoke = InModuleScope -ModuleName 'N2C.GuacAdmin' { Get-Command -Name 'Invoke-GuacRest' }
        $thrown = $null
        try {
            & $invoke -Server $mock.BaseUrl -Token $session.Token -Method GET -Path '/api/notfound'
        }
        catch { $thrown = $_ }
        $thrown | Should -Not -BeNullOrEmpty
        $inner = $thrown.Exception
        $inner.GetType().Name | Should -Be 'N2C_GuacAdmin_GuacRestException'
        $inner.StatusCode | Should -Be 404
        $inner.Type | Should -Be 'NOT_FOUND'
        $inner.Reason | Should -Be 'No such resource.'
        $inner.Endpoint | Should -Be ($mock.BaseUrl + '/api/notfound')
    }

    It 'maps a non-JSON 500 body to the raw text reason' {
        $session = New-GuacSession -Server $mock.BaseUrl -Credential $credential
        $invoke = InModuleScope -ModuleName 'N2C.GuacAdmin' { Get-Command -Name 'Invoke-GuacRest' }
        $thrown = $null
        try {
            & $invoke -Server $mock.BaseUrl -Token $session.Token -Method GET -Path '/api/plaintext-error'
        }
        catch { $thrown = $_ }
        $inner = $thrown.Exception
        $inner.GetType().Name | Should -Be 'N2C_GuacAdmin_GuacRestException'
        $inner.StatusCode | Should -Be 500
        $inner.Type | Should -BeNullOrEmpty
        $inner.Reason | Should -Be 'Internal server error (no JSON body).'
    }

    It 'masks the token in the endpoint of token-path errors' {
        New-GuacSession -Server $mock.BaseUrl -Credential $credential | Out-Null
        $invoke = InModuleScope -ModuleName 'N2C.GuacAdmin' { Get-Command -Name 'Invoke-GuacRest' }
        $thrown = $null
        try {
            & $invoke -Server $mock.BaseUrl -Token 'averylongtokenvalue1234567890' -Method DELETE -Path '/api/tokens/averylongtokenvalue1234567890'
        }
        catch { $thrown = $_ }
        $inner = $thrown.Exception
        $inner.Endpoint | Should -Not -BeLike '*averylongtokenvalue1234567890*'
        $inner.Message | Should -Not -BeLike '*averylongtokenvalue1234567890*'
    }
}

Describe 'Module manifest and export' {
    It 'exports exactly the phase 1 cmdlets' {
        $sm = Get-Module N2C.GuacAdmin
        # ExportedFunctions is a plain hashtable: compare as a set, not by order.
        $expected = @('New-GuacSession', 'Get-GuacSession', 'Remove-GuacSession', 'Test-GuacSession')
        $actual = @($sm.ExportedFunctions.Keys)
        $actual.Count | Should -Be $expected.Count
        foreach ($name in $expected) {
            $actual -contains $name | Should -BeTrue
        }
    }

    It 'has PSData metadata (Tags, ReleaseNotes, ProjectUri)' {
        $manifest = Import-PowerShellDataFile (Join-Path $moduleRoot 'N2C.GuacAdmin.psd1')
        $manifest.PrivateData.PSData.Tags | Should -Not -BeNullOrEmpty
        $manifest.PrivateData.PSData.ReleaseNotes | Should -Not -BeNullOrEmpty
        $manifest.PrivateData.PSData.ProjectUri | Should -BeLike 'https://*'
        $manifest.PowerShellVersion | Should -Be '5.1'
    }
}
