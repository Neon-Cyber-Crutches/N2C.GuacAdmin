function Remove-GuacUser {
    <#
    .SYNOPSIS
        Deletes a Guacamole user.

    .DESCRIPTION
        Deletes the user with the given username from the per-data-source
        UserContext via DirectoryObjectResource.deleteObject
        (DELETE /users/{username}).

        The user is addressed by -Id (a username), or by piping a user object
        (as returned by Get-GuacUser) into the cmdlet; the piped object's
        Identifier is used when -Id is not given. -Id takes precedence over
        the piped identifier.

        Requires the DELETE_USER system permission (or ADMINISTER) on the
        server. The authenticated user cannot delete themselves while
        authenticated (the server enforces this through the directory
        implementation).

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (deleteObject: @DELETE)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("users"))

    .EXAMPLE
        Remove-GuacUser -Id 'jdoe'

    .EXAMPLE
        Get-GuacUser -Id 'jdoe' | Remove-GuacUser
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
                'Remove-GuacUser requires the username: supply -Id or pipe a user object.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Remove-GuacUser'

        if (-not ($PSCmdlet.ShouldProcess(('user {0}' -f $targetId), 'Delete Guacamole user (DELETE users/{username})'))) {
            return
        }

        Invoke-GuacDirectory -Context $ctx -Collection 'users' -Action 'Delete' -Id $targetId | Out-Null
    }
}
