function Get-GuacSchema {
    <#
    .SYNOPSIS
        Gets Guacamole schema attribute sets from the UserContext.

    .DESCRIPTION
        Retrieves the schema attribute definitions of a per-data-source
        UserContext (SchemaResource). Each returned object is a Form:
        { identifier, name, description, label, order, options }.

        -Set selects the attribute set:
        - ConnectionAttributes          (GET .../schema/connectionAttributes)
        - ConnectionGroupAttributes     (GET .../schema/connectionGroupAttributes)
        - SharingProfileAttributes      (GET .../schema/sharingProfileAttributes)
        - UserAttributes                (GET .../schema/userAttributes)
        - UserPreferenceAttributes      (GET .../schema/userPreferenceAttributes)
        - UserGroupAttributes           (GET .../schema/userGroupAttributes)
        - Protocols                     (GET .../schema/protocols; returns the
          protocol name to ProtocolInfo map, not Forms)

        Without -Set, all six attribute sets are retrieved and each result is
        tagged with the "schemaSet" property.

        The connection attributes and connection parameters are the canonical
        source for the arguments a connection form exposes at runtime; use
        them together with Get-GuacConnection -Parameters to validate a
        connection's argument values.

        Reference (Apache Guacamole 1.6.0):
        - guacamole/src/main/java/org/apache/guacamole/rest/session/UserContextResource.java
          (@Path("schema") -> SchemaResource)
        - guacamole/src/main/java/org/apache/guacamole/rest/schema/SchemaResource.java
          (userAttributes, userPreferenceAttributes, userGroupAttributes,
           connectionAttributes, sharingProfileAttributes,
           connectionGroupAttributes, protocols)
        - guacamole/src/main/java/org/apache/guacamole/rest/schema/Form.java
        - guacamole/src/main/java/org/apache/guacamole/rest/schema/ProtocolInfo.java

    .EXAMPLE
        Get-GuacSchema -Set ConnectionAttributes

    .EXAMPLE
        Get-GuacSchema -Set Protocols

    .EXAMPLE
        Get-GuacSchema   # all attribute sets
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
        [ValidateSet('ConnectionAttributes', 'ConnectionGroupAttributes', 'SharingProfileAttributes', 'UserAttributes', 'UserPreferenceAttributes', 'UserGroupAttributes', 'Protocols')]
        [string] $Set = [string]::Empty
    )

    $ctx = Resolve-GuacSessionContext -Session $Session -Server $Server -DataSource $DataSource -CmdletName 'Get-GuacSchema'

    $subPathMap = [ordered]@{
        ConnectionAttributes      = 'connectionAttributes'
        ConnectionGroupAttributes = 'connectionGroupAttributes'
        SharingProfileAttributes  = 'sharingProfileAttributes'
        UserAttributes            = 'userAttributes'
        UserPreferenceAttributes  = 'userPreferenceAttributes'
        UserGroupAttributes       = 'userGroupAttributes'
        Protocols                 = 'protocols'
    }

    $sets = [string[]]$Set
    if ([string]::IsNullOrWhiteSpace($sets[0])) {
        $sets = @('ConnectionAttributes', 'ConnectionGroupAttributes', 'SharingProfileAttributes', 'UserAttributes', 'UserPreferenceAttributes', 'UserGroupAttributes')
    }

    foreach ($setName in $sets) {
        $subPath = [string]$subPathMap[$setName]
        $path = Resolve-GuacContextUrl -DataSource $ctx['DataSource'] -Collection 'schema' -SubPath $subPath
        $result = Invoke-GuacRest -Server $ctx['Server'] -Token $ctx['Token'] -Method GET -Path $path
        if ([string]::IsNullOrWhiteSpace($Set)) {
            # Tag the result so the caller can tell which set it came from.
            if ($null -eq $result) {
                $result = [PSCustomObject]@{ schemaSet = $setName }
            }
            elseif ($result -is [array]) {
                foreach ($item in $result) {
                    if ($null -ne $item) {
                        $item | Add-Member -NotePropertyName schemaSet -NotePropertyValue $setName -Force
                    }
                }
                Write-Output $result
            }
            else {
                $result | Add-Member -NotePropertyName schemaSet -NotePropertyValue $setName -Force
                Write-Output $result
            }
        }
        else {
            Write-Output $result
        }
    }
}
