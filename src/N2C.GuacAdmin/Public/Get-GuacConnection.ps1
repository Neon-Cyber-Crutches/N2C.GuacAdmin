function Get-GuacConnection {
    <#
    .SYNOPSIS
        Gets Guacamole connections from the UserContext.

    .DESCRIPTION
        Retrieves connections from the per-data-source UserContext:
        - without -Id, the full collection (DirectoryResource.getObjects),
          with each entry wrapped so it carries an Identifier property;
        - with -Id, a single connection by identifier
          (DirectoryObjectResource.getObject), including its parameters.

        Each returned object is a [PSCustomObject] mirroring the APIConnection
        fields (name, protocol, parentIdentifier, parameters, attributes,
        activeConnections, lastActive) plus the Identifier property, so the
        results can be piped to Update-GuacConnection and Remove-GuacConnection.

        The connection parameters (host, port, credentials, guac-* options)
        are returned as the "parameters" property; retrieving them requires
        UPDATE permission on the connection (or ADMINISTER), which the server
        enforces in ConnectionResource.getConnectionParameters.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("connections"))
        - guacamole/src/main/java/org/apache/guacamole/rest/connection/ConnectionDirectoryResource.java
        - guacamole/src/main/java/org/apache/guacamole/rest/connection/ConnectionResource.java
        - guacamole/src/main/java/org/apache/guacamole/rest/connection/APIConnection.java
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (getObjects) / DirectoryObjectResource.java (getObject)

    .EXAMPLE
        Get-GuacConnection

    .EXAMPLE
        Get-GuacConnection -Session $session -Id '8b1f2c3d-...'

    .EXAMPLE
        Get-GuacConnection | Where-Object { $_.Protocol -eq 'rdp' }
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

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacConnection'

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        return (Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Get' -Id $Id)
    }
    return (Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'List')
}
