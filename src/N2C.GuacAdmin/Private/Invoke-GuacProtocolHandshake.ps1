function Invoke-GuacProtocolHandshake {
    <#
    .SYNOPSIS
        Performs the Guacamole protocol handshake over a WebSocket connection.

    .DESCRIPTION
        Given an already-connected WebSocket and the tunnel URL, performs the
        handshake sequence:
          1. select {connectionId}
          2. args {argNames...}
          3. size {width,height,dpi}
          4. audio {mimeTypes...}
          5. video {mimeTypes...}
          6. image {mimeTypes...}
          7. timezone {tz}
          8. connect {argValues...}
        Then reads the 'ready' instruction to get the session ID.

        Reference: guacamole-common/src/main/java/org/apache/guacamole/protocol/
                   ConfiguredGuacamoleSocket.java (handshake sequence),
                   TunnelRequest.java (tunnel URL parameters)

    .EXAMPLE
        Invoke-GuacProtocolHandshake -WebSocket $ws -Server $srv -Token $tok -ConnectionId $id -Arguments $args
    #>
    [CmdletBinding()]
    [OutputType([N2C_GuacAdmin_GuacActiveSession])]
    param (
        [Parameter(Mandatory = $true)]
        [System.Net.WebSockets.ClientWebSocket] $WebSocket,

        [Parameter(Mandatory = $true)]
        [N2C_GuacAdmin_GuacSession] $Session,

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

    # Helper: send instruction and wait for response
    # Note: In the real Guacamole protocol, the handshake is request/response,
    # but for simplicity we send all instructions and then wait for 'ready'.

    # 1. select - tell server which connection to use
    if (-not [string]::IsNullOrWhiteSpace($ConnectionId)) {
        $selectInstr = $script:GuacInstructionType::new('select', @($ConnectionId))
        $selectStr = ConvertTo-GuacInstructionString -Instruction $selectInstr
        $selectBytes = [System.Text.Encoding]::UTF8.GetBytes($selectStr)
        $selectSegment = New-Object System.ArraySegment[byte] -ArgumentList $selectBytes
        [void]$WebSocket.SendAsync($selectSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }
    elseif (-not [string]::IsNullOrWhiteSpace($GroupId)) {
        $selectInstr = $script:GuacInstructionType::new('select', @($GroupId))
        $selectStr = ConvertTo-GuacInstructionString -Instruction $selectInstr
        $selectBytes = [System.Text.Encoding]::UTF8.GetBytes($selectStr)
        $selectSegment = New-Object System.ArraySegment[byte] -ArgumentList $selectBytes
        [void]$WebSocket.SendAsync($selectSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }

    # 2. args - list of argument names the client understands
    $argNames = @($Arguments.Keys)
    $argsInstr = $script:GuacInstructionType::new('args', $argNames)
    $argsStr = ConvertTo-GuacInstructionString -Instruction $argsInstr
    $argsBytes = [System.Text.Encoding]::UTF8.GetBytes($argsStr)
    $argsSegment = New-Object System.ArraySegment[byte] -ArgumentList $argsBytes
    [void]$WebSocket.SendAsync($argsSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()

    # 3. size - display resolution
    $sizeInstr = $script:GuacInstructionType::new('size', @("$Width", "$Height", "$Dpi"))
    $sizeStr = ConvertTo-GuacInstructionString -Instruction $sizeInstr
    $sizeBytes = [System.Text.Encoding]::UTF8.GetBytes($sizeStr)
    $sizeSegment = New-Object System.ArraySegment[byte] -ArgumentList $sizeBytes
    [void]$WebSocket.SendAsync($sizeSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()

    # 4. audio - supported audio MIME types
    if ($AudioMimeTypes.Count -gt 0) {
        $audioInstr = $script:GuacInstructionType::new('audio', $AudioMimeTypes)
        $audioStr = ConvertTo-GuacInstructionString -Instruction $audioInstr
        $audioBytes = [System.Text.Encoding]::UTF8.GetBytes($audioStr)
        $audioSegment = New-Object System.ArraySegment[byte] -ArgumentList $audioBytes
        [void]$WebSocket.SendAsync($audioSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }

    # 5. video - supported video MIME types
    if ($VideoMimeTypes.Count -gt 0) {
        $videoInstr = $script:GuacInstructionType::new('video', $VideoMimeTypes)
        $videoStr = ConvertTo-GuacInstructionString -Instruction $videoInstr
        $videoBytes = [System.Text.Encoding]::UTF8.GetBytes($videoStr)
        $videoSegment = New-Object System.ArraySegment[byte] -ArgumentList $videoBytes
        [void]$WebSocket.SendAsync($videoSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }

    # 6. image - supported image MIME types
    if ($ImageMimeTypes.Count -gt 0) {
        $imageInstr = $script:GuacInstructionType::new('image', $ImageMimeTypes)
        $imageStr = ConvertTo-GuacInstructionString -Instruction $imageInstr
        $imageBytes = [System.Text.Encoding]::UTF8.GetBytes($imageStr)
        $imageSegment = New-Object System.ArraySegment[byte] -ArgumentList $imageBytes
        [void]$WebSocket.SendAsync($imageSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }

    # 7. timezone
    if (-not [string]::IsNullOrWhiteSpace($Timezone)) {
        $tzInstr = $script:GuacInstructionType::new('timezone', @($Timezone))
        $tzStr = ConvertTo-GuacInstructionString -Instruction $tzInstr
        $tzBytes = [System.Text.Encoding]::UTF8.GetBytes($tzStr)
        $tzSegment = New-Object System.ArraySegment[byte] -ArgumentList $tzBytes
        [void]$WebSocket.SendAsync($tzSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }

    # 8. connect - provide argument values
    if ($Arguments.Count -gt 0) {
        $argValues = @()
        foreach ($name in $Arguments.Keys) {
            $argValues += $Arguments[$name]
        }
        $connectInstr = $script:GuacInstructionType::new('connect', $argValues)
        $connectStr = ConvertTo-GuacInstructionString -Instruction $connectInstr
        $connectBytes = [System.Text.Encoding]::UTF8.GetBytes($connectStr)
        $connectSegment = New-Object System.ArraySegment[byte] -ArgumentList $connectBytes
        [void]$WebSocket.SendAsync($connectSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }
    else {
        # Still send a connect instruction (empty) to trigger the connection
        $connectInstr = $script:GuacInstructionType::new('connect')
        $connectStr = ConvertTo-GuacInstructionString -Instruction $connectInstr
        $connectBytes = [System.Text.Encoding]::UTF8.GetBytes($connectStr)
        $connectSegment = New-Object System.ArraySegment[byte] -ArgumentList $connectBytes
        [void]$WebSocket.SendAsync($connectSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }

    # Now wait for the 'ready' instruction
    $buffer = New-Object byte[] 4096
    $bufferSegment = New-Object System.ArraySegment[byte] -ArgumentList $buffer

    # Set up cancellation for timeout
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter([TimeSpan]::FromSeconds($HandshakeTimeoutSec))
    $token = $cts.Token

    # Receive loop: collect instructions until we see 'ready'
    $sessionBuffer = [System.Text.StringBuilder]::new()
    while (-not $token.IsCancellationRequested) {
        $result = $WebSocket.ReceiveAsync($bufferSegment, $token).GetAwaiter().GetResult()

        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            throw ($script:GuacRestExceptionType::new('WebSocket closed during handshake.'))
        }

        # Convert received bytes to string
        $receivedText = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
        [void]$sessionBuffer.Append($receivedText)

        # Parse complete instructions (terminated by ';')
        $bufferStr = $sessionBuffer.ToString()
        while ($true) {
            $semiIdx = $bufferStr.IndexOf(';')
            if ($semiIdx -lt 0) {
                break
            }

            $completeInstr = $bufferStr.Substring(0, $semiIdx + 1)
            $bufferStr = $bufferStr.Substring($semiIdx + 1)
            $sessionBuffer.Length = 0
            [void]$sessionBuffer.Append($bufferStr)

            # Parse the instruction
            $instr = ConvertFrom-GuacInstructionString -Raw $completeInstr

            if ($instr.Opcode -eq 'error') {
                $errorCode = 'UNKNOWN'
                $errorMsg = 'Unknown error'
                if ($instr.Arguments.Length -ge 2) {
                    $errorCode = $instr.Arguments[0]
                    $errorMsg = $instr.Arguments[1]
                }
                throw ($script:GuacRestExceptionType::new("Guacamole handshake error [$errorCode]: $errorMsg"))
            }
            elseif ($instr.Opcode -eq 'ready') {
                if ($instr.Arguments.Length -ge 1) {
                    $sessionId = $instr.Arguments[0]
                    Write-Verbose ("N2C.GuacAdmin: handshake complete, session ID: {0}" -f $sessionId)

                    $activeSession = $script:GuacActiveSessionType::new()
                    $activeSession.Session = $Session
                    $activeSession.Id = $sessionId
                    $activeSession.ConnectionId = $ConnectionId
                    $activeSession.Protocol = 'guacamole'
                    $activeSession.WebSocket = $WebSocket
                    return $activeSession
                }
            }
            elseif ($instr.Opcode -eq 'disconnect') {
                $msg = 'Disconnected during handshake'
                if ($instr.Arguments.Length -ge 1) {
                    $msg = $instr.Arguments[0]
                }
                throw ($script:GuacRestExceptionType::new($msg))
            }
            # Other instructions (like 'name') are informational; continue waiting for 'ready'
        }
    }

    throw ($script:GuacRestExceptionType::new("Guacamole handshake timed out after ${HandshakeTimeoutSec}s."))
}
