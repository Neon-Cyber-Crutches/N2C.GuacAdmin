function Remove-GuacUserGroupMember {
    <#
    .SYNOPSIS
        Removes a user from the members of a Guacamole user group.

    .DESCRIPTION
        Removes a user from the memberUsers set of a user group by sending a
        single-operation JSON Patch to the related-object-set endpoint
        (RelatedObjectSetResource.patchObjects, PATCH
        .../userGroups/{id}/memberUsers) with { "op": "remove", "path": "/",
        "value": "<username>" }.

        The group is given by -UserGroup, or by piping a user group object
        (as returned by Get-GuacUserGroup). The member is given by -Member,
        or by piping a user object (as returned by Get-GuacUser) — a piped
        object carrying a "username" property is treated as the member, while
        a piped object without one is treated as the group. Removing a user
        that is not a member is a no-op on the server.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/usergroup/UserGroupResource.java
          (getMemberUsers: @Path("memberUsers"))
        - guacamole/src/main/java/org/apache/guacamole/rest/identifier/RelatedObjectSetResource.java
          (patchObjects: path "/", value is the identifier)

    .EXAMPLE
        Remove-GuacUserGroupMember -UserGroup 'auditors' -Member 'jdoe'

    .EXAMPLE
        Get-GuacUserGroup -Id 'auditors' | Remove-GuacUserGroupMember -Member 'jdoe'
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
        [string] $Member = [string]::Empty,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [object] $InputObject
    )

    begin {
        $pendingGroup = [string]::Empty
        $pendingMember = [string]::Empty
    }

    process {
        if ($null -ne $InputObject) {
            $username = [string]::Empty
            if ($InputObject.PSObject.Properties.Match('username').Count -gt 0) {
                $username = [string]$InputObject.username
            }
            if (-not [string]::IsNullOrWhiteSpace($username)) {
                $pendingMember = $username
            }
            else {
                $pendingGroup = Get-GuacIdentifier -Object $InputObject
            }
        }
    }

    end {
        $groupId = $UserGroup
        if ([string]::IsNullOrWhiteSpace($groupId)) { $groupId = $pendingGroup }
        $member = $Member
        if ([string]::IsNullOrWhiteSpace($member)) { $member = $pendingMember }
        if ([string]::IsNullOrWhiteSpace($groupId)) {
            throw ($script:GuacRestExceptionType::new(
                'Remove-GuacUserGroupMember requires the group: supply -UserGroup or pipe a user group object.'
            ))
        }
        if ([string]::IsNullOrWhiteSpace($member)) {
            throw ($script:GuacRestExceptionType::new(
                'Remove-GuacUserGroupMember requires the member username: supply -Member or pipe a user object.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Remove-GuacUserGroupMember'

        if (-not ($PSCmdlet.ShouldProcess(("user group '{0}' - member '{1}'" -f ($groupId, $member)), 'Remove user group member (PATCH memberUsers)'))) {
            return
        }

        Invoke-GuacRelatedSetPatch -Context $ctx -Collection 'userGroups' -Id $groupId -SubPath 'memberUsers' -Op 'remove' -Identifier $member | Out-Null
    }
}
