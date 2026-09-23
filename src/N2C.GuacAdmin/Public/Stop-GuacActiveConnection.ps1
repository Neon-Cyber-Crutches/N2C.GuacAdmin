function Stop-GuacActiveConnection {
    <#
    .SYNOPSIS
        Stops (disconnects) an active Guacamole connection.

    .DESCRIPTION
        Disconnects an active connection by deleting it from the active
        connections directory (DirectoryResource.deleteObject: DELETE
        /activeConnections/{id}). This immediately terminates the underlying
        tunnel.

        Requires the CONNECTION permission on the active connection.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (deleteObject: @DELETE)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("activeConnections"))

    .EXAMPLE
        Stop-GuacActiveConnection -Id 'abc-123'

    .EXAMPLE
        Get-GuacActiveConnection | Where-Object { $_.Username -eq 'jdoe' } | Stop-GuacActiveConnection
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([void])]
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
        }
    }

    end {
        $targetId = $Id
        if ([string]::IsNullOrWhiteSpace($targetId)) { $targetId = $pendingId }
        if ([string]::IsNullOrWhiteSpace($targetId)) {
            throw ($script:GuacRestExceptionType::new(
                'Stop-GuacActiveConnection requires the active connection identifier: supply -Id or pipe an active connection object.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Stop-GuacActiveConnection'

        if (-not ($PSCmdlet.ShouldProcess(('active connection {0}' -f $targetId), 'Stop active connection (DELETE activeConnections/{id})'))) {
            return
        }

        Invoke-GuacDirectory -Context $ctx -Collection 'activeConnections' -Action 'Delete' -Id $targetId | Out-Null
    }
}
