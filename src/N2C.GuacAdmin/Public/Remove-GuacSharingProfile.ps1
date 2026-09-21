function Remove-GuacSharingProfile {
    <#
    .SYNOPSIS
        Deletes a Guacamole sharing profile.

    .DESCRIPTION
        Deletes the sharing profile with the given identifier from the
        per-data-source UserContext via
        DirectoryObjectResource.deleteObject
        (DELETE /sharingProfiles/{id}).

        The sharing profile is addressed by -Id, or by piping a sharing
        profile object (as returned by Get-GuacSharingProfile) into the
        cmdlet; the piped object's Identifier is used when -Id is not given.
        -Id takes precedence over the piped identifier.

        Requires the DELETE_SHARING_PROFILE system permission (or ADMINISTER)
        on the server. Deleting a sharing profile does not delete the primary
        connection it references.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (deleteObject: @DELETE)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("sharingProfiles"))

    .EXAMPLE
        Remove-GuacSharingProfile -Id 'readonly'

    .EXAMPLE
        Get-GuacSharingProfile -Id 'readonly' | Remove-GuacSharingProfile
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
                'Remove-GuacSharingProfile requires the sharing profile identifier: supply -Id or pipe a profile object.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Remove-GuacSharingProfile'

        if (-not ($PSCmdlet.ShouldProcess(('sharing profile {0}' -f $targetId), 'Delete Guacamole sharing profile (DELETE sharingProfiles/{id})'))) {
            return
        }

        Invoke-GuacDirectory -Context $ctx -Collection 'sharingProfiles' -Action 'Delete' -Id $targetId | Out-Null
    }
}
