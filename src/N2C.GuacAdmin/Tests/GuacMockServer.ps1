#Requires -Version 5.1
<#
.SYNOPSIS
    In-process mock of the Apache Guacamole 1.6.0 REST API for Pester tests.

.DESCRIPTION
    Emulates the endpoints the module uses, with the same response shapes as
    the 1.6.0 source:
    - POST /api/tokens        (TokenRESTService.createToken)
    - DELETE /api/tokens/{t}  (TokenRESTService.invalidateToken)
    - HEAD /api/session       (SessionResource.checkValidity)
    - per-DataSource UserContext surface:
        connections, connectionGroups (incl. {id}/tree), users (incl.
        {username}/password, {username}/permissions,
        {username}/effectivePermissions, {username}/userGroups,
        {username}/history), userGroups (incl. memberUsers, memberUserGroups,
        permissions), sharingProfiles, history/connections, history/users,
        schema/{set}, schema/protocols
    - GET  /api/notfound      (always 404 with an APIError JSON body)
    - GET  /api/plaintext-error (always 500 with a non-JSON body)

    Valid credentials: username "guacadmin", password "secret".
    The 'mysql' data source is seeded with entities; 'ldap' starts empty.
    Every request is appended as a JSON line to the log file (see -LogFile)
    so tests can assert what the client actually sent. Control endpoints
    (/_control/*) let tests toggle behavior without shared state.

    Reference (Apache Guacamole 1.6.0): the per-endpoint Java sources cited
    in the module cmdlets (DirectoryResource, DirectoryObjectResource,
    PermissionSetResource, RelatedObjectSetResource, ActivityRecordSetResource,
    SchemaResource, UserResource, ConnectionGroupResource).
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [int] $Port,

    [Parameter(Mandatory = $true)]
    [string] $LogFile
)

$utf8 = [System.Text.Encoding]::UTF8
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add(('http://127.0.0.1:{0}/guacamole/' -f $Port))
$listener.Start()

$validTokens = @{}
$requireTotp = $false
Write-Output 'READY'
Write-Output ('PORT {0}' -f $Port)

function Send-Response {
    param (
        [System.Net.HttpListenerContext] $Context,
        [int] $Code,
        [string] $ContentType,
        [string] $Body
    )
    $response = $Context.Response
    $response.StatusCode = $Code
    if ($ContentType) { $response.ContentType = $ContentType }
    if ($Body -and $Context.Request.HttpMethod -ne 'HEAD' -and $Code -ne 204) {
        $bytes = $utf8.GetBytes($Body)
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        $response.OutputStream.Flush()
    }
    $response.OutputStream.Close()
}

function Send-Json {
    param (
        [System.Net.HttpListenerContext] $Context,
        [int] $Code,
        [object] $Object
    )
    Send-Response -Context $Context -Code $Code -ContentType 'application/json' `
        -Body ($Object | ConvertTo-Json -Compress -Depth 12)
}

function Send-ApiError {
    param (
        [System.Net.HttpListenerContext] $Context,
        [int] $Code,
        [string] $Type,
        [string] $Message
    )
    $safeMessage = $Message.Replace('"', "'")
    $safeType = [string]$Type
    $body = ('{{"message":"{0}","type":"{1}"}}' -f ($safeMessage, $safeType))
    Send-Response -Context $Context -Code $Code -ContentType 'application/json' -Body $body
}

# ---------------------------------------------------------------------------
# Per-DataSource UserContext store
# ---------------------------------------------------------------------------

function New-GuacMockUserContext {
    return [ordered]@{
        Seeded             = $false
        connections        = @{}
        connectionGroups   = @{}
        users              = @{}
        userGroups         = @{}
        sharingProfiles    = @{}
        activeConnections  = @{}
        permissions        = @{}
        memberships        = @{}
        history            = [ordered]@{ connections = @(); users = @() }
        tunnels            = @{}
    }
}

function New-GuacMockEmptyPermissionSet {
    return [ordered]@{
        connectionPermissions       = @{}
        connectionGroupPermissions  = @{}
        sharingProfilePermissions   = @{}
        activeConnectionPermissions = @{}
        userPermissions             = @{}
        userGroupPermissions        = @{}
        systemPermissions           = @()
    }
}

function New-GuacMockSeededContext {
    # NOTE: $Ctx must be left untyped (NOT [hashtable]) — an [ordered]
    # @{} converted to [hashtable] at the parameter boundary becomes a COPY,
    # so any mutation would be lost. PowerShell passes the OrderedDictionary
    # by reference when no type conversion is forced.
    param ($Ctx)
    if ($Ctx['Seeded']) { return }

    $Ctx['connections'] = @{}
    $Ctx['connections']['conn-1'] = [ordered]@{
        name = 'test-connection'; protocol = 'rdp'
        parameters = @{ hostname = 'host.example.com' }
        parentIdentifier = 'ROOT'; attributes = @{}
        maximumConnections = -1; lastActive = $null
    }
    $Ctx['connections']['conn-2'] = [ordered]@{
        name = 'ssh-server'; protocol = 'ssh'
        parameters = @{ hostname = 'ssh.example.com'; port = '22' }
        parentIdentifier = 'ROOT'; attributes = @{}
        maximumConnections = -1; lastActive = $null
    }

    $Ctx['connectionGroups'] = @{}
    $Ctx['connectionGroups']['group-1'] = [ordered]@{
        name = 'prod'; type = 'ORGANIZATIONAL'; parentIdentifier = 'ROOT'; attributes = @{}
    }
    $Ctx['connectionGroups']['group-2'] = [ordered]@{
        name = 'staging'; type = 'ORGANIZATIONAL'; parentIdentifier = 'group-1'; attributes = @{}
    }

    # NOTE: seeded users carry the "username" field (APIUser.externalUser has
    # it; the single-object endpoint returns the stored record as-is).
    $Ctx['users'] = @{}
    $Ctx['users']['guacadmin'] = [ordered]@{
        username = 'guacadmin'; password = 'secret'; disabled = $false
        attributes = @{ 'guac-full-name' = 'Guac Admin' }; lastActive = $null
    }
    $Ctx['users']['jdoe'] = [ordered]@{
        username = 'jdoe'; password = 'jdoe-pass'; disabled = $false; attributes = @{}; lastActive = $null
    }

    $Ctx['userGroups'] = @{}
    $Ctx['userGroups']['admins'] = [ordered]@{ identifier = 'admins'; disabled = $false; attributes = @{} }
    $Ctx['userGroups']['auditors'] = [ordered]@{ identifier = 'auditors'; disabled = $false; attributes = @{} }

    $Ctx['sharingProfiles'] = @{}
    $Ctx['sharingProfiles']['readonly'] = [ordered]@{
        name = 'read-only'; primaryConnectionIdentifier = 'conn-1'
        parameters = @{ 'guac-readonly' = 'true' }; attributes = @{}
    }

    # NOTE: permission sets are keyed "collection:id" (for example
    # "users:jdoe"), matching the subject key used by the permissions GET/PATCH
    # handler below.
    $admin = New-GuacMockEmptyPermissionSet
    $admin['systemPermissions'] = @('ADMINISTER')
    $Ctx['permissions']['users:guacadmin'] = $admin

    $jdoe = New-GuacMockEmptyPermissionSet
    $jdoe['connectionPermissions'] = @{}
    $jdoe['connectionPermissions']['conn-1'] = @('READ')
    $Ctx['permissions']['users:jdoe'] = $jdoe

    $Ctx['memberships']['admins'] = @{ memberUsers = @('guacadmin'); memberUserGroups = @() }
    $Ctx['memberships']['auditors'] = @{ memberUsers = @(); memberUserGroups = @() }

    $Ctx['history'] = [ordered]@{
        connections = @(
            [ordered]@{
                identifier = 'rec-1'; connectionIdentifier = 'conn-1'; connectionName = 'test-connection'
                username = 'guacadmin'; remoteHost = '10.0.0.5'
                startDate = '2026-01-01T10:00:00Z'; endDate = '2026-01-01T10:30:00Z'
                duration = 1800; readOnly = $false; sharingProfile = $null
            }
        )
        users = @(
            [ordered]@{
                username = 'guacadmin'; remoteHost = '10.0.0.5'
                startDate = '2026-01-01T10:00:00Z'; endDate = '2026-01-01T10:30:00Z'
                duration = 1800; connectionCount = 1; readWriteCount = 1; readOnlyCount = 0
            }
        )
    }

    # Seed a couple of active connections for testing
    $Ctx['activeConnections'] = @{}
    $Ctx['activeConnections']['active-1'] = [ordered]@{
        identifier = 'active-1'
        connectionIdentifier = 'conn-1'
        startDate = '2026-09-23T10:00:00Z'
        remoteHost = '10.0.0.5'
        username = 'guacadmin'
        connectable = $true
    }
    $Ctx['activeConnections']['active-2'] = [ordered]@{
        identifier = 'active-2'
        connectionIdentifier = 'conn-2'
        startDate = '2026-09-23T10:15:00Z'
        remoteHost = '192.168.1.10'
        username = 'jdoe'
        connectable = $true
    }

    $Ctx['Seeded'] = $true
}

$mockSchemaSets = [ordered]@{
    userAttributes = @(
        [ordered]@{ identifier = 'guac-full-name'; name = 'Full name'; label = 'Full name'; description = ''; order = 0; options = @{} }
        [ordered]@{ identifier = 'guac-email-address'; name = 'Email address'; label = 'Email address'; description = ''; order = 1; options = @{} }
    )
    userPreferenceAttributes = @(
        [ordered]@{ identifier = 'guac-timezone'; name = 'Timezone'; label = 'Timezone'; description = ''; order = 0; options = @{} }
        [ordered]@{ identifier = 'guac-language'; name = 'Language'; label = 'Language'; description = ''; order = 1; options = @{} }
    )
    userGroupAttributes = @(
        [ordered]@{ identifier = 'guac-description'; name = 'Description'; label = 'Description'; description = ''; order = 0; options = @{} }
    )
    connectionAttributes = @(
        [ordered]@{ identifier = 'guac-clipboard'; name = 'Clipboard'; label = 'Clipboard'; description = ''; order = 0; options = @{ 'READWRITE' = 'Read / Write' } }
        [ordered]@{ identifier = 'guac-readonly'; name = 'Read only'; label = 'Read only'; description = ''; order = 1; options = @{} }
        [ordered]@{ identifier = 'guac-resize-method'; name = 'Resize method'; label = 'Resize method'; description = ''; order = 2; options = @{} }
    )
    sharingProfileAttributes = @(
        [ordered]@{ identifier = 'guac-reconnect'; name = 'Reconnect'; label = 'Reconnect'; description = ''; order = 0; options = @{} }
    )
    connectionGroupAttributes = @(
        [ordered]@{ identifier = 'guac-failover-method'; name = 'Failover method'; label = 'Failover method'; description = ''; order = 0; options = @{} }
    )
}

$mockProtocols = [ordered]@{
    ssh = [ordered]@{
        name = 'ssh'
        connectionForms = @([ordered]@{ identifier = 'SSH'; name = 'SSH'; order = 0; options = @{}; fields = @('hostname', 'port', 'username', 'password', 'guac-readonly') })
        sharingProfileForms = @([ordered]@{ identifier = 'SHARING'; name = 'Sharing'; order = 0; options = @{}; fields = @('guac-reconnect') })
    }
    rdp = [ordered]@{
        name = 'rdp'
        connectionForms = @([ordered]@{ identifier = 'RDP'; name = 'RDP'; order = 0; options = @{}; fields = @('hostname', 'port', 'username', 'password', 'guac-readonly', 'guac-clipboard') })
        sharingProfileForms = @()
    }
    vnc = [ordered]@{
        name = 'vnc'
        connectionForms = @([ordered]@{ identifier = 'VNC'; name = 'VNC'; order = 0; options = @{}; fields = @('hostname', 'port', 'password', 'guac-readonly') })
        sharingProfileForms = @()
    }
    telnet = [ordered]@{
        name = 'telnet'
        connectionForms = @([ordered]@{ identifier = 'TELNET'; name = 'Telnet'; order = 0; options = @{}; fields = @('hostname', 'port', 'guac-readonly') })
        sharingProfileForms = @()
    }
    kubernetes = [ordered]@{
        name = 'kubernetes'
        connectionForms = @([ordered]@{ identifier = 'KUBERNETES'; name = 'Kubernetes'; order = 0; options = @{}; fields = @('hostname', 'port', 'guac-readonly') })
        sharingProfileForms = @()
    }
}

# Collection name -> store key (same in all data sources).
$collectionKeys = [ordered]@{
    connections       = 'connections'
    connectionGroups  = 'connectionGroups'
    users             = 'users'
    userGroups        = 'userGroups'
    sharingProfiles   = 'sharingProfiles'
}

function Get-MockUserContext {
    param ([string] $DataSource)
    if (-not $userContexts.ContainsKey($DataSource)) {
        $userContexts[$DataSource] = New-GuacMockUserContext
    }
    $ctx = $userContexts[$DataSource]
    if ($DataSource -eq 'mysql') {
        New-GuacMockSeededContext -Ctx $ctx
    }
    return $ctx
}

function Get-MockUserContextCollection {
    param ($Ctx, [string] $Collection)
    if (-not $collectionKeys.Contains($Collection)) { return $null }
    return $Ctx[[string]$collectionKeys[$Collection]]
}

# Identifier of a newly created object, per collection type.
function Get-MockCreatedIdentifier {
    param ([string] $Collection, [object] $Body)
    if ($Collection -eq 'users') { return [string]$Body.username }
    if ($Collection -eq 'userGroups') { return [string]$Body.identifier }
    return [System.Guid]::NewGuid().ToString()
}

# Full-replace the mutable fields of an object, per collection type
# (mirrors each *ObjectTranslator.applyExternalChanges; the user password is
# conditional).
function Update-MockEntity {
    param ([string] $Collection, $Existing, [object] $Body)
    switch ($Collection) {
        'connections' {
            $Existing['name'] = [string]$Body.name
            $Existing['protocol'] = [string]$Body.protocol
            $Existing['parameters'] = (Get-MockMap $Body.parameters)
            $Existing['parentIdentifier'] = [string]$Body.parentIdentifier
            $Existing['attributes'] = (Get-MockMap $Body.attributes)
        }
        'connectionGroups' {
            $Existing['name'] = [string]$Body.name
            $Existing['type'] = [string]$Body.type
            $Existing['parentIdentifier'] = [string]$Body.parentIdentifier
            $Existing['attributes'] = (Get-MockMap $Body.attributes)
        }
        'users' {
            # Password only when present (UserObjectTranslator).
            if ($null -ne $Body.password) { $Existing['password'] = [string]$Body.password }
            $Existing['disabled'] = [bool]$Body.disabled
            $Existing['attributes'] = (Get-MockMap $Body.attributes)
        }
        'userGroups' {
            $Existing['disabled'] = [bool]$Body.disabled
            $Existing['attributes'] = (Get-MockMap $Body.attributes)
        }
        'sharingProfiles' {
            $Existing['name'] = [string]$Body.name
            $Existing['primaryConnectionIdentifier'] = [string]$Body.primaryConnectionIdentifier
            $Existing['parameters'] = (Get-MockMap $Body.parameters)
            $Existing['attributes'] = (Get-MockMap $Body.attributes)
        }
    }
}

function Get-MockMap {
    param ([object] $Value)
    if ($null -eq $Value) { return @{} }
    if ($Value -is [System.Collections.IDictionary]) {
        $map = @{}
        foreach ($key in $Value.Keys) { $map[[string]$key] = $Value[$key] }
        return $map
    }
    $map = @{}
    foreach ($prop in $Value.PSObject.Properties) { $map[$prop.Name] = $prop.Value }
    return $map
}

function Get-MockBool {
    param ([object] $Value)
    if ($null -eq $Value) { return $false }
    return [bool]$Value
}

# Build the connection group tree (ConnectionGroupResource.getConnectionGroupTree).
function Get-MockGroupTree {
    param ($Ctx, [string] $Id)

    # ROOT is an implicit root group that always exists, even with no entities.
    if ($Id -eq 'ROOT') {
        $group = [ordered]@{ name = 'ROOT'; type = 'ORGANIZATIONAL'; parentIdentifier = ''; attributes = @{} }
    }
    else {
        $group = $Ctx['connectionGroups'][$Id]
        if ($null -eq $group) { return $null }
    }

    $children = [ordered]@{}
    foreach ($otherId in @($Ctx['connectionGroups'].Keys)) {
        $other = $Ctx['connectionGroups'][$otherId]
        if ([string]$other['parentIdentifier'] -eq $Id) {
            $subTree = Get-MockGroupTree -Ctx $Ctx -Id $otherId
            if ($null -ne $subTree) { $children[[string]$otherId] = $subTree }
        }
    }
    $childConns = [ordered]@{}
    foreach ($connId in @($Ctx['connections'].Keys)) {
        $conn = $Ctx['connections'][$connId]
        if ([string]$conn['parentIdentifier'] -eq $Id) {
            $childConns[[string]$connId] = $conn
        }
    }
    return [ordered]@{
        identifier = $Id
        name = $group['name']
        type = $group['type']
        parentIdentifier = $group['parentIdentifier']
        activeConnections = @()
        childConnectionGroups = $children
        childConnections = $childConns
        attributes = $group['attributes']
    }
}

# Permission-set PATCH handling (PermissionSetResource.patchPermissions).
function Invoke-MockPermissionPatch {
    param ($Ctx, [string] $SubjectKey, [object] $Operations)
    if (-not $Ctx['permissions'].ContainsKey($SubjectKey)) {
        $Ctx['permissions'][$SubjectKey] = (New-GuacMockEmptyPermissionSet)
    }
    $set = $Ctx['permissions'][$SubjectKey]

    $prefixToCategory = [ordered]@{
        '/connectionPermissions/'       = 'connectionPermissions'
        '/connectionGroupPermissions/'  = 'connectionGroupPermissions'
        '/sharingProfilePermissions/'   = 'sharingProfilePermissions'
        '/activeConnectionPermissions/' = 'activeConnectionPermissions'
        '/userPermissions/'             = 'userPermissions'
        '/userGroupPermissions/'        = 'userGroupPermissions'
    }
    $categoryTarget = [ordered]@{
        connectionPermissions       = 'connections'
        connectionGroupPermissions  = 'connectionGroups'
        sharingProfilePermissions   = 'sharingProfiles'
        activeConnectionPermissions = 'activeConnections'
        userPermissions             = 'users'
        userGroupPermissions        = 'userGroups'
    }

    foreach ($operation in @($Operations)) {
        $op = [string]$operation.op
        $path = [string]$operation.path
        $type = [string]$operation.value

        if ($path -eq '/systemPermissions') {
            $types = @($set['systemPermissions'])
            if ($op -eq 'add') {
                if ($types -notcontains $type) { $types += $type }
            }
            elseif ($op -eq 'remove') {
                $types = @($types | Where-Object { $_ -ne $type })
            }
            $set['systemPermissions'] = $types
            continue
        }

        $matched = $false
        foreach ($prefix in $prefixToCategory.Keys) {
            if ($path.StartsWith($prefix)) {
                $matched = $true
                $category = [string]$prefixToCategory[$prefix]
                $targetId = $path.Substring($prefix.Length)
                if ($category -eq 'activeConnectionPermissions') {
                    # Active connections are runtime state; reject like the
                    # server does when the record is not found.
                    Send-ApiError -Context $script:currentContext -Code 404 -Type 'NOT_FOUND' -Message ('No such active connection: ' + $targetId)
                    return $false
                }
                $store = $Ctx[[string]$categoryTarget[$category]]
                if ($null -eq $store -or -not $store.ContainsKey($targetId)) {
                    Send-ApiError -Context $script:currentContext -Code 404 -Type 'NOT_FOUND' -Message ('No such object: ' + $targetId)
                    return $false
                }
                $map = $set[$category]
                if (-not $map.ContainsKey($targetId)) { $map[$targetId] = @() }
                $types = @($map[$targetId])
                if ($op -eq 'add') {
                    if ($types -notcontains $type) { $types += $type }
                }
                elseif ($op -eq 'remove') {
                    $types = @($types | Where-Object { $_ -ne $type })
                    if ($types.Count -eq 0) { $map.Remove($targetId); continue 2 }
                }
                $map[$targetId] = $types
                break
            }
        }
        if (-not $matched) {
            Send-ApiError -Context $script:currentContext -Code 400 -Type 'UNSUPPORTED' -Message ('Unsupported patch path: ' + $path)
            return $false
        }
    }
    return $true
}

# Related-object-set PATCH handling (RelatedObjectSetResource.patchObjects).
function Invoke-MockRelatedSetPatch {
    param (
        $Ctx,
        [string] $Group,
        [string] $SubPath,
        [object] $Operations
    )
    if (-not $Ctx['userGroups'].ContainsKey($Group)) {
        Send-ApiError -Context $script:currentContext -Code 404 -Type 'NOT_FOUND' -Message ('No such user group: ' + $Group)
        return $false
    }
    if (-not $Ctx['memberships'].ContainsKey($Group)) {
        $Ctx['memberships'][$Group] = @{ memberUsers = @(); memberUserGroups = @() }
    }
    $members = $Ctx['memberships'][$Group]
    $key = if ($SubPath -eq 'memberUsers') { 'memberUsers' } else { 'memberUserGroups' }
    $targetStore = if ($SubPath -eq 'memberUsers') { $Ctx['users'] } else { $Ctx['userGroups'] }

    foreach ($operation in @($Operations)) {
        $op = [string]$operation.op
        if ([string]$operation.path -ne '/') {
            Send-ApiError -Context $script:currentContext -Code 400 -Type 'UNSUPPORTED' -Message ('Unsupported patch path: ' + [string]$operation.path)
            return $false
        }
        $identifier = [string]$operation.value
        if (-not $targetStore.ContainsKey($identifier)) {
            Send-ApiError -Context $script:currentContext -Code 404 -Type 'NOT_FOUND' -Message ('No such object: ' + $identifier)
            return $false
        }
        $list = @($members[$key])
        if ($op -eq 'add') {
            if ($list -notcontains $identifier) { $list += $identifier }
        }
        elseif ($op -eq 'remove') {
            $list = @($list | Where-Object { $_ -ne $identifier })
        }
        $members[$key] = $list
    }
    return $true
}

# Parse a JSON array body that may arrive as a single object (5.1 unwraps
# single-element arrays in ConvertFrom-Json).
function ConvertTo-GuacMockOperationArray {
    param ([object] $Decoded)
    if ($null -eq $Decoded) { return @() }
    if ($Decoded -is [System.Management.Automation.PSCustomObject]) {
        if ($Decoded.PSObject.Properties['op']) { return @($Decoded) }
        return @()
    }
    return @($Decoded)
}

$userContexts = @{}

while ($listener.IsListening) {
    $context = $null
    try { $context = $listener.GetContext() }
    catch [System.Exception] { break }
    $script:currentContext = $context
    $request = $context.Request
    $method = $request.HttpMethod.ToUpperInvariant()
    $relPath = $request.Url.AbsolutePath -replace '^/guacamole', ''
    $tokenHeader = $request.Headers['Guacamole-Token']
    $queryToken = $null
    try {
        $queryString = $request.Url.Query
        if ($queryString -and $queryString.StartsWith('?')) { $queryString = $queryString.Substring(1) }
        foreach ($pair in @($queryString -split '&')) {
            $kv = $pair -split '=', 2
            if ($kv.Count -eq 2 -and $kv[0] -eq 'token') { $queryToken = [uri]::UnescapeDataString($kv[1]) }
        }
    }
    catch [System.Exception] { $queryToken = $null }
    $token = $tokenHeader
    if ([string]::IsNullOrEmpty($token) -and $queryToken) { $token = $queryToken }

    $bodyReader = [System.IO.StreamReader]::new($request.InputStream)
    $body = $bodyReader.ReadToEnd()
    $bodyReader.Dispose()

    # Record the request (JSON line).
    $record = [ordered]@{
        method = $method
        path = $relPath
        query = [string]$request.Url.Query
        token = $token
        tokenViaHeader = [bool]$tokenHeader
        body = $body
        contentType = [string]$request.ContentType
    }
    Add-Content -LiteralPath $LogFile -Value ($record | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8

    # ---- Control endpoints ----
    if ($relPath -eq '/_control/totp-enable') {
        $requireTotp = $true
        Send-Response -Context $context -Code 200 -ContentType 'application/json' -Body '{}'
        continue
    }
    if ($relPath -eq '/_control/totp-disable') {
        $requireTotp = $false
        Send-Response -Context $context -Code 200 -ContentType 'application/json' -Body '{}'
        continue
    }

    # ---- Auth endpoints ----
    if ($relPath -eq '/api/tokens' -and $method -eq 'POST') {
        $fields = @{}
        foreach ($pair in @($body -split '&')) {
            if ([string]::IsNullOrEmpty($pair)) { continue }
            $kv = $pair -split '=', 2
            $k = [uri]::UnescapeDataString($kv[0])
            $v = [uri]::UnescapeDataString($kv[1])
            $fields[$k] = $v
        }
        $username = [string]$fields['username']
        $password = [string]$fields['password']
        $totp = [string]$fields['guac-totp']
        if ($username -ne 'guacadmin' -or $password -ne 'secret') {
            Send-ApiError -Context $context -Code 401 -Type 'INVALID_CREDENTIALS' -Message 'Invalid credentials.'
            continue
        }
        if ($requireTotp) {
            if ([string]::IsNullOrEmpty($totp)) {
                Send-ApiError -Context $context -Code 401 -Type 'INSUFFICIENT_CREDENTIALS' -Message 'A TOTP authentication code is required before login can continue.'
                continue
            }
            if ($totp -ne '123456') {
                Send-ApiError -Context $context -Code 401 -Type 'INVALID_CREDENTIALS' -Message 'Provided TOTP code is not valid.'
                continue
            }
        }
        $newToken = ('mocktoken-' + [System.Guid]::NewGuid().ToString('N'))
        $validTokens[$newToken] = $true
        $result = [ordered]@{
            authToken = $newToken
            username = $username
            dataSource = 'mysql'
            availableDataSources = @('mysql', 'ldap')
        }
        Send-Json -Context $context -Code 200 -Object $result
        continue
    }

    if ($relPath -like '/api/tokens/*' -and $method -eq 'DELETE') {
        $tokenPath = $relPath.Substring('/api/tokens/'.Length)
        if ($validTokens.ContainsKey($tokenPath)) {
            $validTokens.Remove($tokenPath)
            Send-Response -Context $context -Code 204 -ContentType $null -Body $null
        }
        else {
            Send-ApiError -Context $context -Code 401 -Type 'NOT_FOUND' -Message 'No such token.'
        }
        continue
    }

    # Everything under /api/session requires a valid token.
    if ($relPath -like '/api/session*') {
        if ([string]::IsNullOrEmpty($token) -or -not $validTokens.ContainsKey($token)) {
            Send-ApiError -Context $context -Code 401 -Type 'NOT_FOUND' -Message 'No such token.'
            continue
        }
        if ($relPath -eq '/api/session' -and $method -eq 'HEAD') {
            Send-Response -Context $context -Code 200 -ContentType $null -Body $null
            continue
        }

        # ---- Per-DataSource UserContext surface ----
        if ($relPath -like '/api/session/data/*') {
            $segments = @($relPath.Substring('/api/session/data/'.Length) -split '/')
            $dataSource = [uri]::UnescapeDataString($segments[0])
            $ctx = Get-MockUserContext -DataSource $dataSource

            if ($segments.Count -ge 2 -and $segments[1] -eq 'self' -and $method -eq 'GET') {
                $self = [ordered]@{
                    identifier = 'guacadmin'
                    username = 'guacadmin'
                    disabled = $false
                    attributes = $ctx['users']['guacadmin']['attributes']
                }
                Send-Json -Context $context -Code 200 -Object $self
                continue
            }

            if ($segments.Count -ge 2 -and $collectionKeys.Contains($segments[1])) {
                $collection = [string]$segments[1]
                $store = Get-MockUserContextCollection -Ctx $ctx -Collection $collection

                if ($segments.Count -eq 2) {
                    if ($method -eq 'GET') {
                        Send-Json -Context $context -Code 200 -Object $store
                        continue
                    }
                    if ($method -eq 'POST') {
                        $decoded = $body | ConvertFrom-Json -Depth 12
                        $identifier = Get-MockCreatedIdentifier -Collection $collection -Body $decoded
                        if ([string]::IsNullOrWhiteSpace([string]$identifier)) {
                            Send-ApiError -Context $context -Code 400 -Type 'BAD_REQUEST' -Message 'No identifier supplied.'
                            continue
                        }
                        $object = [ordered]@{ attributes = (Get-MockMap $decoded.attributes) }
                        switch ($collection) {
                            'connections' {
                                $object['name'] = [string]$decoded.name
                                $object['protocol'] = [string]$decoded.protocol
                                $object['parameters'] = (Get-MockMap $decoded.parameters)
                                $object['parentIdentifier'] = [string]$decoded.parentIdentifier
                                $object['maximumConnections'] = -1
                                $object['lastActive'] = $null
                            }
                            'connectionGroups' {
                                $object['name'] = [string]$decoded.name
                                $object['type'] = [string]$decoded.type
                                $object['parentIdentifier'] = [string]$decoded.parentIdentifier
                            }
                            'users' {
                                $object['username'] = $identifier
                                $object['password'] = [string]$decoded.password
                                $object['disabled'] = [bool]$decoded.disabled
                                $object['lastActive'] = $null
                            }
                            'userGroups' {
                                $object['identifier'] = $identifier
                                $object['disabled'] = [bool]$decoded.disabled
                            }
                            'sharingProfiles' {
                                $object['name'] = [string]$decoded.name
                                $object['primaryConnectionIdentifier'] = [string]$decoded.primaryConnectionIdentifier
                                $object['parameters'] = (Get-MockMap $decoded.parameters)
                            }
                        }
                        if ($collection -ne 'users') { $object['identifier'] = $identifier }
                        $store[$identifier] = $object
                        Send-Json -Context $context -Code 200 -Object $object
                        continue
                    }
                    if ($method -eq 'PATCH') {
                        $operations = ConvertTo-GuacMockOperationArray ($body | ConvertFrom-Json -Depth 12)
                        $outcomes = @()
                        foreach ($operation in $operations) {
                            $op = [string]$operation.op
                            $path = [string]$operation.path
                            $identifier = [string]::Empty
                            if ($op -eq 'add') {
                                $identifier = Get-MockCreatedIdentifier -Collection $collection -Body $operation.value
                                if ([string]::IsNullOrWhiteSpace($identifier)) {
                                    Send-ApiError -Context $context -Code 400 -Type 'API_PATCH_FAILURE' -Message 'No identifier supplied.'
                                    continue
                                }
                                $object = [ordered]@{ attributes = (Get-MockMap $operation.value.attributes) }
                                switch ($collection) {
                                    'connections' {
                                        $object['name'] = [string]$operation.value.name
                                        $object['protocol'] = [string]$operation.value.protocol
                                        $object['parameters'] = (Get-MockMap $operation.value.parameters)
                                        $object['parentIdentifier'] = [string]$operation.value.parentIdentifier
                                        $object['maximumConnections'] = -1
                                        $object['lastActive'] = $null
                                    }
                                    'connectionGroups' {
                                        $object['name'] = [string]$operation.value.name
                                        $object['type'] = [string]$operation.value.type
                                        $object['parentIdentifier'] = [string]$operation.value.parentIdentifier
                                    }
                                    'users' {
                                        $object['username'] = $identifier
                                        $object['password'] = [string]$operation.value.password
                                        $object['disabled'] = [bool]$operation.value.disabled
                                        $object['lastActive'] = $null
                                    }
                                    'userGroups' {
                                        $object['identifier'] = $identifier
                                        $object['disabled'] = [bool]$operation.value.disabled
                                    }
                                    'sharingProfiles' {
                                        $object['name'] = [string]$operation.value.name
                                        $object['primaryConnectionIdentifier'] = [string]$operation.value.primaryConnectionIdentifier
                                        $object['parameters'] = (Get-MockMap $operation.value.parameters)
                                    }
                                }
                                if ($collection -ne 'users') { $object['identifier'] = $identifier }
                                $store[$identifier] = $object
                            }
                            elseif ($op -eq 'replace') {
                                $identifier = $path.TrimStart('/')
                                if (-not $store.ContainsKey($identifier)) {
                                    Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message ('No such object: ' + $identifier)
                                    continue
                                }
                                Update-MockEntity -Collection $collection -Existing $store[$identifier] -Body $operation.value
                            }
                            elseif ($op -eq 'remove') {
                                $identifier = $path.TrimStart('/')
                                if (-not $store.ContainsKey($identifier)) {
                                    Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message ('No such object: ' + $identifier)
                                    continue
                                }
                                $store.Remove($identifier)
                                if ($collection -eq 'userGroups') { $ctx['memberships'].Remove($identifier) }
                            }
                            $outcomes += [ordered]@{ op = $op; identifier = $identifier; path = $path }
                        }
                        Send-Json -Context $context -Code 200 -Object ([ordered]@{ patches = $outcomes })
                        continue
                    }
                }
                else {
                    $id = [uri]::UnescapeDataString($segments[2])
                    if (-not $store.ContainsKey($id) -and -not ($collection -eq 'connectionGroups' -and $id -eq 'ROOT')) {
                        Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message ('No such object: ' + $id)
                        continue
                    }
                    if ($segments.Count -eq 3) {
                        if ($method -eq 'GET') {
                            Send-Json -Context $context -Code 200 -Object $store[$id]
                            continue
                        }
                        if ($method -eq 'PUT') {
                            $decoded = $body | ConvertFrom-Json -Depth 12
                            # A user may not change their own password here
                            # (UserResource.updateObject).
                            if ($collection -eq 'users' -and $id -eq 'guacadmin' -and $null -ne $decoded.password) {
                                Send-ApiError -Context $context -Code 403 -Type 'PERMISSION_DENIED' -Message 'Permission denied. The password update endpoint must be used to change the current user''s password.'
                                continue
                            }
                            Update-MockEntity -Collection $collection -Existing $store[$id] -Body $decoded
                            Send-Response -Context $context -Code 204 -ContentType $null -Body $null
                            continue
                        }
                        if ($method -eq 'DELETE') {
                            $store.Remove($id)
                            if ($collection -eq 'userGroups') { $ctx['memberships'].Remove($id) }
                            Send-Response -Context $context -Code 204 -ContentType $null -Body $null
                            continue
                        }
                    }

                    # ---- Object subresources ----
                    if ($segments.Count -ge 4) {
                        $sub = $segments[3]

                        # Connection group tree.
                        if ($collection -eq 'connectionGroups' -and $sub -eq 'tree' -and $method -eq 'GET') {
                            $tree = Get-MockGroupTree -Ctx $ctx -Id $id
                            if ($null -eq $tree) {
                                Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message ('No such connection group: ' + $id)
                                continue
                            }
                            Send-Json -Context $context -Code 200 -Object $tree
                            continue
                        }

                        # User: password change.
                        if ($collection -eq 'users' -and $sub -eq 'password' -and $method -eq 'PUT') {
                            $decoded = $body | ConvertFrom-Json -Depth 6
                            $oldPassword = [string]$decoded.oldPassword
                            $newPassword = [string]$decoded.newPassword
                            if ([string]$store[$id]['password'] -ne $oldPassword) {
                                Send-ApiError -Context $context -Code 403 -Type 'PERMISSION_DENIED' -Message 'Permission denied.'
                                continue
                            }
                            $store[$id]['password'] = $newPassword
                            Send-Response -Context $context -Code 204 -ContentType $null -Body $null
                            continue
                        }

                        # User / user group: permission set.
                        if (($collection -eq 'users' -or $collection -eq 'userGroups') -and $sub -eq 'permissions') {
                            $subjectKey = ($collection + ':' + $id)
                            if ($method -eq 'GET') {
                                if (-not $ctx['permissions'].ContainsKey($subjectKey)) {
                                    $ctx['permissions'][$subjectKey] = (New-GuacMockEmptyPermissionSet)
                                }
                                Send-Json -Context $context -Code 200 -Object $ctx['permissions'][$subjectKey]
                                continue
                            }
                            if ($method -eq 'PATCH') {
                                $operations = ConvertTo-GuacMockOperationArray ($body | ConvertFrom-Json -Depth 8)
                                $ok = Invoke-MockPermissionPatch -Ctx $ctx -SubjectKey $subjectKey -Operations $operations
                                if (-not $ok) { continue }
                                Send-Response -Context $context -Code 204 -ContentType $null -Body $null
                                continue
                            }
                        }

                        # User: effective permissions (same shape as the
                        # directly-granted set in this mock).
                        if ($collection -eq 'users' -and $sub -eq 'effectivePermissions' -and $method -eq 'GET') {
                            # Same "collection:id" subject key as the permissions
                            # handler, so the seeded set is what is returned.
                            $subjectKey = ($collection + ':' + $id)
                            if (-not $ctx['permissions'].ContainsKey($subjectKey)) {
                                $ctx['permissions'][$subjectKey] = (New-GuacMockEmptyPermissionSet)
                            }
                            Send-Json -Context $context -Code 200 -Object $ctx['permissions'][$subjectKey]
                            continue
                        }

                        # User: the user groups the user belongs to.
                        if ($collection -eq 'users' -and $sub -eq 'userGroups') {
                            $ids = @()
                            foreach ($groupId in @($ctx['memberships'].Keys)) {
                                $members = $ctx['memberships'][$groupId]
                                if (@($members['memberUsers']) -contains $id) { $ids += [string]$groupId }
                            }
                            if ($method -eq 'GET') {
                                Send-Json -Context $context -Code 200 -Object $ids
                                continue
                            }
                            if ($method -eq 'PATCH') {
                                $operations = ConvertTo-GuacMockOperationArray ($body | ConvertFrom-Json -Depth 8)
                                foreach ($operation in $operations) {
                                    $groupId = [string]$operation.value
                                    $op = [string]$operation.op
                                    if (-not $ctx['userGroups'].ContainsKey($groupId)) {
                                        Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message ('No such user group: ' + $groupId)
                                        continue
                                    }
                                    if (-not $ctx['memberships'].ContainsKey($groupId)) {
                                        $ctx['memberships'][$groupId] = @{ memberUsers = @(); memberUserGroups = @() }
                                    }
                                    $list = @($ctx['memberships'][$groupId]['memberUsers'])
                                    if ($op -eq 'add') {
                                        if ($list -notcontains $id) { $list += $id }
                                    }
                                    elseif ($op -eq 'remove') {
                                        $list = @($list | Where-Object { $_ -ne $id })
                                    }
                                    $ctx['memberships'][$groupId]['memberUsers'] = $list
                                }
                                Send-Response -Context $context -Code 204 -ContentType $null -Body $null
                                continue
                            }
                        }

                        # User: history records for this user.
                        if ($collection -eq 'users' -and $sub -eq 'history' -and $method -eq 'GET') {
                            $records = @($ctx['history']['users'] | Where-Object { [string]$_.username -eq $id })
                            Send-Json -Context $context -Code 200 -Object $records
                            continue
                        }

                        # User group: member sets.
                        if ($collection -eq 'userGroups' -and ($sub -eq 'memberUsers' -or $sub -eq 'memberUserGroups')) {
                            if ($method -eq 'GET') {
                                if (-not $ctx['memberships'].ContainsKey($id)) {
                                    $ctx['memberships'][$id] = @{ memberUsers = @(); memberUserGroups = @() }
                                }
                                Send-Json -Context $context -Code 200 -Object $ctx['memberships'][$id][$sub]
                                continue
                            }
                            if ($method -eq 'PATCH') {
                                $operations = ConvertTo-GuacMockOperationArray ($body | ConvertFrom-Json -Depth 8)
                                $ok = Invoke-MockRelatedSetPatch -Ctx $ctx -Group $id -SubPath $sub -Operations $operations
                                if (-not $ok) { continue }
                                Send-Response -Context $context -Code 204 -ContentType $null -Body $null
                                continue
                            }
                        }

                        # User group: the user groups this group belongs to.
                        if ($collection -eq 'userGroups' -and $sub -eq 'userGroups') {
                            $ids = @()
                            foreach ($groupId in @($ctx['memberships'].Keys)) {
                                $members = $ctx['memberships'][$groupId]
                                if (@($members['memberUserGroups']) -contains $id) { $ids += [string]$groupId }
                            }
                            if ($method -eq 'GET') {
                                Send-Json -Context $context -Code 200 -Object $ids
                                continue
                            }
                            if ($method -eq 'PATCH') {
                                $operations = ConvertTo-GuacMockOperationArray ($body | ConvertFrom-Json -Depth 8)
                                foreach ($operation in $operations) {
                                    $groupId = [string]$operation.value
                                    $op = [string]$operation.op
                                    if (-not $ctx['userGroups'].ContainsKey($groupId)) {
                                        Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message ('No such user group: ' + $groupId)
                                        continue
                                    }
                                    if (-not $ctx['memberships'].ContainsKey($groupId)) {
                                        $ctx['memberships'][$groupId] = @{ memberUsers = @(); memberUserGroups = @() }
                                    }
                                    $list = @($ctx['memberships'][$groupId]['memberUserGroups'])
                                    if ($op -eq 'add') {
                                        if ($list -notcontains $id) { $list += $id }
                                    }
                                    elseif ($op -eq 'remove') {
                                        $list = @($list | Where-Object { $_ -ne $id })
                                    }
                                    $ctx['memberships'][$groupId]['memberUserGroups'] = $list
                                }
                                Send-Response -Context $context -Code 204 -ContentType $null -Body $null
                                continue
                            }
                        }
                    }
                }
            }

            # Active connections surface (Phase 3).
            if ($segments.Count -ge 2 -and $segments[1] -eq 'activeConnections') {
                $activeConns = $ctx['activeConnections']

                if ($segments.Count -eq 2) {
                    if ($method -eq 'GET') {
                        Send-Json -Context $context -Code 200 -Object $activeConns
                        continue
                    }
                    if ($method -eq 'PATCH') {
                        # JSON Patch remove operation to stop an active connection
                        $operations = ConvertTo-GuacMockOperationArray ($body | ConvertFrom-Json -Depth 8)
                        $outcomes = @()
                        foreach ($operation in $operations) {
                            $op = [string]$operation.op
                            $path = [string]$operation.path
                            if ($op -eq 'remove') {
                                $activeId = $path.TrimStart('/')
                                if (-not $activeConns.ContainsKey($activeId)) {
                                    Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message ('No such active connection: ' + $activeId)
                                    continue
                                }
                                $activeConns.Remove($activeId)
                            }
                            $outcomes += [ordered]@{ op = $op; identifier = $activeId; path = $path }
                        }
                        Send-Json -Context $context -Code 200 -Object ([ordered]@{ patches = $outcomes })
                        continue
                    }
                }
                elseif ($segments.Count -ge 3) {
                    $activeId = [uri]::UnescapeDataString($segments[2])

                    if ($segments.Count -eq 3) {
                        if (-not $activeConns.ContainsKey($activeId)) {
                            Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message ('No such active connection: ' + $activeId)
                            continue
                        }
                        if ($method -eq 'GET') {
                            Send-Json -Context $context -Code 200 -Object $activeConns[$activeId]
                            continue
                        }
                        if ($method -eq 'DELETE') {
                            $activeConns.Remove($activeId)
                            Send-Response -Context $context -Code 204 -ContentType $null -Body $null
                            continue
                        }
                    }

                    # Active connection subresources
                    if ($segments.Count -ge 4) {
                        if (-not $activeConns.ContainsKey($activeId)) {
                            Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message ('No such active connection: ' + $activeId)
                            continue
                        }
                        $sub = $segments[3]
                        $activeConn = $activeConns[$activeId]

                        # Get the underlying connection object
                        if ($sub -eq 'connection' -and $method -eq 'GET') {
                            $connId = [string]$activeConn['connectionIdentifier']
                            if ($ctx['connections'].ContainsKey($connId)) {
                                Send-Json -Context $context -Code 200 -Object $ctx['connections'][$connId]
                            }
                            else {
                                Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message ('No such connection: ' + $connId)
                            }
                            continue
                        }

                        # Sharing credentials
                        if ($sub -eq 'sharingCredentials' -and $segments.Count -ge 5 -and $method -eq 'GET') {
                            $sharingProfile = $segments[4]
                            $creds = [ordered]@{
                                username = ('share-{0}-{1}' -f ($activeId, $sharingProfile))
                                password = ('share-pass-' + [System.Guid]::NewGuid().ToString('N'))
                            }
                            Send-Json -Context $context -Code 200 -Object $creds
                            continue
                        }
                    }
                }
            }

            # History surface.
            if ($segments.Count -ge 2 -and $segments[1] -eq 'history' -and $method -eq 'GET') {
                if ($segments.Count -eq 3 -and $segments[2] -eq 'connections') {
                    Send-Json -Context $context -Code 200 -Object $ctx['history']['connections']
                    continue
                }
                if ($segments.Count -eq 3 -and $segments[2] -eq 'users') {
                    Send-Json -Context $context -Code 200 -Object $ctx['history']['users']
                    continue
                }
            }

            # Schema surface.
            if ($segments.Count -ge 2 -and $segments[1] -eq 'schema' -and $method -eq 'GET') {
                if ($segments.Count -eq 3 -and $segments[2] -eq 'protocols') {
                    Send-Json -Context $context -Code 200 -Object $mockProtocols
                    continue
                }
                if ($segments.Count -eq 3 -and $mockSchemaSets.Contains($segments[2])) {
                    Send-Json -Context $context -Code 200 -Object $mockSchemaSets[[string]$segments[2]]
                    continue
                }
            }
        }
    }

    # ---- Session-level endpoints (Phase 3) ----
    # Extension resource (ExtensionRESTService @Path("/ext/{identifier}"))
    if ($relPath -like '/api/ext/*') {
        $extDs = [uri]::UnescapeDataString($relPath.Substring('/api/ext/'.Length))
        $extInfo = [ordered]@{
            dataSource = $extDs
            name = ('guacamole-auth-' + $extDs)
            version = '1.6.0'
        }
        Send-Json -Context $context -Code 200 -Object $extInfo
        continue
    }

    if ($relPath -eq '/api/languages' -and $method -eq 'GET') {
        $languages = [ordered]@{
            en = 'English'
            fr = 'Français'
            de = 'Deutsch'
            es = 'Español'
            ru = 'Русский'
            ja = '日本語'
        }
        Send-Json -Context $context -Code 200 -Object $languages
        continue
    }

    if ($relPath -eq '/api/patches' -and $method -eq 'GET') {
        $patches = @(
            '<html><head><meta name="guac-patch" content="test-patch-1"></head><body></body></html>'
        )
        Send-Json -Context $context -Code 200 -Object $patches
        continue
    }

    if ($relPath -like '/api/session*') {
        if ([string]::IsNullOrEmpty($token) -or -not $validTokens.ContainsKey($token)) {
            Send-ApiError -Context $context -Code 401 -Type 'NOT_FOUND' -Message 'No such token.'
            continue
        }

        # Tunnels collection
        if ($relPath -eq '/api/session/tunnels' -and $method -eq 'GET') {
            $tunnelIds = @('tunnel-1', 'tunnel-2')
            Send-Json -Context $context -Code 200 -Object $tunnelIds
            continue
        }

        if ($relPath -like '/api/session/tunnels/*' -and $method -eq 'GET') {
            $tunnelId = $relPath.Substring('/api/session/tunnels/'.Length)
            $tunnelInfo = [ordered]@{
                identifier = $tunnelId
                protocol = 'ssh'
                activeConnection = 'active-1'
                streams = @()
            }
            Send-Json -Context $context -Code 200 -Object $tunnelInfo
            continue
        }

    }

    if ($relPath -eq '/api/notfound' -and $method -eq 'GET') {
        Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message 'No such resource.'
        continue
    }
    if ($relPath -eq '/api/plaintext-error' -and $method -eq 'GET') {
        Send-Response -Context $context -Code 500 -ContentType 'text/plain' -Body 'Internal server error (no JSON body).'
        continue
    }

    # Default: 404 APIError.
    Send-ApiError -Context $context -Code 404 -Type 'NOT_FOUND' -Message ('No such resource: ' + $relPath)
}

$listener.Stop()
Write-Output 'STOPPED'
