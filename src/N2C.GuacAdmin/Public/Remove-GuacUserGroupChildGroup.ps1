function Remove-GuacUserGroupChildGroup {
    <#
    .SYNOPSIS
        Removes a user group from the members (child groups) of a Guacamole
        user group.

    .DESCRIPTION
        Removes a user group from the memberUserGroups set of a parent user
        group by sending a single-operation JSON Patch to the
        related-object-set endpoint (RelatedObjectSetResource.patchObjects,
        PATCH .../userGroups/{id}/memberUserGroups) with { "op": "remove",
        "path": "/", "value": "<group identifier>" }.

        The parent group is given by -UserGroup, or by piping a user group
        object (as returned by Get-GuacUserGroup); a piped group object is
        always treated as the parent. The child group is given by -ChildGroup.
        Removing a group that is not a member is a no-op on the server.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/usergroup/UserGroupResource.java
          (getMemberUserGroups: @Path("memberUserGroups"))
        - guacamole/src/main/java/org/apache/guacamole/rest/identifier/RelatedObjectSetResource.java
          (patchObjects: path "/", value is the identifier)

    .EXAMPLE
        Remove-GuacUserGroupChildGroup -UserGroup 'auditors' -ChildGroup 'interns'

    .EXAMPLE
        Get-GuacUserGroup -Id 'auditors' | Remove-GuacUserGroupChildGroup -ChildGroup 'interns'
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
        [string] $UserGroup = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $ChildGroup = [string]::Empty,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [object] $InputObject
    )

    begin {
        $pendingGroup = [string]::Empty
    }

    process {
        if ($null -ne $InputObject) {
            # A piped user group object is always treated as the parent.
            $identifier = Get-GuacIdentifier -Object $InputObject
            if (-not [string]::IsNullOrWhiteSpace($identifier)) {
                $pendingGroup = $identifier
            }
        }
    }

    end {
        $groupId = $UserGroup
        if ([string]::IsNullOrWhiteSpace($groupId)) { $groupId = $pendingGroup }
        $child = $ChildGroup
        if ([string]::IsNullOrWhiteSpace($groupId)) {
            throw ($script:GuacRestExceptionType::new(
                'Remove-GuacUserGroupChildGroup requires the parent group: supply -UserGroup or pipe a user group object.'
            ))
        }
        if ([string]::IsNullOrWhiteSpace($child)) {
            throw ($script:GuacRestExceptionType::new(
                'Remove-GuacUserGroupChildGroup requires the child group identifier: supply -ChildGroup.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Remove-GuacUserGroupChildGroup'

        if (-not ($PSCmdlet.ShouldProcess(("user group '{0}' - child '{1}'" -f ($groupId, $child)), 'Remove user group child group (PATCH memberUserGroups)'))) {
            return
        }

        Invoke-GuacRelatedSetPatch -Context $ctx -Collection 'userGroups' -Id $groupId -SubPath 'memberUserGroups' -Op 'remove' -Identifier $child | Out-Null
    }
}
