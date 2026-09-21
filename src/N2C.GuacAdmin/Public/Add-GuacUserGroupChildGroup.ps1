function Add-GuacUserGroupChildGroup {
    <#
    .SYNOPSIS
        Adds a user group as a member (child) of another Guacamole user group.

    .DESCRIPTION
        Adds a user group to the memberUserGroups set of a parent user group
        by sending a single-operation JSON Patch to the related-object-set
        endpoint (RelatedObjectSetResource.patchObjects, PATCH
        .../userGroups/{id}/memberUserGroups) with { "op": "add", "path": "/",
        "value": "<group identifier>" }.

        The parent group is given by -UserGroup, or by piping a user group
        object (as returned by Get-GuacUserGroup); a piped group object is
        always treated as the parent. The child group is given by -ChildGroup.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/usergroup/UserGroupResource.java
          (getMemberUserGroups: @Path("memberUserGroups"))
        - guacamole/src/main/java/org/apache/guacamole/rest/identifier/RelatedObjectSetResource.java
          (patchObjects: path "/", value is the identifier)

    .EXAMPLE
        Add-GuacUserGroupChildGroup -UserGroup 'auditors' -ChildGroup 'interns'

    .EXAMPLE
        Get-GuacUserGroup -Id 'auditors' | Add-GuacUserGroupChildGroup -ChildGroup 'interns'
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
                'Add-GuacUserGroupChildGroup requires the parent group: supply -UserGroup or pipe a user group object.'
            ))
        }
        if ([string]::IsNullOrWhiteSpace($child)) {
            throw ($script:GuacRestExceptionType::new(
                'Add-GuacUserGroupChildGroup requires the child group identifier: supply -ChildGroup or pipe a user group object.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Add-GuacUserGroupChildGroup'

        if (-not ($PSCmdlet.ShouldProcess(("user group '{0}' + child '{1}'" -f ($groupId, $child)), 'Add user group child group (PATCH memberUserGroups)'))) {
            return
        }

        Invoke-GuacRelatedSetPatch -Context $ctx -Collection 'userGroups' -Id $groupId -SubPath 'memberUserGroups' -Op 'add' -Identifier $child | Out-Null
    }
}
