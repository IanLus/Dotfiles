# Shared helpers for clink profile install scripts.

param(
    [string]$Proxy = 'http://127.0.0.1:7890',
    [switch]$NoProxy
)

$script:ClinkProfileDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:SoftwareRoot = if ($env:SOFTWARE_HOME) { $env:SOFTWARE_HOME } else { 'C:\Software' }
# Clink itself lives at C:\Software\clink. Third-party repos (z.lua / clink-fzf / clink-gizmos) go here.
$script:ClinkSoftwareRoot = if ($env:CLINK_SOFTWARE_HOME) { $env:CLINK_SOFTWARE_HOME } else { Join-Path $script:SoftwareRoot 'clink-plugins' }
$script:InstallProxy = if ($NoProxy) { $null } else { $Proxy }

function Add-UserPathEntry {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }
    $Dir = (Resolve-Path -LiteralPath $Dir).Path
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    $parts = $userPath -split ';' | Where-Object { $_ -and $_.Trim() -ne '' }
    foreach ($part in $parts) {
        if ($part.TrimEnd('\') -ieq $Dir.TrimEnd('\')) {
            Write-Host "PATH already contains $Dir"
            return
        }
    }
    $newPath = if ($userPath.Trim()) { "$Dir;$userPath" } else { $Dir }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    if ($env:Path -notlike "*$Dir*") {
        $env:Path = "$Dir;$env:Path"
    }
    Write-Host "Added to user PATH: $Dir" -ForegroundColor Green
}

function Remove-UserPathEntry {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return }
    $want = $Dir.TrimEnd('\')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { return }
    $kept = [System.Collections.Generic.List[string]]::new()
    $removed = $false
    foreach ($part in ($userPath -split ';')) {
        if (-not $part -or $part.Trim() -eq '') { continue }
        if ($part.TrimEnd('\') -ieq $want) {
            $removed = $true
            continue
        }
        $kept.Add($part)
    }
    if (-not $removed) { return }
    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
    $env:Path = (
        ($env:Path -split ';') |
        Where-Object { $_ -and $_.TrimEnd('\') -ine $want }
    ) -join ';'
    Write-Host "Removed from user PATH: $Dir" -ForegroundColor Yellow
}

function Write-InstallSet {
    param(
        [string]$Name,
        [string]$Value
    )
    Write-Host -NoNewline '已设置 '
    Write-Host -NoNewline $Name -ForegroundColor Cyan
    Write-Host -NoNewline ' = '
    Write-Host $Value -ForegroundColor Green
}

function Find-ClinkInstallDir {
    $cmd = Get-Command clink -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        return Split-Path -Parent $cmd.Source
    }
    $candidates = @(
        $env:CLINK_DIR
        (Join-Path $script:SoftwareRoot 'clink')
        "${env:ProgramFiles(x86)}\clink"
        "$env:ProgramFiles\clink"
    ) | Where-Object { $_ }
    foreach ($dir in $candidates) {
        foreach ($name in @('clink.exe', 'clink.bat', 'clink.cmd')) {
            if (Test-Path -LiteralPath (Join-Path $dir $name)) {
                return (Resolve-Path -LiteralPath $dir).Path
            }
        }
    }
    return $null
}

function Get-ClinkCommandPath {
    $cmd = Get-Command clink -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        return $cmd.Source
    }
    $dir = Find-ClinkInstallDir
    if (-not $dir) {
        return $null
    }
    foreach ($name in @('clink.bat', 'clink.exe', 'clink.cmd')) {
        $p = Join-Path $dir $name
        if (Test-Path -LiteralPath $p) {
            return $p
        }
    }
    return $null
}

function Ensure-ClinkAvailable {
    Use-ClinkProfileEnv
    $dir = Find-ClinkInstallDir
    if (-not $dir) {
        Refresh-SessionPath
        $dir = Find-ClinkInstallDir
    }
    if (-not $dir) {
        return $null
    }
    if (-not (Get-Command clink -ErrorAction SilentlyContinue)) {
        Add-UserPathEntry -Dir $dir
    }
    return (Get-ClinkCommandPath)
}

function Use-ClinkProfileEnv {
    $env:CLINK_PROFILE = $script:ClinkProfileDir
}

function Refresh-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($machine -or $user) {
        $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
    }
}

