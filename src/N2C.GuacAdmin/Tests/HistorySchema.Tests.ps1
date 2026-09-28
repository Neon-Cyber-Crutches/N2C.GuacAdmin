#Requires -Version 5.1
# Pester v5 integration tests for the N2C.GuacAdmin history and schema cmdlets.

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

Describe 'Get-GuacHistoryConnections' {
    It 'returns connection history records' {
        $records = @(Get-GuacHistoryConnections -Session $session)
        $records.Count | Should -BeGreaterOrEqual 1
        $records[0].ConnectionName | Should -Be 'test-connection'
        $records[0].Username | Should -Be 'guacadmin'
    }

    It 'converts history record startDate and endDate to [DateTime] UTC' {
        $records = @(Get-GuacHistoryConnections -Session $session)
        $records.Count | Should -BeGreaterOrEqual 1
        $records[0].StartDate | Should -BeOfType [DateTime]
        $records[0].EndDate | Should -BeOfType [DateTime]
        $records[0].StartDate.Kind | Should -Be 'Utc'
        $records[0].EndDate.Kind | Should -Be 'Utc'
        # Mock server uses epoch 1767261600000 = 2026-01-01 10:00:00 UTC
        $records[0].StartDate.Year | Should -Be 2026
        $records[0].StartDate.Month | Should -Be 1
        $records[0].StartDate.Day | Should -Be 1
    }

    It 'converts history record duration to [TimeSpan]' {
        $records = @(Get-GuacHistoryConnections -Session $session)
        $records.Count | Should -BeGreaterOrEqual 1
        $records[0].Duration | Should -BeOfType [TimeSpan]
        $records[0].Duration.TotalSeconds | Should -Be 1800
    }

    It 'passes -Contains and -Order as query parameters' {
        Get-GuacHistoryConnections -Session $session -Contains 'guacadmin' -Order '-startDate' | Out-Null

        $requests = Get-GuacMockLog -FilterPath '/api/session/data/mysql/history/connections'
        $last = $requests[-1]
        $last.query | Should -BeLike '*contains=guacadmin*'
        $last.query | Should -BeLike '*order=-startDate*'
    }
}

Describe 'Get-GuacHistoryUsers' {
    It 'returns user history records' {
        $records = @(Get-GuacHistoryUsers -Session $session)
        $records.Count | Should -BeGreaterOrEqual 1
        $records[0].Username | Should -Be 'guacadmin'
        $records[0].Identifier | Should -Not -BeNullOrEmpty
        $records[0].Uuid | Should -Not -BeNullOrEmpty
    }

    It 'filters user history client-side by username (-Contains)' {
        # User history uses client-side filtering because the upstream Guacamole
        # JDBC mapper has an SQL bug when using the "contains" query parameter.
        $records = @(Get-GuacHistoryUsers -Session $session -Contains 'guacadmin' -Order '-startDate')
        $records.Count | Should -BeGreaterOrEqual 1
        foreach ($rec in $records) {
            $rec.Username | Should -Be 'guacadmin'
        }
    }

    It 'does not pass -Contains as a query parameter for user history' {
        Get-GuacHistoryUsers -Session $session -Contains 'guacadmin' -Order '-startDate' | Out-Null

        $requests = Get-GuacMockLog -FilterPath '/api/session/data/mysql/history/users'
        $last = $requests[-1]
        $last.query | Should -Not -BeLike '*contains=*'
        $last.query | Should -BeLike '*order=-startDate*'
    }

    It 'filters user history client-side by remoteHost' {
        $records = @(Get-GuacHistoryUsers -Session $session -Contains '10.0.0.5')
        $records.Count | Should -BeGreaterOrEqual 1
        foreach ($rec in $records) {
            $rec.RemoteHost | Should -Be '10.0.0.5'
        }
    }

    It 'returns no records when -Contains matches nothing' {
        $records = @(Get-GuacHistoryUsers -Session $session -Contains 'nonexistent-user-xyz')
        $records.Count | Should -Be 0
    }
}

Describe 'Get-GuacSchema' {
    It 'returns a single attribute set by name' {
        $forms = @(Get-GuacSchema -Session $session -Set ConnectionAttributes)
        $forms.Count | Should -BeGreaterOrEqual 1
        $identifiers = @($forms | ForEach-Object { $_.Identifier })
        $identifiers | Should -Contain 'guac-readonly'
    }

    It 'returns all attribute sets tagged with schemaSet when -Set is omitted' {
        $all = @(Get-GuacSchema -Session $session)
        $sets = @($all | ForEach-Object { $_.schemaSet } | Select-Object -Unique)
        $sets | Should -Contain 'ConnectionAttributes'
        $sets | Should -Contain 'UserAttributes'
        $sets | Should -Contain 'SharingProfileAttributes'
        $sets | Should -Contain 'UserGroupAttributes'
        $sets | Should -Contain 'ConnectionGroupAttributes'
        $sets | Should -Contain 'UserPreferenceAttributes'
    }

    It 'returns the protocols set' {
        $result = Get-GuacSchema -Session $session -Set Protocols
        $result | Should -Not -BeNullOrEmpty
        $names = @()
        foreach ($prop in $result.PSObject.Properties) { $names += $prop.Name }
        $names | Should -Contain 'ssh'
        $names | Should -Contain 'rdp'
    }
}

Describe 'Get-GuacProtocol' {
    It 'returns one object per protocol with a Protocol property' {
        $protocols = @(Get-GuacProtocol -Session $session)
        $names = @($protocols | ForEach-Object { $_.Protocol })
        $names | Should -Contain 'ssh'
        $names | Should -Contain 'rdp'
        $ssh = $protocols | Where-Object { $_.Protocol -eq 'ssh' }
        $ssh.ConnectionForms | Should -Not -BeNullOrEmpty
        $ssh.Name | Should -Be 'ssh'
    }

    It 'selects a single protocol by name' {
        $protocol = Get-GuacProtocol -Session $session -Name 'vnc'
        $protocol.Protocol | Should -Be 'vnc'
    }

    It 'throws for an unknown protocol' {
        { Get-GuacProtocol -Session $session -Name 'nope' -ErrorAction Stop } | Should -Throw
    }
}
