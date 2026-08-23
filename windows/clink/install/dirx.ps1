# Install chrisant996/dirx (prebuilt release; used by clink-fzf for relative paths).
# Installs to C:\Software\dirx\dirx.exe and adds that folder (not C:\Software) to PATH.

param(
    [string]$InstallDir,
    [string]$Version,
    [string]$Proxy = 'http://127.0.0.1:7890',
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1" -Proxy $Proxy -NoProxy:$NoProxy

if (-not $InstallDir) { $InstallDir = Join-Path $SoftwareRoot 'dirx' }
$exe = Join-Path $InstallDir 'dirx.exe'
$strayRootExe = Join-Path $SoftwareRoot 'dirx.exe'
$legacyClinkExe = Join-Path $ClinkSoftwareRoot 'dirx\dirx.exe'

function ConvertTo-DirxVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '(\d+)\.(\d+)(?:\.(\d+))?(?:\.(\d+))?')
    if (-not $m.Success) { return $null }
    $build = if ($m.Groups[3].Success) { [int]$m.Groups[3].Value } else { 0 }
    $rev = if ($m.Groups[4].Success) { [int]$m.Groups[4].Value } else { 0 }
    return [version]::new([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, $build, $rev)
}

function Format-DirxVersion {
    param([version]$Version)
    if ($Version.Build -le 0 -and $Version.Revision -le 0) {
        return '{0}.{1}' -f $Version.Major, $Version.Minor
    }
    return $Version.ToString()
}

function Get-InstalledDirxVersion {
    param([string]$ExePath)
    if (-not (Test-Path -LiteralPath $ExePath)) { return $null }
    $prev = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $text = & $ExePath --version 2>&1 | Out-String
        $ver = ConvertTo-DirxVersion $text
        if ($ver) { return $ver }
    } catch {
    } finally {
        $PSNativeCommandUseErrorActionPreference = $prev
    }
    try {
        return ConvertTo-DirxVersion ([Diagnostics.FileVersionInfo]::GetVersionInfo($ExePath).ProductVersion)
    } catch {
        return $null
    }
}

function Get-DirxLatestTag {
    Use-InstallProxy
    $url = 'https://api.github.com/repos/chrisant996/dirx/releases/latest'
    $prev = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        if ($script:InstallProxy) {
            $raw = curl.exe -fsSL -x $script:InstallProxy -H 'User-Agent: clink-dirx-install' $url
        } else {
            $raw = curl.exe -fsSL -H 'User-Agent: clink-dirx-install' $url
        }
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) { return $null }
        $tag = ($raw | ConvertFrom-Json).tag_name
        if ([string]::IsNullOrWhiteSpace($tag)) { return $null }
        return [string]$tag
    } catch {
        return $null
    } finally {
        $PSNativeCommandUseErrorActionPreference = $prev
    }
}

function Confirm-DirxUpdate {
    param(
        [string]$CurrentLabel,
        [string]$TargetTag
    )
    Write-Host -NoNewline '已安装 dirx '
    Write-Host -NoNewline $CurrentLabel -ForegroundColor Yellow
    Write-Host -NoNewline '，最新为 '
    Write-Host $TargetTag -ForegroundColor Green
    $ans = Read-Host "是否更新到 $TargetTag？[Y/n]"
    return [string]::IsNullOrWhiteSpace($ans) -or $ans -match '^[Yy]'
}

function Install-DirxRelease {
    param(
        [string]$Tag,
        [string]$InstallDir,
        [string]$ExePath
    )
    if (-not (Test-Path -LiteralPath $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    $zipName = "dirx-$Tag.zip"
    $url = "https://github.com/chrisant996/dirx/releases/download/$Tag/$zipName"
    $zip = Join-Path $env:TEMP $zipName
    $extract = Join-Path $env:TEMP "dirx-$Tag"

    Write-Host "Downloading $url ..."
    Use-InstallProxy
    $prev = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        if ($script:InstallProxy) {
            curl.exe -fsSL -x $script:InstallProxy -o $zip $url
        } else {
            curl.exe -fsSL -o $zip $url
        }
        if ($LASTEXITCODE -ne 0) {
            throw "download failed: $url (exit $LASTEXITCODE)"
        }
    } finally {
        $PSNativeCommandUseErrorActionPreference = $prev
    }

    if (Test-Path -LiteralPath $extract) {
        Remove-Item -LiteralPath $extract -Recurse -Force
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force

    $found = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'dirx.exe' | Select-Object -First 1
    if (-not $found) {
        throw "dirx.exe not found in $zip"
    }

    Copy-Item -LiteralPath $found.FullName -Destination $ExePath -Force
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue

    Add-UserPathEntry -Dir $InstallDir
    Write-Host "Installed dirx $Tag -> $ExePath" -ForegroundColor Green
}

function Move-DirxIfPresent {
    param([string]$From)
    if (-not (Test-Path -LiteralPath $From)) { return }
    if ($From -ieq $exe) { return }
    if (-not (Test-Path -LiteralPath $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Host "Migrating dirx from $From ..."
        Copy-Item -LiteralPath $From -Destination $exe -Force
    }
    Remove-Item -LiteralPath $From -Force
    Write-Host "Removed stray $From"
}

Move-DirxIfPresent -From $strayRootExe
Move-DirxIfPresent -From $legacyClinkExe
Remove-UserPathEntry -Dir $SoftwareRoot
Refresh-SessionPath

$explicitVersion = $PSBoundParameters.ContainsKey('Version') -and -not [string]::IsNullOrWhiteSpace($Version)
if ($explicitVersion) {
    $targetTag = if ($Version -match '^[Vv]') { $Version } else { "v$Version" }
} else {
    Write-Host '查询 dirx 最新版本...'
    $targetTag = Get-DirxLatestTag
    if (-not $targetTag) {
        $pathExe = Find-PathExe -ExeName @('dirx.exe', 'dirx')
        if ($pathExe) {
            Add-UserPathEntry -Dir (Split-Path -Parent $pathExe)
            Write-Warning "无法查询 dirx 最新版本，保留已安装的 $pathExe"
            return
        }
        throw '无法查询 dirx 最新版本，且 PATH 上找不到 dirx。检查网络或代理后重试，或使用 -Version 指定版本。'
    }
    Write-Host -NoNewline '最新版本: '
    Write-Host $targetTag -ForegroundColor Green
}

$targetVer = ConvertTo-DirxVersion $targetTag
if (-not $targetVer) {
    throw "Invalid dirx version: $targetTag"
}

$pathExe = Find-PathExe -ExeName @('dirx.exe', 'dirx')
if ($pathExe) {
    $installedVer = Get-InstalledDirxVersion $pathExe
    Add-UserPathEntry -Dir (Split-Path -Parent $pathExe)
    if ($installedVer -and $installedVer -ge $targetVer) {
        Write-Host "dirx 已是最新版本: $(Format-DirxVersion $installedVer) ($pathExe)"
        return
    }
    $currentLabel = if ($installedVer) { Format-DirxVersion $installedVer } else { '未知版本' }
    if (-not (Confirm-DirxUpdate -CurrentLabel $currentLabel -TargetTag $targetTag)) {
        Write-Host "跳过更新，保留 $currentLabel"
        return
    }
}

Install-DirxRelease -Tag $targetTag -InstallDir $InstallDir -ExePath $exe
Write-Host 'Restart the terminal so PATH picks up dirx.exe.'