function Get-PersistentEnv {
    param([string]$Name)
    $user = [Environment]::GetEnvironmentVariable($Name, 'User')
    if (-not [string]::IsNullOrWhiteSpace($user)) { return $user }
    $machine = [Environment]::GetEnvironmentVariable($Name, 'Machine')
    if (-not [string]::IsNullOrWhiteSpace($machine)) { return $machine }
    return [Environment]::GetEnvironmentVariable($Name, 'Process')
}

function Set-UserEnvVar {
    param(
        [string]$Name,
        [string]$Value,
        [switch]$Overwrite
    )
    $existing = Get-PersistentEnv -Name $Name
    if (-not $Overwrite -and -not [string]::IsNullOrWhiteSpace($existing)) {
        Write-Host "Keep $Name = $existing"
        return $existing
    }
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    Set-Item -Path "Env:$Name" -Value $expanded
    Write-InstallSet -Name $Name -Value $Value
    return $Value
}

function Ensure-DotDirAndClinkProfile {
    $dotDir = Split-Path -Parent (Split-Path -Parent $script:ClinkProfileDir)
    if (-not (Get-PersistentEnv -Name 'DOTDIR')) {
        Set-UserEnvVar -Name 'DOTDIR' -Value $dotDir | Out-Null
    }
    if (-not (Get-PersistentEnv -Name 'CLINK_PROFILE')) {
        Set-UserEnvVar -Name 'CLINK_PROFILE' -Value '%DOTDIR%\windows\clink' | Out-Null
    }
    Use-ClinkProfileEnv
}

function Invoke-Clink {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ClinkArgs)
    Use-ClinkProfileEnv
    $clink = Ensure-ClinkAvailable
    if (-not $clink) {
        Write-Warning "clink not found; skip: clink $($ClinkArgs -join ' ')"
        return $false
    }
    $prev = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        & $clink @ClinkArgs
        return $LASTEXITCODE -eq 0
    } finally {
        $PSNativeCommandUseErrorActionPreference = $prev
    }
}

function Invoke-ClinkSet {
    param(
        [string]$Name,
        [string]$Value
    )
    Use-ClinkProfileEnv
    $clink = Ensure-ClinkAvailable
    if (-not $clink) {
        Write-Warning "clink not found; skip: clink set $Name $Value"
        return $false
    }
    $prev = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        & $clink set $Name $Value | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "clink set $Name $Value failed (exit $LASTEXITCODE)"
            return $false
        }
    } finally {
        $PSNativeCommandUseErrorActionPreference = $prev
    }
    Write-InstallSet -Name $Name -Value $Value
    return $true
}

function Use-InstallProxy {
    if (-not $script:InstallProxy) { return }
    $env:HTTP_PROXY = $script:InstallProxy
    $env:HTTPS_PROXY = $script:InstallProxy
    $env:ALL_PROXY = $script:InstallProxy
    Write-Host "Using proxy: $($script:InstallProxy)"
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    Use-InstallProxy
    if ($script:InstallProxy) {
        & git -c "http.proxy=$($script:InstallProxy)" -c "https.proxy=$($script:InstallProxy)" @Args
    } else {
        & git @Args
    }
    if ($LASTEXITCODE -ne 0) { throw "git $($Args -join ' ') failed (exit $LASTEXITCODE)" }
}

