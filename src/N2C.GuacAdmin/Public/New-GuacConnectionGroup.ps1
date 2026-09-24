function New-GuacConnectionGroup {
    <#
    .SYNOPSIS
        Creates a new Guacamole connection group.

    .DESCRIPTION
        Creates a connection group in the per-data-source UserContext by
        POSTing an APIConnectionGroup body (DirectoryResource.createObject).
        The body follows the APIConnectionGroup shape: name, type
        (ORGANIZATIONAL or BALANCING; defaults to ORGANIZATIONAL),
        parentIdentifier (the containing group; "ROOT" for the root group),
        and attributes. The server assigns the identifier and returns the
        created group.

        The group body may be supplied as a hashtable/ordered hashtable or a
        PSCustomObject (also from the pipeline via -InputObject). The
        "identifier" property, if present, is ignored: the server assigns it.
        Alternatively, -Name/-Type/-Parent construct the body directly.

        Requires the CREATE_CONNECTION_GROUP system permission (or
        ADMINISTER) on the server.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (createObject: @POST on the directory, returns the created object)
        - guacamole/src/main/java/org/apache/guacamole/rest/connectiongroup/APIConnectionGroup.java
          (name, type, parentIdentifier, attributes)
        - guacamole-ext/src/main/java/org/apache/guacamole/net/auth/ConnectionGroup.java
          (Type: ORGANIZATIONAL, BALANCING)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("connectionGroups"))

    .EXAMPLE
        New-GuacConnectionGroup -Name 'production' -Type BALANCING -Parent 'ROOT'

    .EXAMPLE
        New-GuacConnectionGroup -InputObject @{
            name = 'web-servers'
            type = 'ORGANIZATIONAL'
        } -Parent 'production-group-id'
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
        [ValidateSet('ORGANIZATIONAL', 'BALANCING')]
        [string] $Type = [string]::Empty,

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
            if (-not [string]::IsNullOrWhiteSpace($Type)) { $pendingBody['type'] = $Type }
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
                'New-GuacConnectionGroup requires a group body: supply -Name (optionally with -Type) or -InputObject.'
            ))
        }
        if ([string]::IsNullOrWhiteSpace($Parent)) { $Parent = 'ROOT' }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'New-GuacConnectionGroup'

        $body = ConvertTo-GuacEntityBody -Object $pendingBody -ExcludeProperty @('identifier', 'Identifier')
        $body['parentIdentifier'] = $Parent
        # Always include an attributes object (empty if not provided)
        # to satisfy the MySQL storage layer's NOT NULL constraint.
        if ($null -ne $Attributes) {
            $body['attributes'] = $Attributes
        }
        elseif ($null -eq $body['attributes']) {
            $body['attributes'] = @{}
        }

        $whatIfTarget = 'connection group'
        if (-not [string]::IsNullOrWhiteSpace([string]$body['name'])) { $whatIfTarget = ('connection group "{0}"' -f $body['name']) }
        if (-not ($PSCmdlet.ShouldProcess($whatIfTarget, 'Create Guacamole connection group (POST connectionGroups)'))) {
            return
        }

        return (Invoke-GuacDirectory -Context $ctx -Collection 'connectionGroups' -Action 'Create' -Body $body)
    }
}
