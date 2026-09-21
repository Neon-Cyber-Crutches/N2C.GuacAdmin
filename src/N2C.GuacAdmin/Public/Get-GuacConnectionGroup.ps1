function Get-GuacConnectionGroup {
    <#
    .SYNOPSIS
        Gets Guacamole connection groups from the UserContext.

    .DESCRIPTION
        Retrieves connection groups from the per-data-source UserContext:
        - without -Id, the full collection (DirectoryResource.getObjects),
          with each entry wrapped so it carries an Identifier property;
        - with -Id, a single group by identifier
          (DirectoryObjectResource.getObject);
        - with -Id and -Tree, the group plus all its descendants
          (ConnectionGroupResource.getConnectionGroupTree, GET
          connectionGroups/{id}/tree), with childConnectionGroups and
          childConnections populated.

        Each returned object is a [PSCustomObject] mirroring the
        APIConnectionGroup fields (name, type, parentIdentifier,
        activeConnections, childConnectionGroups, childConnections,
        attributes) plus the Identifier property, so the results can be piped
        to Update-GuacConnectionGroup and Remove-GuacConnectionGroup.

        The -Permission parameter (list) filters the tree to connections the
        current user holds any of the given permissions for; it applies to
        the -Tree form only, matching the server's "permission" query
        parameter.

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
        Get-GuacConnectionGroup -Id 'group-id' -Tree

    .EXAMPLE
        Get-GuacConnectionGroup -Id 'group-id' -Tree -Permission READ, UPDATE
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
        [switch] $Tree,

        [Parameter(Mandatory = $false)]
        [ValidateSet('READ', 'UPDATE', 'DELETE', 'ADMINISTER')]
        [string[]] $Permission
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacConnectionGroup'

    if ($Tree) {
        $query = [string]::Empty
        if ($null -ne $Permission -and $Permission.Count -gt 0) {
            $query = ('permission={0}' -f ($Permission -join '&permission='))
        }
        $path = Resolve-GuacContextUrl -DataSource $ctx['DataSource'] -Collection 'connectionGroups' -Id $Id -SubPath 'tree' -Query $query
        $response = Invoke-GuacRest -Server $ctx['Server'] -Token $ctx['Token'] -Method GET -Path $path
        return (Get-GuacEntityResponse -Response $response -Identifier $Id)
    }

    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        return (Invoke-GuacDirectory -Context $ctx -Collection 'connectionGroups' -Action 'Get' -Id $Id)
    }
    return (Invoke-GuacDirectory -Context $ctx -Collection 'connectionGroups' -Action 'List')
}
