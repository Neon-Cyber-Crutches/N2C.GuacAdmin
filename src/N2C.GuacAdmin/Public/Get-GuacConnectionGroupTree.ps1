function Get-GuacConnectionGroupTree {
    <#
    .SYNOPSIS
        Gets a Guacamole connection group tree with all descendants.

    .DESCRIPTION
        Retrieves the connection group hierarchy rooted at the group identified
        by -Id, including all child groups and child connections at every level.

        Uses the ConnectionGroupResource.getConnectionGroupTree endpoint
        (GET connectionGroups/{id}/tree). The -Permission parameter filters
        the connections included in the tree to those for which the current
        user has any of the specified permissions; connection groups are
        unaffected by this filter.

        The returned object is a [PSCustomObject] mirroring the APIConnectionGroup
        fields (name, type, parentIdentifier, activeConnections,
        childConnectionGroups, childConnections, attributes) plus an Identifier
        property. The childConnectionGroups and childConnections properties are
        maps keyed by identifier.

        By default, -ResolveParentGroupName is $true and the cmdlet resolves
        the root group's parentIdentifier to a human-readable connection group
        name, adding a ParentGroupName property. Use -ResolveParentGroupName:$false
        to skip resolution for raw API data.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/connectiongroup/ConnectionGroupResource.java
          (getConnectionGroupTree: @Path("tree"), "permission" query param)
        - guacamole/src/main/java/org/apache/guacamole/rest/connectiongroup/APIConnectionGroup.java

    .EXAMPLE
        Get-GuacConnectionGroupTree -Id 'group-id'

    .EXAMPLE
        Get-GuacConnectionGroupTree -Id 'group-id' -Permission READ, UPDATE

    .EXAMPLE
        Get-GuacConnectionGroupTree -Id 'group-id' -ResolveParentGroupName:$false
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
        [string] $Id = 'ROOT',

        [Parameter(Mandatory = $false)]
        [ValidateSet('READ', 'UPDATE', 'DELETE', 'ADMINISTER')]
        [string[]] $Permission,

        [Parameter(Mandatory = $false)]
        [bool] $ResolveParentGroupName = $true
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacConnectionGroupTree'

    $query = [string]::Empty
    if ($null -ne $Permission -and $Permission.Count -gt 0) {
        $query = ('permission={0}' -f ($Permission -join '&permission='))
    }
    $path = Resolve-GuacContextUrl -DataSource $ctx['DataSource'] -Collection 'connectionGroups' -Id $Id -SubPath 'tree' -Query $query
    $response = Invoke-GuacRest -Server $ctx['Server'] -Token $ctx['Token'] -Method GET -Path $path
    $tree = Get-GuacEntityResponse -Response $response -Identifier $Id
    if ($ResolveParentGroupName -and $tree.ParentIdentifier) {
        if ($tree.ParentIdentifier -eq 'ROOT') {
            $tree | Add-Member -NotePropertyName ParentGroupName -NotePropertyValue 'ROOT'
        }
        else {
            try {
                $parent = Invoke-GuacDirectory -Context $ctx -Collection 'connectionGroups' -Action 'Get' -Id $tree.ParentIdentifier
                $tree | Add-Member -NotePropertyName ParentGroupName -NotePropertyValue $parent.Name
            }
            catch {
                Write-Verbose ('Get-GuacConnectionGroupTree: could not resolve parent group name for {0}' -f $tree.ParentIdentifier)
                $tree | Add-Member -NotePropertyName ParentGroupName -NotePropertyValue '(unknown)'
            }
        }
    }
    return $tree
}
