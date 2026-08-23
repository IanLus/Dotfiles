# Install chrisant996/clink-gizmos scripts (upstream lives outside dotfiles).
# Clones to C:\Software\clink-plugins\clink-gizmos and symlinks selected .lua files into the profile.

param(
    [string]$Repo,
    [string[]]$Files = @('tilde_autoexpand.lua'),
    [string]$Proxy = 'http://127.0.0.1:7890',
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1" -Proxy $Proxy -NoProxy:$NoProxy
Ensure-SymbolicLinkPrivilege -BoundParameters $PSBoundParameters

if (-not $Repo) { $Repo = Join-Path $ClinkSoftwareRoot 'clink-gizmos' }

Ensure-GitRepo -Repo $Repo -CloneUrl 'https://github.com/chrisant996/clink-gizmos.git'

foreach ($name in $Files) {
    New-ProfileSymlink -ProfileDir $ClinkProfileDir -Name $name -Target (Join-Path $Repo $name)
}

Invoke-ClinkSet -Name 'tilde.autoexpand' -Value 'True' | Out-Null

Write-Host "Done. Linked $($Files.Count) file(s) from clink-gizmos."
