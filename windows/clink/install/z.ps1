# Install skywind3000/z.lua for Clink (upstream lives outside dotfiles).
# Creates z.lua + z.cmd symlinks in the clink profile directory.

param(
    [string]$Proxy = 'http://127.0.0.1:7890',
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_install-common.ps1" -Proxy $Proxy -NoProxy:$NoProxy
Ensure-SymbolicLinkPrivilege -BoundParameters $PSBoundParameters

$ZRepo = if ($env:Z_LUA_HOME) { $env:Z_LUA_HOME } else { Join-Path $ClinkSoftwareRoot 'z.lua' }

Ensure-GitRepo -Repo $ZRepo -CloneUrl 'https://github.com/skywind3000/z.lua.git'

foreach ($name in @('z.lua', 'z.cmd')) {
    New-ProfileSymlink -ProfileDir $ClinkProfileDir -Name $name -Target (Join-Path $ZRepo $name)
}

Write-Host 'Done. Ensure %CLINK_PROFILE% is on PATH so z.cmd is callable.'