function Ensure-GitRepo {
    param(
        [string]$Repo,
        [string]$CloneUrl
    )
    if (Test-Path -LiteralPath (Join-Path $Repo '.git') -PathType Container) {
        $head = Invoke-Git -Args @('-C', $Repo, 'rev-parse', 'HEAD') 2>$null
        if (-not $head) {
            Write-Host "Removing incomplete repo at $Repo ..."
            Remove-Item -LiteralPath $Repo -Recurse -Force
        } else {
            Write-Host "Updating $Repo (git pull) ..."
            Invoke-Git -Args @('-C', $Repo, 'pull', '--ff-only')
            return
        }
    }
    $parent = Split-Path -Parent $Repo
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Write-Host "Cloning $CloneUrl into $Repo ..."
    Invoke-Git -Args @('clone', $CloneUrl, $Repo)
}

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CanCreateSymbolicLink {
    $probe = Join-Path $env:TEMP ('clink-slink-' + [guid]::NewGuid().ToString('N'))
    $target = Join-Path $env:TEMP ('clink-slink-t-' + [guid]::NewGuid().ToString('N'))
    try {
        [void][System.IO.File]::WriteAllText($target, '')
        New-Item -ItemType SymbolicLink -Path $probe -Target $target -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-SymbolicLinkPrivilege {
    param(
        [System.Collections.IDictionary]$BoundParameters
    )
    if (Test-CanCreateSymbolicLink) {
        return
    }
    if (Test-IsAdministrator) {
        throw 'Cannot create symbolic links even as Administrator. Enable Windows Developer Mode.'
    }

    $caller = $MyInvocation.PSCommandPath
    if (-not $caller) {
        throw 'Cannot create symbolic links, and the calling script path is unknown.'
    }

    $shell = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $shell) {
        $shell = Get-Command powershell -ErrorAction SilentlyContinue
    }
    if (-not $shell) {
        throw 'Cannot create symbolic links: pwsh/powershell not found for elevation.'
    }

    $argList = [System.Collections.Generic.List[string]]::new()
    $null = $argList.Add('-NoProfile')
    $null = $argList.Add('-ExecutionPolicy')
    $null = $argList.Add('Bypass')
    $null = $argList.Add('-File')
    $null = $argList.Add($caller)
    if ($BoundParameters) {
        foreach ($key in $BoundParameters.Keys) {
            $val = $BoundParameters[$key]
            if ($val -is [System.Management.Automation.SwitchParameter]) {
                if ($val.IsPresent) { $null = $argList.Add("-$key") }
                continue
            }
            if ($val -is [bool]) {
                if ($val) { $null = $argList.Add("-$key") }
                continue
            }
            if ($null -eq $val -or ($val -is [string] -and $val -eq '')) {
                continue
            }
            $null = $argList.Add("-$key")
            if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                foreach ($item in $val) { $null = $argList.Add([string]$item) }
            } else {
                $null = $argList.Add([string]$val)
            }
        }
    }

    Write-Host '当前无权创建符号链接，正在打开提权窗口...' -ForegroundColor Yellow
    try {
        $proc = Start-Process -FilePath $shell.Source -ArgumentList $argList.ToArray() -Verb RunAs -Wait -PassThru
    } catch {
        throw "Elevation cancelled or failed: $($_.Exception.Message)"
    }
    if ($null -eq $proc) {
        throw 'Elevation failed.'
    }
    exit $proc.ExitCode
}

function New-ProfileSymlink {
    param(
        [string]$ProfileDir,
        [string]$Name,
        [string]$Target
    )
    $link = Join-Path $ProfileDir $Name
    if (-not (Test-Path -LiteralPath $Target)) {
        throw "Missing upstream file: $Target"
    }
    $targetPath = (Resolve-Path -LiteralPath $Target).Path
    if (Test-Path -LiteralPath $link) {
        Remove-Item -LiteralPath $link -Force
    }
    try {
        New-Item -ItemType SymbolicLink -Path $link -Target $targetPath -ErrorAction Stop | Out-Null
        Write-Host "Symlinked $Name -> $targetPath"
    } catch {
        throw @"
Failed to create symlink for $Name.
Enable Windows Developer Mode, or run PowerShell as Administrator, then retry.
$($_.Exception.Message)
"@
    }
}

