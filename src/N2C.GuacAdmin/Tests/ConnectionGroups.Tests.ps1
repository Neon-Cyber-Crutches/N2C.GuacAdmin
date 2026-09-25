#Requires -Version 5.1
# Pester v5 integration tests for the N2C.GuacAdmin connection group cmdlets.

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

Describe 'Get-GuacConnectionGroup' {
    It 'lists groups with Identifier properties' {
        $groups = @(Get-GuacConnectionGroup -Session $session)
        $groups.Count | Should -BeGreaterOrEqual 2
        foreach ($g in $groups) {
            $g.Identifier | Should -Not -BeNullOrEmpty
        }
    }

    It 'gets a single group by id' {
        $group = Get-GuacConnectionGroup -Session $session -Id 'group-1'
        $group.Identifier | Should -Be 'group-1'
        $group.Name | Should -Be 'prod'
        $group.Type | Should -Be 'ORGANIZATIONAL'
    }

    # TODO: Fix -Tree parameter (Issue #1). The mock server returns a tree
    # response that Invoke-GuacDirectory tries to treat as a map of entries.
    It 'returns a group tree with descendants under -Tree' -Skip {
        $tree = Get-GuacConnectionGroup -Session $session -Id 'group-1' -Tree
        $tree.Identifier | Should -Be 'group-1'
        $children = @($tree.ChildConnectionGroups)
        $childIds = @($children | ForEach-Object {
            if ($_ -is [System.Collections.IDictionary]) { $_.Keys | ForEach-Object { $_ } }
            else { $_.PSObject.Properties.Name }
        })
        $childIds | Should -Contain 'group-2'
    }

    It 'resolves ParentGroupName by default for groups with a parent' {
        $group = Get-GuacConnectionGroup -Session $session -Id 'group-2'
        $group.ParentGroupName | Should -Be 'prod'
    }

    It 'sets ParentGroupName to ROOT for top-level groups' {
        $group = Get-GuacConnectionGroup -Session $session -Id 'group-1'
        $group.ParentGroupName | Should -Be 'ROOT'
    }

    It 'skips ParentGroupName resolution when -ResolveParentGroupName is false' {
        $group = Get-GuacConnectionGroup -Session $session -Id 'group-2' -ResolveParentGroupName:$false
        $group.PSObject.Properties['ParentGroupName'] | Should -Be $null
    }
}

Describe 'New-GuacConnectionGroup' {
    It 'creates a group with a server-assigned identifier' {
        $created = New-GuacConnectionGroup -Session $session -Name 'new-group' -Type 'ORGANIZATIONAL' -Parent 'ROOT'
        $created.Identifier | Should -Not -BeNullOrEmpty
        $created.Name | Should -Be 'new-group'
    }

    It 'throws when no body is supplied' {
        { New-GuacConnectionGroup -Session $session -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Update-GuacConnectionGroup' {
    It 'replaces a group with -Replace and re-fetches' {
        $updated = Update-GuacConnectionGroup -Session $session -Id 'group-2' -Replace @{
            name = 'staging-renamed'
            type = 'BALANCING'
            parentIdentifier = 'ROOT'
        }
        $updated.Identifier | Should -Be 'group-2'
        $updated.Name | Should -Be 'staging-renamed'
        $updated.Type | Should -Be 'BALANCING'
    }

    It 'rejects supplying both -Patch and -Replace' {
        { Update-GuacConnectionGroup -Session $session -Id 'group-2' -Replace @{ name = 'x' } -Patch @{ op = 'remove'; path = '/group-2' } -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Remove-GuacConnectionGroup' {
    It 'deletes a group by id' {
        $created = New-GuacConnectionGroup -Session $session -Name 'to-delete' -Type 'ORGANIZATIONAL' -Parent 'ROOT'
        Remove-GuacConnectionGroup -Session $session -Id $created.Identifier -Confirm:$false
        { Get-GuacConnectionGroup -Session $session -Id $created.Identifier -ErrorAction Stop } | Should -Throw
    }
}
