function Get-GuacTransportOptions {
    <#
    .SYNOPSIS
        Builds a splatting hashtable of transport options from a GuacSession.

    .DESCRIPTION
        Extracts the TLS, proxy, and timeout settings carried by a
        [N2C_GuacAdmin_GuacSession] (or a server base URL for anonymous calls)
        into a hashtable suitable for splatting to Invoke-GuacRest. Public
        cmdlets use this so that every request for a session reuses the exact
        channel configuration the session was created with.

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
        [string] $Token = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [int] $TimeoutSec = 0
    )

    $options = [ordered]@{}
    if ($null -ne $Session) {
        if ([string]::IsNullOrWhiteSpace($Server)) { $Server = [string]$Session.Server }
        if ([string]::IsNullOrWhiteSpace($Token)) { $Token = [string]$Session.Token }
        $options['Server'] = $Server
        $options['CertificateThumbprint'] = [string]$Session.CertificateThumbprint
        $options['Certificate'] = $Session.Certificate
        $options['Proxy'] = [string]$Session.Proxy
        $options['ProxyCredential'] = $Session.ProxyCredential
        $options['NoProxy'] = [string]$Session.NoProxy
        if ($TimeoutSec -le 0) { $options['TimeoutSec'] = [int]$Session.TimeoutSec }
    }
    else {
        $options['Server'] = $Server
        $options['CertificateThumbprint'] = [string]::Empty
        $options['Certificate'] = $null
        $options['Proxy'] = [string]::Empty
        $options['ProxyCredential'] = $null
        $options['NoProxy'] = [string]::Empty
    }
    if ($TimeoutSec -gt 0) { $options['TimeoutSec'] = $TimeoutSec }
    $options['Token'] = $Token
    return $options
}

