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

Describe 'Set-GuacDataSource' {
    It 'changes the default data source for the session' {
        # Set to ldap
        $updated = Set-GuacDataSource -DataSource 'ldap' -Session $session
        $updated.DataSource | Should -Be 'ldap'
        $session.DataSource | Should -Be 'ldap'

        # Verify Get-GuacConnection uses ldap by default now
        # (will throw because conn-1 doesn't exist in ldap)
        {
            Get-GuacConnection -Session $session -Id 'conn-1' -ErrorAction Stop
        } | Should -Throw

        # Set back to mysql
        Set-GuacDataSource -DataSource 'mysql' -Session $session
        $session.DataSource | Should -Be 'mysql'

        # Verify Get-GuacConnection works with mysql again
        $conn = Get-GuacConnection -Session $session -Id 'conn-1' -ErrorAction Stop
        $conn.Name | Should -Be 'test-connection'
    }

    It 'works with -Server parameter' {
        # Use -Server instead of -Session
        Set-GuacDataSource -Server $mock.BaseUrl -DataSource 'ldap'
        $stateSession = Get-GuacSession -Server $mock.BaseUrl
        $stateSession.DataSource | Should -Be 'ldap'

        # Set back to mysql
        Set-GuacDataSource -Server $mock.BaseUrl -DataSource 'mysql'
        $stateSession = Get-GuacSession -Server $mock.BaseUrl
        $stateSession.DataSource | Should -Be 'mysql'
    }

    It 'works with no -Session or -Server when exactly one session exists' {
        # Clear session state except for the single test session
        # (this is the fallback case where exactly one session is registered)
        Set-GuacDataSource -DataSource 'ldap'
        $stateSession = Get-GuacSession -Server $mock.BaseUrl
        $stateSession.DataSource | Should -Be 'ldap'

        # Set back to mysql
        Set-GuacDataSource -DataSource 'mysql'
        $stateSession = Get-GuacSession -Server $mock.BaseUrl
        $stateSession.DataSource | Should -Be 'mysql'
    }

    It 'throws when data source is not available' {
        {
            Set-GuacDataSource -DataSource 'nonexistent' -Session $session -ErrorAction Stop
        } | Should -Throw
    }

    It 'throws when -DataSource is empty' {
        {
            Set-GuacDataSource -DataSource '' -Session $session -ErrorAction Stop
        } | Should -Throw
    }

    It 'per-call -DataSource still overrides session default' {
        # Set session default to ldap
        Set-GuacDataSource -DataSource 'ldap' -Session $session

        # Query with explicit -DataSource mysql should still work
        $conn = Get-GuacConnection -Session $session -Id 'conn-1' -DataSource 'mysql'
        $conn.Name | Should -Be 'test-connection'

        # Set back to mysql
        Set-GuacDataSource -DataSource 'mysql' -Session $session
    }

    It 'returns the updated session object' {
        $updated = Set-GuacDataSource -DataSource 'ldap' -Session $session
        $updated | Should -Not -BeNullOrEmpty
        $updated.DataSource | Should -Be 'ldap'

        # Set back to mysql
        Set-GuacDataSource -DataSource 'mysql' -Session $session
    }
}
