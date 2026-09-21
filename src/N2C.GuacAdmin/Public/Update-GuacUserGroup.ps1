function Update-GuacUserGroup {
    <#
    .SYNOPSIS
        Updates an existing Guacamole user group.

    .DESCRIPTION
        Two mutation modes, exactly one of which must be supplied:

        - -Patch (the canonical form): a JSON Patch operations array applied
          via the collection PATCH endpoint (DirectoryResource.patchObjects).
          A single operation or an array of operations is accepted. Supported
          operations: add (create), replace (update, path "/{id}"), and
          remove (path "/{id}").

        - -Replace: a replacement of the group via
          DirectoryObjectResource.updateObject (PUT /userGroups/{id}).

        User group update semantics: the server translator
        (UserGroupObjectTranslator.applyExternalChanges) replaces the
        "disabled" and "attributes" fields; the identifier is the group's
        identity and cannot be changed through this endpoint. A body that
        omits "attributes" nulls the attribute map, while an omitted
        "disabled" is interpreted as $false by the server.

        The target group is addressed by -Id, or by piping a user group
        object (as returned by Get-GuacUserGroup) into the cmdlet (bound to
        -InputObject); the piped object's Identifier is used when -Id is not
        given. -Id takes precedence over the piped identifier.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (patchObjects: @PATCH with List<APIPatch<ExternalType>>)
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (updateObject: @PUT)
        - guacamole/src/main/java/org/apache/guacamole/rest/usergroup/UserGroupObjectTranslator.java
          (applyExternalChanges: disabled, attributes)
        - guacamole/src/main/java/org/apache/guacamole/rest/usergroup/APIUserGroup.java

    .EXAMPLE
        $group = Get-GuacUserGroup -Id 'auditors'
        $group.Disabled = $true
        Update-GuacUserGroup -Id 'auditors' -Replace $group

    .EXAMPLE
        Update-GuacUserGroup -Id 'auditors' -Replace @{
            disabled = $false
            attributes = @{ 'guac-description' = 'Read-only auditors' }
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
                'Update-GuacUserGroup: supply exactly one of -Patch or -Replace, not both.'
            ))
        }
        if (-not $hasPatch -and -not $hasReplace) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacUserGroup: supply -Patch (a JSON Patch operations array) or -Replace (a user group object), or pipe a group object with one of them.'
            ))
        }

        $targetId = $Id
        if ([string]::IsNullOrWhiteSpace($targetId)) { $targetId = $pendingId }
        if ($hasReplace -and [string]::IsNullOrWhiteSpace($targetId)) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacUserGroup -Replace requires the group identifier: supply -Id or pipe a group object carrying an Identifier.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Update-GuacUserGroup'

        if ($hasPatch) {
            if (-not [string]::IsNullOrWhiteSpace($targetId)) {
                $whatIfTarget = ('user group {0}' -f $targetId)
            }
            else {
                $whatIfTarget = 'user group (patch)'
            }
            if (-not ($PSCmdlet.ShouldProcess($whatIfTarget, 'Update Guacamole user group (PATCH userGroups)'))) {
                return
            }
            Invoke-GuacEntityPatch -Context $ctx -Collection 'userGroups' `
                -TargetLabel ('user group {0}' -f $targetId) -Patch $Patch | Out-Null
            return
        }

        # Replacement via PUT. The identifier is the group identity and is not
        # part of the mutable body; drop it so it cannot be "changed".
        $body = ConvertTo-GuacEntityBody -Object $Replace -ExcludeProperty @('identifier', 'Identifier')
        if (-not ($PSCmdlet.ShouldProcess(('user group {0}' -f $targetId), 'Replace Guacamole user group (PUT userGroups/{id})'))) {
            return
        }
        return (Invoke-GuacDirectory -Context $ctx -Collection 'userGroups' -Action 'Update' -Id $targetId -Body $body)
    }
}
