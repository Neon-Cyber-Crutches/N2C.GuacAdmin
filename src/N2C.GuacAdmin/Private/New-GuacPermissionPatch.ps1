#Requires -Version 5.1
function New-GuacPermissionPatch {
    <#
    .SYNOPSIS
        Builds a single permission JSON Patch operation.

    .DESCRIPTION
        Resolves exactly one permission target into the RFC 6902 operation
        consumed by PermissionSetResource.patchPermissions. Object permissions
        address a specific object by identifier under a category-specific path
        prefix; the system permission uses the fixed path "/systemPermissions".
        The value is the permission type string.

        Object permission path prefixes (Apache Guacamole 1.6.0,
        PermissionSetResource):
        - /connectionPermissions/{id}
        - /connectionGroupPermissions/{id}
        - /sharingProfilePermissions/{id}
        - /activeConnectionPermissions/{id}
        - /userPermissions/{id}
        - /userGroupPermissions/{id}
        System permission path: /systemPermissions

        The returned hashtable has the keys op, path, and value, matching the
        APIPatch<String> shape. The -Type is not validated here against the
        object vs system enum; callers are responsible for choosing a type
        that matches the target category.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/permission/PermissionSetResource.java
          (patchPermissions; the *_PATCH_PATH_PREFIX constants)

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('add', 'remove')]
        [string] $Op,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $TargetConnection = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $TargetConnectionGroup = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $TargetSharingProfile = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $TargetActiveConnection = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $TargetUser = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $TargetUserGroup = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [switch] $System,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Type
    )

    $specified = @()
    if (-not [string]::IsNullOrWhiteSpace($TargetConnection))       { $specified += 'connection' }
    if (-not [string]::IsNullOrWhiteSpace($TargetConnectionGroup))  { $specified += 'connectionGroup' }
    if (-not [string]::IsNullOrWhiteSpace($TargetSharingProfile))   { $specified += 'sharingProfile' }
    if (-not [string]::IsNullOrWhiteSpace($TargetActiveConnection)) { $specified += 'activeConnection' }
    if (-not [string]::IsNullOrWhiteSpace($TargetUser))             { $specified += 'user' }
    if (-not [string]::IsNullOrWhiteSpace($TargetUserGroup))        { $specified += 'userGroup' }
    if ($System)                                                    { $specified += 'system' }

    if ($specified.Count -ne 1) {
        throw ($script:GuacRestExceptionType::new(
            ('New-GuacPermissionPatch: exactly one target is required, but {0} were specified ({1}).' -f $specified.Count, ($specified -join ', '))
        ))
    }

    if ($System) {
        return @{ op = $Op; path = '/systemPermissions'; value = $Type }
    }

    switch ($specified[0]) {
        'connection'         { $path = ('/connectionPermissions/{0}' -f $TargetConnection) }
        'connectionGroup'    { $path = ('/connectionGroupPermissions/{0}' -f $TargetConnectionGroup) }
        'sharingProfile'     { $path = ('/sharingProfilePermissions/{0}' -f $TargetSharingProfile) }
        'activeConnection'   { $path = ('/activeConnectionPermissions/{0}' -f $TargetActiveConnection) }
        'user'               { $path = ('/userPermissions/{0}' -f $TargetUser) }
        'userGroup'          { $path = ('/userGroupPermissions/{0}' -f $TargetUserGroup) }
    }
    return @{ op = $Op; path = $path; value = $Type }
}
