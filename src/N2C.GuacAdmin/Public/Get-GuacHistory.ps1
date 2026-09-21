function Get-GuacHistory {
    <#
    .SYNOPSIS
        Gets Guacamole activity history records.

    .DESCRIPTION
        Retrieves activity records from the per-data-source UserContext
        history endpoint (ActivityRecordSetResource.getRecords):
        - -Type Connection: GET .../history/connections
          (APIConnectionRecord: connectionIdentifier, connectionName,
          username, remoteHost, startDate, endDate, duration,
          readOnly, activeConnections, sharingProfile)
        - -Type User: GET .../history/users
          (APIUserRecord: username, remoteHost, startDate, endDate,
          duration, connectionCount, readWriteCount, readOnlyCount)

        The -Contains parameter (one or more strings) filters the records so
        that every string occurs somewhere within each returned record (the
        server's "contains" query parameter). The -Order parameter sorts the
        results; it takes a sortable property name ("startDate") optionally
        prefixed with "-" for descending order (the server's "order" query
        parameter). The server always caps the result at 1000 records.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("history") -> HistoryResource)
        - guacamole/src/main/java/org/apache/guacamole/rest/history/HistoryResource.java
          (getConnectionHistory: @Path("connections"); getUserHistory:
           @Path("users"))
        - guacamole/src/main/java/org/apache/guacamole/rest/history/ActivityRecordSetResource.java
          (getRecords: "contains" and "order" query params)
        - guacamole/src/main/java/org/apache/guacamole/rest/history/APISortPredicate.java
          (order property, "-" descending prefix)
        - guacamole/src/main/java/org/apache/guacamole/rest/history/APIConnectionRecord.java
        - guacamole/src/main/java/org/apache/guacamole/rest/history/APIUserRecord.java

    .EXAMPLE
        Get-GuacHistory -Type Connection

    .EXAMPLE
        Get-GuacHistory -Type User -Contains 'jdoe' -Order '-startDate'

    .EXAMPLE
        Get-GuacHistory -Type Connection -Contains '192.168.1.10' -Order startDate
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

        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('Connection', 'User')]
        [string] $Type,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string[]] $Contains,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Order = [string]::Empty
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacHistory'

    $subPath = if ($Type -eq 'Connection') { 'connections' } else { 'users' }

    $queryParts = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $Contains) {
        foreach ($c in $Contains) {
            if (-not [string]::IsNullOrWhiteSpace($c)) {
                $queryParts.Add(('contains={0}' -f [Uri]::EscapeDataString($c)))
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Order)) {
        $queryParts.Add(('order={0}' -f [Uri]::EscapeDataString($Order)))
    }

    $query = [string]::Empty
    if ($queryParts.Count -gt 0) { $query = ($queryParts -join '&') }

    $path = Resolve-GuacContextUrl -DataSource $ctx['DataSource'] -Collection 'history' -SubPath $subPath -Query $query
    return (Invoke-GuacRest -Server $ctx['Server'] -Token $ctx['Token'] -Method GET -Path $path)
}
