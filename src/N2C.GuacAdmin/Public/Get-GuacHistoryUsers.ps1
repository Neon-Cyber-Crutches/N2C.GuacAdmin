function Get-GuacHistoryUsers {
    <#
    .SYNOPSIS
        Gets Guacamole user activity history records.

    .DESCRIPTION
        Retrieves user activity records from the per-data-source UserContext
        history endpoint (ActivityRecordSetResource.getRecords):
        GET .../history/users

        Each record (APIActivityRecord) contains: username, remoteHost,
        startDate, endDate, active, identifier, uuid, attributes, logs.

        The Guacamole REST API returns time values as Unix epoch milliseconds
        (startDate, endDate). This cmdlet converts them to [DateTime] UTC.
        Duration is not returned by the API; it is computed client-side as
        endDate - startDate for completed sessions, or now - startDate for
        active sessions (active = true). For sessions that are neither
        completed nor active, duration is $null.

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
          (getUserHistory: @Path("users"))
        - guacamole/src/main/java/org/apache/guacamole/rest/history/ActivityRecordSetResource.java
          (getRecords: "contains" and "order" query params)
        - guacamole/src/main/java/org/apache/guacamole/rest/history/APIActivityRecord.java

    .EXAMPLE
        Get-GuacHistoryUsers

    .EXAMPLE
        Get-GuacHistoryUsers -Contains 'jdoe' -Order '-startDate'
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

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string[]] $Contains,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Order = [string]::Empty
    )

    return Get-GuacHistoryRecords -Type 'User' -Session $Session -Server $Server `
        -DataSource $DataSource -Contains $Contains -Order $Order
}
