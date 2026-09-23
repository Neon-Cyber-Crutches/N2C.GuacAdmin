function New-GuacTunnelUrl {
    <#
    .SYNOPSIS
        Builds a WebSocket tunnel URL for a Guacamole connection.

    .DESCRIPTION
        Constructs the URL for a WebSocket tunnel to a specific Guacamole connection
        or connection group. The URL includes all necessary query parameters per
        TunnelRequest.java in the Apache Guacamole 1.6.0 source.

        Reference: guacamole/src/main/java/org/apache/guacamole/tunnel/TunnelRequest.java

    .EXAMPLE
        New-GuacTunnelUrl -Server 'https://guac.example.com/guacamole' -Token 'abc' -ConnectionId 'xyz' -Width 1920 -Height 1080
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Server,

        [Parameter(Mandatory = $true)]
        [string] $Token,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $ConnectionId = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $GroupId = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $DataSource = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [ValidateRange(64, 7680)]
        [int] $Width = 1024,

        [Parameter(Mandatory = $false)]
        [ValidateRange(64, 7680)]
        [int] $Height = 768,

        [Parameter(Mandatory = $false)]
        [ValidateRange(75, 300)]
        [int] $Dpi = 96,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Timezone = [string]::Empty,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string[]] $AudioMimeTypes = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string[]] $VideoMimeTypes = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string[]] $ImageMimeTypes = @()
    )

    # Determine the target type: connection or group
    if (-not [string]::IsNullOrWhiteSpace($ConnectionId)) {
        $type = 'c'
        $id = $ConnectionId
    }
    elseif (-not [string]::IsNullOrWhiteSpace($GroupId)) {
        $type = 'g'
        $id = $GroupId
    }
    else {
        throw ($script:GuacRestExceptionType::new('Either -ConnectionId or -GroupId must be specified.'))
    }

    # Build the base WebSocket URL
    $normalizedServer = ConvertTo-GuacServerUrl -Server $Server
    $base = $normalizedServer.TrimEnd('/')
    $url = "$base/websocket-tunnel?token=$Token"

    if (-not [string]::IsNullOrWhiteSpace($DataSource)) {
        $url += "&GUAC_DATA_SOURCE=$DataSource"
    }
    $url += "&GUAC_TYPE=$type&GUAC_ID=$id"
    $url += "&GUAC_WIDTH=$Width&GUAC_HEIGHT=$Height&GUAC_DPI=$Dpi"

    if (-not [string]::IsNullOrWhiteSpace($Timezone)) {
        $url += "&GUAC_TIMEZONE=$Timezone"
    }

    foreach ($mime in $AudioMimeTypes) {
        if (-not [string]::IsNullOrWhiteSpace($mime)) {
            $url += "&GUAC_AUDIO=$mime"
        }
    }
    foreach ($mime in $VideoMimeTypes) {
        if (-not [string]::IsNullOrWhiteSpace($mime)) {
            $url += "&GUAC_VIDEO=$mime"
        }
    }
    foreach ($mime in $ImageMimeTypes) {
        if (-not [string]::IsNullOrWhiteSpace($mime)) {
            $url += "&GUAC_IMAGE=$mime"
        }
    }

    return $url
}
