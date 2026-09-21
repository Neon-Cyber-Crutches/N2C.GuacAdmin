function New-GuacUserGroup {
    <#
    .SYNOPSIS
        Creates a new Guacamole user group.

    .DESCRIPTION
        Creates a user group in the per-data-source UserContext by POSTing an
        APIUserGroup body (DirectoryResource.createObject). The body follows
        the APIUserGroup shape: identifier (the group name; user groups have
        no separate name field and no parent hierarchy), disabled, and
        attributes.

        The group body may be supplied as a hashtable/ordered hashtable or a
        PSCustomObject (also from the pipeline via -InputObject).
        Alternatively, -Identifier/-Disabled/-Attributes construct the body
        directly.

        Requires the CREATE_USER_GROUP system permission (or ADMINISTER) on
        the server.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (createObject: @POST on the directory, returns the created object)
        - guacamole/src/main/java/org/apache/guacamole/rest/usergroup/APIUserGroup.java
          (identifier, disabled, attributes)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("userGroups"))

    .EXAMPLE
        New-GuacUserGroup -Identifier 'auditors'

    .EXAMPLE
        New-GuacUserGroup -Identifier 'contractors' -Disabled $true `
            -Attributes @{ 'guac-description' = 'External contractors' }
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
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

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Identifier = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [switch] $Disabled,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Attributes
    )

    begin {
        $pendingBody = $null
        if (-not [string]::IsNullOrWhiteSpace($Identifier) -or $Disabled -or $null -ne $Attributes) {
            $pendingBody = [ordered]@{
                identifier = $Identifier
                disabled   = [bool]$Disabled
            }
            if ($null -ne $Attributes) { $pendingBody['attributes'] = $Attributes }
        }
    }

    process {
        if ($null -ne $InputObject) {
            $pendingBody = $InputObject
        }
    }

    end {
        if ($null -eq $pendingBody) {
            throw ($script:GuacRestExceptionType::new(
                'New-GuacUserGroup requires a group body: supply -Identifier (optionally with -Disabled/-Attributes) or -InputObject.'
            ))
        }
        $body = ConvertTo-GuacEntityBody -Object $pendingBody
        if ([string]::IsNullOrWhiteSpace([string]$body['identifier'])) {
            throw ($script:GuacRestExceptionType::new(
                'New-GuacUserGroup requires the group identifier (the group name): supply -Identifier or an object with an identifier property.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'New-GuacUserGroup'

        if (-not ($PSCmdlet.ShouldProcess(('user group "{0}"' -f $body['identifier']), 'Create Guacamole user group (POST userGroups)'))) {
            return
        }

        return (Invoke-GuacDirectory -Context $ctx -Collection 'userGroups' -Action 'Create' -Body $body)
    }
}
