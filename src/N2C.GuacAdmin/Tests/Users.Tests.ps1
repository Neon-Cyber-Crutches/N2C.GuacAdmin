#Requires -Version 5.1
# Pester v5 integration tests for the N2C.GuacAdmin user cmdlets.

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

Describe 'Get-GuacUser' {
    It 'lists users with Identifier (username) properties' {
        $users = @(Get-GuacUser -Session $session)
        $usernames = @($users | ForEach-Object { $_.Identifier })
        $usernames | Should -Contain 'guacadmin'
        $usernames | Should -Contain 'jdoe'
    }

    It 'gets a single user by username' {
        $user = Get-GuacUser -Session $session -Id 'jdoe'
        $user.Identifier | Should -Be 'jdoe'
        $user.Username | Should -Be 'jdoe'
        $user.Disabled | Should -BeFalse
    }

    It 'attaches the permission set with -Permissions' {
        $user = Get-GuacUser -Session $session -Id 'jdoe' -Permissions
        $user.Permissions | Should -Not -BeNullOrEmpty
        $connPerms = $user.Permissions.ConnectionPermissions
        $keys = @()
        if ($connPerms -is [System.Collections.IDictionary]) { $keys = @($connPerms.Keys) }
        else { $keys = @($connPerms.PSObject.Properties.Name) }
        $keys | Should -Contain 'conn-1'
    }

    It 'attaches the effective permission set with -EffectivePermissions' {
        $user = Get-GuacUser -Session $session -Id 'jdoe' -EffectivePermissions
        $user.EffectivePermissions | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-GuacUser filters' {
    It 'filters by exact username' {
        $results = @(Get-GuacUser -Session $session -Name 'jdoe')
        $results.Count | Should -Be 1
        $results[0].Username | Should -Be 'jdoe'
    }

    It 'filters by username wildcard' {
        $results = @(Get-GuacUser -Session $session -Name 'j*')
        $results.Count | Should -Be 1
        $results[0].Username | Should -Be 'jdoe'
    }
}

Describe 'New-GuacUser' {
    It 'creates a user from a PSCredential' {
        $cred = [PSCredential]::new(
            'newuser',
            (ConvertTo-SecureString 'newuser-pass' -AsPlainText -Force)
        )
        $created = New-GuacUser -Session $session -Credential $cred
        $created.Identifier | Should -Be 'newuser'
        $created.Username | Should -Be 'newuser'

        $fetched = Get-GuacUser -Session $session -Id 'newuser'
        $fetched.Password | Should -Be 'newuser-pass'
    }

    It 'throws when no body is supplied' {
        { New-GuacUser -Session $session -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Update-GuacUser' {
    It 'replaces a user with -Replace' {
        $updated = Update-GuacUser -Session $session -Id 'jdoe' -Replace @{
            disabled = $true
            attributes = @{ 'guac-full-name' = 'John Doe' }
        }
        $updated.Identifier | Should -Be 'jdoe'
        $updated.Disabled | Should -BeTrue
    }

    It 'preserves the password when it is omitted from the body' {
        Update-GuacUser -Session $session -Id 'jdoe' -Replace @{ disabled = $false; attributes = @{} }
        $fetched = Get-GuacUser -Session $session -Id 'jdoe'
        $fetched.Password | Should -Be 'jdoe-pass'
    }

    It 'rejects a self password change through the update endpoint' {
        Update-GuacUser -Session $session -Id 'guacadmin' -Replace @{
            disabled = $false
            attributes = @{}
        } | Out-Null
        # The mock stores the seeded password; supply it to trip the guard.
        { 
            Update-GuacUser -Session $session -Id 'guacadmin' -Replace @{
                password = 'hacked'
                disabled = $false
                attributes = @{}
            } -ErrorAction Stop
        } | Should -Throw
    }
}

Describe 'Set-GuacUserPassword' {
    It 'changes a password with the correct old password' {
        Set-GuacUserPassword -Session $session -Id 'jdoe' `
            -OldPassword (ConvertTo-SecureString 'jdoe-pass' -AsPlainText -Force) `
            -NewPassword (ConvertTo-SecureString 'jdoe-pass-2' -AsPlainText -Force)
        $fetched = Get-GuacUser -Session $session -Id 'jdoe'
        $fetched.Password | Should -Be 'jdoe-pass-2'

        # Restore.
        Set-GuacUserPassword -Session $session -Id 'jdoe' `
            -OldPassword (ConvertTo-SecureString 'jdoe-pass-2' -AsPlainText -Force) `
            -NewPassword (ConvertTo-SecureString 'jdoe-pass' -AsPlainText -Force)
    }

    It 'rejects a wrong old password' {
        {
            Set-GuacUserPassword -Session $session -Id 'jdoe' `
                -OldPassword (ConvertTo-SecureString 'wrong' -AsPlainText -Force) `
                -NewPassword (ConvertTo-SecureString 'x' -AsPlainText -Force) `
                -ErrorAction Stop
        } | Should -Throw
    }
}

Describe 'Remove-GuacUser' {
    It 'deletes a user by username' {
        $cred = [PSCredential]::new(
            'todelete',
            (ConvertTo-SecureString 'pass' -AsPlainText -Force)
        )
        New-GuacUser -Session $session -Credential $cred
        Remove-GuacUser -Session $session -Id 'todelete' -Confirm:$false
        { Get-GuacUser -Session $session -Id 'todelete' -ErrorAction Stop } | Should -Throw
    }
}
