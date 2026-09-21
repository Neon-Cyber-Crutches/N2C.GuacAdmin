function New-GuacUser {
    <#
    .SYNOPSIS
        Creates a new Guacamole user.

    .DESCRIPTION
        Creates a user in the per-data-source UserContext by POSTing an APIUser
        body (DirectoryResource.createObject). The body follows the APIUser
        shape: username, password, disabled, and attributes. The username is
        the user's identifier and is assigned by the client in the body (there
        is no server-side identifier generation for users).

        The password is only accepted as part of a PSCredential or as a
        SecureString; plaintext string passwords are deliberately not
        supported. The -Credential parameter supplies both the username and
        the password in one object; -Password may be used instead of
        -Credential when only the password needs to be set (with -Username
        given separately).

        The user body may also be supplied as a hashtable/ordered hashtable or
        a PSCustomObject via -InputObject (a pre-assembled APIUser); in that
        case the "password" property of the body is used as-is.

        Requires the CREATE_USER system permission (or ADMINISTER) on the
        server.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (createObject: @POST on the directory, returns the created object)
        - guacamole/src/main/java/org/apache/guacamole/rest/user/APIUser.java
          (username, password, disabled, attributes)
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("users"))

    .EXAMPLE
        $cred = Get-Credential
        New-GuacUser -Credential $cred

    .EXAMPLE
        New-GuacUser -Username 'jdoe' `
            -Password (ConvertTo-SecureString 'S3cret!' -AsPlainText -Force) `
            -Disabled $false

    .EXAMPLE
        New-GuacUser -InputObject @{
            username = 'jdoe'
            password = 'S3cret!'
            attributes = @{ 'guac-email-address' = 'jdoe@example.com' }
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
        [System.Management.Automation.CredentialAttribute()]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Username = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Security.SecureString] $Password,

        [Parameter(Mandatory = $false)]
        [switch] $Disabled,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Attributes
    )

    begin {
        $pendingBody = $null
        if (-not [string]::IsNullOrWhiteSpace($Username) -or $null -ne $Password -or $null -ne $Credential) {
            $pendingBody = [ordered]@{}
            if ($null -ne $Credential) {
                $pendingBody['username'] = $Credential.UserName
                $pendingBody['password'] = ConvertFrom-GuacSecureString -SecureString $Credential.Password
            }
            else {
                $pendingBody['username'] = $Username
                if ($null -ne $Password) {
                    $pendingBody['password'] = ConvertFrom-GuacSecureString -SecureString $Password
                }
            }
            $pendingBody['disabled'] = [bool]$Disabled
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
                'New-GuacUser requires a user body: supply -Credential, or -Username (optionally with -Password/-Disabled/-Attributes), or -InputObject.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'New-GuacUser'

        $body = ConvertTo-GuacEntityBody -Object $pendingBody
        $whatIfTarget = 'user'
        if (-not [string]::IsNullOrWhiteSpace([string]$body['username'])) { $whatIfTarget = ('user "{0}"' -f $body['username']) }
        if (-not ($PSCmdlet.ShouldProcess($whatIfTarget, 'Create Guacamole user (POST users)'))) {
            return
        }

        return (Invoke-GuacDirectory -Context $ctx -Collection 'users' -Action 'Create' -Body $body)
    }
}
