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

    # Mask the central portion with asterisks, keeping the same total length.
    # First and last 4 characters remain visible.
    $first = $Value.Substring(0, 4)
    $last = $Value.Substring($Value.Length - 4)
    $maskedLength = $Value.Length - 8
    return $first + ('*' * $maskedLength) + $last
}