function ConvertTo-InstallVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '(\d+)\.(\d+)(?:\.(\d+))?(?:\.(\d+))?')
    if (-not $m.Success) { return $null }
    $build = if ($m.Groups[3].Success) { [int]$m.Groups[3].Value } else { 0 }
    $rev = if ($m.Groups[4].Success) { [int]$m.Groups[4].Value } else { 0 }
    return [version]::new([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, $build, $rev)
}

function Format-InstallVersion {
    param($Version, [string]$Fallback)
    if ($Version -is [version]) {
        if ($Version.Build -le 0 -and $Version.Revision -le 0) {
            return '{0}.{1}' -f $Version.Major, $Version.Minor
        }
        if ($Version.Revision -le 0) {
            return '{0}.{1}.{2}' -f $Version.Major, $Version.Minor, $Version.Build
        }
        return $Version.ToString()
    }
    if (-not [string]::IsNullOrWhiteSpace($Fallback)) { return $Fallback }
    return '未知版本'
}

function Invoke-WingetText {
    param([string[]]$WingetArgs)
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget not found'
    }
    Use-InstallProxy
    $prev = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $text = & winget @WingetArgs 2>&1 | ForEach-Object { "$_" } | Out-String
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Text     = $text
        }
    } finally {
        $PSNativeCommandUseErrorActionPreference = $prev
    }
}

function Get-WingetFieldVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '(?im)^\s*(?:Version|版本)\s*:\s*(\S+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-WingetAvailableVersion {
    param([string]$Id)
    $r = Invoke-WingetText -WingetArgs @(
        'show', '-e', '--id', $Id, '--source', 'winget',
        '--accept-source-agreements', '--disable-interactivity'
    )
    if ($r.ExitCode -ne 0) { return $null }
    return (Get-WingetFieldVersion -Text $r.Text)
}

function Get-WingetInstalledVersion {
    param([string]$Id)
    $r = Invoke-WingetText -WingetArgs @(
        'list', '-e', '--id', $Id, '--source', 'winget',
        '--accept-source-agreements', '--disable-interactivity'
    )
    if ($r.ExitCode -ne 0) { return $null }
    if ($r.Text -match 'No installed package found|找不到与输入条件匹配的已安装') {
        return $null
    }
    $found = $null
    $idRe = [regex]::Escape($Id) + '\s+(\S+)'
    foreach ($line in ($r.Text -split '\r?\n')) {
        if ($line -match $idRe) {
            $found = $Matches[1]
        }
    }
    return $found
}

