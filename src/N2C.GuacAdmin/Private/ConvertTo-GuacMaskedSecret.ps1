function ConvertTo-GuacMaskedSecret {
    <#
    .SYNOPSIS
        Returns a masked representation of a secret value (token, password).

    .DESCRIPTION
        Masks a secret for safe display in -Verbose/-Debug output, log messages,
        and error text. Values of 8 characters or fewer are masked entirely;
        longer values keep their first and last 4 characters.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return '****'
    }

    if ($Value.Length -le 8) {
        return '****'
    }

    return $Value.Substring(0, 4) + '...' + $Value.Substring($Value.Length - 4)
}
