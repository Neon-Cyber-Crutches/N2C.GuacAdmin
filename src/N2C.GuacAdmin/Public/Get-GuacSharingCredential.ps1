function Get-GuacSharingCredential {
    <#
    .SYNOPSIS
        Gets sharing credentials for an active connection.

    .DESCRIPTION
        Retrieves a set of credentials that can be used by another user to
        connect to an active session through a specific sharing profile
        (ActiveConnectionResource.getSharingCredentials: GET
        /activeConnections/{id}/sharingCredentials/{sharingProfile}).

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/activeconnection/ActiveConnectionResource.java
          (@Path("sharingCredentials/{sharingProfile}"), getSharingCredentials: @GET
           returns APIUserCredentials)
        - guacamole/src/main/java/org/apache/guacamole/rest/activeconnection/APIUserCredentials.java

    .EXAMPLE
        Get-GuacSharingCredential -Id 'abc-123' -SharingProfile 'readonly'

    .EXAMPLE
        $ac = Get-GuacActiveConnection -Id 'abc-123'
        Get-GuacSharingCredential -ActiveConnection $ac -SharingProfile 'readonly'
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

        [Parameter(Mandatory = $false, Position = 1)]
        [AllowEmptyString()]
        [string] $SharingProfile = [string]::Empty,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [object] $InputObject
    )

    begin {
        $pendingId = [string]::Empty
    }

    process {
            if ($null -ne $InputObject) {
                $pendingId = Get-GuacIdentifier -Object $InputObject
                # DataSource resolution priority: explicit param > piped object > session default
                if ([string]::IsNullOrWhiteSpace($DataSource)) {
                    $pipedDs = Get-GuacDataSourceFromObject -Object $InputObject
                    if (-not [string]::IsNullOrWhiteSpace($pipedDs)) {
                        $DataSource = $pipedDs
                    }
                }
            }
        }
    
        end {
            $targetId = $Id
            if ([string]::IsNullOrWhiteSpace($targetId)) { $targetId = $pendingId }
        if ([string]::IsNullOrWhiteSpace($targetId)) {
            throw ($script:GuacRestExceptionType::new(
                'Get-GuacSharingCredential requires the active connection identifier: supply -Id or pipe an active connection object.'
            ))
        }
        if ([string]::IsNullOrWhiteSpace($SharingProfile)) {
            throw ($script:GuacRestExceptionType::new(
                'Get-GuacSharingCredential requires -SharingProfile.'
            ))
        }

        # Handle -DataSource All by iterating over all available data sources
                if ($DataSource -ieq 'All') {
                    $allCtx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacSharingCredential'
                    foreach ($ds in $allCtx.DataSources) {
                        $singleCtx = [ordered]@{
                            Session    = $allCtx.Session
                            Server     = $allCtx.Server
                            Token      = $allCtx.Token
                            DataSource = $ds
                        }
                        try {
                            $path = Resolve-GuacContextUrl -DataSource $singleCtx['DataSource'] -Collection 'activeConnections' -Id $targetId -SubPath ('sharingCredentials/{0}' -f $SharingProfile)
                            $response = Invoke-GuacRest -Server $singleCtx['Server'] -Token $singleCtx['Token'] -Method GET -Path $path
                            if ($response) {
                                $response | Add-Member -NotePropertyName DataSource -NotePropertyValue $ds -Force
                                Write-Output $response
                            }
                        }
                        catch {
                            Write-Warning ('Get-GuacSharingCredential: error querying data source "{0}": {1}' -f ($ds, $_.Exception.Message))
                        }
                    }
                    return
                }
        
                $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacSharingCredential'
        
                $path = Resolve-GuacContextUrl -DataSource $ctx['DataSource'] -Collection 'activeConnections' -Id $targetId -SubPath ('sharingCredentials/{0}' -f $SharingProfile)
                return (Invoke-GuacRest -Server $ctx['Server'] -Token $ctx['Token'] -Method GET -Path $path)
    }
}
