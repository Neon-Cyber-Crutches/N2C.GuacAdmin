function Set-GuacDataSource {
    <#
    .SYNOPSIS
        Changes the default data source for the current Guacamole session.

    .DESCRIPTION
        In multi-DataSource Guacamole instances (for example, LDAP for
        authentication plus MySQL for connection storage), the default data
        source is set at session creation from the authentication response.
        Set-GuacDataSource changes that default mid-session so that subsequent
        cmdlets without an explicit -DataSource parameter use the new source.

        The requested data source must be one of the session's
        AvailableDataSources (the list returned by the authentication response
        as availableDataSources). If it is not available for the authenticated
        user, a terminating error is thrown.

        This cmdlet does not re-authenticate or contact the server; it only
        changes which data source is used to scope subsequent UserContext REST
        calls for this session. The authentication token and all transport
        options remain unchanged.

        DataSource resolution priority (highest to lowest):
        1. Explicit -DataSource parameter on the individual cmdlet call
        2. Session default set by Set-GuacDataSource
        3. Initial default set by New-GuacSession -DataSource
        4. Token response default ($authResult.dataSource)

    .EXAMPLE
        # Switch default data source for all subsequent queries
        Set-GuacDataSource -DataSource mysql

    .EXAMPLE
        # Switch default data source with an explicit session
        Set-GuacDataSource -Session $session -DataSource ldap

    .EXAMPLE
        # Switch default data source by server name
        Set-GuacDataSource -Server https://guac.example.com/guacamole -DataSource mysql

    .EXAMPLE
        # Per-call override still takes precedence
        Set-GuacDataSource -DataSource mysql
        Get-GuacConnection -DataSource ldap  # queries ldap, not mysql

    .NOTES
        The data source is an AuthenticationProvider identifier (for example,
        "mysql" for guacamole-auth-mysql, "ldap" for guacamole-auth-ldap), not
        a database name.
    #>
    [CmdletBinding()]
    [OutputType([N2C_GuacAdmin_GuacSession])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string] $DataSource,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [N2C_GuacAdmin_GuacSession] $Session,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Server = [string]::Empty
    )

    if ([string]::IsNullOrWhiteSpace($DataSource)) {
        throw ($script:GuacRestExceptionType::new(
            '-DataSource cannot be empty.'
        ))
    }

    # Resolve the session using the same pattern as session-level cmdlets.
    $resolved = Resolve-GuacSessionForServer -Session $Session -Server $Server -CmdletName 'Set-GuacDataSource'

    # Get the session object from state (the resolved hashtable doesn't carry it).
    $server = $resolved.Server
    $stateSession = Get-GuacSessionState -Server $server
    if ($null -eq $stateSession) {
        # If no state entry exists, use the passed session (should be rare).
        if ($null -eq $Session) {
            throw ($script:GuacRestExceptionType::new(
                ('No session found for server "{0}". Create one with New-GuacSession or pass -Session.' -f $server)
            ))
        }
        $stateSession = $Session
    }

    # Validate the requested data source is available for this user.
    $available = @($stateSession.AvailableDataSources)
    if ($available.Count -gt 0 -and $available -notcontains $DataSource) {
        throw ($script:GuacRestExceptionType::new(
            ("Data source '{0}' is not available for this user. Available: {1}" -f ($DataSource, ($available -join ', ')))
        ))
    }

    # Update the session object and session state.
    $stateSession.DataSource = $DataSource
    Set-GuacSessionState -Server $server -Session $stateSession

    Write-Verbose ("N2C.GuacAdmin: default data source for server '{0}' changed to '{1}'" -f ($server, $DataSource))

    return $stateSession
}
