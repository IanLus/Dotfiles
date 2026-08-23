# Install chrisant996/clink-fzf (upstream lives outside dotfiles).
# Clones to C:\Software\clink\fzf and symlinks needed files into the profile.

param(
    [string]$Repo,
    [switch]$Minimal,
    [switch]$NoBindings,
    [string]$Proxy = 'http://127.0.0.1:7890',
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_install-common.ps1" -Proxy $Proxy -NoProxy:$NoProxy
Ensure-SymbolicLinkPrivilege -BoundParameters $PSBoundParameters

if (-not $Repo) { $Repo = Join-Path $ClinkSoftwareRoot 'fzf' }

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

if (-not $NoBindings) {
    Invoke-ClinkSet -Name 'fzf.default_bindings' -Value 'true'
    Invoke-ClinkSet -Name 'fzf_git.default_bindings' -Value 'true'
}

Write-Host 'Done. Requires fzf.exe on PATH (or clink set fzf.exe_location).'
