function New-GuacSharingProfile {
    <#
    .SYNOPSIS
        Creates a new Guacamole sharing profile.

    .DESCRIPTION
        Creates a sharing profile in the per-data-source UserContext by
        POSTing an APISharingProfile body (DirectoryResource.createObject).
        The body follows the APISharingProfile shape: name,
        primaryConnectionIdentifier (the connection the profile shares),
        parameters (a map of parameter name to value that override the
        primary connection's parameters when the profile is used), and
        attributes.

        The sharing profile body may be supplied as a hashtable/ordered
        hashtable or a PSCustomObject (also from the pipeline via
        -InputObject). Alternatively, -Name/-PrimaryConnection/-Parameters/
        -Attributes construct the body directly.

        Requires the CREATE_SHARING_PROFILE system permission (or ADMINISTER)
        on the server. The primary connection must exist and the user must
        have permission to share it.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (createObject: @POST on the directory, returns the created object)
        - guacamole/src/main/java/org/apache/guacamole/rest/sharingprofile/APISharingProfile.java
          (name, primaryConnectionIdentifier, parameters, attributes)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("sharingProfiles"))

    .EXAMPLE
        New-GuacSharingProfile -Name 'read-only' `
            -PrimaryConnection 'conn-id' `
            -Parameters @{ 'guac-readonly' = 'true' }

    .EXAMPLE
        New-GuacSharingProfile -InputObject @{
            name = 'auditor'
            primaryConnectionIdentifier = 'conn-id'
            parameters = @{ 'guac-readonly' = 'true' }
        }
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
        [string] $Name = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $PrimaryConnection = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Parameters,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Attributes
    )

    begin {
        $pendingBody = $null
        if (-not [string]::IsNullOrWhiteSpace($Name) -or -not [string]::IsNullOrWhiteSpace($PrimaryConnection)) {
            $pendingBody = [ordered]@{}
            $pendingBody['name'] = $Name
            if (-not [string]::IsNullOrWhiteSpace($PrimaryConnection)) {
                $pendingBody['primaryConnectionIdentifier'] = $PrimaryConnection
            }
            if ($null -ne $Parameters) { $pendingBody['parameters'] = $Parameters }
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
                'New-GuacSharingProfile requires a profile body: supply -Name (with -PrimaryConnection) or -InputObject.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'New-GuacSharingProfile'

        $body = ConvertTo-GuacEntityBody -Object $pendingBody -ExcludeProperty @('identifier', 'Identifier')
        $whatIfTarget = 'sharing profile'
        if (-not [string]::IsNullOrWhiteSpace([string]$body['name'])) { $whatIfTarget = ('sharing profile "{0}"' -f $body['name']) }
        if (-not ($PSCmdlet.ShouldProcess($whatIfTarget, 'Create Guacamole sharing profile (POST sharingProfiles)'))) {
            return
        }

        return (Invoke-GuacDirectory -Context $ctx -Collection 'sharingProfiles' -Action 'Create' -Body $body)
    }
}
