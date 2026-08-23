# Install Clink to C:\Software\clink (if missing), point it at this profile, and write core settings.
# Safe to run on a machine that has never had Clink.

param(
    [string]$Proxy = 'http://127.0.0.1:7890',
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1" -Proxy $Proxy -NoProxy:$NoProxy

Ensure-DotDirAndClinkProfile

if (-not (Install-ClinkIfMissing)) {
    throw 'Clink is required. Install chrisant996.Clink (winget) and re-run.'
}

Set-ClinkCoreSettings

Write-Host 'Done. Restart the terminal so CLINK_PROFILE and PATH take effect.'
