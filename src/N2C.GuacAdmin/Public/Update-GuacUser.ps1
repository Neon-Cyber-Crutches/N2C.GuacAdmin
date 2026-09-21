function Update-GuacUser {
    <#
    .SYNOPSIS
        Updates an existing Guacamole user.

    .DESCRIPTION
        Two mutation modes, exactly one of which must be supplied:

        - -Patch (the canonical form): a JSON Patch operations array applied
          via the collection PATCH endpoint (DirectoryResource.patchObjects).
          A single operation or an array of operations is accepted. Supported
          operations: add (create), replace (update, path "/{username}"),
          and remove (path "/{username}").

        - -Replace: a replacement of the user via
          DirectoryObjectResource.updateObject (PUT /users/{username}).

        User update semantics differ from connections and groups: the server
        translator (UserObjectTranslator.applyExternalChanges) updates the
        password only when one is present in the body (a body without a
        "password" leaves the existing password unchanged), and replaces the
        "disabled" and "attributes" fields. The username is the user's
        identifier and cannot be changed through this endpoint; to rename a
        user, create a new one and remove the old.

        As with all Update-* cmdlets, omitted fields have a defined effect:
        here, omitting "password" preserves it, while "disabled" and
        "attributes" are replaced (an omitted "attributes" map is nulled).

        The target user is addressed by -Id (a username), or by piping a user
        object (as returned by Get-GuacUser) into the cmdlet (bound to
        -InputObject); the piped object's Identifier is used when -Id is not
        given. -Id takes precedence over the piped identifier.

        A user may not change their own password through this endpoint; the
        server rejects it (UserResource.updateObject). Use
        Set-GuacUserPassword for that case.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryResource.java
          (patchObjects: @PATCH with List<APIPatch<ExternalType>>)
        - guacamole/src/main/java/org/apache/guacamole/rest/directory/DirectoryObjectResource.java
          (updateObject: @PUT)
        - guacamole/src/main/java/org/apache/guacamole/rest/user/UserResource.java
          (updateObject override: self password change is rejected)
        - guacamole/src/main/java/org/apache/guacamole/rest/user/UserObjectTranslator.java
          (applyExternalChanges: password conditional; disabled, attributes
           replaced)
        - guacamole/src/main/java/org/apache/guacamole/rest/user/APIUser.java

    .EXAMPLE
        $user = Get-GuacUser -Id 'jdoe'
        $user.Disabled = $true
        Update-GuacUser -Id 'jdoe' -Replace $user

    .EXAMPLE
        Update-GuacUser -Id 'jdoe' -Patch (
            @{ op = 'replace'; path = '/jdoe'; value = $fullUser }
        )

    .EXAMPLE
        Update-GuacUser -Id 'jdoe' -Replace @{
            disabled = $false
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

        [Parameter(Mandatory = $false, Position = 0)]
        [AllowEmptyString()]
        [string] $Id = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Patch,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Replace,

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
        $hasPatch = ($null -ne $Patch)
        $hasReplace = ($null -ne $Replace)
        if ($hasPatch -and $hasReplace) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacUser: supply exactly one of -Patch or -Replace, not both.'
            ))
        }
        if (-not $hasPatch -and -not $hasReplace) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacUser: supply -Patch (a JSON Patch operations array) or -Replace (a user object), or pipe a user object with one of them.'
            ))
        }

        $targetId = $Id
        if ([string]::IsNullOrWhiteSpace($targetId)) { $targetId = $pendingId }
        if ($hasReplace -and [string]::IsNullOrWhiteSpace($targetId)) {
            throw ($script:GuacRestExceptionType::new(
                'Update-GuacUser -Replace requires the username: supply -Id or pipe a user object carrying an Identifier.'
            ))
        }

        $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Update-GuacUser'

        if ($hasPatch) {
            if (-not [string]::IsNullOrWhiteSpace($targetId)) {
                $whatIfTarget = ('user {0}' -f $targetId)
            }
            else {
                $whatIfTarget = 'user (patch)'
            }
            if (-not ($PSCmdlet.ShouldProcess($whatIfTarget, 'Update Guacamole user (PATCH users)'))) {
                return
            }
            Invoke-GuacEntityPatch -Context $ctx -Collection 'users' `
                -TargetLabel ('user {0}' -f $targetId) -Patch $Patch | Out-Null
            return
        }

        # Replacement via PUT. The username is the identifier and is not part
        # of the mutable body; drop it so it cannot be "changed".
        $body = ConvertTo-GuacEntityBody -Object $Replace -ExcludeProperty @('identifier', 'Identifier', 'username', 'lastActive')
        if (-not ($PSCmdlet.ShouldProcess(('user {0}' -f $targetId), 'Replace Guacamole user (PUT users/{username})'))) {
            return
        }
        return (Invoke-GuacDirectory -Context $ctx -Collection 'users' -Action 'Update' -Id $targetId -Body $body)
    }
}
