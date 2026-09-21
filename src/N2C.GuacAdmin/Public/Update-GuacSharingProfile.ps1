function Update-GuacSharingProfile {
    <#
    .SYNOPSIS
        Updates an existing Guacamole sharing profile.

    .DESCRIPTION
        Two mutation modes, exactly one of which must be supplied:

        - -Patch (the canonical form): a JSON Patch operations array applied
          via the collection PATCH endpoint (DirectoryResource.patchObjects).
          A single operation or an array of operations is accepted. Supported
          operations: add (create), replace (full or partial profile update,
          path "/{id}"), and remove (path "/{id}").

        - -Replace: a full replacement of the sharing profile via
          DirectoryObjectResource.updateObject (PUT sharingProfiles/{id}).
          The body should contain the complete APISharingProfile (name,
          primaryConnectionIdentifier, parameters, attributes).

        WARNING: both modes are full replacements, not merges. The server
        translator (SharingProfileObjectTranslator.applyExternalChanges)
        applies every field of the supplied object unconditionally, so any
        field that is missing from the body (or missing from the "value" of a
        "replace" patch operation) is set to null on the server. To change a
        single field, read the full object first (Get-GuacSharingProfile
        -Id), modify the property, and submit the complete object.

        The target sharing profile is addressed by -Id, or by piping a
        sharing profile object (as returned by Get-GuacSharingProfile) into
        the cmdlet (bound to -InputObject); the piped object's Identifier is
        used when -Id is not given. -Id takes precedence over the piped
        identifier.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (patchObjects: @PATCH with List<APIPatch<ExternalType>>)
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (updateObject: @PUT)
        - guacamole/src/main/java/org/apache/guacamole/rest/sharingprofile/SharingProfileObjectTranslator.java
          (applyExternalChanges: primaryConnectionIdentifier, name,
           parameters, attributes)
        - guacamole/src/main/java/org/apache/guacamole/rest/sharingprofile/APISharingProfile.java

    .EXAMPLE
        # Read-modify-write: submit the complete object, not just the changed field.
        $profile = Get-GuacSharingProfile -Id $id
        $profile.Name = 'read-only (v2)'
        Update-GuacSharingProfile -Id $profile.Identifier -Patch (
            @{ op = 'replace'; path = ('/{0}' -f $profile.Identifier); value = $profile }
        )

    .EXAMPLE
        Update-GuacSharingProfile -Id $profile.Identifier -Replace @{
            name = 'read-only'
            primaryConnectionIdentifier = 'conn-id'
            parameters = @{ 'guac-readonly' = 'true' }
        }
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
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
        [AllowNull()]
        [object] $Patch,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Replace,

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
        $hasPatch = ($null -ne $Patch)
        $hasReplace = ($null -ne $Replace)
        if ($hasPatch -and $hasReplace) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacSharingProfile: supply exactly one of -Patch or -Replace, not both.'
            ))
        }
        if (-not $hasPatch -and -not $hasReplace) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacSharingProfile: supply -Patch (a JSON Patch operations array) or -Replace (a sharing profile object), or pipe a profile object with one of them.'
            ))
        }

        $targetId = $Id
        if ([string]::IsNullOrWhiteSpace($targetId)) { $targetId = $pendingId }
        if ($hasReplace -and [string]::IsNullOrWhiteSpace($targetId)) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacSharingProfile -Replace requires the sharing profile identifier: supply -Id or pipe a profile object carrying an Identifier.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Update-GuacSharingProfile'

        if ($hasPatch) {
            if (-not [string]::IsNullOrWhiteSpace($targetId)) {
                $whatIfTarget = ('sharing profile {0}' -f $targetId)
            }
            else {
                $whatIfTarget = 'sharing profile (patch)'
            }
            if (-not ($PSCmdlet.ShouldProcess($whatIfTarget, 'Update Guacamole sharing profile (PATCH sharingProfiles)'))) {
                return
            }
            Invoke-GuacEntityPatch -Context $ctx -Collection 'sharingProfiles' `
                -TargetLabel ('sharing profile {0}' -f $targetId) -Patch $Patch | Out-Null
            return
        }

        # Full replacement via PUT.
        $body = ConvertTo-GuacEntityBody -Object $Replace -ExcludeProperty @('identifier', 'Identifier')
        if (-not ($PSCmdlet.ShouldProcess(('sharing profile {0}' -f $targetId), 'Replace Guacamole sharing profile (PUT sharingProfiles/{id})'))) {
            return
        }
        return (Invoke-GuacDirectory -Context $ctx -Collection 'sharingProfiles' -Action 'Update' -Id $targetId -Body $body)
    }
}
