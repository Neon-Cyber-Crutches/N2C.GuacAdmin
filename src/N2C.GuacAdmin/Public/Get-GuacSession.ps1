function Get-GuacSession {
    <#
    .SYNOPSIS
        Returns the current default GuacSession registered for a server.

    .DESCRIPTION
        Returns the [N2C_GuacAdmin_GuacSession] that the module is using by
        default for the given server (the "-CmsSession pattern"), or $null if
        no default has been registered for that server (for example because no
        New-GuacSession has been called, or the default was removed by
        Remove-GuacSession).

        This is a read-only inspection helper: it does not authenticate and
        does not touch the server. Use it to see which session a cmdlet that
        was given only -Server would resolve to.

        .Server is matched case-insensitively and without a trailing slash.

    .EXAMPLE
        $default = Get-GuacSession -Server https://guac.example.com/guacamole
        if ($default) { "Default session for user '$($default.Username)' is active." }
    #>
    [CmdletBinding()]
    [OutputType([N2C_GuacAdmin_GuacSession])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Server
    )

    $normalizedServer = ConvertTo-GuacServerUrl -Server $Server
    return (Get-GuacSessionState -Server $normalizedServer)
}
