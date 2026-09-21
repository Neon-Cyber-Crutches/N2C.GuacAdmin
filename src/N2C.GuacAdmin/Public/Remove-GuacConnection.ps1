function Remove-GuacConnection {
    <#
    .SYNOPSIS
        Deletes a Guacamole connection.

    .DESCRIPTION
        Deletes the connection with the given identifier from the
        per-data-source UserContext via DirectoryObjectResource.deleteObject
        (DELETE /connections/{id}).

        The connection is addressed by -Id, or by piping a connection object
        (as returned by Get-GuacConnection) into the cmdlet; the piped
        object's Identifier is used when -Id is not given. -Id takes
        precedence over the piped identifier.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (deleteObject: @DELETE)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("connections"))

    .EXAMPLE
        Remove-GuacConnection -Id '8b1f2c3d-...'

    .EXAMPLE
        Get-GuacConnection -Id $id | Remove-GuacConnection
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
                'Remove-GuacConnection requires the connection identifier: supply -Id or pipe a connection object.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Remove-GuacConnection'

        if (-not ($PSCmdlet.ShouldProcess(('connection {0}' -f $targetId), 'Delete Guacamole connection (DELETE connections/{id})'))) {
            return
        }

        Invoke-GuacDirectory -Context $ctx -Collection 'connections' -Action 'Delete' -Id $targetId | Out-Null
    }
}
