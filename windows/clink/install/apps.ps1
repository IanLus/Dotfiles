# Install CLI apps with winget. Already-installed is PATH (lua / lua.exe), not SOFTWARE_HOME.
# New installs prefer C:\Software\<name>; then add the exe directory to user PATH.
#
#   pwsh -File apps.ps1
#   pwsh -File apps.ps1 -Name fnm, eza

param(
    [string[]]$Name,
    [string]$Version,
    [string]$Proxy = 'http://127.0.0.1:7890',
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1" -Proxy $Proxy -NoProxy:$NoProxy

$script:SoftwareApps = @(
    @{ Id = 'Schniz.fnm';            Name = 'fnm';      ExeName = 'fnm.exe';      DirName = 'fnm' }
    @{ Id = 'eza-community.eza';     Name = 'eza';      ExeName = 'eza.exe';      DirName = 'eza' }
    @{ Id = 'sharkdp.bat';           Name = 'bat';      ExeName = 'bat.exe';      DirName = 'bat' }
    @{ Id = 'DEVCOM.Lua';            Name = 'lua';      ExeName = 'lua.exe';      DirName = 'Lua' }
    @{ Id = 'hpjansson.Chafa';       Name = 'chafa';    ExeName = 'chafa.exe';    DirName = 'chafa' }
    @{ Id = 'Starship.Starship';     Name = 'starship'; ExeName = 'starship.exe'; DirName = 'starship'; LocationIgnored = $true }
    @{ Id = 'JesseDuffield.lazygit'; Name = 'lazygit';  ExeName = 'lazygit.exe';  DirName = 'lazygit' }
)

$wanted = @($script:SoftwareApps)
if ($Name -and $Name.Count -gt 0) {
    $lookup = @{ }
    foreach ($app in $script:SoftwareApps) { $lookup[$app.Name.ToLowerInvariant()] = $app }
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Name) {
        foreach ($part in ($item -split ',')) {
            $key = $part.Trim().ToLowerInvariant()
            if (-not $key) { continue }
            if (-not $lookup.ContainsKey($key)) {
                $known = ($script:SoftwareApps | ForEach-Object { $_.Name }) -join ', '
                throw "Unknown app '$part'. Expected one of: $known"
            }
            $selected.Add($lookup[$key])
        }
    }
    $wanted = @($selected)
}

$explicitVersion = $PSBoundParameters.ContainsKey('Version') -and -not [string]::IsNullOrWhiteSpace($Version)
if ($explicitVersion -and @($wanted).Count -ne 1) {
    throw '-Version 只能和单个 -Name 一起使用。'
}

$failed = [System.Collections.Generic.List[string]]::new()
foreach ($app in $wanted) {
    Write-Host ""
    Write-Host "=== $($app.Name) ($($app.Id)) -> $(Join-Path $SoftwareRoot $app.DirName) ==="
    try {
        $args = @{
            Id      = $app.Id
            Name    = $app.Name
            ExeName = $app.ExeName
            DirName = $app.DirName
        }
        if ($explicitVersion) { $args.Version = $Version }
        if ($app.LocationIgnored) { $args.LocationIgnored = $true }
        Install-WingetSoftware @args
    } catch {
        Write-Warning $_.Exception.Message
        $failed.Add("$($app.Name): $($_.Exception.Message)")
    }
}

if ($wanted | Where-Object { $_.Name -eq 'starship' }) {
    Enable-ClinkStarshipPrompt | Out-Null
}

if ($failed.Count -gt 0) {
    throw ($failed -join '; ')
}

Write-Host 'Restart the terminal so PATH picks up any new executables.'
