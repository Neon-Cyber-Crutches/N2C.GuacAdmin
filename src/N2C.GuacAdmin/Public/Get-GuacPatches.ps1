function Get-GuacPatches {
    <#
    .SYNOPSIS
        Gets the list of HTML patches available on the Guacamole instance.

    .DESCRIPTION
        Retrieves the list of HTML patches (PatchRESTService.getPatches), each of
        which is a raw HTML string containing additional meta tags describing how
        and where the patch should be applied.

        This is a session-level endpoint; it does not require a data source.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/patch/PatchRESTService.java
          (@Path("/patches"), getPatches: @GET returns List<String>)
        - guacamole/src/main/java/org/apache/guacamole/extension/PatchResourceService.java
          (getPatchResources)

    .EXAMPLE
        Get-GuacPatches -Session $session

    .EXAMPLE
        $patches = Get-GuacPatches -Server 'https://guac.example.com/guacamole'
        Write-Output "Patches: $($patches.Count)"
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

    $resolved = Resolve-GuacSessionForServer -Session $Session -Server $Server -CmdletName 'Get-GuacPatches'

    $path = '/api/patches'
    return (Invoke-GuacRest -Server $resolved.Server -Token $resolved.Token -Method GET -Path $path)
}
