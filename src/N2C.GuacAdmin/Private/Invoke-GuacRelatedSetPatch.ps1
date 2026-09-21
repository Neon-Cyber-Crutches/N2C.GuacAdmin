#Requires -Version 5.1
function Invoke-GuacRelatedSetPatch {
    <#
    .SYNOPSIS
        Adds or removes an object from a Guacamole related-object set.

    .DESCRIPTION
        Sends a single-operation JSON Patch to a RelatedObjectSetResource
        endpoint (for example userGroups/{id}/memberUsers or
        userGroups/{id}/memberUserGroups). The related-object-set PATCH
        requires the path "/" and the object identifier as the value, so the
        operation is always { "op": <add|remove>, "path": "/", "value":
        "<identifier>" }.

        The collection, object id, and subpath are passed to
        Resolve-GuacContextUrl so that each segment is URL-escaped
        individually.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/identifier/RelatedObjectSetResource.java
          (patchObjects: path "/", value is the identifier)
        - guacamole/src/main/java/org/apache/guacamole/rest/usergroup/UserGroupResource.java
          (getMemberUsers: @Path("memberUsers"); getMemberUserGroups:
           @Path("memberUserGroups"))

        This function is private to the N2C.GuacAdmin module.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable] $Context,

        [Parameter(Mandatory = $true)]
        [string] $Collection,

        [Parameter(Mandatory = $true)]
        [string] $Id,

        [Parameter(Mandatory = $true)]
        [string] $SubPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('add', 'remove')]
        [string] $Op,

        [Parameter(Mandatory = $true)]
        [string] $Identifier
    )

    $path = Resolve-GuacContextUrl -DataSource $Context['DataSource'] -Collection $Collection -Id $Id -SubPath $SubPath
    $operation = Get-GuacPatchOperation -Op $Op -Path '/' -Value $Identifier
    return (Invoke-GuacPatch -Context $Context -Path $path -Patch $operation)
}
