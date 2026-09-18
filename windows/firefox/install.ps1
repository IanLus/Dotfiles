# Overlay this folder onto the Firefox profile. Does not vendor upstream FlexFox CSS.
#   pwsh -File <dotfiles>\windows\firefox\install.ps1
#   pwsh -File <dotfiles>\windows\firefox\install.ps1 -InstallFlexFox
#
# Ctrl+J is remapped by AutoConfig next to firefox.exe (needs a full quit/start).

param(
    [string]$ProfilePath,
    [switch]$InstallFlexFox,
    [string]$Proxy,
    [switch]$NoProxy,
    [string[]]$FirefoxInstallDir,
    [switch]$SkipAutoconfig
)

$ErrorActionPreference = 'Stop'

$flexFoxVersion = 'v7.0.1'
$flexFoxZipName = 'FlexFox-v7.0.1.zip'
$flexFoxZipUrl = "https://github.com/yuuqilin/FlexFox/releases/download/$flexFoxVersion/$flexFoxZipName"
$flexFoxSha256 = '0BF871B6D8FB7D3D93ADAF2C20D05910FCE8263B99623357157FA74ECCE83BB3'
$defaultProxy = 'http://127.0.0.1:7890'
$overlayFiles = @(
    'user.js'
    'chrome\components\uc-user-settings.css'
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

    $installDefault = $null
    $currentSection = $null
    $entryPath = $null
    $entryRelative = $true
    $entryDefault = $false
    $profiles = New-Object System.Collections.Generic.List[hashtable]

    foreach ($line in Get-Content -LiteralPath $iniPath) {
        $trim = $line.Trim()
        if ($trim -match '^\[(.+)\]$') {
            if ($currentSection -like 'Profile*' -and $entryPath) {
                [void]$profiles.Add(@{
                    Path       = $entryPath
                    IsRelative = $entryRelative
                    Default    = $entryDefault
                })
            }
            $currentSection = $Matches[1]
            $entryPath = $null
            $entryRelative = $true
            $entryDefault = $false
            continue
        }
        if ($trim -notmatch '^(.*?)=(.*)$') { continue }
        $key = $Matches[1].Trim()
        $value = $Matches[2].Trim()
        if ($currentSection -like 'Install*' -and $key -eq 'Default') {
            $installDefault = $value
        }
        if ($currentSection -like 'Profile*') {
            if ($key -eq 'Path') { $entryPath = $value }
            elseif ($key -eq 'IsRelative') { $entryRelative = $value -ne '0' }
            elseif ($key -eq 'Default') { $entryDefault = $value -eq '1' }
        }
    }
    if ($currentSection -like 'Profile*' -and $entryPath) {
        [void]$profiles.Add(@{
            Path       = $entryPath
            IsRelative = $entryRelative
            Default    = $entryDefault
        })
    }

    $picked = $null
    if ($installDefault) {
        foreach ($item in $profiles) {
            if (($item.Path -replace '\\', '/') -ieq ($installDefault -replace '\\', '/')) {
                $picked = $item
                break
            }
        }
        if (-not $picked) {
            $picked = @{ Path = $installDefault; IsRelative = $true }
        }
    }
    if (-not $picked) {
        foreach ($item in $profiles) {
            if ($item.Default) {
                $picked = $item
                break
            }
        }
    }
    if (-not $picked -and $profiles.Count -gt 0) {
        $picked = $profiles[0]
    }
    if (-not $picked -or [string]::IsNullOrWhiteSpace($picked.Path)) {
        throw 'Could not determine the Firefox profile path from profiles.ini.'
    }

    $relative = $picked.Path
    if ((-not $picked.IsRelative) -or $relative -match '^[A-Za-z]:[\\/]' -or $relative.StartsWith('/')) {
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

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Text
    )
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Ensure-UserContentWallpaperImport {
    param([string]$ProfileDir)
    $path = Join-Path $ProfileDir 'chrome\userContent.css'
    $importLine = '@import url(./content/uc-custom-content.css);'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Utf8NoBom -Path $path -Text ($importLine + "`n")
        Write-Host 'Created chrome/userContent.css wallpaper import'
        return
    }
    $text = [System.IO.File]::ReadAllText($path)
    if ($text -match 'uc-custom-content\.css') {
        Write-Host 'userContent.css already imports wallpaper CSS'
        return
    }
    if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) {
        $text += "`n"
    }
    Write-Utf8NoBom -Path $path -Text ($text + $importLine + "`n")
    Write-Host 'Added wallpaper import to userContent.css'
}

