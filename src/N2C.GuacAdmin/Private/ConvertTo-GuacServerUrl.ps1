function ConvertTo-GuacServerUrl {
    <#
    .SYNOPSIS
        Normalizes a Guacamole server base URL.

    .DESCRIPTION
        Validates that the supplied value is an absolute http(s) URL and
        removes any trailing slash so that it can be joined with API paths.
        Accepts the value with or without a context path, for example
        "https://guac.example.com" or "https://guac.example.com/guacamole".

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string] $Server
    )

    if ([string]::IsNullOrWhiteSpace($Server)) {
        throw (New-Object System.ArgumentException(
            'The server URL must be a non-empty absolute http(s) URL, for example "https://guac.example.com/guacamole".', 'Server'))
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($Server.Trim(), [System.UriKind]::Absolute, [ref]$uri)) {
        throw (New-Object System.ArgumentException(
            'The server URL is not a valid absolute URL: "' + $Server + '"', 'Server'))
    }
    if ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https') {
        throw (New-Object System.ArgumentException(
            'Only http and https server URLs are supported: "' + $Server + '"', 'Server'))
    }

    $base = $uri.GetLeftPart([System.UriPartial]::Path)
    return $base.TrimEnd('/')
}

function ConvertTo-GuacRestUrl {
    <#
    .SYNOPSIS
        Joins a normalized server base URL with a Guacamole REST API path.

    .DESCRIPTION
        Produces the absolute request URL for a REST call. The path must
        start with "/" (Guacamole REST paths always do, for example
        "/api/session/data/{dataSource}/connections"). Query strings already
        present in the path are preserved.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Server,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $base = ConvertTo-GuacServerUrl -Server $Server
    if (-not $Path.StartsWith('/')) {
        $Path = '/' + $Path
    }
    return $base + $Path
}