function Invoke-GuacRest {
    <#
    .SYNOPSIS
        Single private REST transport for all Guacamole API calls.

    .DESCRIPTION
        Executes an HTTP request against a Guacamole instance and converts
        every failure into a terminating [N2C_GuacAdmin_GuacRestException]
        (raised as a terminating ErrorRecord, so callers can catch it and read
        StatusCode/Type/Reason/Endpoint/RawBody). No caller can observe a
        silent failure: non-2xx responses and transport-level errors
        (connection refused, DNS failure, timeout) always terminate.

        The authentication token is transmitted via the "Guacamole-Token"
        header rather than the "token" query parameter. Both are accepted by
        the server with the header taking priority (see
        guacamole/src/main/java/org/apache/guacamole/rest/auth/AuthenticationService.java,
        getAuthenticationToken), and using the header keeps the token out of
        URIs that proxies, load balancers, and client-side logging may record.

        On success the response body is returned already decoded: JSON
        responses are parsed to PowerShell objects on both Windows PowerShell
        5.1 and PowerShell 7.x; non-JSON bodies are returned as strings;
        HEAD and empty-body 204 responses return $true.

        Cross-version notes:
        - The request is always sent through a WebRequestSession so that
          custom headers and the client certificate work identically on 5.1
          (where Invoke-WebRequest has no -Headers parameter) and 7.x.
        - -UseBasicParsing is added only on 5.1 (it does not exist in 7.x).
        - -CertificateThumbprint is supported on both versions; an
          X509Certificate2 is installed on the WebRequestSession.
        - Parameter availability is detected once at module load time
          ($script:GuacIwrCapabilities).

        Reference: guacamole/src/main/java/org/apache/guacamole/rest/**
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Server,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Token = [string]::Empty,

        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'HEAD')]
        [string] $Method,

        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Body,

        [Parameter(Mandatory = $false)]
        [ValidateSet('application/json', 'application/x-www-form-urlencoded')]
        [string] $ContentType = 'application/json',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $CertificateThumbprint = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Security.Cryptography.X509Certificates.X509Certificate2] $Certificate,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Proxy = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Management.Automation.PSCredential] $ProxyCredential,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $NoProxy = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [int] $TimeoutSec = 30
    )

    if ($TimeoutSec -le 0) { $TimeoutSec = 30 }

    $url = ConvertTo-GuacRestUrl -Server $Server -Path $Path

    $maskedToken = ConvertTo-GuacMaskedSecret -Value $Token
    Write-Verbose ("N2C.GuacAdmin: {0} {1} (token={2})" -f ($Method, $url, $maskedToken))

    # ---- Build the WebRequestSession (headers + client certificate) ----
    # A WebRequestSession is used (instead of the -Headers parameter, which
    # does not exist on Windows PowerShell 5.1) so that custom headers work
    # identically on both versions.
    $webSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $webSession.UserAgent = 'N2C.GuacAdmin'
    if (-not [string]::IsNullOrEmpty($Token)) {
        $webSession.Headers.Add('Guacamole-Token', $Token)
    }
    if ($null -ne $Certificate) {
        $webSession.ClientCertificate = $Certificate
    }

    # ---- Assemble Invoke-WebRequest arguments ----
    $iwrArgs = [ordered]@{}
    $iwrArgs['Uri'] = $url
    $iwrArgs['Method'] = $Method
    $iwrArgs['WebSession'] = $webSession
    $iwrArgs['TimeoutSec'] = $TimeoutSec
    $iwrArgs['ErrorAction'] = 'Stop'

    if ($null -ne $Body) {
        $bodyString = [string]$Body
        $iwrArgs['Body'] = $bodyString
        $iwrArgs['ContentType'] = $ContentType
    }

    if (-not [string]::IsNullOrEmpty($CertificateThumbprint)) {
        $iwrArgs['CertificateThumbprint'] = $CertificateThumbprint
    }
    if (-not [string]::IsNullOrEmpty($Proxy)) {
        $iwrArgs['Proxy'] = $Proxy
        if ($null -ne $ProxyCredential) {
            $iwrArgs['ProxyCredential'] = $ProxyCredential
        }
    }
    if (-not [string]::IsNullOrEmpty($NoProxy) -and $script:GuacIwrCapabilities.Contains('NoProxy')) {
        $iwrArgs['NoProxy'] = $NoProxy
    }
    if ($script:GuacIwrCapabilities.Contains('UseBasicParsing')) {
        $iwrArgs['UseBasicParsing'] = $true
    }

    # ---- Execute ----
    try {
        $response = Invoke-WebRequest @iwrArgs
    }
    catch [System.Management.Automation.ActionPreferenceStopException] {
        throw
    }
    catch [System.Exception] {
        $statusCode = Get-GuacResponseStatus -ErrorRecord $_
        $bodyText = $null
        if ($statusCode -ne 0) {
            $bodyText = Get-GuacResponseBody -ErrorRecord $_
        }
        $apiError = ConvertFrom-GuacErrorBody -Body $bodyText

        $reason = $null
        if ($null -ne $apiError.Message) {
            $reason = [string]$apiError.Message
        }
        elseif ($null -ne $apiError.Type) {
            $reason = [string]$apiError.Type
        }
        else {
            $reason = $_.Exception.Message
        }

        # Mask the token in the endpoint (it may appear in the URL path, for
        # example DELETE /api/tokens/{token}).
        $safeUrl = $url
        if (-not [string]::IsNullOrEmpty($Token) -and $safeUrl.Contains($Token)) {
            $safeUrl = $safeUrl.Replace($Token, $maskedToken)
        }

        if ($statusCode -eq 0) {
            $message = 'Guacamole REST request failed: {0} {1} ({2})' -f ($Method, $safeUrl, $reason)
        }
        else {
            $message = 'Guacamole REST request failed: {0} {1} -> HTTP {2}: {3}' -f ($Method, $safeUrl, $statusCode, $reason)
        }

        # Construct via the module-scope type reference (captured at load time
        # in N2C.GuacAdmin.psm1) rather than New-Object by name: runtime
        # resolution of the class name inside module scope is unreliable in
        # some hosts (observed: TypeNotFound under Pester 5.7.1).
        $exception = $script:GuacRestExceptionType::new($message, $_.Exception)
        $exception.StatusCode = $statusCode
        $exception.Type = [string]$apiError.Type
        $exception.Endpoint = $safeUrl
        $exception.Reason = $reason
        $exception.RawBody = $bodyText

        $category = Get-GuacErrorCategory -StatusCode $statusCode
        $record = New-Object System.Management.Automation.ErrorRecord(
            $exception, 'GuacRestRequestFailed', $category, $url)
        $PSCmdlet.ThrowTerminatingError($record)
    }

    # ---- Decode the success response ----
    if ($Method -eq 'HEAD') {
        return $true
    }

    $content = $response.Content
    $responseHeaders = $null
    try {
        $responseHeaders = $response.Headers
    }
    catch [System.Exception] {
        $responseHeaders = $null
    }
    $responseContentType = Get-GuacResponseHeaderValue -Headers $responseHeaders -Name 'Content-Type'

    if ($null -eq $content) {
        return $true
    }
    if ($content -is [string]) {
        if ([string]::IsNullOrEmpty($content)) {
            return $true
        }
        if ($responseContentType -and $responseContentType -match 'json') {
            return ($content | ConvertFrom-Json)
        }
        return $content
    }
    # PowerShell 7.x Invoke-WebRequest already decodes JSON content into
    # objects; return whatever it produced.
    return $content
}
