#Requires -Version 5.1
# Pester v5 integration tests for the N2C.GuacAdmin connection cmdlets, run
# against the local mock Guacamole server (Tests/GuacMockServer.ps1).

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

Describe 'Get-GuacConnection' {
    It 'lists connections with Identifier properties' {
        $connections = @(Get-GuacConnection -Session $session)
        $connections.Count | Should -BeGreaterOrEqual 2
        $names = @($connections | ForEach-Object { $_.Name })
        $names | Should -Contain 'test-connection'
        foreach ($c in $connections) {
            $c.Identifier | Should -Not -BeNullOrEmpty
        }
    }

    It 'gets a single connection by id' {
        $conn = Get-GuacConnection -Session $session -Id 'conn-1'
        $conn.Identifier | Should -Be 'conn-1'
        $conn.Name | Should -Be 'test-connection'
        $conn.Protocol | Should -Be 'rdp'
        $conn.Parameters['hostname'] | Should -Be 'host.example.com'
    }

    It 'throws a terminating error for an unknown id' {
        { Get-GuacConnection -Session $session -Id 'does-not-exist' -ErrorAction Stop } | Should -Throw
    }

    It 'resolves ParentGroupName by default for connections with a parent group' {
        # Move conn-1 to group-1 to test parent resolution
        Update-GuacConnection -Session $session -Id 'conn-1' -Replace @{
            name = 'test-connection'
            protocol = 'rdp'
            parameters = @{ hostname = 'host.example.com' }
            parentIdentifier = 'group-1'
        } | Out-Null
        $conn = Get-GuacConnection -Session $session -Id 'conn-1'
        $conn.ParentGroupName | Should -Be 'prod'
        # Move it back
        Update-GuacConnection -Session $session -Id 'conn-1' -Replace @{
            name = 'test-connection'
            protocol = 'rdp'
            parameters = @{ hostname = 'host.example.com' }
            parentIdentifier = 'ROOT'
        } | Out-Null
    }

    It 'skips ParentGroupName resolution when -ResolveParentGroupName is false' {
        $conn = Get-GuacConnection -Session $session -Id 'conn-1' -ResolveParentGroupName:$false
        $conn.PSObject.Properties['ParentGroupName'] | Should -Be $null
    }

    It 'sets ParentGroupName to ROOT for top-level connections' {
        $conn = Get-GuacConnection -Session $session -Id 'conn-2'
        $conn.ParentGroupName | Should -Be 'ROOT'
    }
}

Describe 'New-GuacConnection' {
    It 'creates a connection and returns it with a server-assigned identifier' {
        $created = New-GuacConnection -Session $session -InputObject @{
            name = 'new-conn'
            protocol = 'telnet'
            parameters = @{ hostname = 'telnet.example.com' }
            parentIdentifier = 'ROOT'
        }
        $created.Identifier | Should -Not -BeNullOrEmpty
        $created.Name | Should -Be 'new-conn'
        $created.Protocol | Should -Be 'telnet'

        $fetched = Get-GuacConnection -Session $session -Id $created.Identifier
        $fetched.Name | Should -Be 'new-conn'
    }

    It 'auto-fills all protocol parameters from schema when only minimal params are provided' {
        $created = New-GuacConnection -Session $session -Name 'auto-fill-test' -Protocol 'ssh' -Parameters @{ hostname = 'ssh-host.example.com' }
        $created.Identifier | Should -Not -BeNullOrEmpty
        $created.Protocol | Should -Be 'ssh'

        # User-provided parameter should be present
        $created.Parameters['hostname'] | Should -Be 'ssh-host.example.com'

        # Other SSH parameters from the schema should be auto-filled with empty strings
        $created.Parameters.Keys | Should -Contain 'port'
        $created.Parameters.Keys | Should -Contain 'username'
        $created.Parameters.Keys | Should -Contain 'password'
        $created.Parameters.Keys | Should -Contain 'guac-readonly'
    }

    It 'honors -WhatIf by not creating the connection' {
        $before = @(Get-GuacConnection -Session $session).Count
        # NOTE: the "What if: ..." line printed above this test is the engine's
        # WhatIf confirmation, written straight to the host UI; it is NOT part of
        # the information stream and cannot be suppressed with -InformationAction
        # or $InformationPreference (verified on pwsh 7.6). It is expected output.
        New-GuacConnection -Session $session -Name 'whatif-conn' -Protocol 'telnet' -WhatIf
        $after = @(Get-GuacConnection -Session $session).Count
        $before | Should -Be $after
    }

    It 'throws when no body is supplied' {
        { New-GuacConnection -Session $session -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Update-GuacConnection' {
    It 'replaces a connection with -Replace (PUT) and re-fetches' {
        $updated = Update-GuacConnection -Session $session -Id 'conn-2' -Replace @{
            name = 'ssh-server-renamed'
            protocol = 'ssh'
            parameters = @{ hostname = 'ssh2.example.com'; port = '22' }
            parentIdentifier = 'ROOT'
        }
        $updated.Identifier | Should -Be 'conn-2'
        $updated.Name | Should -Be 'ssh-server-renamed'
        $updated.Parameters['hostname'] | Should -Be 'ssh2.example.com'
    }

    It 'applies a JSON Patch replace operation' {
        $conn = Get-GuacConnection -Session $session -Id 'conn-1'
        $conn.Name = 'renamed-conn-1'
        Update-GuacConnection -Session $session -Id 'conn-1' -Patch (
            @{ op = 'replace'; path = '/conn-1'; value = $conn }
        )
        $fetched = Get-GuacConnection -Session $session -Id 'conn-1'
        $fetched.Name | Should -Be 'renamed-conn-1'
    }

    It 'accepts a piped connection object as the target' {
        $conn = Get-GuacConnection -Session $session -Id 'conn-1'
        $conn.Name = 'piped-update'
        $conn | Update-GuacConnection -Replace $conn
        $fetched = Get-GuacConnection -Session $session -Id 'conn-1'
        $fetched.Name | Should -Be 'piped-update'
    }

    It 'rejects supplying both -Patch and -Replace' {
        { Update-GuacConnection -Session $session -Id 'conn-1' -Replace @{ name = 'x'; protocol = 'rdp' } -Patch @{ op = 'remove'; path = '/conn-1' } -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Remove-GuacConnection' {
    It 'deletes a connection by id' {
        $created = New-GuacConnection -Session $session -InputObject @{
            name = 'to-delete'; protocol = 'telnet'; parameters = @{}; parentIdentifier = 'ROOT'
        }
        Remove-GuacConnection -Session $session -Id $created.Identifier -Confirm:$false
        { Get-GuacConnection -Session $session -Id $created.Identifier -ErrorAction Stop } | Should -Throw
    }

    It 'deletes a piped connection object' {
        $created = New-GuacConnection -Session $session -InputObject @{
            name = 'to-delete-2'; protocol = 'telnet'; parameters = @{}; parentIdentifier = 'ROOT'
        }
        Get-GuacConnection -Session $session -Id $created.Identifier | Remove-GuacConnection -Confirm:$false
        { Get-GuacConnection -Session $session -Id $created.Identifier -ErrorAction Stop } | Should -Throw
    }
}
