function New-GuacSession {
    <#
    .SYNOPSIS
        Authenticates to an Apache Guacamole instance and returns a session object.

    .DESCRIPTION
        Performs the Guacamole REST login (POST /api/tokens) with the supplied
        credentials and returns a [N2C_GuacAdmin_GuacSession] object holding
        the authentication token, the authenticated username, the default
        data source (AuthenticationProvider identifier) from the token
        response, and all available data sources.

        The returned session object is the single source of authentication
        state for all other cmdlets: pass it via -Session, or rely on the
        module default (this cmdlet registers the new session as the default
        for its server, the "-CmsSession pattern"). Multiple servers and
        multiple users can be worked with in one process; each server keeps
        its own default session.

        The password is only accepted as part of a PSCredential; plaintext
        string passwords are deliberately not supported. If TOTP two-factor
        authentication is enabled on the instance, supply -TotpCode
        (a SecureString).

        Transport options (TLS client certificate, proxy, timeout) are
        carried by the session object and applied to every request made with
        it.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/auth/TokenRESTService.java
          (POST /api/tokens; form parameters username, password, token)
        - extensions/guacamole-auth-totp/.../form/AuthenticationCodeField.java
          (the optional "guac-totp" form parameter)
        - guacamole/src/main/java/org/apache/guacamole/rest/auth/APIAuthenticationResult.java
          (response: authToken, username, dataSource, availableDataSources)

    .EXAMPLE
        $cred = Get-Credential
        $session = New-GuacSession -Server https://guac.example.com/guacamole -Credential $cred

    .EXAMPLE
        $session = New-GuacSession -Server https://guac.example.com/guacamole `
            -Credential $cred -TotpCode (Read-Host -Prompt 'TOTP code' -AsSecureString)

    .EXAMPLE
        $session = New-GuacSession -Server https://guac.example.com/guacamole `
            -Credential $cred -DataSource ldap
    #>
    [CmdletBinding()]
    [OutputType([N2C_GuacAdmin_GuacSession])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Server,

        [Parameter(Mandatory = $true, Position = 1)]
        [System.Management.Automation.CredentialAttribute()]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Security.SecureString] $TotpCode,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $DataSource = [string]::Empty,

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
        [ValidateRange(1, 3600)]
        [int] $TimeoutSec = 30
    )

    $normalizedServer = ConvertTo-GuacServerUrl -Server $Server

    # Build the login form body (username/password, optional guac-totp).
    # The plaintext password exists only inside the form body and the
    # WebRequestSession; it is never stored on the session object.
    $password = ConvertFrom-GuacSecureString -SecureString $Credential.Password
    $formFields = [ordered]@{
        'username' = $Credential.UserName
        'password' = $password
    }
    if ($null -ne $TotpCode) {
        $formFields['guac-totp'] = ConvertFrom-GuacSecureString -SecureString $TotpCode
    }
    $formBody = ConvertTo-GuacFormUrlEncoded -Fields $formFields

    Write-Verbose ("N2C.GuacAdmin: authenticating to {0} as '{1}'" -f ($normalizedServer, $Credential.UserName))

    # Anonymous call (no token yet). The server base URL is passed directly.
    try {
        $authResult = Invoke-GuacRest -Server $normalizedServer -Method POST -Path '/api/tokens' `
            -Body $formBody -ContentType 'application/x-www-form-urlencoded' `
            -CertificateThumbprint $CertificateThumbprint -Certificate $Certificate `
            -Proxy $Proxy -ProxyCredential $ProxyCredential -NoProxy $NoProxy -TimeoutSec $TimeoutSec
    }
    finally {
        # Wipe the local plaintext password as soon as it is no longer needed.
        $password = $null
    }

    if ($null -eq $authResult) {
        throw ($script:GuacRestExceptionType::new(
            'Guacamole authentication failed: the server returned no authentication result.'
        ))
    }

    $authToken = $authResult.authToken
    $username = $authResult.username
    $defaultDataSource = $authResult.dataSource
    $availableDataSources = @($authResult.availableDataSources)
    if ($null -eq $availableDataSources) {
        $availableDataSources = @()
    }

    if ([string]::IsNullOrEmpty($authToken)) {
        throw ($script:GuacRestExceptionType::new(
            'Guacamole authentication failed: the server returned no authToken.'
        ))
    }

    # Default the data source from the token response; -DataSource overrides.
    if ([string]::IsNullOrEmpty($DataSource)) {
        $DataSource = $defaultDataSource
    }
    elseif ($availableDataSources.Count -gt 0 -and $availableDataSources -notcontains $DataSource) {
        throw ($script:GuacRestExceptionType::new(
            ("Data source '{0}' is not available for this user. Available: {1}" -f $DataSource, ($availableDataSources -join ', '))
        ))
    }

    $session = $script:GuacSessionType::new()
    $session.Server = $normalizedServer
    $session.Token = $authToken
    $session.DataSource = $DataSource
    $session.Username = $username
    $session.AvailableDataSources = $availableDataSources
    $session.CertificateThumbprint = $CertificateThumbprint
    $session.Certificate = $Certificate
    $session.Proxy = $Proxy
    $session.ProxyCredential = $ProxyCredential
    $session.NoProxy = $NoProxy
    $session.TimeoutSec = $TimeoutSec

    # Register as the default session for this server (the -CmsSession pattern).
    Set-GuacSessionState -Server $normalizedServer -Session $session

    Write-Verbose ("N2C.GuacAdmin: session established for user '{0}' (data source '{1}', token={2})" -f ($username, $DataSource, (ConvertTo-GuacMaskedSecret -Value $authToken)))

    return $session
}
