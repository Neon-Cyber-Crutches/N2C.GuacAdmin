function Get-GuacProtocol {
    <#
    .SYNOPSIS
        Gets the protocols available on a Guacamole instance.

    .DESCRIPTION
        Retrieves the protocol registry of the per-data-source UserContext
        (SchemaResource.getProtocols, GET .../schema/protocols). The server
        returns a map of protocol name to ProtocolInfo; this cmdlet unwraps
        the map into one [PSCustomObject] per protocol, each carrying:
        - Protocol    : the protocol name (also the "name" field)
        - name        : the protocol name
        - connectionForms      : the Forms describing the connection
          parameters of this protocol
        - sharingProfileForms  : the Forms describing the sharing profile
          parameters of this protocol

        A single protocol may be requested by name with -Name.

        The protocol Forms are the offline argument reference for validating
        a connection's parameters; at runtime, the effective attribute set for
        a connection is Get-GuacSchema -Set ConnectionAttributes (the
        server-side, per-data-source view).

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/schema/SchemaResource.java
          (getProtocols: @GET @Path("protocols"), Map<String, ProtocolInfo>)
        - guacamole-ext/src/main/java/org/apache/guacamole/protocols/ProtocolInfo.java
          (name, connectionForms, sharingProfileForms)
        - guacamole/src/main/java/org/apache/guacamole/rest/schema/Form.java

    .EXAMPLE
        Get-GuacProtocol

    .EXAMPLE
        Get-GuacProtocol -Name ssh
    #>
    [CmdletBinding()]
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
        [string] $Name = [string]::Empty
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacProtocol'

    $path = Resolve-GuacContextUrl -DataSource $ctx['DataSource'] -Collection 'schema' -SubPath 'protocols'
    $map = Invoke-GuacRest -Server $ctx['Server'] -Token $ctx['Token'] -Method GET -Path $path

    $names = @()
    foreach ($prop in $map.PSObject.Properties) {
        $names += $prop.Name
    }
    if ($names.Count -eq 0) {
        return
    }

    $selected = $names
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        if ($names -notcontains $Name) {
            throw ($script:GuacRestExceptionType::new(
                ('Protocol {0} is not available on this instance. Available: {1}' -f ($Name, ($names -join ', ')))
            ))
        }
        $selected = @($Name)
    }

    foreach ($protocolName in $selected) {
        $info = $map.$protocolName
        $obj = [PSCustomObject]$info
        $obj | Add-Member -NotePropertyName Protocol -NotePropertyValue $protocolName -Force
        Write-Output $obj
    }
}
