function Remove-GuacUserGroup {
    <#
    .SYNOPSIS
        Deletes a Guacamole user group.

    .DESCRIPTION
        Deletes the user group with the given identifier from the
        per-data-source UserContext via DirectoryObjectResource.deleteObject
        (DELETE /userGroups/{id}).

        The group is addressed by -Id, or by piping a user group object (as
        returned by Get-GuacUserGroup) into the cmdlet; the piped object's
        Identifier is used when -Id is not given. -Id takes precedence over
        the piped identifier.

        Requires the DELETE_USER_GROUP system permission (or ADMINISTER) on
        the server. Deleting a group removes the group and its membership
        links; member users are not deleted.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (deleteObject: @DELETE)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("userGroups"))

    .EXAMPLE
        Remove-GuacUserGroup -Id 'auditors'

    .EXAMPLE
        Get-GuacUserGroup -Id 'auditors' | Remove-GuacUserGroup
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
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

        [Parameter(Mandatory = $false, Position = 0)]
        [AllowEmptyString()]
        [string] $Id = [string]::Empty,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [object] $InputObject
    )

    begin {
        $pendingId = [string]::Empty
    }

    process {
        if ($null -ne $InputObject) {
            $pendingId = Get-GuacIdentifier -Object $InputObject
        }
    }

    end {
        $targetId = $Id
        if ([string]::IsNullOrWhiteSpace($targetId)) { $targetId = $pendingId }
        if ([string]::IsNullOrWhiteSpace($targetId)) {
            throw ($script:GuacRestExceptionType::new(
                'Remove-GuacUserGroup requires the group identifier: supply -Id or pipe a group object.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Remove-GuacUserGroup'

        if (-not ($PSCmdlet.ShouldProcess(('user group {0}' -f $targetId), 'Delete Guacamole user group (DELETE userGroups/{id})'))) {
            return
        }

        Invoke-GuacDirectory -Context $ctx -Collection 'userGroups' -Action 'Delete' -Id $targetId | Out-Null
    }
}