function Install-HomepageWallpaper {
    param(
        [string]$HereDir,
        [string]$ProfileDir
    )
    $chrome = Join-Path $ProfileDir 'chrome'
    if (-not (Test-Path -LiteralPath $chrome)) {
        New-Item -ItemType Directory -Path $chrome -Force | Out-Null
    }
    Copy-OverlayFile -From (Join-Path $HereDir 'chrome\wallpaper.png') -To (Join-Path $chrome 'wallpaper.png')
    Copy-OverlayFile -From (Join-Path $HereDir 'chrome\wallpaper-light.png') -To (Join-Path $chrome 'wallpaper-light.png')
    # FlexFox uc.flex.newtab-background reads these names from chrome/
    Copy-OverlayFile -From (Join-Path $HereDir 'chrome\wallpaper-light.png') -To (Join-Path $chrome 'background-0.png')
    Copy-OverlayFile -From (Join-Path $HereDir 'chrome\wallpaper.png') -To (Join-Path $chrome 'background-1.png')
    Copy-OverlayFile -From (Join-Path $HereDir 'chrome\content\uc-custom-content.css') -To (Join-Path $chrome 'content\uc-custom-content.css')
    Ensure-UserContentWallpaperImport -ProfileDir $ProfileDir
    Write-Host 'Homepage wallpaper enabled'
}

function Get-FirefoxInstallDirs {
    param([string[]]$Requested)

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    function Add-Dir([string]$Dir) {
        if ([string]::IsNullOrWhiteSpace($Dir)) { return }
        try {
            $full = [IO.Path]::GetFullPath($Dir)
        } catch {
            return
        }
        if (Test-Path -LiteralPath (Join-Path $full 'firefox.exe')) {
            [void]$seen.Add($full)
        }
    }

    foreach ($dir in @($Requested)) {
        Add-Dir $dir
    }
    if ($seen.Count -gt 0) {
        return @($seen)
    }

    Get-Process -Name firefox -ErrorAction SilentlyContinue | ForEach-Object {
        try { Add-Dir (Split-Path -Parent $_.Path) } catch { }
    }

    foreach ($root in @(
            'HKLM:\SOFTWARE\Mozilla\Mozilla Firefox'
            'HKLM:\SOFTWARE\WOW6432Node\Mozilla\Mozilla Firefox'
        )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            $main = Join-Path $_.PSPath 'Main'
            if (-not (Test-Path -LiteralPath $main)) { continue }
            Add-Dir ((Get-ItemProperty -LiteralPath $main -ErrorAction SilentlyContinue).'Install Directory')
        }
        $cur = (Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue).CurrentVersion
        if ($cur) {
            $main = Join-Path $root ($cur + '\Main')
            if (Test-Path -LiteralPath $main) {
                Add-Dir ((Get-ItemProperty -LiteralPath $main -ErrorAction SilentlyContinue).'Install Directory')
            }
        }
    }

    Add-Dir (Join-Path $env:ProgramFiles 'Mozilla Firefox')
    if (${env:ProgramFiles(x86)}) {
        Add-Dir (Join-Path ${env:ProgramFiles(x86)} 'Mozilla Firefox')
    }

    $cmd = Get-Command firefox.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        Add-Dir (Split-Path -Parent $cmd.Source)
    }

    if ($seen.Count -eq 0) {
        throw 'Could not find firefox.exe. Pass -FirefoxInstallDir or use -SkipAutoconfig.'
    }
    return @($seen)
}

