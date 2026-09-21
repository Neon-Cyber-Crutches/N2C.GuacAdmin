function ConvertTo-GuacFormUrlEncoded {
    <#
    .SYNOPSIS
        Encodes a field collection as an application/x-www-form-urlencoded body.

    .DESCRIPTION
        Encodes the given key/value pairs as a URL-encoded form body, as
        required by POST /api/tokens (TokenRESTService.createToken accepts
        @FormParam username/password). Values are percent-encoded with
        [Uri]::EscapeDataString, which is UTF-8 based on both Windows
        PowerShell 5.1 and PowerShell 7.x.

        Null values are skipped (used for the optional guac-totp field).

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Fields
    )

    $builder = [System.Text.StringBuilder]::new()
    foreach ($key in $Fields.Keys) {
        $value = $Fields[$key]
        if ($null -eq $value) {
            continue
        }
        if ($builder.Length -gt 0) {
            [void]$builder.Append('&')
        }
        [void]$builder.Append([Uri]::EscapeDataString([string]$key))
        [void]$builder.Append('=')
        [void]$builder.Append([Uri]::EscapeDataString([string]$value))
    }
    return $builder.ToString()
}
