function ConvertTo-GuacInstructionString {
    <#
    .SYNOPSIS
        Encodes a Guacamole protocol instruction to its wire string format.

    .DESCRIPTION
        Serializes a [N2C_GuacAdmin_GuacInstruction] (or opcode + arguments)
        into the Guacamole protocol wire format: length.opcode,length.arg1,...,;
        where each argument is UTF-8 byte length followed by the argument value,
        and the instruction is terminated by a semicolon.

        Reference: guacamole-common/src/main/java/org/apache/guacamole/protocol/
                   GuacamoleInstruction.java (write), GuacamoleProtocol.java

    .EXAMPLE
        ConvertTo-GuacInstructionString -Instruction $instr
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
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

    if ($null -eq $Instruction) {
        if ([string]::IsNullOrEmpty($Opcode)) {
            throw ($script:GuacRestExceptionType::new('Either -Instruction or -Opcode must be specified.'))
        }
        $Instruction = $script:GuacInstructionType::new($Opcode, @($Arguments))
    }

    # Build the instruction string: len.opcode,len.arg1,len.arg2,...,;
    $sb = [System.Text.StringBuilder]::new()

    # Opcode (always included as an argument)
    [void]$sb.Append($Instruction.Opcode.Length)
    [void]$sb.Append('.')
    [void]$sb.Append($Instruction.Opcode)

    # Arguments
    foreach ($arg in $Instruction.Arguments) {
        [void]$sb.Append(',')
        [void]$sb.Append($arg.Length)
        [void]$sb.Append('.')
        [void]$sb.Append($arg)
    }

    [void]$sb.Append(';')

    return $sb.ToString()
}