function Copy-AutoconfigPair {
    param(
        [string]$ConfigJs,
        [string]$ConfigPrefs,
        [string]$InstallDir
    )
    $dstPrefDir = Join-Path $InstallDir 'defaults\pref'
    if (-not (Test-Path -LiteralPath $dstPrefDir)) {
        New-Item -ItemType Directory -Path $dstPrefDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $ConfigJs -Destination (Join-Path $InstallDir 'config.js') -Force
    Copy-Item -LiteralPath $ConfigPrefs -Destination (Join-Path $dstPrefDir 'config-prefs.js') -Force
}

function Test-AccessDenied {
    param($ErrorRecord)
    $ex = $ErrorRecord.Exception
    while ($ex) {
        if ($ex -is [UnauthorizedAccessException]) { return $true }
        if ($ex.Message -match 'Access is denied|UnauthorizedAccess') { return $true }
        $ex = $ex.InnerException
    }
    return $false
}

function ConvertTo-PsSingleQuoted {
    param([string]$Value)
    "'" + ($Value -replace "'", "''") + "'"
}

function Install-FirefoxAutoconfig {
    param(
        [string]$HereDir,
        [string[]]$InstallDirs
    )
    $configJs = Join-Path $HereDir 'autoconfig\config.js'
    $configPrefs = Join-Path $HereDir 'autoconfig\defaults\pref\config-prefs.js'
    if (-not (Test-Path -LiteralPath $configJs) -or -not (Test-Path -LiteralPath $configPrefs)) {
        throw "Missing AutoConfig files under $HereDir\autoconfig"
    }

    $failed = New-Object System.Collections.Generic.List[string]
    foreach ($dir in $InstallDirs) {
        try {
            Copy-AutoconfigPair -ConfigJs $configJs -ConfigPrefs $configPrefs -InstallDir $dir
            Write-Host "AutoConfig Ctrl+J -> downloads panel: $dir"
        } catch {
            if (-not (Test-AccessDenied $_)) { throw }
            [void]$failed.Add($dir)
        }
    }
    if ($failed.Count -eq 0) {
        return
    }

    Write-Host 'Need elevation to write Firefox AutoConfig next to firefox.exe...' -ForegroundColor Yellow
    $quotedDirs = ($failed | ForEach-Object { ConvertTo-PsSingleQuoted $_ }) -join ', '
    $script = @"
`$ErrorActionPreference = 'Stop'
`$configJs = $(ConvertTo-PsSingleQuoted $configJs)
`$configPrefs = $(ConvertTo-PsSingleQuoted $configPrefs)
foreach (`$dir in @($quotedDirs)) {
    `$dstPrefDir = Join-Path `$dir 'defaults\pref'
    New-Item -ItemType Directory -Path `$dstPrefDir -Force | Out-Null
    Copy-Item -LiteralPath `$configJs -Destination (Join-Path `$dir 'config.js') -Force
    Copy-Item -LiteralPath `$configPrefs -Destination (Join-Path `$dstPrefDir 'config-prefs.js') -Force
}
"@
    $temp = Join-Path $env:TEMP ('firefox-autoconfig-' + [guid]::NewGuid().ToString('N') + '.ps1')
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($temp, $script, $utf8)
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList @(
            '-NoProfile'
            '-ExecutionPolicy'
            'Bypass'
            '-File'
            $temp
        )
        if (-not $proc -or $proc.ExitCode -ne 0) {
            throw 'Failed to install Firefox AutoConfig. Re-run from an elevated PowerShell, or pass -SkipAutoconfig.'
        }
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
    foreach ($dir in $failed) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir 'config.js'))) {
            throw "AutoConfig was not written to $dir"
        }
        Write-Host "AutoConfig Ctrl+J -> downloads panel: $dir"
    }
}

function Clear-FirefoxStartupCache {
    param([string]$ProfileDir)
    $leaf = Split-Path -Leaf $ProfileDir
    $localCache = Join-Path $env:LOCALAPPDATA "Mozilla\Firefox\Profiles\$leaf\startupCache"
    if (-not (Test-Path -LiteralPath $localCache)) {
        return
    }
    if (Test-Path -LiteralPath (Join-Path $ProfileDir 'parent.lock')) {
        return
    }
    Remove-Item -LiteralPath $localCache -Recurse -Force
    Write-Host 'Cleared Firefox startup cache'
}

function Set-ToggleShortcuts {
    param(
        [string]$ProfileDir,
        [string]$SpecPath
    )
    $spec = Get-Content -LiteralPath $SpecPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $settingsPath = Join-Path $ProfileDir 'extension-settings.json'
    $now = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        Write-Utf8NoBom -Path $settingsPath -Text '{"version":3,"url_overrides":{},"prefs":{},"default_search":{},"commands":{},"homepageNotification":{},"tabHideNotification":{},"newTabNotification":{}}'
    }
    $raw = [System.IO.File]::ReadAllText($settingsPath)
    foreach ($style in $spec.styles) {
        if ([string]::IsNullOrWhiteSpace([string]$style.shortcut)) { continue }
        $id = [string]$style.id
        $shortcut = [string]$style.shortcut
        $addonId = [string]$spec.addonId
        $needle = '"{0}":{{"precedenceList":[{{"id":"{1}"' -f $id, $addonId
        $idx = $raw.IndexOf($needle)
        if ($idx -lt 0) {
            $needle = '"' + $id + '":{"precedenceList":[{"id":"' + $addonId + '"'
            $idx = $raw.IndexOf($needle)
        }
        if ($idx -ge 0) {
            $tail = $raw.Substring($idx)
            $m = [regex]::Match($tail, '"shortcut"\s*:\s*"[^"]*"')
            if (-not $m.Success) {
                throw "Found Toggle command $id but no shortcut field in $settingsPath"
            }
            $raw = $raw.Substring(0, $idx) + $tail.Substring(0, $m.Index) + ('"shortcut":"' + $shortcut + '"') + $tail.Substring($m.Index + $m.Length)
            Write-Host "Shortcut $shortcut -> Toggle $id"
            continue
        }
        $entry = '"{0}":{{"precedenceList":[{{"id":"{1}","installDate":{2},"value":{{"shortcut":"{3}"}},"enabled":true}}]}}' -f $id, $addonId, $now, $shortcut
        if ($raw -match '"commands"\s*:\s*\{\s*\}') {
            $raw = [regex]::Replace($raw, '"commands"\s*:\s*\{\s*\}', ('"commands":{' + $entry + '}'), 1)
        } elseif ($raw -match '"commands"\s*:\s*\{') {
            $raw = [regex]::Replace($raw, '"commands"\s*:\s*\{', ('"commands":{' + $entry + ','), 1)
        } else {
            $trimmed = $raw.TrimEnd()
            if ($trimmed.EndsWith('}')) {
                $raw = $trimmed.Substring(0, $trimmed.Length - 1) + ',"commands":{' + $entry + '}}'
            } else {
                throw "Cannot insert Toggle shortcuts into $settingsPath"
            }
        }
        Write-Host "Shortcut $shortcut -> Toggle $id (inserted)"
    }
    Write-Utf8NoBom -Path $settingsPath -Text $raw
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

Install-HomepageWallpaper -HereDir $here -ProfileDir $profile
Set-ToggleShortcuts -ProfileDir $profile -SpecPath (Join-Path $here 'toggle-shortcuts.json')

if (-not $SkipAutoconfig) {
    $installDirs = Get-FirefoxInstallDirs -Requested $FirefoxInstallDir
    Install-FirefoxAutoconfig -HereDir $here -InstallDirs $installDirs
    Clear-FirefoxStartupCache -ProfileDir $profile
} else {
    Write-Host 'Skipped AutoConfig (Ctrl+J still opens the Library window).'
}

Write-Host ''
Write-Host 'Overlay applied. Fully quit Firefox and reopen so user.js, wallpaper, shortcuts, and Ctrl+J take effect.'
if (Test-Path -LiteralPath (Join-Path $profile 'parent.lock')) {
    Write-Host 'Firefox is running; quit fully before the new Ctrl+J mapping can load. If it still opens a window, use about:support -> Clear startup cache.' -ForegroundColor Yellow
}
Write-Host 'Toggle style names still need Apply changes in the extension options; see notes.txt'
