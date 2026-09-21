function Remove-GuacSession {
    <#
    .SYNOPSIS
        Revokes a Guacamole session token and clears its module state.

    .DESCRIPTION
        Revokes the authentication token of a [N2C_GuacAdmin_GuacSession]
        via DELETE /api/tokens/{token} and removes the session from the
        module default-session state for its server. The token becomes
        unusable on the server: any active tunnels or pending requests
        associated with it are invalidated.

        The session object can be supplied directly (-Session, also from the
        pipeline) or resolved from the module default state for -Server.

        If the token has already been revoked or has expired server-side,
        the server reports "no such token" (401/404). In that case the local
        state entry is stale and is cleared without an error (a verbose
        message is written); -Force is accepted for scripting symmetry and
        does not change behavior. Any other failure (network, 5xx) terminates
        and leaves the local state intact.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/auth/TokenRESTService.java
          (DELETE /api/tokens/{token} -> invalidateToken)

    .EXAMPLE
        Remove-GuacSession -Session $session

    .EXAMPLE
        Remove-GuacSession -Server https://guac.example.com/guacamole

    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([void])]
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
        # Resolve the session: explicit -Session (also from pipeline) wins;
        # otherwise fall back to the module default for -Server.
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
                'Remove-GuacSession requires a session: supply -Session or -Server.'
            ))
        }

        $target = $pendingSession
        $targetServer = $pendingServer

        if (-not ($PSCmdlet.ShouldProcess($targetServer, 'Revoke Guacamole session token (DELETE /api/tokens)'))) {
            return
        }

        $serverCallSucceeded = $false
        try {
            Invoke-GuacRest -Server $targetServer -Token $target.Token -Method DELETE `
                -Path ('/api/tokens/{0}' -f [Uri]::EscapeDataString($target.Token)) | Out-Null
            $serverCallSucceeded = $true
        }
        catch {
            # Filter via the module-scope type reference (runtime catch-clause
            # type literals are resolved by name and unreliable in some hosts).
            # Note: $_ is the ErrorRecord; the status/reason live on the
            # wrapped exception, so capture that.
            if ($_.Exception -isnot $script:GuacRestExceptionType) {
                throw
            }
            $restError = $_.Exception
            $tokenAlreadyGone = ($restError.StatusCode -in 401, 404) -or
                (($restError.Reason -and $restError.Reason -match 'no such token'))
            if ($tokenAlreadyGone) {
                $serverCallSucceeded = $true
                Write-Verbose ("N2C.GuacAdmin: token for '{0}' was already invalid on the server; clearing local state only." -f $targetServer)
            }
            else {
                throw
            }
        }

        # The token is gone on the server (revoked or already expired), so
        # the local default-state entry is stale: remove it.
        if ($serverCallSucceeded) {
            Clear-GuacSessionState -Server $targetServer
        }
    }
}
