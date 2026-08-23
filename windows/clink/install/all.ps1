# One-shot Clink profile install: z.lua, clink-fzf, gizmos, dirx.
# For a new machine: pwsh -File "$env:CLINK_PROFILE\install\all.ps1"

param(
    [switch]$Minimal,
    [switch]$NoBindings,
    [string]$Proxy = 'http://127.0.0.1:7890',
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_install-common.ps1" -Proxy $Proxy -NoProxy:$NoProxy

$common = @{
    Proxy   = $Proxy
    NoProxy = $NoProxy
}

$steps = @(
    @{ Name = 'z.lua'; Script = 'z.ps1'; Args = @{} }
    @{ Name = 'clink-fzf'; Script = 'clink-fzf.ps1'; Args = @{ Minimal = $Minimal; NoBindings = $NoBindings } }
    @{ Name = 'clink-gizmos'; Script = 'clink-gizmos.ps1'; Args = @{} }
    @{ Name = 'dirx'; Script = 'dirx.ps1'; Args = @{} }
)

foreach ($step in $steps) {
    $path = Join-Path $PSScriptRoot $step.Script
    Write-Host ""
    Write-Host "=== $($step.Name) ($($step.Script)) ==="
    $invoke = @{
        Proxy   = $Proxy
        NoProxy = $NoProxy
    }
    foreach ($key in $step.Args.Keys) {
        $invoke[$key] = $step.Args[$key]
    }
    try {
        & $path @invoke
    } catch {
        throw "$($step.Name) failed: $($_.Exception.Message)"
    }
}

Add-UserPathEntry -Dir $ClinkProfileDir

Write-Host ""
Write-Host 'All install scripts finished. Restart the terminal so PATH and Clink pick up the new links.'
