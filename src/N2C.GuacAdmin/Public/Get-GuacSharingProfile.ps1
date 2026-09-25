function Get-GuacSharingProfile {
    <#
    .SYNOPSIS
        Gets Guacamole sharing profiles from the UserContext.

    .DESCRIPTION
        Retrieves sharing profiles from the per-data-source UserContext:
        - without -Id, the full collection (DirectoryResource.getObjects),
          with each entry wrapped so it carries an Identifier property;
        - with -Id, a single sharing profile by identifier
          (DirectoryObjectResource.getObject), including its parameters.

        Each returned object mirrors the APISharingProfile fields: name,
        primaryConnectionIdentifier, parameters, attributes — plus the
        Identifier property, so the results can be piped to
        Update-GuacSharingProfile and Remove-GuacSharingProfile.

        By default, -ResolveConnectionName is $true and the cmdlet resolves
        each primaryConnectionIdentifier to a human-readable connection name,
        adding a PrimaryConnectionName property. Use -ResolveConnectionName:$false
        to skip resolution for raw API data.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("sharingProfiles"))
        - guacamole/src/main/java/org/apache/guacamole/rest/sharingprofile/SharingProfileResource.java
          (getParameters: @GET @Path("parameters"))
        - guacamole/src/main/java/org/apache/guacamole/rest/sharingprofile/APISharingProfile.java
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (getObjects) / DirectoryObjectResource.java (getObject)

    .EXAMPLE
        Get-GuacSharingProfile

    .EXAMPLE
        Get-GuacSharingProfile -Id 'readonly'

    .EXAMPLE
        Get-GuacSharingProfile | Select-Object Name, PrimaryConnectionName

    .EXAMPLE
        Get-GuacSharingProfile -ResolveConnectionName:$false
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [N2C_GuacAdmin_GuacSession] $Session,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Server = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $DataSource = [string]::Empty,

        [Parameter(Mandatory = $false, Position = 0)]
        [AllowEmptyString()]
        [string] $Id = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [bool] $ResolveConnectionName = $true
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacSharingProfile'

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $sh_profile = Invoke-GuacDirectory -Context $ctx -Collection 'sharingProfiles' -Action 'Get' -Id $Id
        if ($ResolveConnectionName -and -not [string]::IsNullOrWhiteSpace($sh_profile.PrimaryConnectionIdentifier)) {
            try {
                $conn = Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Get' -Id $sh_profile.PrimaryConnectionIdentifier
                $sh_profile | Add-Member -NotePropertyName PrimaryConnectionName -NotePropertyValue $conn.Name
            }
            catch {
                Write-Verbose ('Get-GuacSharingProfile: could not resolve connection name for {0}' -f $sh_profile.PrimaryConnectionIdentifier)
                $sh_profile | Add-Member -NotePropertyName PrimaryConnectionName -NotePropertyValue '(unknown)'
            }
        }
        return $sh_profile
    }

    $profiles = @(Invoke-GuacDirectory -Context $ctx -Collection 'sharingProfiles' -Action 'List')
    if ($ResolveConnectionName -and $profiles.Count -gt 0) {
        $connIds = @($profiles | ForEach-Object { if ($_.PrimaryConnectionIdentifier) { $_.PrimaryConnectionIdentifier } }) | Select-Object -Unique
        $connMap = @{}
        foreach ($connId in $connIds) {
            try {
                $conn = Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Get' -Id $connId
                $connMap[$connId] = $conn.Name
            }
            catch {
                Write-Verbose ('Get-GuacSharingProfile: could not resolve connection name for {0}' -f $connId)
                $connMap[$connId] = '(unknown)'
            }
        }
        foreach ($sh_profile in $profiles) {
            if ($sh_profile.PrimaryConnectionIdentifier) {
                $sh_profile | Add-Member -NotePropertyName PrimaryConnectionName -NotePropertyValue $connMap[$sh_profile.PrimaryConnectionIdentifier]
            }
        }
    }
    return $profiles
}
