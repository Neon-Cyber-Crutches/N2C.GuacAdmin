function Remove-GuacActiveSession {
    <#
    .SYNOPSIS
        Gracefully disconnects and closes a Guacamole active session.

    .DESCRIPTION
        Sends a 'disconnect' instruction over the active session's tunnel,
        then closes the WebSocket connection. This releases server-side
        resources associated with the session.

        Reference (Apache Guacamole 1.6.0):
        - guacamole-common/src/main/java/org/apache/guacamole/protocol/GuacamoleProtocol.java
          (DISCONNECT instruction)

    .EXAMPLE
        Remove-GuacActiveSession -Session $active

    .EXAMPLE
        $active | Remove-GuacActiveSession
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [N2C_GuacAdmin_GuacActiveSession] $Session
    )

    process {
        if ($Session.Closed) {
            Write-Verbose ("N2C.GuacAdmin: active session {0} is already closed." -f $Session.Id)
            return
        }

        if ($PSCmdlet.ShouldProcess("Guacamole active session {0}" -f $Session.Id, "disconnect and close")) {
            try {
                # Send disconnect instruction
                $disconnectInstr = $script:GuacInstructionType::new('disconnect', @(''))
                $disconnectStr = ConvertTo-GuacInstructionString -Instruction $disconnectInstr
                $disconnectBytes = [System.Text.Encoding]::UTF8.GetBytes($disconnectStr)
                $disconnectSegment = New-Object System.ArraySegment[byte] -ArgumentList $disconnectBytes
                [void]$Session.WebSocket.SendAsync($disconnectSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
            }
            catch {
                Write-Verbose ("N2C.GuacAdmin: failed to send disconnect instruction: {0}" -f $_.Exception.Message)
            }

            # Close the WebSocket
            try {
                if ($Session.WebSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                    [void]$Session.WebSocket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'Session ended', [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
                }
            }
            catch {
                Write-Verbose ("N2C.GuacAdmin: failed to close WebSocket: {0}" -f $_.Exception.Message)
            }

            $Session.Closed = $true
            Write-Verbose ("N2C.GuacAdmin: active session {0} closed." -f $Session.Id)
        }
    }
}