function Find-InstallExe {
    param(
        [string]$InstallDir,
        [string[]]$ExeName
    )
    if (-not (Test-Path -LiteralPath $InstallDir)) { return $null }
    foreach ($name in $ExeName) {
        $direct = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $direct) {
            return (Resolve-Path -LiteralPath $direct).Path
        }
    }
    foreach ($name in $ExeName) {
        $found = Get-ChildItem -LiteralPath $InstallDir -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Confirm-SoftwareUpdate {
    param(
        [string]$Name,
        [string]$CurrentLabel,
        [string]$TargetLabel
    )
    Write-Host -NoNewline "已安装 $Name "
    Write-Host -NoNewline $CurrentLabel -ForegroundColor Yellow
    Write-Host -NoNewline '，最新为 '
    Write-Host $TargetLabel -ForegroundColor Green
    $ans = Read-Host "是否更新到 $TargetLabel？[Y/n]"
    return [string]::IsNullOrWhiteSpace($ans) -or $ans -match '^[Yy]'
}

function Confirm-WingetLocationIgnored {
    param(
        [string]$Name,
        [string]$InstallDir
    )
    Write-Host "winget 安装 $Name 时 --location 无效，不会装到 $InstallDir，一般会落到 Program Files。" -ForegroundColor Yellow
    $ans = Read-Host "是否仍用 winget 继续安装 $Name？[Y/n]"
    return [string]::IsNullOrWhiteSpace($ans) -or $ans -match '^[Yy]'
}

function Invoke-WingetLocate {
    param(
        [string]$Id,
        [string]$Location,
        [string]$Version,
        [switch]$Upgrade
    )
    $base = @(
        $(if ($Upgrade) { 'upgrade' } else { 'install' })
        '-e', '--id', $Id, '--source', 'winget'
        '--accept-package-agreements', '--accept-source-agreements'
        '--disable-interactivity'
        '--location', $Location
        '--force'
    )
    if ($Version) {
        $base += @('--version', $Version)
    }

    $withScope = $base + @('--scope', 'user')
    Write-Host "winget $($withScope -join ' ')"
    $r = Invoke-WingetText -WingetArgs $withScope
    if ($r.ExitCode -eq 0) { return $true }

    Write-Host 'Retry without --scope user ...'
    $r = Invoke-WingetText -WingetArgs $base
    if ($r.ExitCode -eq 0) { return $true }

    Write-Host $r.Text
    return $false
}

function Add-InstallExePath {
    param([string]$ExePath)
    if (-not $ExePath) { return }
    Add-UserPathEntry -Dir (Split-Path -Parent $ExePath)
}

function Install-WingetSoftware {
    param(
        [string]$Id,
        [string]$Name,
        [string[]]$ExeName,
        [string]$DirName,
        [string]$Version,
        [switch]$LocationIgnored
    )
    $installDir = Join-Path $script:SoftwareRoot $DirName
    $exe = Find-InstallExe -InstallDir $installDir -ExeName $ExeName
    $exeLabel = $ExeName -join '/'
    $explicitVersion = -not [string]::IsNullOrWhiteSpace($Version)
    $targetTag = if ($explicitVersion) { $Version } else { $null }

    if (-not $explicitVersion) {
        Write-Host "查询 $Name 最新版本..."
        $targetTag = Get-WingetAvailableVersion -Id $Id
        if (-not $targetTag) {
            if ($exe) {
                Add-InstallExePath -ExePath $exe
                Write-Warning "无法查询 $Name 最新版本，保留已安装的 $exe"
                return
            }
            throw "无法查询 $Name 最新版本，且未在 $installDir 找到 $exeLabel。检查网络或代理后重试，或使用 -Version 指定版本。"
        }
        Write-Host -NoNewline '最新版本: '
        Write-Host $targetTag -ForegroundColor Green
    }

    $targetVer = ConvertTo-InstallVersion $targetTag
    if ($exe) {
        $installedTag = Get-WingetInstalledVersion -Id $Id
        $installedVer = ConvertTo-InstallVersion $installedTag
        Add-InstallExePath -ExePath $exe
        if (-not $explicitVersion -and $installedVer -and $targetVer -and $installedVer -ge $targetVer) {
            Write-Host "$Name 已是最新版本: $(Format-InstallVersion $installedVer $installedTag) ($exe)"
            return
        }
        if (-not $explicitVersion -and $installedTag -and $targetTag -and $installedTag -ieq $targetTag) {
            Write-Host "$Name 已是最新版本: $installedTag ($exe)"
            return
        }
        $currentLabel = if ($installedTag) { $installedTag } else { '未知版本' }
        if (-not (Confirm-SoftwareUpdate -Name $Name -CurrentLabel $currentLabel -TargetLabel $targetTag)) {
            Write-Host "跳过更新，保留 $currentLabel"
            return
        }
        if (-not (Invoke-WingetLocate -Id $Id -Location $installDir -Version $targetTag -Upgrade)) {
            if (-not (Invoke-WingetLocate -Id $Id -Location $installDir -Version $targetTag)) {
                throw "winget 更新 $Name ($Id) 失败"
            }
        }
    } else {
        if ($LocationIgnored) {
            if (-not (Confirm-WingetLocationIgnored -Name $Name -InstallDir $installDir)) {
                Write-Host "跳过安装 $Name"
                return
            }
        }
        if (-not (Test-Path -LiteralPath $installDir)) {
            New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        }
        if (-not (Invoke-WingetLocate -Id $Id -Location $installDir -Version $targetTag)) {
            throw "winget 安装 $Name ($Id) 到 $installDir 失败"
        }
    }

    Refresh-SessionPath
    $exe = Find-InstallExe -InstallDir $installDir -ExeName $ExeName
    if (-not $exe -and $LocationIgnored) {
        foreach ($name in $ExeName) {
            $cmd = Get-Command $name -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source) {
                $exe = $cmd.Source
                break
            }
        }
        if ($exe) {
            Write-Warning "$Name 已安装，但不在 $installDir：$exe"
        }
    }
    if (-not $exe) {
        throw "$Name 已通过 winget 处理，但 $installDir 下没有 $exeLabel"
    }
    Add-InstallExePath -ExePath $exe
    Write-Host "Installed $Name $targetTag -> $exe" -ForegroundColor Green
}

