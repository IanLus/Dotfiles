# Build profile-local helpers from tools/*.c (not checked in).

param(
    [switch]$Force,
    [string]$Proxy = 'http://127.0.0.1:7890',
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1" -Proxy $Proxy -NoProxy:$NoProxy

if (-not (Build-ClinkTools -Force:$Force)) {
    Write-Warning 'Some tools/*.exe were not built. UTF-8 and fnm cleanup need gcc (MinGW or Git for Windows).'
    return
}

Write-Host 'Done. tools/set_console_utf8.exe and tools/fnm_multishell_cleanup.exe are ready.'
