# Install chrisant996/clink-fzf (upstream lives outside dotfiles).
# Clones to C:\Software\clink-plugins\clink-fzf (git pull if present), installs
# fzf.exe to C:\Software\fzf with the same version prompt as apps.ps1, and
# symlinks needed files into the profile.

param(
    [string]$Repo,
    [switch]$Minimal,
    [switch]$NoBindings,
    [string]$Proxy = 'http://127.0.0.1:7890',
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1" -Proxy $Proxy -NoProxy:$NoProxy
Ensure-SymbolicLinkPrivilege -BoundParameters $PSBoundParameters

if (-not $Repo) { $Repo = Join-Path $ClinkSoftwareRoot 'clink-fzf' }

$AllFiles = @(
    'fzf.lua',
    'fzf_git.lua',
    'fzf_git_helper.cmd',
    'fzf_rg.lua',
    'fzf_rg.cmd'
)
$Files = if ($Minimal) { @('fzf.lua') } else { $AllFiles }

Ensure-GitRepo -Repo $Repo -CloneUrl 'https://github.com/chrisant996/clink-fzf.git'

foreach ($name in $Files) {
    New-ProfileSymlink -ProfileDir $ClinkProfileDir -Name $name -Target (Join-Path $Repo $name)
}

Ensure-FzfExe | Out-Null

if (-not $NoBindings) {
    Set-ClinkFzfSettings
}

Write-Host 'Done. Requires fzf.exe on PATH (or clink set fzf.exe_location).'