function Install-ClinkIfMissing {
    try {
        Install-WingetSoftware -Id 'chrisant996.Clink' -Name 'clink' -ExeName @('clink.exe', 'clink.bat', 'clink.cmd') -DirName 'clink'
    } catch {
        Write-Warning $_.Exception.Message
        return $false
    }
    Refresh-SessionPath
    Ensure-ClinkAvailable | Out-Null
    if (-not (Find-ClinkInstallDir)) {
        Write-Warning 'Clink was installed but clink.exe is not on PATH yet. Restart the terminal and re-run.'
        return $false
    }
    return $true
}

function Find-Gcc {
    if ($env:CC) {
        $cc = Get-Command $env:CC -ErrorAction SilentlyContinue
        if ($cc) { return $cc.Source }
        if (Test-Path -LiteralPath $env:CC) { return $env:CC }
    }
    $gcc = Get-Command gcc -ErrorAction SilentlyContinue
    if ($gcc) { return $gcc.Source }
    $candidates = @(
        $(if ($env:GIT) { Join-Path $env:GIT 'mingw64\bin\gcc.exe' })
        'C:\Program Files\Git\mingw64\bin\gcc.exe'
        'C:\Software\mingw64\bin\gcc.exe'
    ) | Where-Object { $_ }
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Test-ShouldRebuild {
    param(
        [string]$Exe,
        [string]$Source
    )
    if (-not (Test-Path -LiteralPath $Exe)) { return $true }
    if (-not (Test-Path -LiteralPath $Source)) { return $false }
    return (Get-Item -LiteralPath $Source).LastWriteTime -gt (Get-Item -LiteralPath $Exe).LastWriteTime
}

function Build-ClinkTools {
    param([switch]$Force)
    $gcc = Find-Gcc
    if (-not $gcc) {
        Write-Warning 'gcc not found; skip tools/*.exe. Install MinGW or Git for Windows, or set CC.'
        return $false
    }
    $tools = Join-Path $script:ClinkProfileDir 'tools'
    if (-not (Test-Path -LiteralPath $tools)) {
        New-Item -ItemType Directory -Path $tools -Force | Out-Null
    }

    $jobs = @(
        @{
            Src = Join-Path $tools 'set_console_utf8.c'
            Exe = Join-Path $tools 'set_console_utf8.exe'
            Args = @('-O2', '-s', '-o')
        }
        @{
            Src = Join-Path $tools 'fnm_multishell_cleanup.c'
            Exe = Join-Path $tools 'fnm_multishell_cleanup.exe'
            Args = @('-O2', '-s', '-mwindows', '-o')
            Libs = @('-lshell32')
        }
    )

    $ok = $true
    foreach ($job in $jobs) {
        if (-not (Test-Path -LiteralPath $job.Src)) {
            Write-Warning "Missing $($job.Src)"
            $ok = $false
            continue
        }
        if (-not $Force -and -not (Test-ShouldRebuild -Exe $job.Exe -Source $job.Src)) {
            Write-Host "Up to date: $($job.Exe)"
            continue
        }
        $gccArgs = @($job.Args) + @($job.Exe, $job.Src)
        if ($job.Libs) { $gccArgs += $job.Libs }
        Write-Host "gcc $($gccArgs -join ' ')"
        $prev = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
        try {
            & $gcc @gccArgs
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "gcc failed for $($job.Src) (exit $LASTEXITCODE)"
                $ok = $false
                continue
            }
        } finally {
            $PSNativeCommandUseErrorActionPreference = $prev
        }
        Write-Host "Built $($job.Exe)" -ForegroundColor Green
    }
    return $ok
}

