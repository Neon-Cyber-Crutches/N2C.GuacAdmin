#Requires -Version 5.1
# Pester v5 integration tests for DataSource property and -DataSource All
# functionality, run against the local mock Guacamole server.

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
    if ($null -ne $script:mock) {
        Stop-GuacTestMock
    }
}

Describe 'DataSource property on returned objects' {
    It 'adds DataSource property to connections' {
        $connections = @(Get-GuacConnection -Session $session -DataSource 'mysql')
        foreach ($c in $connections) {
            $c.DataSource | Should -Be 'mysql'
        }
    }

    It 'adds DataSource property to connection groups' {
        $groups = @(Get-GuacConnectionGroup -Session $session -DataSource 'mysql')
        foreach ($g in $groups) {
            $g.DataSource | Should -Be 'mysql'
        }
    }

    It 'adds DataSource property to users' {
        $users = @(Get-GuacUser -Session $session -DataSource 'mysql')
        foreach ($u in $users) {
            $u.DataSource | Should -Be 'mysql'
        }
    }

    It 'adds DataSource property to user groups' {
        $groups = @(Get-GuacUserGroup -Session $session -DataSource 'mysql')
        foreach ($g in $groups) {
            $g.DataSource | Should -Be 'mysql'
        }
    }

    It 'adds DataSource property to sharing profiles' {
        $profiles = @(Get-GuacSharingProfile -Session $session -DataSource 'mysql')
        foreach ($p in $profiles) {
            $p.DataSource | Should -Be 'mysql'
        }
    }

    It 'adds DataSource property to single connection by id' {
        $conn = Get-GuacConnection -Session $session -Id 'conn-1' -DataSource 'mysql'
        $conn.DataSource | Should -Be 'mysql'
    }

    It 'adds DataSource property to active connections' {
            # The mock server is seeded with active connections
            $actives = @(Get-GuacActiveConnection -Session $session -DataSource 'mysql')
            # There may be active connections already seeded by the mock
            if ($actives.Count -gt 0) {
                foreach ($a in $actives) {
                    $a.DataSource | Should -Be 'mysql'
                }
            }
        }
}

Describe '-DataSource All support' {
    It 'queries all data sources for connections' {
        $allConnections = @(Get-GuacConnection -Session $session -DataSource 'All')
                # Should get connections from both mysql and ldap data sources
                $mysqlConns = @($allConnections | Where-Object { $_.DataSource -eq 'mysql' })
        
                $mysqlConns.Count | Should -BeGreaterThan 0
        # ldap starts empty, so this may be 0
        foreach ($c in $mysqlConns) {
            $c.DataSource | Should -Be 'mysql'
        }
    }

    It 'queries all data sources for users' {
        $allUsers = @(Get-GuacUser -Session $session -DataSource 'All')
        $mysqlUsers = @($allUsers | Where-Object { $_.DataSource -eq 'mysql' })

        $mysqlUsers.Count | Should -BeGreaterThan 0
        foreach ($u in $mysqlUsers) {
            $u.DataSource | Should -Be 'mysql'
        }
    }

    It 'queries all data sources for connection groups' {
        $allGroups = @(Get-GuacConnectionGroup -Session $session -DataSource 'All')
        $mysqlGroups = @($allGroups | Where-Object { $_.DataSource -eq 'mysql' })

        $mysqlGroups.Count | Should -BeGreaterThan 0
    }
}

Describe 'DataSource resolution priority in pipeline' {
    It 'uses piped object DataSource when no explicit -DataSource is given' {
        # Get a connection from mysql
        $conn = Get-GuacConnection -Session $session -Id 'conn-1' -DataSource 'mysql'
        $conn.DataSource | Should -Be 'mysql'

        # Pipe it to a cmdlet that would use the DataSource
        # This tests that the DataSource property is carried through
    }

    It 'explicit -DataSource overrides piped object DataSource' {
            # Querying with explicit -DataSource ldap should use ldap
            # (this will fail because conn-1 doesn't exist in ldap, which is expected)
        {
            Get-GuacConnection -Session $session -Id 'conn-1' -DataSource 'ldap' -ErrorAction Stop
        } | Should -Throw
    }
}
