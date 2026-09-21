function Update-GuacConnection {
    <#
    .SYNOPSIS
        Updates an existing Guacamole connection.

    .DESCRIPTION
        Two mutation modes, exactly one of which must be supplied:

        - -Patch (the canonical form): a JSON Patch operations array applied
          via the collection PATCH endpoint (DirectoryResource.patchObjects).
          A single operation or an array of operations is accepted. Supported
          operations: add (create), replace (full or partial object update,
          path "/{id}"), and remove (path "/{id}").

        - -Replace: a full replacement of the connection via
          DirectoryObjectResource.updateObject (PUT /connections/{id}). The
          body should contain the complete APIConnection (name, protocol,
          parameters, parentIdentifier, attributes).

        WARNING: both modes are full replacements, not merges. The server
        translator (ConnectionObjectTranslator.applyExternalChanges) applies
        every field of the supplied object unconditionally, so any field that
        is missing from the body (or missing from the "value" of a "replace"
        patch operation) is set to null on the server. To change a single
        field, read the full object first (Get-GuacConnection -Id), modify
        the property, and submit the complete object.

        The target connection is addressed by -Id, or by piping a connection
        object (as returned by Get-GuacConnection) into the cmdlet (bound to
        -InputObject); the piped object's Identifier is used when -Id is not
        given. -Id takes precedence over the piped identifier.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (patchObjects: @PATCH with List<APIPatch<ExternalType>>)
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (updateObject: @PUT)
        - guacamole/src/main/java/org/apache/guacamole/rest/connection/ConnectionObjectTranslator.java
          (applyExternalChanges: protocol, parameters, parentIdentifier, name,
           attributes)
        - guacamole/src/main/java/org/apache/guacamole/rest/connection/APIConnection.java

    .EXAMPLE
        # Read-modify-write: submit the complete object, not just the changed field.
        $conn = Get-GuacConnection -Id $id
        $conn.Name = 'renamed'
        Update-GuacConnection -Id $conn.Identifier -Patch (
            @{ op = 'replace'; path = ('/{0}' -f $conn.Identifier); value = $conn }
        )

    .EXAMPLE
        # A batch of atomic operations on the same collection: replace one
        # connection and remove another, all-or-nothing.
        Update-GuacConnection -Id $id -Patch @(
            @{ op = 'replace'; path = ('/{0}' -f $id); value = $fullConn }
            @{ op = 'remove'; path = ('/{0}' -f $obsoleteConn.Identifier) }
        )

    .EXAMPLE
        Update-GuacConnection -Id $conn.Identifier -Replace @{
            name = 'db-server'
            protocol = 'ssh'
            parameters = @{ hostname = 'db2.example.com' }
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
                'Update-GuacConnection: supply exactly one of -Patch or -Replace, not both.'
            ))
        }
        if (-not $hasPatch -and -not $hasReplace) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacConnection: supply -Patch (a JSON Patch operations array) or -Replace (a full connection object), or pipe a connection object with one of them.'
            ))
        }

        $targetId = $Id
        if ([string]::IsNullOrWhiteSpace($targetId)) { $targetId = $pendingId }
        if ($hasReplace -and [string]::IsNullOrWhiteSpace($targetId)) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacConnection -Replace requires the connection identifier: supply -Id or pipe a connection object carrying an Identifier.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Update-GuacConnection'

        if ($hasPatch) {
            if (-not [string]::IsNullOrWhiteSpace($targetId)) {
                $whatIfTarget = ('connection {0}' -f $targetId)
            }
            else {
                $whatIfTarget = 'connection (patch)'
            }
            if (-not ($PSCmdlet.ShouldProcess($whatIfTarget, 'Update Guacamole connection (PATCH connections)'))) {
                return
            }
            Invoke-GuacEntityPatch -Context $ctx -Collection 'connections' `
                -TargetLabel ('connection {0}' -f $targetId) -Patch $Patch | Out-Null
            return
        }

        # Full replacement via PUT.
        $body = ConvertTo-GuacEntityBody -Object $Replace -ExcludeProperty @('identifier', 'Identifier', 'activeConnections', 'lastActive', 'sharingProfiles')
        if (-not ($PSCmdlet.ShouldProcess(('connection {0}' -f $targetId), 'Replace Guacamole connection (PUT connections/{id})'))) {
            return
        }
        return (Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Update' -Id $targetId -Body $body)
    }
}
