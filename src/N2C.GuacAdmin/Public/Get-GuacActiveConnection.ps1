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

        By default, -ResolveConnectionName is $true and the cmdlet resolves
        each connectionIdentifier to a human-readable connection name, adding
        a ConnectionName property. Use -ResolveConnectionName:$false to skip
        resolution for raw API data.

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

    .EXAMPLE
        Get-GuacActiveConnection | Where-Object { $_.ConnectionName -eq 'prod-db' }

    .EXAMPLE
        Get-GuacActiveConnection -ResolveConnectionName:$false
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
        [bool] $ResolveConnectionName = $true
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacActiveConnection'

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $active = Invoke-GuacDirectory -Context $ctx -Collection 'activeConnections' -Action 'Get' -Id $Id
        if ($ResolveConnectionName -and -not [string]::IsNullOrWhiteSpace($active.ConnectionIdentifier)) {
            try {
                $conn = Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Get' -Id $active.ConnectionIdentifier
                $active | Add-Member -NotePropertyName ConnectionName -NotePropertyValue $conn.Name
            }
            catch {
                Write-Verbose ('Get-GuacActiveConnection: could not resolve connection name for {0}: {1}' -f ($active.ConnectionIdentifier, $_.Exception.Message))
                $active | Add-Member -NotePropertyName ConnectionName -NotePropertyValue '(unknown)'
            }
        }
        return $active
    }

    $activeList = @(Invoke-GuacDirectory -Context $ctx -Collection 'activeConnections' -Action 'List')
    if ($ResolveConnectionName -and $activeList.Count -gt 0) {
        $connIds = @($activeList | ForEach-Object { if ($_.ConnectionIdentifier) { $_.ConnectionIdentifier } }) | Select-Object -Unique
        $connMap = @{}
        foreach ($connId in $connIds) {
            try {
                $conn = Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Get' -Id $connId
                $connMap[$connId] = $conn.Name
            }
            catch {
                Write-Verbose ('Get-GuacActiveConnection: could not resolve connection name for {0}' -f $connId)
                $connMap[$connId] = '(unknown)'
            }
        }
        foreach ($active in $activeList) {
            if ($active.ConnectionIdentifier) {
                $active | Add-Member -NotePropertyName ConnectionName -NotePropertyValue $connMap[$active.ConnectionIdentifier]
            }
        }
    }
    return $activeList
}
