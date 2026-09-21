function Add-GuacPermission {
    <#
    .SYNOPSIS
        Grants a permission to a Guacamole user or user group.

    .DESCRIPTION
        Adds one permission to the permission set of a subject (a user or a
        user group) by sending a single-operation JSON Patch to the subject's
        permissions endpoint (PermissionSetResource.patchPermissions):
        - user:      PATCH .../users/{username}/permissions
        - user group: PATCH .../userGroups/{id}/permissions

        The subject is given by -User (a username), -UserGroup (a group
        identifier), or by piping the subject object (a user from
        Get-GuacUser or a user group from Get-GuacUserGroup); a piped object
        is detected by its "username" property (user) or its Identifier
        (user group). Exactly one subject must be supplied.

        The permission target is exactly one of:
        - -Connection         (a connection identifier)
        - -ConnectionGroup    (a connection group identifier)
        - -SharingProfile     (a sharing profile identifier)
        - -TargetUser         (a username)
        - -TargetUserGroup    (a user group identifier)
        - -System             (the system as a whole)

        The -Permission type depends on the target:
        - object targets: READ, UPDATE, DELETE, or ADMINISTER
          (ObjectPermission.Type)
        - -System: CREATE_USER, CREATE_USER_GROUP, CREATE_CONNECTION,
          CREATE_CONNECTION_GROUP, CREATE_SHARING_PROFILE, AUDIT, or
          ADMINISTER (SystemPermission.Type)

        The wire operation is { "op": "add", "path": "/<category>/<id>" or
        "/systemPermissions", "value": "<permission type>" }.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/user/UserResource.java
          (getPermissions: @Path("permissions"))
        - guacamole/src/main/java/org/apache/guacamole/rest/usergroup/UserGroupResource.java
          (getPermissions: @Path("permissions"))
        - guacamole/src/main/java/org/apache/guacamole/rest/permission/PermissionSetResource.java
          (patchPermissions: add/remove; path prefixes; value is the type)
        - guacamole-ext/src/main/java/org/apache/guacamole/net/auth/permission/ObjectPermission.java
          (Type: READ, UPDATE, DELETE, ADMINISTER)
        - guacamole-ext/src/main/java/org/apache/guacamole/net/auth/permission/SystemPermission.java
          (Type: CREATE_USER, CREATE_USER_GROUP, CREATE_CONNECTION,
           CREATE_CONNECTION_GROUP, CREATE_SHARING_PROFILE, AUDIT, ADMINISTER)

    .EXAMPLE
        Add-GuacPermission -User 'jdoe' -Connection 'conn-id' -Permission READ

    .EXAMPLE
        Add-GuacPermission -UserGroup 'auditors' -ConnectionGroup 'prod' -Permission READ

    .EXAMPLE
        Add-GuacPermission -User 'admin2' -System -Permission ADMINISTER

    .EXAMPLE
        Get-GuacUser -Id 'jdoe' | Add-GuacPermission -Connection 'conn-id' -Permission READ
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
                'Add-GuacPermission requires the permission subject: supply -User or -UserGroup, or pipe a user / user group object.'
            ))
        }

        $objectTypes = @('READ', 'UPDATE', 'DELETE', 'ADMINISTER')
        $systemTypes = @('CREATE_USER', 'CREATE_USER_GROUP', 'CREATE_CONNECTION', 'CREATE_CONNECTION_GROUP', 'CREATE_SHARING_PROFILE', 'AUDIT', 'ADMINISTER')
        if ($System) {
            if ($systemTypes -notcontains $Permission) {
                throw ($script:GuacRestExceptionType::new(
                    ('Add-GuacPermission: {0} is not a system permission. Valid system permissions: {1}' -f ($Permission, ($systemTypes -join ', ')))
                ))
            }
        }
        else {
            if ($objectTypes -notcontains $Permission) {
                throw ($script:GuacRestExceptionType::new(
                    ('Add-GuacPermission: {0} is not an object permission for {1} targets. Valid object permissions: {2}' -f ($Permission, 'object', ($objectTypes -join ', ')))
                ))
            }
        }

        $operation = New-GuacPermissionPatch -Op 'add' `
            -TargetConnection $Connection `
            -TargetConnectionGroup $ConnectionGroup `
            -TargetSharingProfile $SharingProfile `
            -TargetActiveConnection $null `
            -TargetUser $TargetUser `
            -TargetUserGroup $TargetUserGroup `
            -System:$System.IsPresent `
            -Type $Permission

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Add-GuacPermission'

        $collection = if ($subjectType -eq 'user') { 'users' } else { 'userGroups' }
        $path = Resolve-GuacContextUrl -DataSource $ctx['DataSource'] -Collection $collection -Id $subjectId -SubPath 'permissions'

        $label = ('{0} {1} -> {2} ({3})' -f $subjectType, $subjectId, $operation['path'], $Permission)
        if (-not ($PSCmdlet.ShouldProcess($label, 'Grant Guacamole permission (PATCH permissions)'))) {
            return
        }

        Invoke-GuacPatch -Context $ctx -Path $path -Patch $operation | Out-Null
    }
}
