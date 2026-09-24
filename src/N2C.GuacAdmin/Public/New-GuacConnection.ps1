function New-GuacConnection {
    <#
    .SYNOPSIS
        Creates a new Guacamole connection.

    .DESCRIPTION
        Creates a connection in the per-data-source UserContext by POSTing an
        APIConnection body (DirectoryResource.createObject). The body follows
        the APIConnection shape: name, protocol, parameters (a map of
        parameter name to value), parentIdentifier (the containing connection
        group; "ROOT" for the root group), and attributes. The server assigns
        the identifier and returns the created object.

        The connection body may be supplied as a hashtable/ordered hashtable
        or a PSCustomObject (also from the pipeline via -InputObject). The
        "identifier" property, if present, is ignored: the server assigns it.
        Alternatively, -Name/-Protocol/-Parameters/-Parent construct the body
        directly.

        Requires the CREATE_CONNECTION system permission (or ADMINISTER) on
        the server.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (createObject: @POST on the directory, returns the created object)
        - guacamole/src/main/java/org/apache/guacamole/rest/connection/APIConnection.java
          (name, protocol, parameters, parentIdentifier, attributes)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("connections"))

    .EXAMPLE
        New-GuacConnection -Name 'db-server' -Protocol 'ssh' `
            -Parameters @{ hostname = 'db.example.com'; port = '22' } `
            -Parent 'ROOT'

    .EXAMPLE
        New-GuacConnection -InputObject @{
            name = 'print-server'
            protocol = 'rdp'
            parameters = @{ hostname = 'print.example.com'; port = '3389' }
        } -Parent 'ROOT'
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

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Name = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Protocol = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Parameters,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Parent = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Attributes
    )

    begin {
        $pendingBody = $null
        if (-not [string]::IsNullOrWhiteSpace($Name)) {
            $pendingBody = [ordered]@{}
            $pendingBody['name'] = $Name
            if (-not [string]::IsNullOrWhiteSpace($Protocol)) { $pendingBody['protocol'] = $Protocol }
            if ($null -ne $Parameters) { $pendingBody['parameters'] = $Parameters }
        }
    }

    process {
        if ($null -ne $InputObject) {
            $pendingBody = $InputObject
        }
    }

    end {
        if ($null -eq $pendingBody) {
            throw ($script:GuacRestExceptionType::new(
                'New-GuacConnection requires a connection body: supply -Name (optionally with -Protocol/-Parameters) or -InputObject.'
            ))
        }
        if ([string]::IsNullOrWhiteSpace($Parent)) { $Parent = 'ROOT' }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'New-GuacConnection'

        $body = ConvertTo-GuacEntityBody -Object $pendingBody -ExcludeProperty @('identifier', 'Identifier')
        $body['parentIdentifier'] = $Parent

        # Determine the protocol for schema-based parameter completion
        $connectionProtocol = [string]$body['protocol']
        if ([string]::IsNullOrWhiteSpace($connectionProtocol) -and -not [string]::IsNullOrWhiteSpace($Protocol)) {
            $connectionProtocol = $Protocol
            $body['protocol'] = $connectionProtocol
        }

        # If a protocol is known, fetch its schema and ensure all required
        # parameter fields are present (defaulting to empty string). This
        # matches the behavior of the Guacamole web UI and is required by
        # some server configurations that expect the complete parameter set.
        if (-not [string]::IsNullOrWhiteSpace($connectionProtocol)) {
            $defaultParams = $null
            try {
                # Directly fetch the protocol schema to avoid type resolution issues
                # when calling Get-GuacProtocol from within the same module.
                $schemaPath = Resolve-GuacContextUrl -DataSource $ctx['DataSource'] -Collection 'schema' -SubPath 'protocols'
                $protocolsMap = Invoke-GuacRest -Server $ctx['Server'] -Token $ctx['Token'] -Method GET -Path $schemaPath

                if ($null -ne $protocolsMap -and $protocolsMap.PSObject.Properties[$connectionProtocol]) {
                    $protocolInfo = $protocolsMap.$connectionProtocol
                    if ($null -ne $protocolInfo) {
                        # Collect all field names from the protocol's connection forms
                        $fieldNames = @()
                        foreach ($form in @($protocolInfo.connectionForms)) {
                            if ($null -ne $form -and $form.PSObject.Properties['fields']) {
                                foreach ($f in @($form.fields)) {
                                    if ([string]::IsNullOrWhiteSpace([string]$f) -eq $false) {
                                        $fieldNames += [string]$f
                                    }
                                }
                            }
                        }

                        # Build default parameters with empty strings
                        $defaultParams = @{}
                        foreach ($fieldName in $fieldNames) {
                            $defaultParams[$fieldName] = ''
                        }
                    }
                }
            }
            catch {
                Write-Warning ('Failed to fetch protocol schema for "{0}": {1}. Using provided parameters only.' -f ($connectionProtocol, $_.Exception.Message))
            }

            # Merge: defaults first, then user-provided parameters override
            $userParams = $null
            if ($null -ne $body['parameters']) {
                $userParams = $body['parameters']
            }
            elseif ($null -ne $Parameters) {
                $userParams = $Parameters
            }

            $mergedParams = @{}
            if ($null -ne $defaultParams) {
                foreach ($key in $defaultParams.Keys) {
                    $mergedParams[$key] = $defaultParams[$key]
                }
            }
            if ($null -ne $userParams) {
                foreach ($key in $userParams.Keys) {
                    $mergedParams[$key] = $userParams[$key]
                }
            }
            $body['parameters'] = $mergedParams
        }

        # Always include an attributes object (empty if not provided)
        if ($null -ne $Attributes) {
            $body['attributes'] = $Attributes
        }
        elseif ($null -eq $body['attributes']) {
            $body['attributes'] = @{}
        }

        $whatIfTarget = 'connection'
        if (-not [string]::IsNullOrWhiteSpace([string]$body['name'])) { $whatIfTarget = ('connection "{0}"' -f $body['name']) }
        if (-not ($PSCmdlet.ShouldProcess($whatIfTarget, 'Create Guacamole connection (POST connections)'))) {
            return
        }

        return (Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Create' -Body $body)
    }
}
