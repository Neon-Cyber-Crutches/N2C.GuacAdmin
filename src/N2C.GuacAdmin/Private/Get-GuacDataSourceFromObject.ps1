#Requires -Version 5.1
function Get-GuacDataSourceFromObject {
    <#
    .SYNOPSIS
        Extracts the DataSource property from a Guacamole entity object.

    .DESCRIPTION
        Returns the DataSource carried by an entity object returned by the
        module's Get-* entity cmdlets, which is the "DataSource" property
        added by Get-GuacEntityResponse. Returns an empty string when the
        object carries no DataSource property or the object is null.

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

    # NOTE: property lookup is done by iterating and matching the name
    # (case-insensitive). Integer indexing into $Object.PSObject.Properties is
    # NOT used: it is a PSMemberInfoIntegratingCollection, and indexing it with
    # an int performs a name-match query that returns an empty PSPropertyInfo
    # (verified on pwsh 7.6), which silently yields $null values.
    foreach ($prop in $Object.PSObject.Properties) {
        if ($prop.Name -ieq 'DataSource') {
            $value = [string]$prop.Value
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
    }
    return [string]::Empty
}
