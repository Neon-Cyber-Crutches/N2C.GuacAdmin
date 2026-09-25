#Requires -Version 5.1
# Pester v5 integration tests for the N2C.GuacAdmin Phase 3 cmdlets (active
# sessions, tunnels, languages, patches, extensions), run against the local
# mock Guacamole server (Tests/GuacMockServer.ps1).

$script:mock = $null
$script:credential = $null
$script:session = $null

BeforeAll {
    $script:moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:moduleRoot 'Tests/GuacTestHelpers.psm1') -Force
    $script:mock = Start-GuacTestMock -WorkDir $PSScriptRoot
    Import-Module (Join-Path $script:moduleRoot 'N2C.GuacAdmin.psd1') -Force
    $script:credential = [PSCredential]::new(
        'guacadmin',
        (ConvertTo-SecureString 'secret' -AsPlainText -Force)
    )
    $script:session = New-GuacSession -Server $mock.BaseUrl -Credential $credential
}

AfterAll {
    if ($null -ne $mock) {
        Stop-GuacTestMock
    }
}

Describe 'Get-GuacActiveConnection' {
    It 'lists all active connections' {
        $activeConns = @(Get-GuacActiveConnection -Session $session)
        $activeConns.Count | Should -BeGreaterOrEqual 2
        $ids = @($activeConns | ForEach-Object { $_.Identifier })
        $ids | Should -Contain 'active-1'
        $ids | Should -Contain 'active-2'
    }

    It 'gets a single active connection by id' {
        $activeConn = Get-GuacActiveConnection -Session $session -Id 'active-1'
        $activeConn.Identifier | Should -Be 'active-1'
        $activeConn.ConnectionIdentifier | Should -Be 'conn-1'
        $activeConn.Username | Should -Be 'guacadmin'
    }

    It 'throws for an unknown active connection id' {
        { Get-GuacActiveConnection -Session $session -Id 'does-not-exist' -ErrorAction Stop } | Should -Throw
    }

    It 'resolves ConnectionName by default' {
        $activeConn = Get-GuacActiveConnection -Session $session -Id 'active-1'
        $activeConn.ConnectionName | Should -Be 'test-connection'
    }

    It 'skips ConnectionName resolution when -ResolveConnectionName is false' {
        $activeConn = Get-GuacActiveConnection -Session $session -Id 'active-1' -ResolveConnectionName:$false
        $activeConn.PSObject.Properties['ConnectionName'] | Should -Be $null
    }
}

Describe 'Get-GuacSharingCredential' {
    It 'gets sharing credentials for an active connection' {
        $creds = Get-GuacSharingCredential -Session $session -Id 'active-1' -SharingProfile 'readonly'
        $creds | Should -Not -BeNullOrEmpty
        $creds.username | Should -BeLike 'share-active-1-*'
    }

    It 'throws when -SharingProfile is not supplied' {
        { Get-GuacSharingCredential -Session $session -Id 'active-1' -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Stop-GuacActiveConnection' {
    It 'stops an active connection by id' {
        Get-GuacActiveConnection -Session $session -Id 'active-2' | Should -Not -BeNullOrEmpty
        Stop-GuacActiveConnection -Session $session -Id 'active-2' -Confirm:$false
        { Get-GuacActiveConnection -Session $session -Id 'active-2' -ErrorAction Stop } | Should -Throw
    }

    It 'stops a piped active connection object' {
        Get-GuacActiveConnection -Session $session -Id 'active-1' | Stop-GuacActiveConnection -Confirm:$false
        { Get-GuacActiveConnection -Session $session -Id 'active-1' -ErrorAction Stop } | Should -Throw
    }

    It 'honors -WhatIf' {
        # After previous tests, no active connections remain; should not throw
        {
            Get-GuacActiveConnection -Session $session | ForEach-Object {
                Stop-GuacActiveConnection -Session $session -Id $_.Identifier -WhatIf
            }
        } | Should -Not -Throw
    }
}

Describe 'Get-GuacTunnel' {
    It 'lists tunnel UUIDs' {
        $tunnels = @(Get-GuacTunnel -Session $session)
        $tunnels.Count | Should -BeGreaterOrEqual 1
        $tunnels | Should -Contain 'tunnel-1'
    }
}

Describe 'Get-GuacLanguage' {
    It 'returns a map of languages' {
        $languages = Get-GuacLanguage -Session $session
        $languages | Should -Not -BeNullOrEmpty
        # The response is a PSCustomObject in PS 7.x (string indexer not supported)
        # and an OrderedDictionary in PS 5.1. Use property access for both.
        $languages.en | Should -Be 'English'
        $languages.fr | Should -Be 'Français'
        $languages.de | Should -Be 'Deutsch'
    }
}

Describe 'Get-GuacPatches' {
    It 'returns an array of HTML patches' {
        $patches = @(Get-GuacPatches -Session $session)
        $patches.Count | Should -BeGreaterOrEqual 1
        $patches[0] | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-GuacExtension' {
    It 'returns extension resource for a data source' {
        $ext = Get-GuacExtension -Session $session -DataSource 'mysql'
        $ext | Should -Not -BeNullOrEmpty
        $ext.DataSource | Should -Be 'mysql'
    }

    It 'throws when -DataSource is not supplied' {
        { Get-GuacExtension -Session $session -ErrorAction Stop } | Should -Throw
    }
}
