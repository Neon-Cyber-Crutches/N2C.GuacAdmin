#Requires -Version 5.1
# Pester v5 integration tests for the N2C.GuacAdmin permission cmdlets.

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
    $script:session = New-GuacSession -Server $script:mock.BaseUrl -Credential $script:credential

    # Defined inside BeforeAll (not at file scope) so that Pester v5 can see
    # it from It-block execution scope.
    function ConvertTo-GuacTestMap {
        # Recursively converts PSCustomObject (ConvertFrom-Json output) into
        # hashtables so that $set.ConnectionPermissions['conn-1'] indexing works
        # on every PowerShell version.
        param ($Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            $map = @{}
            foreach ($prop in $Value.PSObject.Properties) {
                $map[$prop.Name] = (ConvertTo-GuacTestMap -Value $prop.Value)
            }
            return $map
        }
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            $items = @()
            foreach ($item in $Value) { $items += (ConvertTo-GuacTestMap -Value $item) }
            return $items
        }
        return $Value
    }
    function Get-TestPermissionSet {
        param ([string] $Subject, [string] $Id)
        $collection = if ($Subject -eq 'user') { 'users' } else { 'userGroups' }
        $response = Invoke-WebRequest -Uri ($script:mock.BaseUrl + '/api/session/data/mysql/' + $collection + '/' + $Id + '/permissions') `
            -Headers @{ 'Guacamole-Token' = $script:session.Token } -UseBasicParsing
        return (ConvertTo-GuacTestMap -Value ($response.Content | ConvertFrom-Json))
    }
}

AfterAll {
    if ($null -ne $mock) {
        Stop-GuacTestMock
    }
}

Describe 'Add-GuacPermission' {
    It 'grants a connection permission to a user' {
        Add-GuacPermission -Session $session -User 'jdoe' -Connection 'conn-2' -Permission 'UPDATE'

        $set = Get-TestPermissionSet -Subject 'user' -Id 'jdoe'
        $types = @($set.ConnectionPermissions['conn-2'])
        $types | Should -Contain 'UPDATE'
    }

    It 'grants a connection group permission to a user group' {
        Add-GuacPermission -Session $session -UserGroup 'auditors' -ConnectionGroup 'group-1' -Permission 'READ'

        $set = Get-TestPermissionSet -Subject 'userGroup' -Id 'auditors'
        $types = @($set.ConnectionGroupPermissions['group-1'])
        $types | Should -Contain 'READ'
    }

    It 'grants a system permission' {
        Add-GuacPermission -Session $session -User 'jdoe' -System -Permission 'AUDIT'

        $set = Get-TestPermissionSet -Subject 'user' -Id 'jdoe'
        @($set.SystemPermissions) | Should -Contain 'AUDIT'
    }

    It 'accepts a piped user object as the subject' {
        Get-GuacUser -Session $session -Id 'jdoe' | Add-GuacPermission -Connection 'conn-1' -Permission 'DELETE'

        $set = Get-TestPermissionSet -Subject 'user' -Id 'jdoe'
        $types = @($set.ConnectionPermissions['conn-1'])
        $types | Should -Contain 'DELETE'
    }

    It 'rejects an object permission type on -System' {
        { Add-GuacPermission -Session $session -User 'jdoe' -System -Permission 'READ' -ErrorAction Stop } | Should -Throw
    }

    It 'rejects a system permission type on an object target' {
        { Add-GuacPermission -Session $session -User 'jdoe' -Connection 'conn-1' -Permission 'AUDIT' -ErrorAction Stop } | Should -Throw
    }

    It 'requires a subject' {
        { Add-GuacPermission -Session $session -Connection 'conn-1' -Permission 'READ' -ErrorAction Stop } | Should -Throw
    }

    It 'sends a single-operation PATCH with the correct wire format' {
        Add-GuacPermission -Session $session -User 'jdoe' -Connection 'conn-2' -Permission 'ADMINISTER'

        $requests = Get-GuacMockLog -FilterPath '/api/session/data/mysql/users/jdoe/permissions'
        $last = $requests[-1]
        $last.method | Should -Be 'PATCH'
        $decoded = $last.body | ConvertFrom-Json
        $operations = @($decoded)
        $operations[0].op | Should -Be 'add'
        $operations[0].path | Should -Be '/connectionPermissions/conn-2'
        $operations[0].value | Should -Be 'ADMINISTER'
    }
}

Describe 'Remove-GuacPermission' {
    It 'revokes a previously granted connection permission' {
        Add-GuacPermission -Session $session -User 'jdoe' -Connection 'conn-1' -Permission 'UPDATE'
        $set = Get-TestPermissionSet -Subject 'user' -Id 'jdoe'
        @($set.ConnectionPermissions['conn-1']) | Should -Contain 'UPDATE'

        Remove-GuacPermission -Session $session -User 'jdoe' -Connection 'conn-1' -Permission 'UPDATE'
        $set = Get-TestPermissionSet -Subject 'user' -Id 'jdoe'
        $types = @($set.ConnectionPermissions['conn-1'])
        $types | Should -Not -Contain 'UPDATE'
    }

    It 'revokes a system permission' {
        Add-GuacPermission -Session $session -UserGroup 'auditors' -System -Permission 'CREATE_USER'
        Remove-GuacPermission -Session $session -UserGroup 'auditors' -System -Permission 'CREATE_USER'

        $set = Get-TestPermissionSet -Subject 'userGroup' -Id 'auditors'
        @($set.SystemPermissions) | Should -Not -Contain 'CREATE_USER'
    }

    It 'sends a remove operation with the permission type as value' {
        Remove-GuacPermission -Session $session -User 'jdoe' -Connection 'conn-1' -Permission 'DELETE'

        $requests = Get-GuacMockLog -FilterPath '/api/session/data/mysql/users/jdoe/permissions'
        $last = $requests[-1]
        $decoded = $last.body | ConvertFrom-Json
        $operations = @($decoded)
        $operations[0].op | Should -Be 'remove'
        $operations[0].path | Should -Be '/connectionPermissions/conn-1'
        $operations[0].value | Should -Be 'DELETE'
    }
}
