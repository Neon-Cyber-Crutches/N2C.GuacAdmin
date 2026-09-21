function Get-GuacSessionState {
    <#
    .SYNOPSIS
        Retrieves the default GuacSession for a server from module session state.

    .DESCRIPTION
        Returns the [N2C_GuacAdmin_GuacSession] stored in the module session
        state dictionary for the given server, or $null if none has been
        stored. This implements the "-CmsSession pattern": cmdlets whose
        -Session parameter was not bound (and which cannot be bound from the
        pipeline) fall back to the default session for their -Server.

        The server is matched case-insensitively and without a trailing slash.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Server
    )

    if ($script:GuacSessionState.Count -eq 0) {
        return $null
    }

    foreach ($key in $script:GuacSessionState.Keys) {
        if ($key -ieq $Server) {
            return $script:GuacSessionState[$key]
        }
    }
    return $null
}

function Set-GuacSessionState {
    <#
    .SYNOPSIS
        Stores a GuacSession in module session state as the default for a server.

    .DESCRIPTION
        Registers the given session as the default for its server so that
        subsequent cmdlet calls without -Session can resolve it. Called by
        New-GuacSession (unless -PassThru-like suppression via -NoState is not
        requested; by default New-GuacSession always registers state).

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Server,

        [Parameter(Mandatory = $true)]
        [object] $Session
    )

    $script:GuacSessionState[$Server] = $Session
}

function Clear-GuacSessionState {
    <#
    .SYNOPSIS
        Removes the default GuacSession for a server from module session state.

    .DESCRIPTION
        Removes the state entry for the given server, so that subsequent
        cmdlet calls without -Session fail with a clear error instead of
        reusing a revoked or abandoned session. Called by Remove-GuacSession.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Server
    )

    $script:GuacSessionState.Remove($Server)
}
