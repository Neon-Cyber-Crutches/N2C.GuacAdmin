#Requires -Version 5.1
function Get-GuacMapEntries {
    <#
    .SYNOPSIS
        Enumerates the entries of a decoded Guacamole JSON map.

    .DESCRIPTION
        Guacamole directory listings are JSON objects keyed by identifier
        (DirectoryResource.getObjects returns Map<String, ExternalType>).
        Depending on the PowerShell version and the HTTP response decoder,
        such a body arrives either as a [System.Collections.IDictionary]
        (Windows PowerShell 5.1 ConvertFrom-Json) or as a [PSCustomObject]
        whose properties are the entries (PowerShell 7.x Invoke-WebRequest
        JSON decoding, or a single-element array unwrap).

        This helper accepts either shape and yields one [PSCustomObject] per
        entry, with the entry key in the "Key" property and the entry value in
        the "Value" property. A $null body yields nothing.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Position = 0)]
        [AllowNull()]
        [object] $Map
    )

    if ($null -eq $Map) {
        return
    }

    if ($Map -is [System.Collections.IDictionary]) {
        foreach ($key in $Map.Keys) {
            $keyName = [string]$key
            Write-Output ([PSCustomObject]@{ Key = $keyName; Value = $Map[$key] })
        }
        return
    }

    foreach ($prop in $Map.PSObject.Properties) {
        Write-Output ([PSCustomObject]@{ Key = $prop.Name; Value = $prop.Value })
    }
}

function Get-GuacEntityResponse {
    <#
    .SYNOPSIS
        Wraps a decoded Guacamole entity JSON body in a PSCustomObject with an Identifier.

    .DESCRIPTION
        The Guacamole REST API returns directory listings as a JSON object
        keyed by identifier (DirectoryResource.getObjects returns
        Map<String, ExternalType>) and single objects as a plain JSON object
        without their identifier (DirectoryObjectResource.getObject returns
        the ExternalType directly). This helper normalizes both into
        [PSCustomObject] instances that carry the original properties plus an
        "Identifier" property, so that entity objects can be piped to
        Update-/Remove- cmdlets via ValueFromPipelineByPropertyName.

        The "Identifier" value comes from the -Identifier parameter (the map
        key for listings, the path parameter for single objects) and takes
        precedence over any "identifier" property present in the body.

        A $null body (for example a 204-style empty response) returns $null.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (getObjects: Map<String, ExternalType>)
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (getObject: ExternalType)

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Position = 0)]
        [AllowNull()]
        [object] $Response,

        [Parameter(Position = 1)]
        [AllowEmptyString()]
        [string] $Identifier = [string]::Empty
    )

    if ($null -eq $Response) {
        return $null
    }

    $props = [ordered]@{}
    if ($Response -is [System.Collections.IDictionary]) {
        foreach ($key in $Response.Keys) {
            $props[[string]$key] = $Response[$key]
        }
    }
    else {
        foreach ($prop in $Response.PSObject.Properties) {
            $props[$prop.Name] = $prop.Value
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Identifier)) {
        $props['Identifier'] = $Identifier
    }
    return [PSCustomObject]$props
}

function ConvertTo-GuacEntityBody {
    <#
    .SYNOPSIS
        Converts a user-supplied entity object into a JSON-serializable body.

    .DESCRIPTION
        Copies the properties of a PSCustomObject or hashtable into an
        ordered hashtable suitable for ConvertTo-GuacJson, optionally
        excluding named properties (for example "Identifier" when creating
        an object, where the server assigns the identifier).

        Nested PSCustomObject/hashtable values (for example a "parameters"
        map) are preserved and serialize correctly on both Windows
        PowerShell 5.1 and PowerShell 7.x.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Position = 0)]
        [AllowNull()]
        [object] $Object,

        [Parameter(Position = 1)]
        [string[]] $ExcludeProperty = @()
    )

    if ($null -eq $Object) {
        return [ordered]@{}
    }

    $props = [ordered]@{}
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            $keyName = [string]$key
            if ($ExcludeProperty -contains $keyName) { continue }
            $props[$keyName] = $Object[$key]
        }
    }
    else {
        foreach ($prop in $Object.PSObject.Properties) {
            if ($ExcludeProperty -contains $prop.Name) { continue }
            $props[$prop.Name] = $prop.Value
        }
    }
    return $props
}

function Get-GuacIdentifier {
    <#
    .SYNOPSIS
        Extracts the identifier of a Guacamole entity object.

    .DESCRIPTION
        Returns the identifier carried by an entity object returned by the
        module's Get-* entity cmdlets, which is the "Identifier" property
        added by Get-GuacEntityResponse. Also falls back to the lowercase
        "identifier" property that some raw API objects carry, and to the
        "username" property for users (the APIUser external shape has no
        "identifier" field; the username is the user's identifier).

        Returns an empty string when the object carries no identifier.

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Position = 0)]
        [AllowNull()]
        [object] $Object
    )

    if ($null -eq $Object) {
        return [string]::Empty
    }

    $names = @()
    if ($Object -is [System.Collections.IDictionary]) {
        $names = @($Object.Keys | ForEach-Object { [string]$_ })
    }
    else {
        $names = @($Object.PSObject.Properties | ForEach-Object { $_.Name })
    }

    foreach ($candidate in @('Identifier', 'identifier', 'username')) {
        $index = -1
        for ($i = 0; $i -lt $names.Count; $i++) {
            if ($names[$i] -ieq $candidate) { $index = $i; break }
        }
        if ($index -lt 0) { continue }

        $value = [string]::Empty
        if ($Object -is [System.Collections.IDictionary]) {
            $value = [string]$Object[$names[$index]]
        }
        else {
            $value = [string]$Object.PSObject.Properties[$index].Value
        }
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }
    return [string]::Empty
}
