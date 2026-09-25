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

        By default, -ResolveParentGroupName is $true and the cmdlet resolves
        each parentIdentifier to a human-readable connection group name, adding
        a ParentGroupName property. Use -ResolveParentGroupName:$false to skip
        resolution for raw API data.

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

    .EXAMPLE
        Get-GuacConnection | Select-Object Name, ParentGroupName, Protocol

    .EXAMPLE
        Get-GuacConnection -ResolveParentGroupName:$false
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
        [string] $Id = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [bool] $ResolveParentGroupName = $true
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacConnection'

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $conn = Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Get' -Id $Id
        if ($ResolveParentGroupName -and -not [string]::IsNullOrWhiteSpace($conn.ParentIdentifier) -and $conn.ParentIdentifier -ne 'ROOT') {
            try {
                $group = Invoke-GuacDirectory -Context $ctx -Collection 'connectionGroups' -Action 'Get' -Id $conn.ParentIdentifier
                $conn | Add-Member -NotePropertyName ParentGroupName -NotePropertyValue $group.Name
            }
            catch {
                Write-Verbose ('Get-GuacConnection: could not resolve parent group name for {0}' -f $conn.ParentIdentifier)
                $conn | Add-Member -NotePropertyName ParentGroupName -NotePropertyValue '(unknown)'
            }
        }
        return $conn
    }

    $connections = @(Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'List')
    if ($ResolveParentGroupName -and $connections.Count -gt 0) {
        $groupIds = @($connections | ForEach-Object { if ($_.ParentIdentifier -and $_.ParentIdentifier -ne 'ROOT') { $_.ParentIdentifier } }) | Select-Object -Unique
        $groupMap = @{}
        foreach ($groupId in $groupIds) {
            try {
                $group = Invoke-GuacDirectory -Context $ctx -Collection 'connectionGroups' -Action 'Get' -Id $groupId
                $groupMap[$groupId] = $group.Name
            }
            catch {
                Write-Verbose ('Get-GuacConnection: could not resolve parent group name for {0}' -f $groupId)
                $groupMap[$groupId] = '(unknown)'
            }
        }
        foreach ($conn in $connections) {
            if ($conn.ParentIdentifier -and $conn.ParentIdentifier -ne 'ROOT') {
                $conn | Add-Member -NotePropertyName ParentGroupName -NotePropertyValue $groupMap[$conn.ParentIdentifier]
            }
        }
    }
    return $connections
}
