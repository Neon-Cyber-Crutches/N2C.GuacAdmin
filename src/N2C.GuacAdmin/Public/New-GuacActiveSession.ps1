function New-GuacActiveSession {
    <#
    .SYNOPSIS
        Opens a new Guacamole active session (interactive connection).

    .DESCRIPTION
        Opens a WebSocket tunnel to the specified Guacamole connection or
        connection group and performs the full protocol handshake
        (select, args, size, audio, video, image, timezone, connect) to
        establish an active session. Returns a [N2C_GuacAdmin_GuacActiveSession]
        object containing the session ID and the live WebSocket connection
        for the instruction pump.

        Use Send-GuacInstruction and Receive-GuacInstruction to exchange
        instructions with the session. Use Remove-GuacActiveSession to
        gracefully disconnect.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/tunnel/TunnelRequest.java
          (tunnel URL parameters)
        - guacamole/src/main/java/org/apache/guacamole/tunnel/websocket/WebSocketTunnel.java
        - guacamole-common/src/main/java/org/apache/guacamole/protocol/ConfiguredGuacamoleSocket.java
          (handshake sequence)

    .EXAMPLE
        $session = New-GuacSession -Server https://guac.example.com/guacamole -Credential $cred
        $active = New-GuacActiveSession -Session $session -ConnectionId 'abc-123'
        # Use the session...
        Remove-GuacActiveSession -Session $active
    #>
    [CmdletBinding()]
    [OutputType([N2C_GuacAdmin_GuacActiveSession])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [N2C_GuacAdmin_GuacSession] $Session,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Server = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $DataSource = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $ConnectionId = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $GroupId = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [ValidateRange(64, 7680)]
        [int] $Width = 1024,

        [Parameter(Mandatory = $false)]
        [ValidateRange(64, 7680)]
        [int] $Height = 768,

        [Parameter(Mandatory = $false)]
        [ValidateRange(75, 300)]
        [int] $Dpi = 96,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Timezone = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string[]] $AudioMimeTypes = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string[]] $VideoMimeTypes = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string[]] $ImageMimeTypes = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [hashtable] $Arguments = @{},

        [Parameter(Mandatory = $false)]
        [ValidateRange(5, 300)]
        [int] $HandshakeTimeoutSec = 30
    )

    # Resolve session
    $resolved = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'New-GuacActiveSession'
    $sessionObj = $resolved.Session

    # Build the tunnel URL
    $tunnelUrl = New-GuacTunnelUrl -Server $sessionObj.Server `
        -Token $sessionObj.Token `
        -ConnectionId $ConnectionId `
        -GroupId $GroupId `
        -DataSource $sessionObj.DataSource `
        -Width $Width -Height $Height -Dpi $Dpi `
        -Timezone $Timezone `
        -AudioMimeTypes $AudioMimeTypes `
        -VideoMimeTypes $VideoMimeTypes `
        -ImageMimeTypes $ImageMimeTypes

    Write-Verbose ("N2C.GuacAdmin: opening WebSocket tunnel to {0}" -f $tunnelUrl)

    # Open WebSocket connection with subprotocol "guacamole"
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    try {
        $ws.ConnectAsync([Uri]$tunnelUrl, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
        Write-Verbose ("N2C.GuacAdmin: WebSocket connected, performing handshake")

        # Perform the protocol handshake
        $activeSession = Invoke-GuacProtocolHandshake -WebSocket $ws `
            -Session $sessionObj `
            -ConnectionId $ConnectionId `
            -GroupId $GroupId `
            -Width $Width -Height $Height -Dpi $Dpi `
            -Timezone $Timezone `
            -AudioMimeTypes $AudioMimeTypes `
            -VideoMimeTypes $VideoMimeTypes `
            -ImageMimeTypes $ImageMimeTypes `
            -Arguments $Arguments `
            -HandshakeTimeoutSec $HandshakeTimeoutSec

        return $activeSession
    }
    catch {
        # Close the WebSocket on failure
        if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            try {
                [void]$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'Handshake failed', [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
            }
            catch {
                # Ignore close errors
            }
        }
        throw
    }
}
