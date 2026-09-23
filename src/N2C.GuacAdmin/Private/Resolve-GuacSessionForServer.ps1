#Requires -Version 5.1
function Resolve-GuacSessionForServer {
    <#
    .SYNOPSIS
        Resolves the session and server for a session-level REST call (no data source).

    .DESCRIPTION
        Like Resolve-GuacSessionContext but without data-source resolution;
        used for endpoints that are not scoped to a specific AuthenticationProvider
        (for example GET /api/languages, GET /api/patches, GET /api/session/tunnels).

        Returns an ordered hashtable with Server and Token keys.

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
        [string] $CmdletName = [string]::Empty
    )

    $label = $CmdletName
    if ([string]::IsNullOrWhiteSpace($label)) { $label = 'this cmdlet' }

    $server = [string]::Empty
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
        $token = [string]$stateSession.Token
    }
    elseif ($script:GuacSessionState.Count -eq 1) {
        $server = [string]$script:GuacSessionState.Keys[0]
        $stateSession = $script:GuacSessionState[$server]
        $token = [string]$stateSession.Token
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

    return [ordered]@{
        Server = $server
        Token  = $token
    }
}
