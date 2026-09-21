function ConvertTo-GuacJson {
    <#
    .SYNOPSIS
        Serializes an object to JSON, preserving single-element arrays.

    .DESCRIPTION
        Wraps ConvertTo-Json with two cross-version guarantees:

        1. Windows PowerShell 5.1 unwraps single-element (and empty) arrays
           when serializing, turning @($oneObject) into an object and @()
           into null. This function detects those cases and re-serializes them
           as proper JSON arrays, which is required for JSON Patch request
           bodies (RFC 6902) and any other array-valued REST body.
        2. A string input is passed through unchanged, so callers can supply
           pre-serialized JSON (for example form-encoded bodies are handled by
           the caller, not here).

        Nested serialization still delegates to ConvertTo-Json -Depth 10
        -Compress, which behaves identically on 5.1 and 7.x for the object
        shapes used by the Guacamole REST API.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [object] $InputObject
    )

    if ($null -eq $InputObject) {
        return 'null'
    }

    if ($InputObject -is [string]) {
        return $InputObject
    }

    $isCollection = ($InputObject -is [System.Collections.IEnumerable]) -and
        ($InputObject -isnot [string]) -and
        ($InputObject -isnot [System.Collections.IDictionary])

    if ($isCollection) {
        $items = @($InputObject)
        if ($items.Count -eq 0) {
            return '[]'
        }
        if ($items.Count -eq 1) {
            $element = $items[0]
            if ($element -is [string]) {
                $escaped = $element.Replace('\', '\\').Replace('"', '\"')
                return ('["{0}"]' -f $escaped)
            }
            return ('[{0}]' -f (ConvertTo-GuacJson -InputObject $element))
        }
        return ($items | ConvertTo-Json -Depth 10 -Compress)
    }

    return ($InputObject | ConvertTo-Json -Depth 10 -Compress)
}
