function ConvertFrom-GuacSecureString {
    <#
    .SYNOPSIS
        Converts a SecureString to a plaintext string on any platform.

    .DESCRIPTION
        Uses System.Runtime.InteropServices.Marshal::SecureStringToBSTR, which
        works on Windows PowerShell 5.1 and PowerShell 7.x on Windows/Linux/
        macOS. This is the portable replacement for the PowerShell 6+ only
        ConvertFrom-SecureString -AsPlaintext (which is broken on 5.1).

        The BSTR is zeroed and freed immediately after conversion.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString] $SecureString
    )

    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}
