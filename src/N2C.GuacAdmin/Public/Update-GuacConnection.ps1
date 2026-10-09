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

        Use -Merge with -Replace to change only specific fields while
        preserving existing parameter and attribute values. With -Merge,
        the cmdlet fetches the current connection state, merges the
        provided parameters and attributes with the existing values
        (provided values take precedence), and submits the merged result.
        This prevents silent loss of credentials (username, password) when
        only updating non-credential parameters such as hostname or port.

        WARNING: without -Merge, both modes are full replacements, not
        merges. The server translator (ConnectionObjectTranslator.applyExternalChanges)
        applies every field of the supplied object unconditionally, so any
        field that is missing from the body (or missing from the "value" of
        a "replace" patch operation) is set to null on the server. To change
        a single field, read the full object first (Get-GuacConnection -Id),
        modify the property, and submit the complete object.

        Active session check: before updating via -Replace, the cmdlet
        checks whether the connection has active user sessions. If it does,
        the update is aborted with a clear error message. Use -Force to skip
        this check and allow the update even with active sessions.

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

    .EXAMPLE
        # Merge mode: only the provided fields are changed, others are preserved.
        # Only hostname is updated; username, password, domain are kept from the server.
        Update-GuacConnection -Id $conn.Identifier -Replace @{
            parameters = @{ hostname = 'db2.example.com' }
        } -Merge

    .EXAMPLE
        # Force update even if the connection has active user sessions.
        Update-GuacConnection -Id $conn.Identifier -Replace $fullConn -Force
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Replace')]
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

        [Parameter(Mandatory = $false, ParameterSetName = 'Patch')]
        [AllowNull()]
        [object] $Patch,

        [Parameter(Mandatory = $false, ParameterSetName = 'Replace')]
        [AllowNull()]
        [object] $Replace,

        [Parameter(Mandatory = $false)]
        [switch] $Merge,

        [Parameter(Mandatory = $false)]
        [switch] $Force,

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
                # DataSource resolution priority: explicit param > piped object > session default
                if ([string]::IsNullOrWhiteSpace($DataSource)) {
                    $pipedDs = Get-GuacDataSourceFromObject -Object $InputObject
                    if (-not [string]::IsNullOrWhiteSpace($pipedDs)) {
                        $DataSource = $pipedDs
                    }
                }
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

        if ($Merge -and -not $hasReplace) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacConnection: -Merge can only be used with -Replace.'
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

        # Check for active sessions before update (Issue #49-1)
        # The list endpoint may return stale activeConnections counts, so we
        # fetch the single-connection endpoint for accurate data.
        if ($hasReplace -and -not $Force -and -not [string]::IsNullOrWhiteSpace($targetId)) {
            try {
                $currentConn = Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Get' -Id $targetId
                if ($null -ne $currentConn -and $currentConn.PSObject.Properties['activeConnections']) {
                    $activeCount = [int]$currentConn.activeConnections
                    if ($activeCount -gt 0) {
                        $activeSessions = @(Get-GuacActiveConnection -Server $ctx.Server -DataSource $ctx.DataSource | Where-Object { $_.connectionIdentifier -eq $targetId })
                        throw ($script:GuacRestExceptionType::new(
                            ('Update-GuacConnection: cannot update connection "{0}" ({1}) because it has {2} active session(s). ' +
                             'Use -Force to override this check or disconnect the active sessions first.') -f
                            ($currentConn.Name, $targetId, $activeSessions.Count)
                        ))
                    }
                }
            }
            catch {
                # Re-throw if it's our active session check, otherwise continue
                if ($_.Exception -is $script:GuacRestExceptionType -and $_.Exception.Message -like '*active session*') {
                    throw
                }
                Write-Verbose ('Update-GuacConnection: could not check active sessions: {0}' -f $_.Exception.Message)
            }
        }

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
        if ($Merge) {
            # Merge mode: fetch current connection and merge parameters (Issue #49-2)
            $currentConn = Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Get' -Id $targetId
            $currentBody = ConvertTo-GuacEntityBody -Object $currentConn -ExcludeProperty @('identifier', 'Identifier', 'activeConnections', 'lastActive', 'sharingProfiles')
            $replaceBody = ConvertTo-GuacEntityBody -Object $Replace -ExcludeProperty @('identifier', 'Identifier', 'activeConnections', 'lastActive', 'sharingProfiles')

            # Merge parameters
            if ($null -ne $replaceBody['parameters']) {
                $mergedParams = @{}
                if ($null -ne $currentBody['parameters']) {
                    foreach ($key in $currentBody['parameters'].Keys) {
                        $mergedParams[$key] = $currentBody['parameters'][$key]
                    }
                }
                foreach ($key in $replaceBody['parameters'].Keys) {
                    $mergedParams[$key] = $replaceBody['parameters'][$key]
                }
                $replaceBody['parameters'] = $mergedParams
            }

            # Merge attributes
            if ($null -ne $replaceBody['attributes']) {
                $mergedAttrs = @{}
                if ($null -ne $currentBody['attributes']) {
                    foreach ($key in $currentBody['attributes'].Keys) {
                        $mergedAttrs[$key] = $currentBody['attributes'][$key]
                    }
                }
                foreach ($key in $replaceBody['attributes'].Keys) {
                    $mergedAttrs[$key] = $replaceBody['attributes'][$key]
                }
                $replaceBody['attributes'] = $mergedAttrs
            }

            # Apply other replace fields on top of current
            foreach ($key in $replaceBody.Keys) {
                if ($key -ne 'parameters' -and $key -ne 'attributes') {
                    $currentBody[$key] = $replaceBody[$key]
                }
            }
            $body = $currentBody
        }
        else {
            $body = ConvertTo-GuacEntityBody -Object $Replace -ExcludeProperty @('identifier', 'Identifier', 'activeConnections', 'lastActive', 'sharingProfiles')
        }

        if (-not ($PSCmdlet.ShouldProcess(('connection {0}' -f $targetId), 'Replace Guacamole connection (PUT connections/{id})'))) {
            return
        }

        try {
            return (Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Update' -Id $targetId -Body $body)
        }
        catch {
            # Issue #49-3: Provide better context for HTTP 500 errors
            if ($_.Exception.StatusCode -eq 500) {
                $detail = ('HTTP 500 "Unexpected internal error" from Guacamole server. ' +
                           'Common causes: connection has active user sessions, or the server encountered an unexpected condition. ' +
                           'Try running Get-GuacConnection -Id {0} to check for active sessions, or use -Force to skip the active session check.') -f $targetId
                Write-Warning $detail
            }
            throw
        }
    }
}