function Set-ClinkCoreSettings {
    $settings = @(
        @{ Name = 'autosuggest.enable'; Value = 'True' }
        @{ Name = 'autosuggest.inline'; Value = 'True' }
        @{ Name = 'autosuggest.strategy'; Value = 'match_prev_cmd history completion' }
        @{ Name = 'clink.default_bindings'; Value = 'bash' }
        @{ Name = 'clink.logo'; Value = 'none' }
        @{ Name = 'cmd.ctrld_exits'; Value = 'True' }
        @{ Name = 'history.max_lines'; Value = '25000' }
        @{ Name = 'history.time_stamp'; Value = 'show' }
        @{ Name = 'match.expand_envvars'; Value = 'True' }
        @{ Name = 'match.substring'; Value = 'True' }
        @{ Name = 'color.arginfo'; Value = 'sgr 38;5;172' }
        @{ Name = 'color.argmatcher'; Value = 'sgr 1;38;5;40' }
        @{ Name = 'color.cmdredir'; Value = 'sgr 38;5;172' }
        @{ Name = 'color.cmdsep'; Value = 'sgr 38;5;135' }
        @{ Name = 'color.comment_row'; Value = 'sgr 38;5;87;48;5;18' }
        @{ Name = 'color.description'; Value = 'sgr 38;5;39' }
        @{ Name = 'color.doskey'; Value = 'sgr 1;38;5;75' }
        @{ Name = 'color.executable'; Value = 'sgr 1;38;5;33' }
        @{ Name = 'color.flag'; Value = 'sgr 38;5;117' }
        @{ Name = 'color.hidden'; Value = 'sgr 38;5;160' }
        @{ Name = 'color.histexpand'; Value = 'sgr 97;48;5;55' }
        @{ Name = 'color.horizscroll'; Value = 'sgr 38;5;16;48;5;30' }
        @{ Name = 'color.input'; Value = 'sgr 38;5;214' }
        @{ Name = 'color.readonly'; Value = 'sgr 38;5;28' }
        @{ Name = 'color.selection'; Value = 'sgr 38;5;16;48;5;179' }
        @{ Name = 'color.suggestionlist_dim'; Value = 'sgr 38;5;242' }
        @{ Name = 'color.suggestionlist_highlight'; Value = 'sgr 38;5;87' }
        @{ Name = 'color.suggestionlist_markup'; Value = 'sgr 38;2;253;174;31' }
        @{ Name = 'color.suggestionlist_selected'; Value = 'sgr 48;5;238' }
        @{ Name = 'color.unrecognized'; Value = 'sgr 38;5;203' }
    )
    foreach ($item in $settings) {
        Invoke-ClinkSet -Name $item.Name -Value $item.Value | Out-Null
    }
}

function Set-ClinkStarshipPrompt {
    Use-ClinkProfileEnv
    $clink = Ensure-ClinkAvailable
    if (-not $clink) {
        Write-Warning 'clink not found; skip: clink config prompt use starship'
        return $false
    }
    $prev = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        & $clink config prompt use starship | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "clink config prompt use starship failed (exit $LASTEXITCODE)"
            return $false
        }
    } finally {
        $PSNativeCommandUseErrorActionPreference = $prev
    }
    Write-InstallSet -Name 'clink.customprompt' -Value 'starship'
    return $true
}

