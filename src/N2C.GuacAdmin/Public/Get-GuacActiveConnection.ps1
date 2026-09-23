function Get-GuacActiveConnection {
    <#
    .SYNOPSIS
        Gets active Guacamole connections from the UserContext.

    .DESCRIPTION
        Retrieves active connections (currently in use) from the per-data-source
        UserContext (ActiveConnectionDirectoryResource). Without -Id, returns
        all active connections; with -Id, returns a single active connection.

        Each returned object is a [PSCustomObject] mirroring the APIActiveConnection
        fields (identifier, connectionIdentifier, startDate, remoteHost, username,
        connectable) plus the Identifier property, so results can be piped to
        Stop-GuacActiveConnection.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("activeConnections"))
        - guacamole/src/main/java/org/apache/guacamole/rest/activeconnection/ActiveConnectionDirectoryResource.java
        - guacamole/src/main/java/org/apache/guacamole/rest/activeconnection/APIActiveConnection.java

    .EXAMPLE
        Get-GuacActiveConnection

    .EXAMPLE
        Get-GuacActiveConnection -Session $session -Id 'abc-123'

    .EXAMPLE
        Get-GuacActiveConnection | Where-Object { $_.Username -eq 'jdoe' }
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
        [string] $Id = [string]::Empty
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacActiveConnection'

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        return (Invoke-GuacDirectory -Context $ctx -Collection 'activeConnections' -Action 'Get' -Id $Id)
    }
    return (Invoke-GuacDirectory -Context $ctx -Collection 'activeConnections' -Action 'List')
}
