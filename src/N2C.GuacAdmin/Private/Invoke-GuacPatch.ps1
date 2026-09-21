#Requires -Version 5.1
function Get-GuacPatchOperation {
    <#
    .SYNOPSIS
        Builds a single RFC 6902 JSON Patch operation.

    .DESCRIPTION
        Constructs the ordered hashtable form of one JSON Patch operation,
        matching the wire format Guacamole deserializes into APIPatch<T>:
        { "op": <operation>, "path": <path>, "value": <value> }.

        The "value" key is always included (it may be $null). Guacamole's
        DirectoryResource.patchObjects omits "value" entirely for "remove"
        operations, and its RelatedObjectSetResource / PermissionSetResource
        PATCH endpoints require a string "value", so callers must supply the
        correct value shape per endpoint:
        - collection PATCH (connections, users, ...): value is the object
          for add/replace and $null for remove
        - permission set PATCH: value is the permission type string
          (for example "UPDATE" or "ADMINISTER")
        - related-object-set PATCH (memberUsers, userGroups, ...): value is
          the identifier string

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/jsonpatch/APIPatch.java
          (op, path, value)
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (patchObjects: add/replace/remove)
        - guacamole/src/main/java/org/apache/guacamole/rest/permission/PermissionSetResource.java
          (patchPermissions: permission type as value)
        - guacamole/src/main/java/org/apache/guacamole/rest/identifier/RelatedObjectSetResource.java
          (patchObjects: identifier as value, path "/")

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('add', 'remove', 'replace')]
        [string] $Op,

        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Path,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Value = $null
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not $Path.StartsWith('/')) {
        throw (New-Object System.ArgumentException(
            'A JSON Patch path must be non-empty and start with "/" (RFC 6902).', 'Path'))
    }

    return [ordered]@{
        op    = $Op
        path  = $Path
        value = $Value
    }
}

function ConvertTo-GuacJsonPatch {
    <#
    .SYNOPSIS
        Normalizes JSON Patch input into an RFC 6902 operations array.

    .DESCRIPTION
        Accepts the -Patch parameter values the public cmdlets expose and
        returns an array of ordered hashtables with the canonical wire form
        { op, path, value }:
        - a single ordered/regular hashtable with an "op" key
        - an array of hashtables (one operation each)

        Guards against the Windows PowerShell 5.1 pipeline quirk where a
        single-element array arrives as its lone element: the input is
        always re-wrapped as an array before validation.

        Throws on empty input, on a hashtable without an "op" key, and on an
        operation type other than add/replace/remove (the operations
        DirectoryResource.patchObjects supports; RFC 6902 also defines
        test/copy/move, which Guacamole's collection PATCH rejects).

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/jsonpatch/APIPatch.java
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (patchObjects: "Only add, replace, and remove are supported.")

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.ArrayList])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [object] $Patch
    )

    $operations = @($Patch)
    if ($operations.Count -eq 0) {
        throw (New-Object System.ArgumentException(
            'A patch must contain at least one operation.', 'Patch'))
    }

    $result = [System.Collections.ArrayList]::new()
    foreach ($item in $operations) {
        if ($null -eq $item) {
            throw (New-Object System.ArgumentException(
                'A patch operation cannot be null.', 'Patch'))
        }
        if ($item -is [System.Collections.IDictionary]) {
            $dict = $item
        }
        elseif ($item.PSObject.Properties.Match('op').Count -gt 0) {
            $dict = [ordered]@{}
            foreach ($prop in $item.PSObject.Properties) {
                $dict[$prop.Name] = $prop.Value
            }
        }
        else {
            throw (New-Object System.ArgumentException(
                ('Each patch operation must be a hashtable with an "op" key; got: {0}' -f $item.GetType().Name), 'Patch'))
        }

        if ($dict.Count -eq 0 -or -not $dict.Contains('op')) {
            throw (New-Object System.ArgumentException(
                'Each patch operation must include an "op" key (add, replace, or remove).', 'Patch'))
        }

        $op = [string]$dict['op']
        switch ($op.ToLowerInvariant()) {
            'add'     { }
            'replace' { }
            'remove'  { }
            default {
                throw (New-Object System.ArgumentException(
                    ("Unsupported patch operation '{0}': Guacamole collection PATCH supports add, replace, and remove." -f $op), 'Patch'))
            }
        }

        if (-not $dict.Contains('path')) {
            throw (New-Object System.ArgumentException(
                ('Each patch operation must include a "path" key; operation "{0}" has none.' -f $op), 'Patch'))
        }
        $path = [string]$dict['path']
        if ([string]::IsNullOrWhiteSpace($path) -or -not $path.StartsWith('/')) {
            throw (New-Object System.ArgumentException(
                ('A JSON Patch path must be non-empty and start with "/" (RFC 6902): "{0}"' -f $path), 'Patch'))
        }

        $normalized = [ordered]@{
            op    = $op.ToLowerInvariant()
            path  = $path
            value = $null
        }
        if ($dict.Contains('value')) {
            $normalized['value'] = $dict['value']
        }
        [void]$result.Add($normalized)
    }

    return $result
}

function Invoke-GuacPatch {
    <#
    .SYNOPSIS
        Applies a JSON Patch (RFC 6902) to a Guacamole collection endpoint.

    .DESCRIPTION
        Wraps Invoke-GuacRest for the collection mutation endpoints:
        serializes an array of RFC 6902 operations (as normalized by
        ConvertTo-GuacJsonPatch) to JSON and sends it as PATCH.

        DirectoryResource.patchObjects responds with an APIPatchResponse
        (a JSON object: { "patches": [ { "op", "identifier", "path" }, ... ] })
        and returns HTTP 400 (APIPatchFailureException) when any operation
        fails, in which case Invoke-GuacRest converts it into a terminating
        GuacRestException carrying the parsed body. The PermissionSetResource
        and RelatedObjectSetResource PATCH endpoints return an empty body
        (HTTP 204/200), for which this function returns $true.

        The returned object is the decoded response body (an object on both
        Windows PowerShell 5.1 and 7.x), or $true for an empty response.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (patchObjects -> APIPatchResponse)
        - guacamole/src/main/java/org/apache/guacamole/rest/jsonpatch/APIPatchResponse.java
          (patches list)
        - guacamole/src/main/java/org/apache/guacamole/rest/permission/PermissionSetResource.java
          (patchPermissions: void)
        - guacamole/src/main/java/org/apache/guacamole/rest/identifier/RelatedObjectSetResource.java
          (patchObjects: void)

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable] $Context,

        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object] $Patch
    )

    $operations = ConvertTo-GuacJsonPatch -Patch $Patch
    $body = ConvertTo-GuacJson -InputObject $operations
    return (Invoke-GuacRest -Server $Context['Server'] -Token $Context['Token'] `
        -Method PATCH -Path $Path -Body $body -ContentType 'application/json')
}
