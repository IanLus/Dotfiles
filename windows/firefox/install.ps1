# Overlay this folder onto the Firefox profile. Does not vendor upstream FlexFox CSS.
#   pwsh -File <dotfiles>\windows\firefox\install.ps1
#   pwsh -File <dotfiles>\windows\firefox\install.ps1 -InstallFlexFox

param(
    [string]$ProfilePath,
    [switch]$InstallFlexFox,
    [string]$Proxy,
    [switch]$NoProxy
)

$ErrorActionPreference = 'Stop'

$flexFoxVersion = 'v7.0.1'
$flexFoxZipName = 'FlexFox-v7.0.1.zip'
$flexFoxZipUrl = "https://github.com/yuuqilin/FlexFox/releases/download/$flexFoxVersion/$flexFoxZipName"
$flexFoxSha256 = '0BF871B6D8FB7D3D93ADAF2C20D05910FCE8263B99623357157FA74ECCE83BB3'
$defaultProxy = 'http://127.0.0.1:7890'
$overlayFiles = @(
    'user.js'
    'chrome\content\uc-custom-content.css'
    'chrome\components\uc-user-settings.css'
    'chrome\wallpaper.png'
    'chrome\wallpaper-light.png'
)

$here = $PSScriptRoot

function Get-InstallProxy {
    if ($NoProxy) { return $null }
    if ($PSBoundParameters.ContainsKey('Proxy')) {
        if ([string]::IsNullOrWhiteSpace($Proxy)) { return $null }
        return $Proxy.Trim()
    }
    $fromEnv = @(
        $env:HTTPS_PROXY
        $env:HTTP_PROXY
        $env:ALL_PROXY
        $env:https_proxy
        $env:http_proxy
        $env:all_proxy
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    if ($fromEnv) { return $fromEnv.Trim() }
    return $defaultProxy
}

function Read-IniFile {
    param([string]$Path)
    $sections = [ordered]@{}
    $name = ''
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trim = $line.Trim()
        if ($trim -match '^\[(.+)\]$') {
            $name = $Matches[1]
            if (-not $sections.Contains($name)) {
                $sections[$name] = @{}
            }
            continue
        }
        if ($name -and $trim -match '^(.*?)=(.*)$') {
            $sections[$name][$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    return $sections
}

function Get-FirefoxProfilePath {
    param([string]$Requested)
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        if (-not (Test-Path -LiteralPath $Requested)) {
            throw "ProfilePath not found: $Requested"
        }
        return (Resolve-Path -LiteralPath $Requested).Path
    }

    $firefoxRoot = Join-Path $env:APPDATA 'Mozilla\Firefox'
    $iniPath = Join-Path $firefoxRoot 'profiles.ini'
    if (-not (Test-Path -LiteralPath $iniPath)) {
        throw "Firefox profiles.ini not found: $iniPath"
    }

    $ini = Read-IniFile -Path $iniPath
    $relative = $null
    $isRelative = $true

    foreach ($section in $ini.Keys) {
        if ($section -like 'Install*' -and $ini[$section]['Default']) {
            $relative = $ini[$section]['Default']
            break
        }
    }

    foreach ($section in $ini.Keys) {
        if ($section -notlike 'Profile*') { continue }
        $profile = $ini[$section]
        $matchesInstall = $relative -and (
            ($profile['Path'] -replace '\\', '/') -ieq ($relative -replace '\\', '/')
        )
        $markedDefault = $profile['Default'] -eq '1'
        if ($matchesInstall -or (-not $relative -and $markedDefault)) {
            $relative = $profile['Path']
            $isRelative = $profile['IsRelative'] -ne '0'
            break
        }
    }

    if (-not $relative) {
        throw 'Could not determine the Firefox profile path from profiles.ini.'
    }

    if (-not $isRelative -or $relative -match '^[A-Za-z]:[\\/]' -or $relative.StartsWith('/')) {
        return $relative
    }
    return Join-Path $firefoxRoot ($relative -replace '/', '\')
}

function Copy-OverlayFile {
    param(
        [string]$From,
        [string]$To
    )
    if (-not (Test-Path -LiteralPath $From)) {
        throw "Missing overlay file: $From"
    }
    $parent = Split-Path -Parent $To
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $From -Destination $To -Force
    Write-Host "Copied $(Split-Path -Leaf $From)"
}

function Save-Url {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$DownloadProxy
    )
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $curlArgs = @('-fsSL', '--retry', '3', '-o', $OutFile, $Url)
        if ($DownloadProxy) {
            $curlArgs = @('-fsSL', '--retry', '3', '-x', $DownloadProxy, '-o', $OutFile, $Url)
        }
        & curl.exe @curlArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Download failed (curl exit $LASTEXITCODE): $Url"
        }
        return
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $iwr = @{
        Uri             = $Url
        OutFile         = $OutFile
        UseBasicParsing = $true
    }
    if ($DownloadProxy) {
        $iwr['Proxy'] = $DownloadProxy
    }
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest @iwr
}

function Install-FlexFoxChrome {
    param(
        [string]$ProfileDir,
        [string]$DownloadProxy
    )
    $temp = Join-Path $env:TEMP ('flexfox-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp | Out-Null
    try {
        $zipPath = Join-Path $temp $flexFoxZipName
        Write-Host "Downloading FlexFox $flexFoxVersion ..."
        Save-Url -Url $flexFoxZipUrl -OutFile $zipPath -DownloadProxy $DownloadProxy
        $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
        if ($actual -ine $flexFoxSha256) {
            throw "FlexFox SHA256 mismatch. expected=$flexFoxSha256 actual=$actual"
        }
        Expand-Archive -LiteralPath $zipPath -DestinationPath (Join-Path $temp 'extracted') -Force
        $chromeSrc = Get-ChildItem -LiteralPath (Join-Path $temp 'extracted') -Recurse -Directory -Filter 'chrome' |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'userChrome.css') } |
            Select-Object -First 1
        if (-not $chromeSrc) {
            throw 'chrome/userChrome.css not found in FlexFox zip.'
        }
        $chromeDst = Join-Path $ProfileDir 'chrome'
        if (-not (Test-Path -LiteralPath $chromeDst)) {
            New-Item -ItemType Directory -Path $chromeDst -Force | Out-Null
        }
        Copy-Item -Path (Join-Path $chromeSrc.FullName '*') -Destination $chromeDst -Recurse -Force
        Write-Host "Installed FlexFox $flexFoxVersion chrome/"
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$profile = Get-FirefoxProfilePath -Requested $ProfilePath
if (-not (Test-Path -LiteralPath $profile)) {
    throw "Firefox profile not found: $profile"
}
Write-Host "Firefox profile: $profile"

if (Test-Path -LiteralPath (Join-Path $profile 'parent.lock')) {
    Write-Host 'Firefox looks running (parent.lock). CSS can still be copied; user.js applies on the next full quit/start.' -ForegroundColor Yellow
}

$downloadProxy = Get-InstallProxy
if ($InstallFlexFox) {
    if ($downloadProxy) {
        Write-Host "Using proxy: $downloadProxy"
    }
    Install-FlexFoxChrome -ProfileDir $profile -DownloadProxy $downloadProxy
}

$userChrome = Join-Path $profile 'chrome\userChrome.css'
if (-not (Test-Path -LiteralPath $userChrome)) {
    Write-Host 'chrome/userChrome.css is missing. Re-run with -InstallFlexFox to fetch the theme.' -ForegroundColor Yellow
}

foreach ($rel in $overlayFiles) {
    Copy-OverlayFile -From (Join-Path $here $rel) -To (Join-Path $profile $rel)
}

Write-Host ''
Write-Host 'Overlay applied. Fully quit Firefox and reopen so user.js takes effect.'
Write-Host 'Toggle shortcuts: see notes.txt and toggle-shortcuts.json'
