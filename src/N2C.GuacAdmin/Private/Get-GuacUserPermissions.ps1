#Requires -Version 5.1
function Get-GuacUserPermissions {
    <#
    .SYNOPSIS
        Appends permission sets to a user object.

    .DESCRIPTION
        Fetches the directly-granted permission set (GET users/{id}/permissions,
        PermissionSetResource.getPermissions) and/or the effective permission
        set (GET users/{id}/effectivePermissions,
        UserResource.getEffectivePermissions) for a user and copies the result
        onto a copy of the user object as the "permissions" /
        "effectivePermissions" properties.

        The input user object is not mutated; a new [PSCustomObject] is
        returned. If a switch is not set, the corresponding property is not
        added. A $null user yields $null.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/user/UserResource.java
        - guacamole/src/main/java/org/apache/guacamole/rest/permission/PermissionSetResource.java
          (getPermissions)
        - guacamole/src/main/java/org/apache/guacamole/rest/permission/APIPermissionSet.java

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $User,

        [Parameter(Mandatory = $true)]
        [hashtable] $Context,

        [Parameter(Mandatory = $false)]
        [switch] $Direct,

        [Parameter(Mandatory = $false)]
        [switch] $Effective
    )

    if ($null -eq $User) {
        return $null
    }
    if (-not $Direct -and -not $Effective) {
        return $User
    }

    $identifier = Get-GuacIdentifier -Object $User
    $props = ConvertTo-GuacEntityBody -Object $User
    $server = [string]$Context['Server']
    $token = [string]$Context['Token']
    $dataSource = [string]$Context['DataSource']

    if ($Direct) {
        $path = Resolve-GuacContextUrl -DataSource $dataSource -Collection 'users' -Id $identifier -SubPath 'permissions'
        $props['permissions'] = Invoke-GuacRest -Server $server -Token $token -Method GET -Path $path
    }
    if ($Effective) {
        $path = Resolve-GuacContextUrl -DataSource $dataSource -Collection 'users' -Id $identifier -SubPath 'effectivePermissions'
        $props['effectivePermissions'] = Invoke-GuacRest -Server $server -Token $token -Method GET -Path $path
    }
    return [PSCustomObject]$props
}
