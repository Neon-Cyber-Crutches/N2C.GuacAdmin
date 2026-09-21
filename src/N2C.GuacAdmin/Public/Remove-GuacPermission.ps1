function Remove-GuacPermission {
    <#
    .SYNOPSIS
        Revokes a permission from a Guacamole user or user group.

    .DESCRIPTION
        Removes one permission from the permission set of a subject (a user or
        a user group) by sending a single-operation JSON Patch to the
        subject's permissions endpoint (PermissionSetResource.patchPermissions):
        - user:      PATCH .../users/{username}/permissions
        - user group: PATCH .../userGroups/{id}/permissions

        The subject is given by -User (a username), -UserGroup (a group
        identifier), or by piping the subject object (a user from
        Get-GuacUser or a user group from Get-GuacUserGroup). Exactly one
        subject must be supplied.

        The permission target is exactly one of: -Connection,
        -ConnectionGroup, -SharingProfile, -TargetUser, -TargetUserGroup, or
        -System. The -Permission type must match the target (object targets:
        READ, UPDATE, DELETE, ADMINISTER; -System: the system permission
        types). The wire operation is { "op": "remove", "path": ..., "value":
        "<permission type>" }.

        Removing a permission that is not granted is a no-op on the server
        (the PermissionSetPatch queues a remove for a permission that is
        absent).

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/user/UserResource.java
          (getPermissions: @Path("permissions"))
        - guacamole/src/main/java/org/apache/guacamole/rest/usergroup/UserGroupResource.java
          (getPermissions: @Path("permissions"))
        - guacamole/src/main/java/org/apache/guacamole/rest/permission/PermissionSetResource.java
          (patchPermissions: add/remove)
        - guacamole/src/main/java/org/apache/guacamole/rest/permission/PermissionSetPatch.java
          (removePermission)

    .EXAMPLE
        Remove-GuacPermission -User 'jdoe' -Connection 'conn-id' -Permission READ

    .EXAMPLE
        Remove-GuacPermission -UserGroup 'auditors' -System -Permission AUDIT

    .EXAMPLE
        Get-GuacUserGroup -Id 'auditors' | Remove-GuacPermission -Connection 'conn-id' -Permission UPDATE
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [N2C_GuacAdmin_GuacSession] $Session,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Server = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $DataSource = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $User = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $UserGroup = [string]::Empty,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Connection = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $ConnectionGroup = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $SharingProfile = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $TargetUser = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $TargetUserGroup = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [switch] $System,

        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('READ', 'UPDATE', 'DELETE', 'ADMINISTER', 'CREATE_USER', 'CREATE_USER_GROUP', 'CREATE_CONNECTION', 'CREATE_CONNECTION_GROUP', 'CREATE_SHARING_PROFILE', 'AUDIT')]
        [string] $Permission
    )

    begin {
        $pendingSubject = [ordered]@{}
    }

    process {
        if ($null -ne $InputObject) {
            $username = [string]::Empty
            if ($InputObject.PSObject.Properties.Match('username').Count -gt 0) {
                $username = [string]$InputObject.username
            }
            if (-not [string]::IsNullOrWhiteSpace($username)) {
                $pendingSubject = [ordered]@{ Type = 'user'; Id = $username }
            }
            else {
                $pendingSubject = [ordered]@{ Type = 'userGroup'; Id = (Get-GuacIdentifier -Object $InputObject) }
            }
        }
    }

    end {
        $subjectType = [string]::Empty
        $subjectId = [string]::Empty
        if (-not [string]::IsNullOrWhiteSpace($User)) {
            $subjectType = 'user'
            $subjectId = $User
        }
        elseif (-not [string]::IsNullOrWhiteSpace($UserGroup)) {
            $subjectType = 'userGroup'
            $subjectId = $UserGroup
        }
        elseif ($pendingSubject.Count -gt 0) {
            $subjectType = [string]$pendingSubject['Type']
            $subjectId = [string]$pendingSubject['Id']
        }
        if ([string]::IsNullOrWhiteSpace($subjectType)) {
            throw ($script:GuacRestExceptionType::new(
                'Remove-GuacPermission requires the permission subject: supply -User or -UserGroup, or pipe a user / user group object.'
            ))
        }

        $objectTypes = @('READ', 'UPDATE', 'DELETE', 'ADMINISTER')
        $systemTypes = @('CREATE_USER', 'CREATE_USER_GROUP', 'CREATE_CONNECTION', 'CREATE_CONNECTION_GROUP', 'CREATE_SHARING_PROFILE', 'AUDIT', 'ADMINISTER')
        if ($System) {
            if ($systemTypes -notcontains $Permission) {
                throw ($script:GuacRestExceptionType::new(
                    ('Remove-GuacPermission: {0} is not a system permission. Valid system permissions: {1}' -f ($Permission, ($systemTypes -join ', ')))
                ))
            }
        }
        else {
            if ($objectTypes -notcontains $Permission) {
                throw ($script:GuacRestExceptionType::new(
                    ('Remove-GuacPermission: {0} is not an object permission for {1} targets. Valid object permissions: {2}' -f ($Permission, 'object', ($objectTypes -join ', ')))
                ))
            }
        }

        $operation = New-GuacPermissionPatch -Op 'remove' `
            -TargetConnection $Connection `
            -TargetConnectionGroup $ConnectionGroup `
            -TargetSharingProfile $SharingProfile `
            -TargetActiveConnection $null `
            -TargetUser $TargetUser `
            -TargetUserGroup $TargetUserGroup `
            -System:$System.IsPresent `
            -Type $Permission

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Remove-GuacPermission'

        $collection = if ($subjectType -eq 'user') { 'users' } else { 'userGroups' }
        $path = Resolve-GuacContextUrl -DataSource $ctx['DataSource'] -Collection $collection -Id $subjectId -SubPath 'permissions'

        $label = ('{0} {1} -> {2} ({3})' -f $subjectType, $subjectId, $operation['path'], $Permission)
        if (-not ($PSCmdlet.ShouldProcess($label, 'Revoke Guacamole permission (PATCH permissions)'))) {
            return
        }

        Invoke-GuacPatch -Context $ctx -Path $path -Patch $operation | Out-Null
    }
}
