# N2C.GuacAdmin - type definitions.
#
# Classes are defined in a separate file loaded via TypesToProcess in the
# module manifest so that they are visible to the caller scope (a class
# defined in the module .psm1 is only visible inside the module).

# PowerShell class names cannot contain dots (no namespaces in class names),
# so the classes in this module use underscore identifiers:
# [N2C_GuacAdmin_GuacSession] and [N2C_GuacAdmin_GuacRestException].

class N2C_GuacAdmin_GuacSession {
    # Authentication session for a Guacamole instance.
    #
    # Holds the server base URI, the authentication token obtained from
    # POST /api/tokens (TokenRESTService.createToken), the authenticated
    # username, and the AuthenticationProvider identifier (data source) used
    # to scope all UserContext REST calls
    # (SessionResource.getUserContextResource). Also carries transport
    # options (TLS, proxy, timeout) so every request uses the same channel
    # configuration.
    #
    # The token is masked in string representations so that piping the
    # object or logging it does not leak the credential.
    #
    # Reference: guacamole/src/main/java/org/apache/guacamole/rest/auth/
    #            APIAuthenticationResult.java
    [string]$Server = [string]::Empty
    [string]$Token = [string]::Empty
    [string]$DataSource = [string]::Empty
    [string]$Username = [string]::Empty
    [string[]]$AvailableDataSources = @()
    [string]$CertificateThumbprint = [string]::Empty
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate = $null
    [string]$Proxy = [string]::Empty
    [System.Management.Automation.PSCredential]$ProxyCredential = $null
    [string]$NoProxy = [string]::Empty
    [int]$TimeoutSec = 30

    [string]ToString() {
        $masked = '****'
        if ($this.Token -and $this.Token.Length -gt 8) {
            $masked = $this.Token.Substring(0, 4) + '...' + $this.Token.Substring($this.Token.Length - 4)
        }
        return ("N2C.GuacAdmin.GuacSession: Server={0} User={1} DataSource={2} Token={3}" -f $this.Server, $this.Username, $this.DataSource, $masked)
    }
}

class N2C_GuacAdmin_GuacRestException : System.Exception {
    # Terminating exception raised by the REST transport on any failure.
    #
    # Carries the HTTP status code (0 for transport-level failures such as
    # connection refusal or timeout), the Guacamole APIError type (for example
    # NOT_FOUND or INVALID_CREDENTIALS, per APIError.Type), the request
    # endpoint (with the token masked), the human-readable reason, and the raw
    # response body.
    #
    # Reference: guacamole/src/main/java/org/apache/guacamole/rest/APIError.java
    #            guacamole/src/main/java/org/apache/guacamole/rest/
    #            RESTExceptionMapper.java
    [int]$StatusCode = 0
    [string]$Type = [string]::Empty
    [string]$Endpoint = [string]::Empty
    [string]$Reason = [string]::Empty
    [object]$RawBody = $null

    N2C_GuacAdmin_GuacRestException([string]$message) : base($message) { }
    N2C_GuacAdmin_GuacRestException([string]$message, [System.Exception]$innerException) : base($message, $innerException) { }
}
