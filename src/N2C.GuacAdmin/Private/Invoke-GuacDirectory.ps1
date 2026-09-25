#Requires -Version 5.1
function Invoke-GuacDirectory {
    <#
    .SYNOPSIS
        Executes a directory (collection) operation against a UserContext endpoint.

    .DESCRIPTION
        Shared implementation for the per-entity Get/New/Update/Remove
        cmdlets over the Guacamole DirectoryResource surface. All five
        directory types (connections, connectionGroups, users, userGroups,
        sharingProfiles) expose the identical operation set, so this helper
        performs the HTTP work and the response wrapping while the public
        cmdlets handle parameter validation, ShouldProcess, and body
        construction.

        Actions:
        - List    : GET  /{collection}          -> one [PSCustomObject] per
                  entry (identifier from the map key), each carrying an
                  Identifier property.
        - Get     : GET  /{collection}/{id}     -> a single [PSCustomObject]
                  with an Identifier property.
        - Create  : POST /{collection}          -> the created object wrapped
                  with its server-assigned Identifier.
        - Update  : PUT  /{collection}/{id}     -> the current state re-fetched
                  after the replacement (DirectoryObjectResource.updateObject
                  returns void).
        - Delete  : DELETE /{collection}/{id}   -> no output.

        The Context hashtable is produced by Resolve-GuacSessionContext and
        carries Server, Token, and DataSource.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (getObjects: @GET; createObject: @POST; @Path("{identifier}"))
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (getObject: @GET; updateObject: @PUT; deleteObject: @DELETE)

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
        [ValidateSet('List', 'Get', 'Create', 'Update', 'Delete')]
        [string] $Action,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Id = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Body,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string[]] $Permission
    )

    $server = [string]$Context['Server']
    $token = [string]$Context['Token']
    $dataSource = [string]$Context['DataSource']

    switch ($Action) {
        'List' {
            $query = [string]::Empty
            if ($null -ne $Permission -and $Permission.Count -gt 0) {
                $query = ('permission={0}' -f ($Permission -join '&permission='))
            }
            $path = Resolve-GuacContextUrl -DataSource $dataSource -Collection $Collection -Query $query
            $map = Invoke-GuacRest -Server $server -Token $token -Method GET -Path $path
            if ($null -eq $map) {
                return
            }
            foreach ($entry in (Get-GuacMapEntries -Map $map)) {
                $wrapped = Get-GuacEntityResponse -Response $entry.Value -Identifier $entry.Key
                if ($null -ne $wrapped) {
                    Write-Output $wrapped
                }
            }
        }
        'Get' {
            $path = Resolve-GuacContextUrl -DataSource $dataSource -Collection $Collection -Id $Id
            $response = Invoke-GuacRest -Server $server -Token $token -Method GET -Path $path
            return (Get-GuacEntityResponse -Response $response -Identifier $Id)
        }
        'Create' {
            $path = Resolve-GuacContextUrl -DataSource $dataSource -Collection $Collection
            $jsonBody = ConvertTo-GuacJson -InputObject $Body
            $created = Invoke-GuacRest -Server $server -Token $token -Method POST `
                -Path $path -Body $jsonBody -ContentType 'application/json'
            $identifier = [string]::Empty
            if ($null -ne $created) {
                $identifier = Get-GuacIdentifier -Object (Get-GuacEntityResponse -Response $created)
            }
            return (Get-GuacEntityResponse -Response $created -Identifier $identifier)
        }
        'Update' {
            $path = Resolve-GuacContextUrl -DataSource $dataSource -Collection $Collection -Id $Id
            $jsonBody = ConvertTo-GuacJson -InputObject $Body
            Invoke-GuacRest -Server $server -Token $token -Method PUT `
                -Path $path -Body $jsonBody -ContentType 'application/json' | Out-Null
            $updated = Invoke-GuacRest -Server $server -Token $token -Method GET -Path $path
            return (Get-GuacEntityResponse -Response $updated -Identifier $Id)
        }
        'Delete' {
            $path = Resolve-GuacContextUrl -DataSource $dataSource -Collection $Collection -Id $Id
            Invoke-GuacRest -Server $server -Token $token -Method DELETE -Path $path | Out-Null
        }
    }
}

function Invoke-GuacEntityPatch {
    <#
    .SYNOPSIS
        Applies a JSON Patch to a directory collection and checks the outcomes.

    .DESCRIPTION
        Wraps Invoke-GuacPatch for the directory collection PATCH endpoint
        (DirectoryResource.patchObjects) and converts a failed outcome into a
        terminating [N2C_GuacAdmin_GuacRestException]. The server also returns
        HTTP 400 (APIPatchFailureException) when any operation fails, which
        Invoke-GuacRest already terminates on; this additionally inspects the
        per-operation outcomes in a 2xx APIPatchResponse for error entries.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (patchObjects)
        - guacamole/src/main/java/org/apache/guacamole/rest/jsonpatch/APIPatchResponse.java
        - guacamole/src/main/java/org/apache/guacamole/rest/jsonpatch/APIPatchError.java

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
        [string] $TargetLabel,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object] $Patch
    )

    $path = Resolve-GuacContextUrl -DataSource $Context['DataSource'] -Collection $Collection
    $response = Invoke-GuacPatch -Context $Context -Path $path -Patch $Patch

    $failed = $null
    if ($null -ne $response -and $response.PSObject.Properties['patches']) {
        foreach ($outcome in @($response.patches)) {
            if ($outcome.PSObject.Properties['error']) {
                $failed = $outcome
                break
            }
        }
    }
    if ($null -ne $failed) {
        $message = [string]$failed.error
        if ([string]::IsNullOrWhiteSpace($message) -and $failed.PSObject.Properties['message']) {
            $message = [string]$failed.message
        }
        throw ($script:GuacRestExceptionType::new(
            ('Guacamole JSON Patch failed for {0}: {1}' -f ($TargetLabel, $message))
        ))
    }
    return $response
}
