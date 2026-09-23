#Requires -Version 5.1
<#
.SYNOPSIS
    N2C.GuacAdmin - administrative PowerShell module for Apache Guacamole 1.6.x.

.DESCRIPTION
    This module administers a deployed Apache Guacamole instance through the
    Guacamole REST API and (in later phases) the Guacamole protocol over
    WebSocket tunnels.

    Design notes:
    - Authentication state is carried by [N2C_GuacAdmin_GuacSession] objects
      (created by New-GuacSession), never by module-scope globals. A single
      module-scope session-state dictionary provides a "default session" for
      cmdlets (the -CmsSession pattern), so multiple instances can be worked
      with in one process.
    - All REST traffic goes through the private Invoke-GuacRest transport,
      which parses Guacamole APIError bodies and converts every failure into a
      terminating N2C_GuacAdmin_GuacRestException. No cmdlet returns $false on
      API failure.
    - Compatible with Windows PowerShell 5.1 and PowerShell 7.x on
      Windows/Linux/macOS. No PowerShell 6+ only APIs are used.

    Reference implementation facts are traced to the Apache Guacamole 1.6.0
    source (see ANALYSIS/guacamole-client-1.6.0/ in the repository root).
#>

# NOTE: Set-StrictMode is intentionally not used. API responses are untrusted
# JSON parsed with ConvertFrom-Json; strict property access on those objects
# would turn missing fields into confusing runtime errors. API response fields
# are accessed defensively instead (see ConvertFrom-GuacErrorBody).

# Force TLS 1.2 on Windows PowerShell 5.1 (the .NET Framework default is TLS 1.0,
# which modern Guacamole deployments may reject).
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
}

# Type definitions ([N2C_GuacAdmin_GuacSession], [N2C_GuacAdmin_GuacRestException])
# live in Types.ps1, which the module manifest lists in ScriptsToProcess. Those
# scripts run in a caller-visible scope, so the classes resolve to the same
# type in both the module and the caller (verified empirically on PowerShell
# 5.1/7.x: a class defined in the .psm1 instead is module-scope only and cannot
# be cast across the module boundary).

# The class types are captured as module-scope variables exactly once, at load
# time. Runtime name resolution of the class identifiers inside module
# functions is unreliable in some host scopes (empirically observed under
# Pester 5.7.1: `New-Object N2C_GuacAdmin_GuacRestException` fails with
# TypeNotFound inside the module even though the import itself succeeded), so
# every construction and every runtime type test in the module goes through
# these variables instead of type literals.
$script:GuacSessionType = [N2C_GuacAdmin_GuacSession]
$script:GuacActiveSessionType = [N2C_GuacAdmin_GuacActiveSession]
$script:GuacInstructionType = [N2C_GuacAdmin_GuacInstruction]
$script:GuacRestExceptionType = [N2C_GuacAdmin_GuacRestException]

# Module session state: keyed by normalized server URI. This is the ONLY module
# scope state the module keeps (no token/server globals), and it exists solely
# to provide the "default session" resolution for the -Session parameter.
$script:GuacSessionState = [System.Collections.Generic.Dictionary[string, object]]::new()

# Cached capability set of the running Invoke-WebRequest implementation, used to
# plumb parameters that differ between Windows PowerShell 5.1 and PowerShell 7.x
# (-UseBasicParsing, -Certificate vs -PfxCertificate, -NoProxy).
$script:GuacIwrCapabilities = [System.Collections.Generic.HashSet[string]]::new()
foreach ($name in (Get-Command -Name Invoke-WebRequest).Parameters.Keys) {
    [void]$script:GuacIwrCapabilities.Add($name)
}

# Load private functions, then public functions.
$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
Get-ChildItem -Path $privatePath -Filter '*.ps1' -File | ForEach-Object {
    . $_.FullName
}
$publicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
Get-ChildItem -Path $publicPath -Filter '*.ps1' -File | ForEach-Object {
    . $_.FullName
}

Export-ModuleMember -Function @(
    'New-GuacSession', 'Get-GuacSession', 'Remove-GuacSession', 'Test-GuacSession',
    'Get-GuacConnection', 'New-GuacConnection', 'Update-GuacConnection', 'Remove-GuacConnection',
    'Get-GuacConnectionGroup', 'New-GuacConnectionGroup', 'Update-GuacConnectionGroup', 'Remove-GuacConnectionGroup',
    'Get-GuacUser', 'New-GuacUser', 'Update-GuacUser', 'Remove-GuacUser', 'Set-GuacUserPassword',
    'Get-GuacUserGroup', 'New-GuacUserGroup', 'Update-GuacUserGroup', 'Remove-GuacUserGroup',
    'Get-GuacSharingProfile', 'New-GuacSharingProfile', 'Update-GuacSharingProfile', 'Remove-GuacSharingProfile',
    'Add-GuacPermission', 'Remove-GuacPermission',
    'Add-GuacUserGroupMember', 'Remove-GuacUserGroupMember', 'Add-GuacUserGroupChildGroup', 'Remove-GuacUserGroupChildGroup',
    'Get-GuacHistory', 'Get-GuacSchema', 'Get-GuacProtocol',
    'Get-GuacActiveConnection', 'Stop-GuacActiveConnection', 'Get-GuacSharingCredential',
    'Get-GuacTunnel', 'Get-GuacLanguage', 'Get-GuacPatches', 'Get-GuacExtension',
    'New-GuacActiveSession', 'Send-GuacInstruction', 'Receive-GuacInstruction', 'Remove-GuacActiveSession'
)
