function Get-GuacConnectionGroup {
    <#
    .SYNOPSIS
        Gets Guacamole connection groups from the UserContext.

    .DESCRIPTION
        Retrieves connection groups from the per-data-source UserContext:
        - without -Id, the full collection (DirectoryResource.getObjects),
          with each entry wrapped so it carries an Identifier property;
        - with -Id, a single group by identifier
          (DirectoryObjectResource.getObject).

        Each returned object is a [PSCustomObject] mirroring the
        APIConnectionGroup fields (name, type, parentIdentifier,
        activeConnections, childConnectionGroups, childConnections,
        attributes) plus the Identifier property, so the results can be piped
        to Update-GuacConnectionGroup and Remove-GuacConnectionGroup.

        By default, -ResolveParentGroupName is $true and the cmdlet resolves
        each parentIdentifier to a human-readable connection group name, adding
        a ParentGroupName property. Use -ResolveParentGroupName:$false to skip
        resolution for raw API data.

        The -Permission parameter (list) filters the returned groups to those
        for which the current user holds any of the given permissions, matching
        the server's "permission" query parameter on the directory listing
        endpoint.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("connectionGroups"))
        - guacamole/src/main/java/org/apache/guacamole/rest/connectiongroup/ConnectionGroupResource.java
          (getConnectionGroupTree: @Path("tree"), "permission" query param)
        - guacamole/src/main/java/org/apache/guacamole/rest/connectiongroup/APIConnectionGroup.java
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (getObjects) / DirectoryObjectResource.java (getObject)

    .EXAMPLE
        Get-GuacConnectionGroup

    .EXAMPLE
        Get-GuacConnectionGroup -Id 'group-id'

    .EXAMPLE
        Get-GuacConnectionGroup -Permission READ, UPDATE

    .EXAMPLE
        Get-GuacConnectionGroup | Select-Object Name, ParentGroupName

    .EXAMPLE
        Get-GuacConnectionGroup -ResolveParentGroupName:$false
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
        [ValidateSet('READ', 'UPDATE', 'DELETE', 'ADMINISTER')]
        [string[]] $Permission,

        [Parameter(Mandatory = $false)]
        [bool] $ResolveParentGroupName = $true
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacConnectionGroup'

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $group = Invoke-GuacDirectory -Context $ctx -Collection 'connectionGroups' -Action 'Get' -Id $Id
        if ($ResolveParentGroupName -and $group.ParentIdentifier) {
            if ($group.ParentIdentifier -eq 'ROOT') {
                $group | Add-Member -NotePropertyName ParentGroupName -NotePropertyValue 'ROOT'
            }
            else {
                try {
                    $parent = Invoke-GuacDirectory -Context $ctx -Collection 'connectionGroups' -Action 'Get' -Id $group.ParentIdentifier
                    $group | Add-Member -NotePropertyName ParentGroupName -NotePropertyValue $parent.Name
                }
                catch {
                    Write-Verbose ('Get-GuacConnectionGroup: could not resolve parent group name for {0}' -f $group.ParentIdentifier)
                    $group | Add-Member -NotePropertyName ParentGroupName -NotePropertyValue '(unknown)'
                }
            }
        }
        return $group
    }

    $groups = @(Invoke-GuacDirectory -Context $ctx -Collection 'connectionGroups' -Action 'List' -Permission $Permission)
    if ($ResolveParentGroupName -and $groups.Count -gt 0) {
        $parentIds = @($groups | ForEach-Object { if ($_.ParentIdentifier -and $_.ParentIdentifier -ne 'ROOT') { $_.ParentIdentifier } }) | Select-Object -Unique
        $parentMap = @{}
        foreach ($parentId in $parentIds) {
            try {
                $parent = Invoke-GuacDirectory -Context $ctx -Collection 'connectionGroups' -Action 'Get' -Id $parentId
                $parentMap[$parentId] = $parent.Name
            }
            catch {
                Write-Verbose ('Get-GuacConnectionGroup: could not resolve parent group name for {0}' -f $parentId)
                $parentMap[$parentId] = '(unknown)'
            }
        }
        foreach ($group in $groups) {
            if ($group.ParentIdentifier) {
                if ($group.ParentIdentifier -eq 'ROOT') {
                    $group | Add-Member -NotePropertyName ParentGroupName -NotePropertyValue 'ROOT'
                }
                else {
                    $group | Add-Member -NotePropertyName ParentGroupName -NotePropertyValue $parentMap[$group.ParentIdentifier]
                }
            }
        }
    }
    return $groups
}
