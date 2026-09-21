function Remove-GuacConnectionGroup {
    <#
    .SYNOPSIS
        Deletes a Guacamole connection group.

    .DESCRIPTION
        Deletes the connection group with the given identifier from the
        per-data-source UserContext via DirectoryObjectResource.deleteObject
        (DELETE /connectionGroups/{id}).

        The group is addressed by -Id, or by piping a group object (as
        returned by Get-GuacConnectionGroup) into the cmdlet; the piped
        object's Identifier is used when -Id is not given. -Id takes
        precedence over the piped identifier.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (deleteObject: @DELETE)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("connectionGroups"))

    .EXAMPLE
        Remove-GuacConnectionGroup -Id 'group-id'

    .EXAMPLE
        Get-GuacConnectionGroup -Id $id | Remove-GuacConnectionGroup
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
                'Remove-GuacConnectionGroup requires the group identifier: supply -Id or pipe a group object.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Remove-GuacConnectionGroup'

        if (-not ($PSCmdlet.ShouldProcess(('connection group {0}' -f $targetId), 'Delete Guacamole connection group (DELETE connectionGroups/{id})'))) {
            return
        }

        Invoke-GuacDirectory -Context $ctx -Collection 'connectionGroups' -Action 'Delete' -Id $targetId | Out-Null
    }
}
