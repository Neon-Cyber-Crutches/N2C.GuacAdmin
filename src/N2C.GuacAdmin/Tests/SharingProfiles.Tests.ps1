#Requires -Version 5.1
# Pester v5 integration tests for the N2C.GuacAdmin sharing profile cmdlets.

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

Describe 'Get-GuacSharingProfile' {
    It 'lists sharing profiles with Identifier properties' {
        $profiles = @(Get-GuacSharingProfile -Session $session)
        $ids = @($profiles | ForEach-Object { $_.Identifier })
        $ids | Should -Contain 'readonly'
    }

    It 'gets a single sharing profile by id' {
        $sh_profile = Get-GuacSharingProfile -Session $session -Id 'readonly'
        $sh_profile.Identifier | Should -Be 'readonly'
        $sh_profile.Name | Should -Be 'read-only'
        $sh_profile.PrimaryConnectionIdentifier | Should -Be 'conn-1'
        $sh_profile.Parameters['guac-readonly'] | Should -Be 'true'
    }

    It 'throws a terminating error for an unknown id' {
        { Get-GuacSharingProfile -Session $session -Id 'does-not-exist' -ErrorAction Stop } | Should -Throw
    }

    It 'resolves PrimaryConnectionName by default' {
        $sh_profile = Get-GuacSharingProfile -Session $session -Id 'readonly'
        $sh_profile.PrimaryConnectionName | Should -Be 'test-connection'
    }

    It 'skips PrimaryConnectionName resolution when -ResolveConnectionName is false' {
        $sh_profile = Get-GuacSharingProfile -Session $session -Id 'readonly' -ResolveConnectionName:$false
        $sh_profile.PSObject.Properties['PrimaryConnectionName'] | Should -Be $null
    }
}

Describe 'Get-GuacSharingProfile filters' {
    It 'filters by exact name' {
        $results = @(Get-GuacSharingProfile -Session $session -Name 'read-only')
        $results.Count | Should -Be 1
        $results[0].Name | Should -Be 'read-only'
    }

    It 'filters by name wildcard' {
        $results = @(Get-GuacSharingProfile -Session $session -Name 'read-*')
        $results.Count | Should -Be 1
        $results[0].Name | Should -Be 'read-only'
    }

    It 'returns empty when no name matches' {
        $results = @(Get-GuacSharingProfile -Session $session -Name 'nonexistent-*')
        $results.Count | Should -Be 0
    }
}

Describe 'New-GuacSharingProfile' {
    It 'creates a sharing profile' {
        $created = New-GuacSharingProfile -Session $session -Name 'new-profile' `
            -PrimaryConnection 'conn-2' -Parameters @{ 'guac-readonly' = 'false' }
        $created.Identifier | Should -Not -BeNullOrEmpty
        $created.Name | Should -Be 'new-profile'
        $created.PrimaryConnectionIdentifier | Should -Be 'conn-2'
    }

    It 'throws when no body is supplied' {
        { New-GuacSharingProfile -Session $session -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Update-GuacSharingProfile' {
    It 'replaces a sharing profile with -Replace' {
        $updated = Update-GuacSharingProfile -Session $session -Id 'readonly' -Replace @{
            name = 'read-only-v2'
            primaryConnectionIdentifier = 'conn-1'
            parameters = @{ 'guac-readonly' = 'true' }
        }
        $updated.Identifier | Should -Be 'readonly'
        $updated.Name | Should -Be 'read-only-v2'
    }

    It 'rejects supplying both -Patch and -Replace' {
        { Update-GuacSharingProfile -Session $session -Id 'readonly' -Replace @{ name = 'x' } -Patch @{ op = 'remove'; path = '/readonly' } -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Remove-GuacSharingProfile' {
    It 'deletes a sharing profile by id' {
        $created = New-GuacSharingProfile -Session $session -Name 'to-delete' -PrimaryConnection 'conn-1'
        Remove-GuacSharingProfile -Session $session -Id $created.Identifier -Confirm:$false
        { Get-GuacSharingProfile -Session $session -Id $created.Identifier -ErrorAction Stop } | Should -Throw
    }
}
