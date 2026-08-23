# One-shot Clink setup from a machine that may not have Clink yet.
#   pwsh -File <dotfiles>\windows\clink\install\all.ps1

param(
    [switch]$Minimal,
    [switch]$NoBindings,
    [string]$Proxy,
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'

$defaultProxy = 'http://127.0.0.1:7890'
$envProxy = @(
    $env:HTTPS_PROXY
    $env:HTTP_PROXY
    $env:ALL_PROXY
    $env:https_proxy
    $env:http_proxy
    $env:all_proxy
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1

if (-not $NoProxy -and -not $PSBoundParameters.ContainsKey('Proxy')) {
    if ($envProxy) {
        $Proxy = $envProxy.Trim()
        Write-Host "Using proxy from environment: $Proxy"
    } else {
        $inputProxy = Read-Host "代理地址 [$defaultProxy]"
        $Proxy = if ([string]::IsNullOrWhiteSpace($inputProxy)) { $defaultProxy } else { $inputProxy.Trim() }
    }
} elseif (-not $NoProxy -and [string]::IsNullOrWhiteSpace($Proxy)) {
    $Proxy = $defaultProxy
}

. "$PSScriptRoot\common.ps1" -Proxy $Proxy -NoProxy:$NoProxy
Ensure-DotDirAndClinkProfile

$elevateParams = @{}
foreach ($key in $PSBoundParameters.Keys) {
	$elevateParams[$key] = $PSBoundParameters[$key]
}
if ($Proxy) { $elevateParams['Proxy'] = $Proxy }
if ($NoProxy) { $elevateParams['NoProxy'] = $true }
Ensure-SymbolicLinkPrivilege -BoundParameters $elevateParams

$steps = @(
    @{ Name = 'clink'; Script = 'clink.ps1'; Args = @{} }
    @{ Name = 'tools'; Script = 'tools.ps1'; Args = @{} }
    @{ Name = 'apps'; Script = 'apps.ps1'; Args = @{} }
    @{ Name = 'z.lua'; Script = 'z.ps1'; Args = @{} }
    @{ Name = 'fzf'; Script = 'fzf.ps1'; Args = @{ Minimal = $Minimal; NoBindings = $NoBindings } }
    @{ Name = 'gizmos'; Script = 'gizmos.ps1'; Args = @{} }
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
        throw "$($step.Name): $($_.Exception.Message)"
    }
}

Add-UserPathEntry -Dir $ClinkProfileDir

Write-Host ""
Write-Host 'All install scripts finished. Restart the terminal so CLINK_PROFILE, PATH, and Clink pick up the new setup.'
