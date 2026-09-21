function Set-GuacUserPassword {
    <#
    .SYNOPSIS
        Changes the password of an existing Guacamole user.

    .DESCRIPTION
        Changes the user's password via the dedicated password endpoint
        (PUT /users/{username}/password, UserResource.updatePassword). The
        body is an APIUserPasswordUpdate: { oldPassword, newPassword }.

        The server verifies the old password by authenticating it through the
        AuthenticationProvider; a wrong or missing old password is rejected
        with "Permission denied." Both passwords are only accepted as
        SecureString values; plaintext strings are deliberately not
        supported.

        This endpoint is also the way a user changes their own password: the
        general user-update endpoint (PUT /users/{username}) rejects self
        password changes (UserResource.updateObject), so -Id may name the
        authenticated user.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/user/UserResource.java
          (updatePassword: @PUT @Path("password"), APIUserPasswordUpdate)
        - guacamole/src/main/java/org/apache/guacamole/rest/user/APIUserPasswordUpdate.java
          (oldPassword, newPassword)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("users"))

    .EXAMPLE
        Set-GuacUserPassword -Id 'jdoe' `
            -OldPassword (ConvertTo-SecureString 'old' -AsPlainText -Force) `
            -NewPassword (ConvertTo-SecureString 'new' -AsPlainText -Force)

    .EXAMPLE
        # A user changes their own password.
        Set-GuacUserPassword -Id $session.Username -OldPassword $old -NewPassword $new
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
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

        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Id,

        [Parameter(Mandatory = $true, Position = 1)]
        [System.Security.SecureString] $OldPassword,

        [Parameter(Mandatory = $true, Position = 2)]
        [System.Security.SecureString] $NewPassword,

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

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Set-GuacUserPassword'

        if (-not ($PSCmdlet.ShouldProcess(('user {0}' -f $targetId), 'Change Guacamole user password (PUT users/{username}/password)'))) {
            return
        }

        $oldPlaintext = ConvertFrom-GuacSecureString -SecureString $OldPassword
        $newPlaintext = ConvertFrom-GuacSecureString -SecureString $NewPassword
        try {
            $body = [ordered]@{
                oldPassword = $oldPlaintext
                newPassword = $newPlaintext
            }
            $jsonBody = ConvertTo-GuacJson -InputObject $body
            $path = Resolve-GuacContextUrl -DataSource $ctx['DataSource'] -Collection 'users' -Id $targetId -SubPath 'password'
            Invoke-GuacRest -Server $ctx['Server'] -Token $ctx['Token'] -Method PUT `
                -Path $path -Body $jsonBody -ContentType 'application/json' | Out-Null
        }
        finally {
            $oldPlaintext = $null
            $newPlaintext = $null
        }
    }
}
