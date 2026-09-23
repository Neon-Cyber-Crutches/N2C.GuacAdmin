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
        Get-GuacExtension -Session $session -DataSource ldap

    .EXAMPLE
        $ext = Get-GuacExtension -Server 'https://guac.example.com/guacamole' -DataSource 'kerberos'
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

    if ([string]::IsNullOrWhiteSpace($DataSource)) {
        throw ($script:GuacRestExceptionType::new(
            'Get-GuacExtension requires -DataSource.'
        ))
    }

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacExtension'

    # Extension resource is at /api/ext/{dataSource}, NOT under /api/session/data
    $path = ('/api/ext/{0}' -f [Uri]::EscapeDataString($ctx['DataSource']))
    return (Invoke-GuacRest -Server $ctx['Server'] -Token $ctx['Token'] -Method GET -Path $path)
}
