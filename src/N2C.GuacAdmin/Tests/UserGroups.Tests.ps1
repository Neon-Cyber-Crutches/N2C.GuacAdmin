#Requires -Version 5.1
# Pester v5 integration tests for the N2C.GuacAdmin user group cmdlets and
# the membership cmdlets (memberUsers / memberUserGroups).

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

Describe 'Get-GuacUserGroup' {
    It 'lists user groups with Identifier properties' {
        $groups = @(Get-GuacUserGroup -Session $session)
        $names = @($groups | ForEach-Object { $_.Identifier })
        $names | Should -Contain 'admins'
        $names | Should -Contain 'auditors'
    }

    It 'gets a single user group by id' {
        $group = Get-GuacUserGroup -Session $session -Id 'auditors'
        $group.Identifier | Should -Be 'auditors'
        $group.Disabled | Should -BeFalse
    }
}

Describe 'New-GuacUserGroup' {
    It 'creates a user group' {
        $created = New-GuacUserGroup -Session $session -Identifier 'newgroup' -Disabled $false
        $created.Identifier | Should -Be 'newgroup'
    }

    It 'requires an identifier' {
        { New-GuacUserGroup -Session $session -Disabled $false -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Update-GuacUserGroup' {
    It 'replaces a user group with -Replace' {
        $updated = Update-GuacUserGroup -Session $session -Id 'auditors' -Replace @{
            disabled = $true
            attributes = @{ 'guac-description' = 'Read-only auditors' }
        }
        $updated.Identifier | Should -Be 'auditors'
        $updated.Disabled | Should -BeTrue

        # Restore.
        Update-GuacUserGroup -Session $session -Id 'auditors' -Replace @{ disabled = $false; attributes = @{} }
    }
}

Describe 'Remove-GuacUserGroup' {
    It 'deletes a user group by id' {
        New-GuacUserGroup -Session $session -Identifier 'todelete'
        Remove-GuacUserGroup -Session $session -Id 'todelete' -Confirm:$false
        { Get-GuacUserGroup -Session $session -Id 'todelete' -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Add/Remove-GuacUserGroupMember' {
    It 'adds and removes a user from a group''s memberUsers set' {
        New-GuacUserGroup -Session $session -Identifier 'member-test'
        try {
            Add-GuacUserGroupMember -Session $session -UserGroup 'member-test' -Member 'jdoe'

            $members = @(Invoke-WebRequest -Uri ($mock.BaseUrl + '/api/session/data/mysql/userGroups/member-test/memberUsers') -Headers @{ 'Guacamole-Token' = $session.Token } -UseBasicParsing).Content | ConvertFrom-Json
            @($members) | Should -Contain 'jdoe'

            Remove-GuacUserGroupMember -Session $session -UserGroup 'member-test' -Member 'jdoe'
            $members = @(Invoke-WebRequest -Uri ($mock.BaseUrl + '/api/session/data/mysql/userGroups/member-test/memberUsers') -Headers @{ 'Guacamole-Token' = $session.Token } -UseBasicParsing).Content | ConvertFrom-Json
            @($members) | Should -Not -Contain 'jdoe'
        }
        finally {
            Remove-GuacUserGroup -Session $session -Id 'member-test' -Confirm:$false
        }
    }

    It 'rejects adding a user that does not exist' {
        { Add-GuacUserGroupMember -Session $session -UserGroup 'auditors' -Member 'ghost' -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Add/Remove-GuacUserGroupChildGroup' {
    It 'adds and removes a child group from memberUserGroups' {
        New-GuacUserGroup -Session $session -Identifier 'child-test'
        New-GuacUserGroup -Session $session -Identifier 'child-test-child'
        try {
            Add-GuacUserGroupChildGroup -Session $session -UserGroup 'child-test' -ChildGroup 'child-test-child'

            $children = @(Invoke-WebRequest -Uri ($mock.BaseUrl + '/api/session/data/mysql/userGroups/child-test/memberUserGroups') -Headers @{ 'Guacamole-Token' = $session.Token } -UseBasicParsing).Content | ConvertFrom-Json
            @($children) | Should -Contain 'child-test-child'

            Remove-GuacUserGroupChildGroup -Session $session -UserGroup 'child-test' -ChildGroup 'child-test-child'
        }
        finally {
            Remove-GuacUserGroup -Session $session -Id 'child-test-child' -Confirm:$false
            Remove-GuacUserGroup -Session $session -Id 'child-test' -Confirm:$false
        }
    }
}
