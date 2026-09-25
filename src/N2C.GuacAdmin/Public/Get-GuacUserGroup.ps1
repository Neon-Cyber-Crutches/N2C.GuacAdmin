function Get-GuacUserGroup {
    <#
    .SYNOPSIS
        Gets Guacamole user groups from the UserContext.

    .DESCRIPTION
        Retrieves user groups from the per-data-source UserContext:
        - without -Id, the full collection (DirectoryResource.getObjects),
          with each entry wrapped so it carries an Identifier property;
        - with -Id, a single user group by identifier
          (DirectoryObjectResource.getObject).

        Each returned object mirrors the APIUserGroup fields: identifier,
        disabled, attributes — plus the Identifier property, so the results
        can be piped to Update-GuacUserGroup and Remove-GuacUserGroup.

        Related-object subresources are exposed by the dedicated membership
        cmdlets (Add-/Remove-GuacUserGroupMember and the user group
        permission cmdlets), which operate on the userGroups/{id}/memberUsers,
        memberUserGroups, and permissions endpoints.

        The -Name parameter performs client-side filtering by group name
        using PowerShell's -like semantics (wildcards supported). -Id takes
        precedence; if both are specified, -Id wins and the filter is ignored
        with a warning.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("userGroups"))
        - guacamole/src/main/java/org/apache/guacamole/rest/usergroup/UserGroupResource.java
          (memberUsers, memberUserGroups, userGroups, permissions subresources)
        - guacamole/src/main/java/org/apache/guacamole/rest/usergroup/APIUserGroup.java
          (identifier, disabled, attributes)
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (getObjects) / DirectoryObjectResource.java (getObject)

    .EXAMPLE
        Get-GuacUserGroup

    .EXAMPLE
        Get-GuacUserGroup -Id 'admin-group'

    .EXAMPLE
        Get-GuacUserGroup -Name "admin*"
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
        [AllowEmptyString()]
        [string] $Name = [string]::Empty
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacUserGroup'

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        if (-not [string]::IsNullOrWhiteSpace($Name)) {
            Write-Warning 'Both -Id and -Name were specified. -Id takes precedence; -Name is ignored.'
        }
        return (Invoke-GuacDirectory -Context $ctx -Collection 'userGroups' -Action 'Get' -Id $Id)
    }

    $groups = @(Invoke-GuacDirectory -Context $ctx -Collection 'userGroups' -Action 'List')

    # Client-side filtering (user groups use 'identifier' as their name)
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $groups = @($groups | Where-Object { $_.Identifier -like $Name })
    }

    return $groups
}
