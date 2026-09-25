function Send-GuacInstruction {
    <#
    .SYNOPSIS
        Sends a Guacamole protocol instruction over an active session.

    .DESCRIPTION
        Encodes the instruction and sends it as a WebSocket text frame over
        the active session's tunnel. The instruction is specified either as
        a [N2C_GuacAdmin_GuacInstruction] object or as an opcode with
        variable arguments.

        Reference (Apache Guacamole 1.6.0):
        - guacamole-common/src/main/java/org/apache/guacamole/protocol/GuacamoleInstruction.java
          (write method)

    .EXAMPLE
        $instr = [N2C_GuacAdmin_GuacInstruction]::new('key', @('1', '65', 'true'))
        Send-GuacInstruction -Session $active -Instruction $instr

    .EXAMPLE
        Send-GuacInstruction -Session $active -Opcode 'key' -Arguments @('1', '65', 'true')
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [N2C_GuacAdmin_GuacActiveSession] $Session,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [N2C_GuacAdmin_GuacInstruction] $Instruction,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Opcode = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string[]] $Arguments = $null
    )

    process {
        if ($Session.Closed) {
            throw ($script:GuacRestExceptionType::new("Active session {0} is already closed." -f $Session.Id))
        }

        if ($null -eq $Instruction -and [string]::IsNullOrEmpty($Opcode)) {
            throw ($script:GuacRestExceptionType::new('Either -Instruction or -Opcode must be specified.'))
        }

        $instrString = ConvertTo-GuacInstructionString -Instruction $Instruction -Opcode $Opcode -Arguments $Arguments

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($instrString)
        $segment = New-Object System.ArraySegment[byte] -ArgumentList $bytes
        [void]$Session.WebSocket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()

        $verboseOpcode = $Opcode
        if ($null -ne $Instruction -and $null -ne $Instruction.Opcode) {
            $verboseOpcode = $Instruction.Opcode
        }
        Write-Verbose ("N2C.GuacAdmin: sent instruction '{0}'" -f $verboseOpcode)
    }
}
