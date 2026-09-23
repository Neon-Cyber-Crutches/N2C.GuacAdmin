function Get-GuacUser {
    <#
    .SYNOPSIS
        Gets Guacamole users from the UserContext.

    .DESCRIPTION
        Retrieves users from the per-data-source UserContext:
        - without -Id, the full collection (DirectoryResource.getObjects),
          with each entry wrapped so it carries an Identifier property;
        - with -Id, a single user by username (DirectoryObjectResource.getObject).

        For users the identifier IS the username: the APIUser external shape
        carries username (not "identifier"), so the Identifier property added
        by this cmdlet is the username itself, and -Id expects a username.

        Each returned object mirrors the APIUser fields: username, password,
        disabled, attributes, lastActive — plus the Identifier property, so
        the results can be piped to Update-GuacUser and Remove-GuacUser.

        WARNING: the server includes the user's password in plaintext in the
        APIUser response (APIUser is constructed from User.getPassword()).
        Treat the output of this cmdlet as sensitive: do not log it or pass it
        to untrusted consumers.

        With -Permissions, the user's directly-granted permission set
        (PermissionSetResource.getPermissions, GET users/{id}/permissions) is
        appended to each returned object as the "permissions" property (an
        APIPermissionSet). With -EffectivePermissions, the effective
        (inherited and implied) permission set is appended as the
        "effectivePermissions" property (GET users/{id}/effectivePermissions).
        The two switches may be combined.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("users"))
        - guacamole/src/main/java/org/apache/guacamole/rest/user/UserResource.java
          (getPermissions: @Path("permissions"); getEffectivePermissions:
           @GET @Path("effectivePermissions"))
        - guacamole/src/main/java/org/apache/guacamole/rest/user/APIUser.java
          (username, password, disabled, attributes, lastActive)
        - guacamole/src/main/java/org/apache/guacamole/rest/permission/APIPermissionSet.java
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (getObjects) / DirectoryObjectResource.java (getObject)

    .EXAMPLE
        Get-GuacUser

    .EXAMPLE
        Get-GuacUser -Id 'jdoe' -Permissions

    .EXAMPLE
        Get-GuacUser -Id 'jdoe' -EffectivePermissions | Select-Object effectivePermissions
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
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

        [Parameter(Mandatory = $false, Position = 0)]
        [AllowEmptyString()]
        [string] $Id = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [switch] $Permissions,

        [Parameter(Mandatory = $false)]
        [switch] $EffectivePermissions
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacUser'

    # NOTE: switch values are forwarded with the colon syntax (-Direct:$Permissions).
    # The value form (-Direct $Permissions) makes PowerShell treat the switch as a
    # positional argument and throws PositionalParameterNotFound (verified on
    # pwsh 7.x).
    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $user = Invoke-GuacDirectory -Context $ctx -Collection 'users' -Action 'Get' -Id $Id
        return (Get-GuacUserPermissions -User $user -Context $ctx -Direct:$Permissions -Effective:$EffectivePermissions)
    }

    $users = @(Invoke-GuacDirectory -Context $ctx -Collection 'users' -Action 'List')
    if ($Permissions -or $EffectivePermissions) {
        foreach ($user in $users) {
            Write-Output (Get-GuacUserPermissions -User $user -Context $ctx -Direct:$Permissions -Effective:$EffectivePermissions)
        }
        return
    }
    foreach ($user in $users) {
        Write-Output $user
    }
}