function Set-ClinkFzfSettings {
    Invoke-ClinkSet -Name 'fzf.default_bindings' -Value 'True' | Out-Null
    Invoke-ClinkSet -Name 'fzf_git.default_bindings' -Value 'True' | Out-Null
    Invoke-ClinkSet -Name 'fzf.height' -Value '80%' | Out-Null
    Invoke-ClinkSet -Name 'fzf_git.height' -Value '50%' | Out-Null
    Invoke-ClinkSet -Name 'fzf_rg.show_preview' -Value 'right' | Out-Null
    Invoke-ClinkSet -Name 'fzf_rg.height' -Value '75%' | Out-Null
    Invoke-ClinkSet -Name 'fzf_rg.editor' -Value 'nvim {file} +{line}' | Out-Null
}

function Ensure-FzfExe {
    try {
        Install-WingetSoftware -Id 'junegunn.fzf' -Name 'fzf' -ExeName 'fzf.exe' -DirName 'fzf'
        return $true
    } catch {
        Write-Warning $_.Exception.Message
        return $false
    }
}

function Test-LooksLikeClinkPluginsDir {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return $false }
    foreach ($name in @('clink.exe', 'clink.bat', 'clink.cmd', 'clink_x64.exe')) {
        if (Test-Path -LiteralPath (Join-Path $Dir $name)) { return $false }
    }
    foreach ($name in @('z.lua', 'clink-fzf', 'clink-gizmos', 'fzf', 'gizmos')) {
        if (Test-Path -LiteralPath (Join-Path $Dir $name)) { return $true }
    }
    return $false
}

function Move-LegacyClinkPluginsRoot {
    if ($env:CLINK_SOFTWARE_HOME) { return }
    $legacy = Join-Path $script:SoftwareRoot 'clink'
    $dest = $script:ClinkSoftwareRoot
    if (-not (Test-LooksLikeClinkPluginsDir $legacy)) { return }
    if (Test-Path -LiteralPath $dest) {
        Write-Warning "$legacy still holds plugins, but $dest already exists. Move the plugins out so $legacy can be Clink."
        return
    }
    Write-Host "Renaming plugin root $legacy -> $dest"
    try {
        Rename-Item -LiteralPath $legacy -NewName (Split-Path -Leaf $dest) -ErrorAction Stop
        return
    } catch {
        Write-Host "Rename-Item denied; moving children instead."
    }
    if (-not (Test-Path -LiteralPath $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }
    Get-ChildItem -LiteralPath $legacy -Force | ForEach-Object {
        Move-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
    }
    Remove-Item -LiteralPath $legacy -Force
}

function Move-LegacyPluginRepoDir {
    param(
        [string]$OldName,
        [string]$NewName
    )
    $old = Join-Path $script:ClinkSoftwareRoot $OldName
    $new = Join-Path $script:ClinkSoftwareRoot $NewName
    if (-not (Test-Path -LiteralPath $old)) { return }
    if (Test-Path -LiteralPath $new) {
        Write-Warning "Both $old and $new exist; keeping $new"
        return
    }
    Write-Host "Renaming plugin repo $old -> $new"
    try {
        Rename-Item -LiteralPath $old -NewName $NewName -ErrorAction Stop
        return
    } catch {
        Write-Host "Rename-Item denied; moving children instead."
    }
    New-Item -ItemType Directory -Path $new -Force | Out-Null
    Get-ChildItem -LiteralPath $old -Force | ForEach-Object {
        Move-Item -LiteralPath $_.FullName -Destination (Join-Path $new $_.Name) -Force
    }
    Remove-Item -LiteralPath $old -Force
}

Move-LegacyClinkPluginsRoot
Move-LegacyPluginRepoDir -OldName 'fzf' -NewName 'clink-fzf'
Move-LegacyPluginRepoDir -OldName 'gizmos' -NewName 'clink-gizmos'
