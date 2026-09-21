function Get-GuacResponseStatus {
    <#
    .SYNOPSIS
        Extracts the HTTP status code from a caught transport error.

    .DESCRIPTION
        Walks the exception chain (the exception itself and its inner
        exceptions, because PowerShell 7 wraps Invoke-WebRequest failures in
        additional exception layers) and returns the status code found on the
        first response object. Response objects may be HttpWebResponse
        (Windows PowerShell 5.1) or HttpResponseMessage (PowerShell 7.x).
        Returns 0 when no response is available, which is how the transport
        signals a transport-level failure (connection refusal, DNS failure,
        timeout) as opposed to an HTTP error status.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        try {
            $response = $exception.Response
        }
        catch [System.Exception] {
            $response = $null
        }
        if ($null -ne $response) {
            try {
                return [int]$response.StatusCode
            }
            catch [System.Exception] {
                # Response object without a usable status; keep walking.
            }
        }
        $exception = $exception.InnerException
    }
    return 0
}

function Get-GuacResponseBody {
    <#
    .SYNOPSIS
        Extracts the raw response body text from a caught transport error.

    .DESCRIPTION
        Tries, in order: PowerShell's ErrorDetails.Message (populated by
        Invoke-WebRequest on HTTP error responses on both 5.1 and 7.x), the
        HttpResponseMessage content (PowerShell 7.x), and finally the
        underlying response stream (Windows PowerShell 5.1). Returns $null
        when no body is available (transport-level failures have no body).

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        return $ErrorRecord.ErrorDetails.Message
    }

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        try {
            $response = $exception.Response
        }
        catch [System.Exception] {
            $response = $null
        }
        if ($null -ne $response) {
            if ($response -is [System.Net.Http.HttpResponseMessage] -and $null -ne $response.Content) {
                try {
                    return $response.Content.ReadAsStringAsync().Result
                }
                catch [System.Exception] {
                    # Fall through to the stream attempt below.
                }
            }
            try {
                $stream = $response.GetResponseStream()
                if ($null -ne $stream) {
                    $reader = [System.IO.StreamReader]::new($stream)
                    try {
                        return $reader.ReadToEnd()
                    }
                    finally {
                        $reader.Dispose()
                    }
                }
            }
            catch [System.Exception] {
                # No stream available; keep walking.
            }
        }
        $exception = $exception.InnerException
    }
    return $null
}

function Get-GuacResponseHeaderValue {
    <#
    .SYNOPSIS
        Looks up a response header value case-insensitively.

    .DESCRIPTION
        Response header collections differ between Windows PowerShell 5.1
        (case-insensitive NameValueCollection) and PowerShell 7.x
        (case-sensitive OrderedDictionary), so the lookup scans the keys with
        an ordinal case-insensitive comparison.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object] $Headers,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if ($null -eq $Headers) {
        return $null
    }

    try {
        foreach ($key in $Headers.Keys) {
            if ([string]$key -ieq $Name) {
                return [string]$Headers[$key]
            }
        }
    }
    catch [System.Exception] {
        # Header collection without a Keys property; nothing to look up.
    }
    return $null
}

function Get-GuacErrorCategory {
    <#
    .SYNOPSIS
        Maps an HTTP status code to a PowerShell error category.

    .DESCRIPTION
        Used by the transport to build terminating ErrorRecords with
        meaningful ErrorCategory values. A status of 0 (transport failure)
        maps to ConnectionFailure.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorCategory])]
    param (
        [Parameter(Mandatory = $true)]
        [int] $StatusCode
    )

    switch ($StatusCode) {
        0 {
            # Note: the correct member is ConnectionError; there is no
            # ConnectionFailure on System.Management.Automation.ErrorCategory
            # (an incorrect static member resolves to $null at runtime).
            return [System.Management.Automation.ErrorCategory]::ConnectionError
        }
        { $_ -eq 401 -or $_ -eq 403 } {
            return [System.Management.Automation.ErrorCategory]::SecurityError
        }
        { $_ -ge 400 -and $_ -lt 500 } {
            return [System.Management.Automation.ErrorCategory]::InvalidArgument
        }
        default {
            return [System.Management.Automation.ErrorCategory]::ResourceUnavailable
        }
    }
}
