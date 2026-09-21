#Requires -Version 5.1
<#
.SYNOPSIS
    In-process mock of the Apache Guacamole 1.6.0 REST API for Pester tests.

.DESCRIPTION
    Emulates the endpoints the module uses, with the same response shapes as
    the 1.6.0 source:
    - POST /api/tokens        (TokenRESTService.createToken)
    - DELETE /api/tokens/{t}  (TokenRESTService.invalidateToken)
    - HEAD /api/session       (SessionResource.checkValidity)
    - GET  /api/session/data/{dataSource}/self
    - GET  /api/session/data/{dataSource}/connections
    - GET  /api/notfound      (always 404 with an APIError JSON body)
    - GET  /api/plaintext-error (always 500 with a non-JSON body)

    Valid credentials: username "guacadmin", password "secret".
    Every request is appended as a JSON line to the log file (see -LogFile)
    so tests can assert what the client actually sent. Control endpoints
    (/_control/*) let tests toggle behavior without shared state.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [int] $Port,

    [Parameter(Mandatory = $true)]
    [string] $LogFile
)

$utf8 = [System.Text.Encoding]::UTF8
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add(('http://127.0.0.1:{0}/guacamole/' -f $Port))
$listener.Start()

$validTokens = @{}
$requireTotp = $false
Write-Output 'READY'
Write-Output ('PORT {0}' -f $Port)

function Send-Response {
    param (
        [System.Net.HttpListenerContext] $Context,
        [int] $Code,
        [string] $ContentType,
        [string] $Body
    )
    $response = $Context.Response
    $response.StatusCode = $Code
    if ($ContentType) { $response.ContentType = $ContentType }
    if ($Body -and $Context.Request.HttpMethod -ne 'HEAD' -and $Code -ne 204) {
        $bytes = $utf8.GetBytes($Body)
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        $response.OutputStream.Flush()
    }
    $response.OutputStream.Close()
}

function Send-ApiError {
    param (
        [System.Net.HttpListenerContext] $Context,
        [int] $Code,
        [string] $Type,
        [string] $Message
    )
    $safeMessage = $Message.Replace('"', "'")
    $safeType = [string]$Type
    $body = ('{{"message":"{0}","type":"{1}"}}' -f ($safeMessage, $safeType))
    Send-Response -Context $Context -Code $Code -ContentType 'application/json' -Body $body
}

while ($listener.IsListening) {
    $context = $null
    try { $context = $listener.GetContext() }
    catch [System.Exception] { break }
    $request = $context.Request
    $method = $request.HttpMethod.ToUpperInvariant()
    $relPath = $request.Url.AbsolutePath -replace '^/guacamole', ''
    $tokenHeader = $request.Headers['Guacamole-Token']
    $queryToken = $null
    try {
        $queryString = $request.Url.Query
        if ($queryString -and $queryString.StartsWith('?')) { $queryString = $queryString.Substring(1) }
        foreach ($pair in @($queryString -split '&')) {
            $kv = $pair -split '=', 2
            if ($kv.Count -eq 2 -and $kv[0] -eq 'token') { $queryToken = [uri]::UnescapeDataString($kv[1]) }
        }
    }
    catch [System.Exception] { $queryToken = $null }
    $token = $tokenHeader
    if ([string]::IsNullOrEmpty($token) -and $queryToken) { $token = $queryToken }

    $bodyReader = [System.IO.StreamReader]::new($request.InputStream)
    $body = $bodyReader.ReadToEnd()
    $bodyReader.Dispose()

    # Record the request (JSON line).
    $record = [ordered]@{
        method = $method
        path = $relPath
        token = $token
        tokenViaHeader = [bool]$tokenHeader
        body = $body
        contentType = [string]$request.ContentType
    }
    Add-Content -LiteralPath $LogFile -Value ($record | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8

    # ---- Control endpoints ----
    if ($relPath -eq '/_control/totp-enable') {
        $requireTotp = $true
        Send-Response -Context $context -Code 200 -ContentType 'application/json' -Body '{}'
        continue
    }
    if ($relPath -eq '/_control/totp-disable') {
        $requireTotp = $false
        Send-Response -Context $context -Code 200 -ContentType 'application/json' -Body '{}'
        continue
    }

    # ---- API endpoints ----
    if ($relPath -eq '/api/tokens' -and $method -eq 'POST') {
        # Parse the form body.
        $fields = @{}
        foreach ($pair in @($body -split '&')) {
            if ([string]::IsNullOrEmpty($pair)) { continue }
            $kv = $pair -split '=', 2
            $k = [uri]::UnescapeDataString($kv[0])
            $v = [uri]::UnescapeDataString($kv[1])
            $fields[$k] = $v
        }
        $username = [string]$fields['username']
        $password = [string]$fields['password']
        $totp = [string]$fields['guac-totp']
        if ($username -ne 'guacadmin' -or $password -ne 'secret') {
            Send-ApiError -Context $context -Code 401 -Type 'INVALID_CREDENTIALS' -Message 'Invalid credentials.'
            continue
        }
        if ($requireTotp) {
            if ([string]::IsNullOrEmpty($totp)) {
                Send-ApiError -Context $context -Code 401 -Type 'INSUFFICIENT_CREDENTIALS' -Message 'A TOTP authentication code is required before login can continue.'
                continue
            }
            if ($totp -ne '123456') {
                Send-ApiError -Context $context -Code 401 -Type 'INVALID_CREDENTIALS' -Message 'Provided TOTP code is not valid.'
                continue
            }
        }
        $newToken = ('mocktoken-' + [System.Guid]::NewGuid().ToString('N'))
        $validTokens[$newToken] = $true
        $result = [ordered]@{
            authToken = $newToken
            username = $username
            dataSource = 'mysql'
            availableDataSources = @('mysql', 'ldap')
        }
        Send-Response -Context $context -Code 200 -ContentType 'application/json' -Body ($result | ConvertTo-Json -Compress -Depth 5)
        continue
    }

    if ($relPath -like '/api/tokens/*' -and $method -eq 'DELETE') {
        $tokenPath = $relPath.Substring('/api/tokens/'.Length)
        if ($validTokens.ContainsKey($tokenPath)) {
            $validTokens.Remove($tokenPath)
            Send-Response -Context $context -Code 204 -ContentType $null -Body $null
        }
        else {
            Send-ApiError -Context $context -Code 401 -Type 'NOT_FOUND' -Message 'No such token.'
        }
        continue
    }

    # Everything under /api/session requires a valid token
    # (SessionRESTService.getSessionResource -> getGuacamoleSession).
    if ($relPath -like '/api/session*') {
        if ([string]::IsNullOrEmpty($token) -or -not $validTokens.ContainsKey($token)) {
            Send-ApiError -Context $context -Code 401 -Type 'NOT_FOUND' -Message 'No such token.'
            continue
        }
        if ($relPath -eq '/api/session' -and $method -eq 'HEAD') {
            Send-Response -Context $context -Code 200 -ContentType $null -Body $null
            continue
        }
        if ($relPath -eq '/api/session/data/mysql/self' -and $method -eq 'GET') {
            $self = [ordered]@{
                identifier = 'guacadmin'
                email = 'guacadmin@example.com'
                attributes = @{ 'guac-full-name' = 'Guac Admin' }
            }
            Send-Response -Context $context -Code 200 -ContentType 'application/json' -Body ($self | ConvertTo-Json -Compress -Depth 5)
            continue
        }
        if ($relPath -eq '/api/session/data/mysql/connections' -and $method -eq 'GET') {
            $conns = [ordered]@{
                'conn-1' = [ordered]@{
                    name = 'test-connection'
                    protocol = 'rdp'
                    parameters = @{ 'hostname' = 'host.example.com' }
                    maximumConnections = -1
                }
            }
            Send-Response -Context $context -Code 200 -ContentType 'application/json' -Body ($conns | ConvertTo-Json -Compress -Depth 6)
            continue
        }
    }

    if ($relPath -eq '/api/notfound' -and $method -eq 'GET') {
        Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message 'No such resource.'
        continue
    }
    if ($relPath -eq '/api/plaintext-error' -and $method -eq 'GET') {
        Send-Response -Context $context -Code 500 -ContentType 'text/plain' -Body 'Internal server error (no JSON body).'
        continue
    }

    # Default: 404 APIError.
    Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message ('No such resource: ' + $relPath)
}

$listener.Stop()
Write-Output 'STOPPED'
