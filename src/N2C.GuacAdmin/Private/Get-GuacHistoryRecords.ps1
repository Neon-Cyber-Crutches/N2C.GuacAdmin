function Get-GuacHistoryRecords {
    <#
    .SYNOPSIS
        Private helper: gets Guacamole activity history records.

    .DESCRIPTION
        Shared implementation for Get-GuacHistoryConnections and
        Get-GuacHistoryUsers. Retrieves activity records from the per-data-source
        UserContext history endpoint (ActivityRecordSetResource.getRecords).

        The Guacamole REST API returns time values as Unix epoch milliseconds
        (startDate, endDate). This function converts them to [DateTime] UTC.
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
          (getConnectionHistory: @Path("connections"); getUserHistory:
           @Path("users"))
        - guacamole/src/main/java/org/apache/guacamole/rest/history/ActivityRecordSetResource.java
          (getRecords: "contains" and "order" query params)
        - guacamole/src/main/java/org/apache/guacamole/rest/history/APISortPredicate.java
          (order property, "-" descending prefix)
        - guacamole/src/main/java/org/apache/guacamole/rest/history/APIActivityRecord.java
        - guacamole/src/main/java/org/apache/guacamole/rest/history/APIConnectionRecord.java
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Session,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Server = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $DataSource = [string]::Empty,

        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateSet('Connection', 'User')]
        [string] $Type = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string[]] $Contains,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Order = [string]::Empty
    )

    # Handle -DataSource All by iterating over all available data sources
    if ($DataSource -ieq 'All') {
        $allCtx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacHistoryRecords'
        foreach ($ds in $allCtx.DataSources) {
            $singleCtx = [ordered]@{
                Session    = $allCtx.Session
                Server     = $allCtx.Server
                Token      = $allCtx.Token
                DataSource = $ds
            }
            try {
                $subPath = if ($Type -eq 'Connection') { 'connections' } else { 'users' }

                # For user history, avoid the "contains" query parameter due to
                # the upstream JDBC mapper bug; filter client-side instead.
                $useServerFilter = ($Type -eq 'Connection')
                $hasContains = ($null -ne $Contains) -and ($Contains.Count -gt 0)

                $queryParts = [System.Collections.Generic.List[string]]::new()
                if ($useServerFilter -and $hasContains) {
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

                $path = Resolve-GuacContextUrl -DataSource $singleCtx['DataSource'] -Collection 'history' -SubPath $subPath -Query $query
                $response = Invoke-GuacRest -Server $singleCtx['Server'] -Token $singleCtx['Token'] -Method GET -Path $path
                if ($response) {
                    $items = if ($response -is [array]) { $response } else { @($response) }
                    foreach ($item in $items) {
                        Convert-GuacHistoryRecord -Record $item | Out-Null
                        $item | Add-Member -NotePropertyName DataSource -NotePropertyValue $ds -Force

                        # Client-side filtering for user history
                        if (-not $useServerFilter -and $hasContains) {
                            $match = $true
                            foreach ($term in $Contains) {
                                if ([string]::IsNullOrWhiteSpace($term)) { continue }
                                $termLower = $term.ToLower()
                                if ($item.Username -and $item.Username.ToString().ToLower().Contains($termLower)) { continue }
                                if ($item.RemoteHost -and $item.RemoteHost.ToString().ToLower().Contains($termLower)) { continue }
                                if ($item.StartDate -and $item.StartDate.ToString('yyyy-MM-dd').Contains($termLower)) { continue }
                                $match = $false
                                break
                            }
                            if (-not $match) { continue }
                        }
                        Write-Output $item
                    }
                }
            }
            catch {
                Write-Warning ('Get-GuacHistoryRecords: error querying data source "{0}": {1}' -f ($ds, $_.Exception.Message))
            }
        }
        return
    }

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacHistoryRecords'

    $subPath = if ($Type -eq 'Connection') { 'connections' } else { 'users' }

    # Determine if we should do server-side or client-side filtering.
    # For user history, the Guacamole JDBC mapper has an SQL syntax bug in the
    # search query that causes HTTP 500 when using the "contains" query
    # parameter (verified against guacamole-client-1.6.0 source). Additionally,
    # user history records only contain username and remoteHost — there is no
    # connection name to search. So for user history with -Contains, we always
    # fetch all records and filter client-side.
    $useServerFilter = ($Type -eq 'Connection')
    $hasContains = ($null -ne $Contains) -and ($Contains.Count -gt 0)

    if ($useServerFilter -and $hasContains) {
        # Connection history: use server-side filtering (works correctly)
        $queryParts = [System.Collections.Generic.List[string]]::new()
        foreach ($c in $Contains) {
            if (-not [string]::IsNullOrWhiteSpace($c)) {
                $queryParts.Add(('contains={0}' -f [Uri]::EscapeDataString($c)))
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($Order)) {
            $queryParts.Add(('order={0}' -f [Uri]::EscapeDataString($Order)))
        }
        $query = [string]::Empty
        if ($queryParts.Count -gt 0) { $query = ($queryParts -join '&') }
    }
    else {
        # User history or no contains: only pass order if specified
        $queryParts = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace($Order)) {
            $queryParts.Add(('order={0}' -f [Uri]::EscapeDataString($Order)))
        }
        $query = [string]::Empty
        if ($queryParts.Count -gt 0) { $query = ($queryParts -join '&') }
    }

    $path = Resolve-GuacContextUrl -DataSource $ctx['DataSource'] -Collection 'history' -SubPath $subPath -Query $query
    $response = Invoke-GuacRest -Server $ctx['Server'] -Token $ctx['Token'] -Method GET -Path $path

    # Collect results into an array so we can filter client-side if needed
    $records = [System.Collections.Generic.List[PSCustomObject]]::new()
    if ($response) {
        if ($response -is [array]) {
            foreach ($item in $response) {
                Convert-GuacHistoryRecord -Record $item | Out-Null
                $records.Add($item)
            }
        }
        else {
            Convert-GuacHistoryRecord -Record $response | Out-Null
            $records.Add($response)
        }
    }

    # Client-side filtering for user history
    if (-not $useServerFilter -and $hasContains) {
        $filtered = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($rec in $records) {
            $match = $true
            foreach ($term in $Contains) {
                if ([string]::IsNullOrWhiteSpace($term)) { continue }
                $termLower = $term.ToLower()

                # Check username
                if ($rec.Username -and $rec.Username.ToString().ToLower().Contains($termLower)) {
                    continue
                }
                # Check remoteHost
                if ($rec.RemoteHost -and $rec.RemoteHost.ToString().ToLower().Contains($termLower)) {
                    continue
                }
                # Check startDate as string (for date-like search terms)
                if ($rec.StartDate -and $rec.StartDate.ToString('yyyy-MM-dd').Contains($termLower)) {
                    continue
                }
                $match = $false
                break
            }
            if ($match) {
                $filtered.Add($rec)
            }
        }
        foreach ($rec in $filtered) {
            Write-Output $rec
        }
    }
    else {
        foreach ($rec in $records) {
            Write-Output $rec
        }
    }
}
