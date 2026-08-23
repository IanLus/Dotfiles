# Shared helpers for clink profile install scripts.

param(
    [string]$Proxy = 'http://127.0.0.1:7890',
    [switch]$NoProxy
)

$script:ClinkProfileDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:ClinkSoftwareRoot = if ($env:CLINK_SOFTWARE_HOME) { $env:CLINK_SOFTWARE_HOME } else { 'C:\Software\clink' }
$script:SoftwareRoot = if ($env:SOFTWARE_HOME) { $env:SOFTWARE_HOME } else { 'C:\Software' }
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
    $dir = Find-ClinkInstallDir
    if (-not $dir) {
        return $null
    }
    if (-not (Get-Command clink -ErrorAction SilentlyContinue)) {
        Add-UserPathEntry -Dir $dir
    }
    return (Get-ClinkCommandPath)
}

function Invoke-ClinkSet {
    param(
        [string]$Name,
        [string]$Value
    )
    $clink = Ensure-ClinkAvailable
    if (-not $clink) {
        Write-Warning "clink not found; skip: clink set $Name $Value"
        return $false
    }
    & $clink set $Name $Value | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "clink set $Name $Value failed (exit $LASTEXITCODE)"
        return $false
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
            Write-Host "Updating $Repo ..."
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
