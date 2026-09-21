function Test-GuacSession {
    <#
    .SYNOPSIS
        Checks whether a Guacamole session token is still valid.

    .DESCRIPTION
        Issues HEAD /api/session with the token of a
        [N2C_GuacAdmin_GuacSession] and reports whether the server still
        accepts it. The server always returns 200 for a valid token
        (SessionResource.checkValidity); an invalid or expired token is
        rejected with a 401/404 by the token validation layer before the
        resource is reached, which this cmdlet converts into $false.

        The session object can be supplied directly (-Session, also from the
        pipeline) or resolved from the module default state for -Server.
        A transport failure (connection refused, timeout) terminates rather
        than returning $false, so network problems are not confused with an
        invalid token.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/session/SessionResource.java
          (HEAD /api/session -> checkValidity)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/SessionRESTService.java
          (token validation for @TokenParam)

    .EXAMPLE
        Test-GuacSession -Session $session

    .EXAMPLE
        if (Test-GuacSession -Server https://guac.example.com/guacamole) {
            # token is still valid
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [N2C_GuacAdmin_GuacSession] $Session,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Server = [string]::Empty
    )

    begin {
        $pendingSession = $null
        $pendingServer = [string]::Empty
    }

    process {
        if ($null -ne $Session) {
            $pendingSession = $Session
            $pendingServer = $Session.Server
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Server)) {
            $pendingServer = ConvertTo-GuacServerUrl -Server $Server
            $pendingSession = Get-GuacSessionState -Server $pendingServer
            if ($null -eq $pendingSession) {
                throw ($script:GuacRestExceptionType::new(
                    ("No default GuacSession exists for server '{0}'. Create one with New-GuacSession or pass -Session." -f $pendingServer)
                ))
            }
        }
    }

    end {
        if ($null -eq $pendingSession) {
            throw ($script:GuacRestExceptionType::new(
                'Test-GuacSession requires a session: supply -Session or -Server.'
            ))
        }

        try {
            Invoke-GuacRest -Server $pendingServer -Token $pendingSession.Token -Method HEAD -Path '/api/session' | Out-Null
        }
        catch {
            # Filter via the module-scope type reference (runtime catch-clause
            # type literals are resolved by name and unreliable in some hosts).
            # Note: $_ is the ErrorRecord; the status lives on the wrapped
            # exception, so capture that.
            if ($_.Exception -isnot $script:GuacRestExceptionType) {
                throw
            }
            $restError = $_.Exception
            if ($restError.StatusCode -eq 401 -or $restError.StatusCode -eq 404) {
                return $false
            }
            throw
        }
        return $true
    }
}
