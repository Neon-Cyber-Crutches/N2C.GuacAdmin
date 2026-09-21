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
        if ($null -ne $Attributes) {
            $body['attributes'] = $Attributes
        }

        $whatIfTarget = 'connection'
        if (-not [string]::IsNullOrWhiteSpace([string]$body['name'])) { $whatIfTarget = ('connection "{0}"' -f $body['name']) }
        if (-not ($PSCmdlet.ShouldProcess($whatIfTarget, 'Create Guacamole connection (POST connections)'))) {
            return
        }

        return (Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Create' -Body $body)
    }
}
