#Requires -Version 5.1
<#
.SYNOPSIS
    Test helper: manages the GuacMockServer process and module import for Pester.
#>

$script:Mock = $null

function Start-GuacTestMock {
    <#
    .SYNOPSIS
        Starts the mock Guacamole server process and imports the module under test.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $false)]
        [string] $WorkDir
    )

    if ($null -ne $script:Mock) {
        return $script:Mock
    }

    if (-not $WorkDir) {
        $WorkDir = (Get-Item (Split-Path -Parent $MyInvocation.ScriptName)).FullName
    }

    $port = Get-Random -Minimum 20000 -Maximum 60000
    $logFile = Join-Path ([System.IO.Path]::GetTempPath()) ('guacmock-' + [System.Guid]::NewGuid().ToString('N') + '.log')
    $scriptPath = Join-Path $WorkDir 'GuacMockServer.ps1'
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)
    if (-not $pwsh) { $pwsh = (Get-Command powershell) }

    $argList = @('-NoProfile', '-File', $scriptPath, '-Port', [string]$port, '-LogFile', $logFile)
    $process = Start-Process -FilePath $pwsh.Source -ArgumentList $argList `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path ([System.IO.Path]::GetTempPath()) ('guacmock-out-' + [System.Guid]::NewGuid().ToString('N') + '.txt')) `
        -RedirectStandardError (Join-Path ([System.IO.Path]::GetTempPath()) ('guacmock-err-' + [System.Guid]::NewGuid().ToString('N') + '.txt'))

    # Wait for the listener to come up.
    $baseUrl = ('http://127.0.0.1:{0}/guacamole' -f $port)
    $deadline = (Get-Date).AddSeconds(15)
    $up = $false
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri ($baseUrl + '/_control/totp-disable') -UseBasicParsing -TimeoutSec 2
            if ($response.StatusCode -eq 200) { $up = $true; break }
        }
        catch [System.Exception] {
            Start-Sleep -Milliseconds 200
        }
        if ($process.HasExited) { break }
    }
    if (-not $up) {
        throw ('The mock Guacamole server did not start on port {0} (process exited: {1})' -f ($port, $process.HasExited))
    }

    # Import the module under test (manifest path relative to the test helper).
    $modulePath = Join-Path (Split-Path -Parent $WorkDir) 'N2C.GuacAdmin.psd1'
    Import-Module $modulePath -Force

    $script:Mock = [PSCustomObject]@{
        Process   = $process
        BaseUrl   = $baseUrl
        LogFile   = $logFile
        Port      = $port
    }
    return $script:Mock
}

function Stop-GuacTestMock {
    <#
    .SYNOPSIS
        Stops the mock server process and removes the log file.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $script:Mock) {
        return
    }
    try {
        if (-not $script:Mock.Process.HasExited) {
            $script:Mock.Process.Kill()
            $null = $script:Mock.Process.WaitForExit(5000)
        }
    }
    catch [System.Exception] {
        # Best effort.
    }
    Remove-Item -LiteralPath $script:Mock.LogFile -Force -ErrorAction SilentlyContinue
    $script:Mock = $null
}

function Get-GuacMockLog {
    <#
    .SYNOPSIS
        Returns the recorded mock server requests (JSON lines) as objects.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $false)]
        [string] $FilterPath
    )

    if ($null -eq $script:Mock) {
        return @()
    }
    if (-not (Test-Path -LiteralPath $script:Mock.LogFile)) {
        return @()
    }
    $lines = Get-Content -LiteralPath $script:Mock.LogFile
    $records = foreach ($line in $lines) {
        if ($line -and $line.Trim()) {
            $line | ConvertFrom-Json
        }
    }
    if ($FilterPath) {
        return @($records | Where-Object { $_.path -like $FilterPath })
    }
    return @($records)
}

function Invoke-GuacMockControl {
    <#
    .SYNOPSIS
        Calls a mock control endpoint (e.g. /_control/totp-enable).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Path
    )
    Invoke-WebRequest -Uri ($script:Mock.BaseUrl + $Path) -UseBasicParsing -TimeoutSec 5 | Out-Null
}

Export-ModuleMember -Function 'Start-GuacTestMock', 'Stop-GuacTestMock', 'Get-GuacMockLog', 'Invoke-GuacMockControl'
