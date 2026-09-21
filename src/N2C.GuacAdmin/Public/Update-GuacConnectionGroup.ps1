function Update-GuacConnectionGroup {
    <#
    .SYNOPSIS
        Updates an existing Guacamole connection group.

    .DESCRIPTION
        Two mutation modes, exactly one of which must be supplied:

        - -Patch (the canonical form): a JSON Patch operations array applied
          via the collection PATCH endpoint (DirectoryResource.patchObjects).
          A single operation or an array of operations is accepted. Supported
          operations: add (create), replace (full or partial group update,
          path "/{id}"), and remove (path "/{id}").

        - -Replace: a full replacement of the group via
          DirectoryObjectResource.updateObject (PUT connectionGroups/{id}).
          The body should contain the complete APIConnectionGroup (name,
          type, parentIdentifier, attributes).

        WARNING: both modes are full replacements, not merges. The server
        translator (ConnectionGroupObjectTranslator.applyExternalChanges)
        applies every field of the supplied object unconditionally, so any
        field that is missing from the body (or missing from the "value" of a
        "replace" patch operation) is set to null on the server. To change a
        single field, read the full object first (Get-GuacConnectionGroup
        -Id), modify the property, and submit the complete object.

        The target group is addressed by -Id, or by piping a group object
        (as returned by Get-GuacConnectionGroup) into the cmdlet (bound to
        -InputObject); the piped object's Identifier is used when -Id is not
        given. -Id takes precedence over the piped identifier. Reparenting is
        done by setting parentIdentifier in the replacement body.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (patchObjects: @PATCH with List<APIPatch<ExternalType>>)
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (updateObject: @PUT)
        - guacamole/src/main/java/org/apache/guacamole/rest/connectiongroup/ConnectionGroupObjectTranslator.java
          (applyExternalChanges: name, type, parentIdentifier, attributes)
        - guacamole/src/main/java/org/apache/guacamole/rest/connectiongroup/APIConnectionGroup.java

    .EXAMPLE
        # Read-modify-write: submit the complete object, not just the changed field.
        $group = Get-GuacConnectionGroup -Id $id
        $group.Name = 'renamed-group'
        Update-GuacConnectionGroup -Id $group.Identifier -Patch (
            @{ op = 'replace'; path = ('/{0}' -f $group.Identifier); value = $group }
        )

    .EXAMPLE
        Update-GuacConnectionGroup -Id $group.Identifier -Replace @{
            name = 'production'
            type = 'BALANCING'
            parentIdentifier = 'ROOT'
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
                'Update-GuacConnectionGroup: supply exactly one of -Patch or -Replace, not both.'
            ))
        }
        if (-not $hasPatch -and -not $hasReplace) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacConnectionGroup: supply -Patch (a JSON Patch operations array) or -Replace (a full group object), or pipe a group object with one of them.'
            ))
        }

        $targetId = $Id
        if ([string]::IsNullOrWhiteSpace($targetId)) { $targetId = $pendingId }
        if ($hasReplace -and [string]::IsNullOrWhiteSpace($targetId)) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacConnectionGroup -Replace requires the group identifier: supply -Id or pipe a group object carrying an Identifier.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Update-GuacConnectionGroup'

        if ($hasPatch) {
            if (-not [string]::IsNullOrWhiteSpace($targetId)) {
                $whatIfTarget = ('connection group {0}' -f $targetId)
            }
            else {
                $whatIfTarget = 'connection group (patch)'
            }
            if (-not ($PSCmdlet.ShouldProcess($whatIfTarget, 'Update Guacamole connection group (PATCH connectionGroups)'))) {
                return
            }
            Invoke-GuacEntityPatch -Context $ctx -Collection 'connectionGroups' `
                -TargetLabel ('connection group {0}' -f $targetId) -Patch $Patch | Out-Null
            return
        }

        # Full replacement via PUT.
        $body = ConvertTo-GuacEntityBody -Object $Replace -ExcludeProperty @('identifier', 'Identifier', 'activeConnections', 'childConnectionGroups', 'childConnections')
        if (-not ($PSCmdlet.ShouldProcess(('connection group {0}' -f $targetId), 'Replace Guacamole connection group (PUT connectionGroups/{id})'))) {
            return
        }
        return (Invoke-GuacDirectory -Context $ctx -Collection 'connectionGroups' -Action 'Update' -Id $targetId -Body $body)
    }
}
