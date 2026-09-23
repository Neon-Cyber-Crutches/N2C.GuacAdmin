function Get-GuacTunnel {
    <#
    .SYNOPSIS
        Gets the tunnels associated with the current session.

    .DESCRIPTION
        Retrieves the set of tunnel UUIDs associated with the current session
        (TunnelCollectionResource.getTunnelUUIDs: GET /api/session/tunnels).
        This is read-only metadata; the tunnels cannot be controlled through
        this endpoint.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/session/SessionResource.java
          (@Path("tunnels") -> TunnelCollectionResource)
        - guacamole/src/main/java/org/apache/guacamole/rest/tunnel/TunnelCollectionResource.java
          (getTunnelUUIDs: @GET returns Set<String>)

    .EXAMPLE
        Get-GuacTunnel -Session $session

    .EXAMPLE
        $tunnels = Get-GuacTunnel -Server 'https://guac.example.com/guacamole'
        Write-Output "Tunnels: $($tunnels.Count)"
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [N2C_GuacAdmin_GuacSession] $Session,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Server = [string]::Empty
    )

    $resolved = Resolve-GuacSessionForServer -Session $Session -Server $Server -CmdletName 'Get-GuacTunnel'

    $path = '/api/session/tunnels'
    return (Invoke-GuacRest -Server $resolved.Server -Token $resolved.Token -Method GET -Path $path)
}
