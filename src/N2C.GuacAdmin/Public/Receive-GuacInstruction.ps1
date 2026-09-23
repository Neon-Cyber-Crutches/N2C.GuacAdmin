function Receive-GuacInstruction {
    <#
    .SYNOPSIS
        Receives the next Guacamole protocol instruction from an active session.

    .DESCRIPTION
        Receives WebSocket frames from the active session's tunnel, buffers
        them, and returns complete instructions as they become available
        (terminated by semicolons). Instructions are parsed into
        [N2C_GuacAdmin_GuacInstruction] objects.

        If -TimeoutSec is specified and no instruction arrives within that
        time, returns $null. If the session is closed or the WebSocket is
        closed, returns $null.

        Reference (Apache Guacamole 1.6.0):
        - guacamole-common/src/main/java/org/apache/guacamole/protocol/GuacamoleProtocolReader.java
          (readInstruction method)

    .EXAMPLE
        $instr = Receive-GuacInstruction -Session $active
        if ($instr -and $instr.Opcode -eq 'data') {
            # Process base64 image data
        }

    .EXAMPLE
        # Receive with timeout
        $instr = Receive-GuacInstruction -Session $active -TimeoutSec 5
    #>
    [CmdletBinding()]
    [OutputType([N2C_GuacAdmin_GuacInstruction])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [N2C_GuacAdmin_GuacActiveSession] $Session,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [int] $TimeoutSec = 0
    )

    process {
        if ($Session.Closed) {
            return $null
        }

        $buffer = New-Object byte[] 4096
        $bufferSegment = New-Object System.ArraySegment[byte] -ArgumentList $buffer

        # Set up cancellation for timeout
        $cts = if ($TimeoutSec -gt 0) {
            New-Object System.Threading.CancellationTokenSource
            $cts.CancelAfter([TimeSpan]::FromSeconds($TimeoutSec))
            $cts.Token
        } else {
            [System.Threading.CancellationToken]::None
        }

        try {
            # Try to receive data
            $result = $Session.WebSocket.ReceiveAsync($bufferSegment, $cts).GetAwaiter().GetResult()

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                $Session.Closed = $true
                return $null
            }

            $receivedText = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)

            # Find complete instructions (terminated by ';')
            $semiIdx = $receivedText.IndexOf(';')
            if ($semiIdx -ge 0) {
                $completeInstr = $receivedText.Substring(0, $semiIdx + 1)
                $parsed = ConvertFrom-GuacInstructionString -Raw $completeInstr
                return $parsed
            }

            # Partial instruction; return null (caller should try again)
            return $null
        }
        catch [System.OperationCanceledException] {
            # Timeout
            return $null
        }
        finally {
            if ($null -ne $cts) {
                $cts.Dispose()
            }
        }
    }
}
