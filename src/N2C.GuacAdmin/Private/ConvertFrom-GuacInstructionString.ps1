function ConvertFrom-GuacInstructionString {
    <#
    .SYNOPSIS
        Parses a Guacamole protocol instruction string into a GuacInstruction object.

    .DESCRIPTION
        Parses the wire format len.opcode,len.arg1,...,; into a
        [N2C_GuacAdmin_GuacInstruction] with the opcode and arguments decoded.

        Reference: guacamole-common/src/main/java/org/apache/guacamole/protocol/
                   GuacamoleInstruction.java (read), GuacamoleProtocol.java

    .EXAMPLE
        $instr = ConvertFrom-GuacInstructionString -Raw '6.select,35.abc-123-uuid;'
    #>
    [CmdletBinding()]
    [OutputType([N2C_GuacAdmin_GuacInstruction])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Raw
    )

    # Strip the terminating semicolon if present
    $body = $Raw.TrimEnd(';')
    if ($body -eq '') {
        throw ($script:GuacRestExceptionType::new('Empty Guacamole instruction string.'))
    }

    $parts = $body -split ','

    if ($parts.Length -lt 1) {
        throw ($script:GuacRestExceptionType::new('Malformed Guacamole instruction: no opcode.'))
    }

    # Parse opcode: length.opcode
    $opcodePart = $parts[0]
    $dotIdx = $opcodePart.IndexOf('.')
    if ($dotIdx -lt 0) {
        throw ($script:GuacRestExceptionType::new('Malformed Guacamole instruction: opcode missing dot.'))
    }

    $opcodeLen = [int]$opcodePart.Substring(0, $dotIdx)
    $opcode = $opcodePart.Substring($dotIdx + 1, $opcodeLen)

    # Parse arguments
    $argsList = [System.Collections.Generic.List[string]]::new()
    for ($i = 1; $i -lt $parts.Length; $i++) {
        $argPart = $parts[$i]
        $argDotIdx = $argPart.IndexOf('.')
        if ($argDotIdx -lt 0) {
            throw ($script:GuacRestExceptionType::new('Malformed Guacamole instruction argument at index ' + $i))
        }

        $argLen = [int]$argPart.Substring(0, $argDotIdx)
        $argValue = $argPart.Substring($argDotIdx + 1, $argLen)
        $argsList.Add($argValue)
    }

    return $script:GuacInstructionType::new($opcode, $argsList.ToArray())
}
