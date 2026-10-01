function Get-GuacErrorCategory {
    <#
    .SYNOPSIS
        Maps an HTTP status code to a PowerShell ErrorCategory.

    .DESCRIPTION
        Transport-level failures (status 0) map to ConnectionError.
        Authentication failures (401, 403) map to SecurityError.
        Client errors (404, 429, etc.) map to InvalidArgument.
        Server errors (500, 503, etc.) map to ResourceUnavailable.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorCategory])]
    param (
        [Parameter(Mandatory = $true)]
        [int] $StatusCode
    )

    switch ($StatusCode) {
        0 { return [System.Management.Automation.ErrorCategory]::ConnectionError }
        401 { return [System.Management.Automation.ErrorCategory]::SecurityError }
        403 { return [System.Management.Automation.ErrorCategory]::SecurityError }
        404 { return [System.Management.Automation.ErrorCategory]::InvalidArgument }
        429 { return [System.Management.Automation.ErrorCategory]::InvalidArgument }
        500 { return [System.Management.Automation.ErrorCategory]::ResourceUnavailable }
        503 { return [System.Management.Automation.ErrorCategory]::ResourceUnavailable }
        default {
            if ($StatusCode -ge 500) {
                return [System.Management.Automation.ErrorCategory]::ResourceUnavailable
            }
            return [System.Management.Automation.ErrorCategory]::InvalidArgument
        }
    }
}

function Get-GuacResponseStatus {
    <#
    .SYNOPSIS
        Extracts the HTTP status code from a caught transport error.

    .DESCRIPTION
        Inspects the exception chain to find the underlying web response. In
        PowerShell 7.x, Invoke-WebRequest throws HttpRequestException with a
        Response property of type HttpResponseMessage. In Windows PowerShell
        5.1, it throws WebException with Response of type HttpWebResponse.
        Returns 0 when the exception is transport-level (no response received).

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
        # Windows PowerShell 5.1: WebException with HttpWebResponse.
        try {
            if ($exception -is [System.Net.WebException] -and
                $null -ne $exception.Response) {
                $response = $exception.Response
                if ($response -is [System.Net.HttpWebResponse]) {
                    return [int]$response.StatusCode
                }
            }
        }
        catch [System.Exception] {
            # Best effort; keep walking.
        }

        # PowerShell 7.x: HttpRequestException with HttpResponseMessage.
        # The type check must be wrapped because the type may not exist
        # in Windows PowerShell 5.1 (.NET Framework).
        try {
            $httpReqExType = [System.Net.Http.HttpRequestException]
            if ($exception -is $httpReqExType -and
                $null -ne $exception.Response) {
                return [int]$exception.Response.StatusCode
            }
        }
        catch [System.Exception] {
            # Type may not exist in PS 5.1; keep walking.
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

    # First check ErrorDetails.Message (set by Invoke-WebRequest on HTTP errors)
    if ($null -ne $ErrorRecord.ErrorDetails) {
        try {
            $message = $ErrorRecord.ErrorDetails.Message
            if (-not [string]::IsNullOrEmpty($message)) {
                return $message
            }
        }
        catch [System.Exception] {
            # Best effort; keep going.
        }
    }

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        $response = $null
        try {
            # Windows PowerShell 5.1: WebException with HttpWebResponse
            if ($exception -is [System.Net.WebException]) {
                $webEx = $exception
                if ($null -ne $webEx.Response) {
                    $response = $webEx.Response
                }
            }
            # PowerShell 7.x: HttpRequestException with HttpResponseMessage
            elseif ($exception -is [System.Net.Http.HttpRequestException]) {
                $httpEx = $exception
                if ($null -ne $httpEx.Response) {
                    $response = $httpEx.Response
                }
            }
        }
        catch [System.Exception] {
            # Best effort; keep walking.
        }

        if ($null -ne $response) {
            try {
                # PowerShell 7.x: HttpResponseMessage
                # The type check must be wrapped because the type may not exist
                # in Windows PowerShell 5.1 (.NET Framework).
                try {
                    $httpRespMsgType = [System.Net.Http.HttpResponseMessage]
                    if ($response -is $httpRespMsgType) {
                        $task = $response.Content.ReadAsStringAsync()
                        $task.Wait(2000)
                        return $task.Result
                    }
                }
                catch [System.Exception] {
                    # Type may not exist in PS 5.1; fall through to WebResponse handling.
                }

                # Windows PowerShell 5.1: WebResponse
                if ($response -is [System.Net.WebResponse]) {
                    $stream = $response.GetResponseStream()
                    if ($null -ne $stream) {
                        try {
                            # Use UTF-8 encoding explicitly for PS 5.1 compatibility
                            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
                            try {
                                $body = $reader.ReadToEnd()
                                if (-not [string]::IsNullOrEmpty($body)) {
                                    return $body
                                }
                            }
                            finally {
                                $reader.Dispose()
                            }
                        }
                        finally {
                            $stream.Dispose()
                        }
                    }
                }
            }
            catch [System.Exception] {
                # Best effort; keep walking.
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
        # No Keys property or enumeration failed; return null.
    }

    # Fall back to direct indexer access (case-insensitive on 5.1).
    try {
        $value = $Headers[$Name]
        if ($null -ne $value) {
            return [string]$value
        }
    }
    catch [System.Exception] {
        # Indexer not available; return null.
    }

    return $null
}
