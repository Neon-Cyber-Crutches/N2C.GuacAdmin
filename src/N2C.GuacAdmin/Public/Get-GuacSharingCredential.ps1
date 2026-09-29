function Get-GuacSharingCredential {
    <#
    .SYNOPSIS
        Gets sharing credentials for an active connection.

    .DESCRIPTION
        Retrieves a sharing key that allows another user to join an already-active
        session through a specific sharing profile. The sharing key is a temporary
        query parameter value that encodes the sharing semantics (e.g., read-only
        vs. full access) defined by the sharing profile.

        The returned object contains:
        - Key: The sharing key (use this to let another user join the session)
        - ActiveConnectionId: The identifier of the active connection
        - SharingProfileId: The identifier of the sharing profile used
        - Username: The username of the user who owns the active session
        - RemoteHost: The remote host of the user who owns the active session
        - ConnectionName: The name of the underlying connection
        - SharingProfileName: The name of the sharing profile
        - DataSource: The data source identifier

        The sharing key can be shared with another user, who can then connect
        to the same session by providing the key when joining.

        Prerequisites:
        1. A connection must exist.
        2. A sharing profile must be created for that connection
           (New-GuacSharingProfile).
        3. An active session must exist on that connection
           (visible via Get-GuacActiveConnection).

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/activeconnection/ActiveConnectionResource.java
          (@Path("sharingCredentials/{sharingProfile}"), getSharingCredentials: @GET
           returns APIUserCredentials)
        - guacamole/src/main/java/org/apache/guacamole/rest/activeconnection/APIUserCredentials.java
        - guacamole-ext/src/main/java/org/apache/guacamole/net/auth/Shareable.java
          (getSharingCredentials() interface)

    .EXAMPLE
        Get-GuacSharingCredential -Id da7cb142-d5f5-3683-ad22-98b1a1f132b4 -SharingProfile 3
        
        Gets sharing credentials for active connection with Id da7cb142-d5f5-3683-ad22-98b1a1f132b4 using the
        sharing profile with Identifier 3.
        The -Id parameter must be the Identifier from an active connection object
        (obtained via Get-GuacActiveConnection).
        The -SharingProfile parameter must be the Identifier from a sharing profile object
        (obtained via Get-GuacSharingProfile).

    .EXAMPLE
        $ac = Get-GuacActiveConnection -Id da7cb142-d5f5-3683-ad22-98b1a1f132b4
        
        Get-GuacSharingCredential -ActiveConnection $ac -SharingProfile 3
        Pipes an active connection object to get sharing credentials.

    .EXAMPLE
        $creds = Get-GuacSharingCredential -Id da7cb142-d5f5-3683-ad22-98b1a1f132b4 -SharingProfile 3
        Write-Host "Sharing key: $($creds.Key)"
        Write-Host "Connection: $($creds.ConnectionName)"
        Write-Host "User: $($creds.Username)"
        
        Extracts the sharing key and session context from the returned credentials.
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
                        $normalized = ConvertTo-GuacMapValue -Value $response
                        $sharingKey = $normalized['values']['key']

                        $activeConn = $null
                        $username = ''
                        $remoteHost = ''
                        $connectionId = ''
                        try {
                            $activeConn = Invoke-GuacDirectory -Context $singleCtx -Collection 'activeConnections' -Action 'Get' -Id $targetId
                            if ($activeConn) {
                                $username = [string]$activeConn.Username
                                $remoteHost = [string]$activeConn.RemoteHost
                                $connectionId = [string]$activeConn.ConnectionIdentifier
                            }
                        }
                        catch {
                            Write-Verbose ('Get-GuacSharingCredential: could not fetch active connection details: {0}' -f $_.Exception.Message)
                        }

                        $connectionName = '(unknown)'
                        if ($connectionId) {
                            try {
                                $conn = Invoke-GuacDirectory -Context $singleCtx -Collection 'connections' -Action 'Get' -Id $connectionId
                                if ($conn) {
                                    $connectionName = [string]$conn.Name
                                }
                            }
                            catch {
                                Write-Verbose ('Get-GuacSharingCredential: could not resolve connection name: {0}' -f $_.Exception.Message)
                            }
                        }

                        $sharingProfileName = '(unknown)'
                        try {
                            $sh_profile = Invoke-GuacDirectory -Context $singleCtx -Collection 'sharingProfiles' -Action 'Get' -Id $SharingProfile
                            if ($sh_profile) {
                                $sharingProfileName = [string]$sh_profile.Name
                            }
                        }
                        catch {
                            Write-Verbose ('Get-GuacSharingCredential: could not resolve sharing profile name: {0}' -f $_.Exception.Message)
                        }

                        Write-Output ([PSCustomObject]@{
                            Key = $sharingKey
                            ActiveConnectionId = $targetId
                            SharingProfileId = $SharingProfile
                            Username = $username
                            RemoteHost = $remoteHost
                            ConnectionName = $connectionName
                            SharingProfileName = $sharingProfileName
                            DataSource = $ds
                        })
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
        $response = Invoke-GuacRest -Server $ctx['Server'] -Token $ctx['Token'] -Method GET -Path $path

        $normalized = ConvertTo-GuacMapValue -Value $response
        $sharingKey = $normalized['values']['key']

        $activeConn = $null
        $username = ''
        $remoteHost = ''
        $connectionId = ''
        try {
            $activeConn = Invoke-GuacDirectory -Context $ctx -Collection 'activeConnections' -Action 'Get' -Id $targetId
            if ($activeConn) {
                $username = [string]$activeConn.Username
                $remoteHost = [string]$activeConn.RemoteHost
                $connectionId = [string]$activeConn.ConnectionIdentifier
            }
        }
        catch {
            Write-Verbose ('Get-GuacSharingCredential: could not fetch active connection details: {0}' -f $_.Exception.Message)
        }

        $connectionName = '(unknown)'
        if ($connectionId) {
            try {
                $conn = Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Get' -Id $connectionId
                if ($conn) {
                    $connectionName = [string]$conn.Name
                }
            }
            catch {
                Write-Verbose ('Get-GuacSharingCredential: could not resolve connection name: {0}' -f $_.Exception.Message)
            }
        }

        $sharingProfileName = '(unknown)'
        try {
            $sh_profile = Invoke-GuacDirectory -Context $ctx -Collection 'sharingProfiles' -Action 'Get' -Id $SharingProfile
            if ($sh_profile) {
                $sharingProfileName = [string]$sh_profile.Name
            }
        }
        catch {
            Write-Verbose ('Get-GuacSharingCredential: could not resolve sharing profile name: {0}' -f $_.Exception.Message)
        }

        return [PSCustomObject]@{
            Key = $sharingKey
            ActiveConnectionId = $targetId
            SharingProfileId = $SharingProfile
            Username = $username
            RemoteHost = $remoteHost
            ConnectionName = $connectionName
            SharingProfileName = $sharingProfileName
            DataSource = $ctx['DataSource']
        }
    }
}
