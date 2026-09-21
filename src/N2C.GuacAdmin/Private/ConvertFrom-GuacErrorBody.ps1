function ConvertFrom-GuacErrorBody {
    <#
    .SYNOPSIS
        Parses a Guacamole APIError JSON body into structured fields.

    .DESCRIPTION
        Guacamole returns errors as a JSON body with the shape
        (guacamole/src/main/java/org/apache/guacamole/rest/APIError.java):
            {
              "message": "No such token.",
              "translatableMessage": { "key": "...", "variables": { ... } },
              "statusCode": 404,
              "expected": [ ... ],
              "patches": [ ... ],
              "type": "NOT_FOUND"
            }
        Not every error carries every field (for example, servlet-level errors
        may return plain text), so all fields are optional.

        Returns a PSCustomObject with: Type, Message, StatusCode (the
        protocol status code from the body, or $null), Expected, Patches, and
        Raw (the original body text).

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Body
    )

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return [PSCustomObject]@{
            Type = $null
            Message = $null
            StatusCode = $null
            Expected = $null
            Patches = $null
            Raw = $Body
        }
    }

    $parsed = $null
    $isJson = $false
    try {
        $parsed = $Body | ConvertFrom-Json
        $isJson = $true
    }
    catch [System.Exception] {
        $isJson = $false
    }

    if (-not $isJson) {
        # Non-JSON error body (for example a servlet or reverse-proxy error page).
        $text = $Body
        if ($text.Length -gt 2000) {
            $text = $text.Substring(0, 2000) + '...'
        }
        return [PSCustomObject]@{
            Type = $null
            Message = $text
            StatusCode = $null
            Expected = $null
            Patches = $null
            Raw = $Body
        }
    }

    $type = $null
    if ($null -ne $parsed.type) { $type = [string]$parsed.type }
    $message = $null
    if ($null -ne $parsed.message) { $message = [string]$parsed.message }
    $protocolStatusCode = $null
    if ($null -ne $parsed.statusCode) { $protocolStatusCode = $parsed.statusCode }
    $expected = $null
    if ($null -ne $parsed.expected) { $expected = $parsed.expected }
    $patches = $null
    if ($null -ne $parsed.patches) { $patches = $parsed.patches }

    return [PSCustomObject]@{
        Type = $type
        Message = $message
        StatusCode = $protocolStatusCode
        Expected = $expected
        Patches = $patches
        Raw = $Body
    }
}
