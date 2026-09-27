function Get-GuacExtension {
    <#
    .SYNOPSIS
        Gets the extension resource for a specific data source.

    .DESCRIPTION
        Retrieves the extension-specific resource for the given data source
        (ExtensionRESTService.getExtensionResource). The response shape is
        extension-dependent; for example guacamole-auth-ldap exposes LDAP
        directory configuration, while guacamole-auth-kerberos exposes Kerberos
        settings.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/extension/ExtensionRESTService.java
          (@Path("/ext/{identifier}"), getExtensionResource: @GET returns Object)

    .EXAMPLE
        PS> Get-GuacExtension

        Gets the extension resource using the default data source from the
        current session.

    .EXAMPLE
        PS> Get-GuacExtension -Session $session -DataSource ldap

        Gets the extension resource for the LDAP data source.

    .EXAMPLE
        PS> $ext = Get-GuacExtension -Server 'https://guac.example.com/guacamole' -DataSource 'kerberos'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [N2C_GuacAdmin_GuacSession] $Session,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Server = [string]::Empty,

        [Parameter(Mandatory = $false, Position = 0)]
        [AllowEmptyString()]
        [string] $DataSource = [string]::Empty
    )

    # When -DataSource is not specified, Resolve-GuacSessionContext will
    # fall back to the session's default data source.
    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacExtension'

    # Extension resource is at /api/ext/{dataSource}, NOT under /api/session/data
    $path = ('/api/ext/{0}' -f [Uri]::EscapeDataString($ctx['DataSource']))
    try {
        return (Invoke-GuacRest -Server $ctx['Server'] -Token $ctx['Token'] -Method GET -Path $path)
    }
    catch [System.Exception] {
        # When no extension is registered for this data source, the server
        # returns HTTP 404. In that case, return an empty list rather than
        # throwing an error.
        $exc = $_.Exception
        if ($exc -and $exc.StatusCode -eq 404) {
            Write-Verbose ('No extension resource found for data source "{0}".' -f $ctx['DataSource'])
            # PowerShell unwraps single-element arrays and swallows empty
            # arrays from function output. Wrap the result in [object[]]
            # so callers consistently receive an empty array, not $null.
            return [object[]]@()
        }
        throw
    }
}
