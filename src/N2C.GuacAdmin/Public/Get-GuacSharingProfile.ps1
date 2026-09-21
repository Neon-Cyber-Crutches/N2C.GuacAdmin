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
        [string] $Id = [string]::Empty
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacSharingProfile'

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        return (Invoke-GuacDirectory -Context $ctx -Collection 'sharingProfiles' -Action 'Get' -Id $Id)
    }
    return (Invoke-GuacDirectory -Context $ctx -Collection 'sharingProfiles' -Action 'List')
}
