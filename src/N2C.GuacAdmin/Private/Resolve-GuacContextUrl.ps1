#Requires -Version 5.1
function Resolve-GuacSessionContext {
    <#
    .SYNOPSIS
        Resolves the session, server, and data source for a UserContext REST call.

    .DESCRIPTION
        Implements the shared -Session/-Server resolution used by every
        entity cmdlet (the same pattern as Remove-GuacSession and
        Test-GuacSession): an explicit [N2C_GuacAdmin_GuacSession] (also
        accepted from the pipeline) wins; otherwise the module default
        session for -Server is used.

        Returns an ordered hashtable with the resolved values:
        - Session      : the [N2C_GuacAdmin_GuacSession] to use
        - Server       : the normalized server base URL
        - Token        : the authentication token (masked nowhere; carried
                         only for the transport)
        - DataSource   : the data source (AuthenticationProvider identifier)
                         to scope the UserContext path to; defaults to
                         $session.DataSource

        Throws a terminating [N2C_GuacAdmin_GuacRestException] when no
        session can be resolved, when the session carries no token, or when
        an explicit -DataSource override is not among the session's
        available data sources.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/session/SessionResource.java
          (getUserContextResource: /session/data/{dataSource})
        - guacamole/src/main/java/org/apache/guacamole/rest/auth/APIAuthenticationResult.java
          (dataSource, availableDataSources from POST /api/tokens)

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Session,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Server = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $DataSource = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [string] $CmdletName = [string]::Empty
    )

    $label = $CmdletName
    if ([string]::IsNullOrWhiteSpace($label)) { $label = 'this cmdlet' }

    $token = [string]::Empty
    if ($null -ne $Session) {
        $server = [string]$Session.Server
        $token = [string]$Session.Token
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Server)) {
        $server = ConvertTo-GuacServerUrl -Server $Server
        $stateSession = Get-GuacSessionState -Server $server
        if ($null -eq $stateSession) {
            throw ($script:GuacRestExceptionType::new(
                ("No default GuacSession exists for server '{0}'. Create one with New-GuacSession or pass -Session." -f $server)
            ))
        }
        $Session = $stateSession
        $token = [string]$Session.Token
    }
    else {
        throw ($script:GuacRestExceptionType::new(
            ('{0} requires a session: supply -Session or -Server.' -f $label)
        ))
    }

    if ([string]::IsNullOrWhiteSpace($token)) {
        throw ($script:GuacRestExceptionType::new(
            ("The session for server '{0}' carries no authentication token." -f $server)
        ))
    }

    if ([string]::IsNullOrWhiteSpace($DataSource)) {
        $DataSource = [string]$Session.DataSource
    }
    $available = @($Session.AvailableDataSources)
    if ($available -and $available.Count -gt 0 -and $available -notcontains $DataSource) {
        throw ($script:GuacRestExceptionType::new(
            ("Data source '{0}' is not available for this user. Available: {1}" -f ($DataSource, ($available -join ', ')))
        ))
    }
    if ([string]::IsNullOrWhiteSpace($DataSource)) {
        throw ($script:GuacRestExceptionType::new(
            'The session carries no data source and no -DataSource was supplied.'
        ))
    }

    return [ordered]@{
        Session      = $Session
        Server       = $server
        Token        = $token
        DataSource   = $DataSource
    }
}

function Resolve-GuacContextUrl {
    <#
    .SYNOPSIS
        Builds a per-DataSource UserContext REST API path.

    .DESCRIPTION
        Produces the request path for the UserContext REST surface:
        "/api/session/data/{dataSource}/{collection}[/{id}][/{subpath}][?query]".

        Each segment is URL-escaped individually with [Uri]::EscapeDataString,
        which is required because Guacamole identifiers (connection UUIDs,
        usernames, group names) may legally contain characters such as "/"
        or "#". The collection name, the object identifier, and the literal
        subpath are therefore passed as separate parameters. A query string
        (without the leading "?") may be appended last; it is not escaped.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/session/SessionResource.java
          (getUserContextResource: @Path("data/{dataSource}"))
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path subresources: connections, connectionGroups, users, userGroups,
           sharingProfiles, history, schema)
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (@Path("{identifier}") object resource)

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $DataSource,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Collection = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Id = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $SubPath = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Query = [string]::Empty
    )

    if ([string]::IsNullOrWhiteSpace($DataSource)) {
        throw (New-Object System.ArgumentException(
            'The data source must be a non-empty AuthenticationProvider identifier.', 'DataSource'))
    }

    $url = '/api/session/data/' + [Uri]::EscapeDataString($DataSource)
    if (-not [string]::IsNullOrWhiteSpace($Collection)) {
        $url += '/' + [Uri]::EscapeDataString($Collection)
    }
    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $url += '/' + [Uri]::EscapeDataString($Id)
    }
    if (-not [string]::IsNullOrWhiteSpace($SubPath)) {
        $sub = $SubPath
        if ($sub.StartsWith('/')) { $sub = $sub.Substring(1) }
        if ($sub.EndsWith('/')) { $sub = $sub.TrimEnd('/') }
        $url += '/' + $sub
    }
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $url += '?' + $Query
    }
    return $url
}
