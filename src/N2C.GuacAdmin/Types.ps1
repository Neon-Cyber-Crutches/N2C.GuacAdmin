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

class N2C_GuacAdmin_GuacActiveSession {
    # Represents an active Guacamole protocol session (an interactive connection).
    #
    # Created by New-GuacActiveSession, which opens a WebSocket tunnel and
    # completes the protocol handshake (select/args/size/audio/video/image/
    # timezone/name/connect). Carries the session ID returned by the `ready`
    # instruction, the underlying connection ID and protocol, and the live
    # WebSocket connection used for the instruction pump.
    #
    # The WebSocket instance is exposed so callers can manage the instruction
    # pump via Send-GuacInstruction and Receive-GuacInstruction. Callers MUST
    # call Remove-GuacActiveSession (or manually close the WebSocket) when
    # done to release resources and gracefully disconnect on the server.
    #
    # Reference: guacamole/src/main/java/org/apache/guacamole/tunnel/websocket/
    #            WebSocketTunnel.java, guacamole-common/src/main/java/org/apache/
    #            guacamole/protocol/GuacamoleProtocol.java
    [N2C_GuacAdmin_GuacSession]$Session = $null
    [string]$Id = [string]::Empty
    [string]$ConnectionId = [string]::Empty
    [string]$Protocol = [string]::Empty
    [System.Net.WebSockets.ClientWebSocket]$WebSocket = $null
    [bool]$Closed = $false

    [string]ToString() {
        return ("N2C.GuacAdmin.GuacActiveSession: Id={0} Connection={1} Protocol={2} Closed={3}" -f $this.Id, $this.ConnectionId, $this.Protocol, $this.Closed)
    }
}

class N2C_GuacAdmin_GuacInstruction {
    # Represents a single Guacamole protocol instruction.
    #
    # Wire format: length.opcode,length.arg1,length.arg2,...,length.argN;
    # where each argument is UTF-8 bytes prefixed by its length. Instructions
    # are delimited by the semicolon terminator. This object holds the decoded
    # opcode and arguments as strings for easy manipulation in PowerShell.
    #
    # Reference: guacamole-common/src/main/java/org/apache/guacamole/protocol/
    #            GuacamoleInstruction.java, GuacamoleProtocol.java
    [string]$Opcode = [string]::Empty
    [string[]]$Arguments = @()

    # Constructor: opcode + variable arguments
    N2C_GuacAdmin_GuacInstruction([string]$opcode, [string[]]$arguments) {
        $this.Opcode = $opcode
        $this.Arguments = $arguments
    }

    # Constructor: opcode only
    N2C_GuacAdmin_GuacInstruction([string]$opcode) {
        $this.Opcode = $opcode
        $this.Arguments = @()
    }

    [string]ToString() {
        return ("GuacInstruction: {0} ({1} args)" -f $this.Opcode, $this.Arguments.Length)
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
