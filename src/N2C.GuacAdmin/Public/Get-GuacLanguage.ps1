function Get-GuacLanguage {
    <#
    .SYNOPSIS
        Gets the list of available languages on the Guacamole instance.

    .DESCRIPTION
        Retrieves the map of available language keys to their human-readable
        display names from the Guacamole instance (LanguageRESTService.getLanguages).

        This is a session-level endpoint; it does not require a data source.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/language/LanguageRESTService.java
          (@Path("/languages"), getLanguages: @GET returns Map<String, String>)
        - guacamole/src/main/java/org/apache/guacamole/extension/LanguageResourceService.java
          (getLanguageNames)

    .EXAMPLE
        Get-GuacLanguage -Session $session

    .EXAMPLE
        $langs = Get-GuacLanguage -Server 'https://guac.example.com/guacamole'
        $langs | ForEach-Object { "$($_.Key) - $($_.Value)" }
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [N2C_GuacAdmin_GuacSession] $Session,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Server = [string]::Empty
    )

    # Session-level endpoint: resolve server/token but not data source
    $resolved = Resolve-GuacSessionForServer -Session $Session -Server $Server -CmdletName 'Get-GuacLanguage'

    $path = '/api/languages'
    return (Invoke-GuacRest -Server $resolved.Server -Token $resolved.Token -Method GET -Path $path)
}
