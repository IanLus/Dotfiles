# CurrentUserAllHosts — encoding, prompt, node/zoxide, PSReadLine

$utf8 = [System.Text.UTF8Encoding]::new()
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$PSStyle.FileInfo.Directory = "`e[34;1m"

function Invoke-ProfileHook {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$Script
    )
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        return
    }
    try {
        & $Script
    } catch {
        Write-Warning "Profile hook failed ($Name): $($_.Exception.Message)"
    }
}

# Skip fancy prompt in non-VT / dumb terminals (CI, redirected hosts, etc.)
if ($env:TERM -ne 'dumb' -and $Host.UI.SupportsVirtualTerminal) {
    Invoke-ProfileHook starship {
        starship init powershell | Out-String | Invoke-Expression
    }
}

Invoke-ProfileHook fnm {
    # Align with WSL/Clink: recursive so leaving a project reverts to default.
    $fnmArgs = @('env', '--use-on-cd', '--shell', 'powershell')
    if (-not $env:FNM_VERSION_FILE_STRATEGY) {
        $fnmArgs += @('--version-file-strategy', 'recursive')
    }
    & fnm @fnmArgs | Out-String | Invoke-Expression

    # fnm leaves FNM_MULTISHELL_PATH behind. Closing a WT tab skips
    # PowerShell.Exiting; the waiter covers that. Live profile is often
    # Documents\PowerShell\profile.ps1, so do not resolve the exe via $PSScriptRoot.
    if ($env:FNM_MULTISHELL_PATH) {
        $fnmLink = $env:FNM_MULTISHELL_PATH
        Register-EngineEvent -SourceIdentifier PowerShell.Exiting -MessageData $fnmLink -Action {
            $target = $Event.MessageData
            if (-not $target -or $target -notlike '*fnm_multishells*') { return }
            try { [IO.Directory]::Delete($target) } catch {
                try { [IO.File]::Delete($target) } catch {}
            }
        } | Out-Null

        $cleanupExe = @(
            $(if ($env:CLINK_PROFILE) {
                Join-Path ([Environment]::ExpandEnvironmentVariables($env:CLINK_PROFILE)) 'tools\fnm_multishell_cleanup.exe'
            })
            $(if ($env:DOTDIR) {
                Join-Path ([Environment]::ExpandEnvironmentVariables($env:DOTDIR)) 'windows\clink\tools\fnm_multishell_cleanup.exe'
            })
            (Join-Path $PSScriptRoot '..\clink\tools\fnm_multishell_cleanup.exe')
        ) | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_) } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($cleanupExe) {
            Start-Process -FilePath $cleanupExe -ArgumentList @("$PID", $fnmLink) -WindowStyle Hidden -ErrorAction SilentlyContinue
        }
    }
}

Invoke-ProfileHook zoxide {
    zoxide init powershell | Out-String | Invoke-Expression
}

# fnm --use-on-cd only aliases `cd`. zoxide's `z` calls Set-Location directly,
# so it bypasses that alias (same class of issue as z.lua vs doskey on CMD).
# Mirror Clink onbeginedit: run fnm use whenever the location changes.
# Native fnm output must NOT enter prompt()'s success stream — PowerShell would
# treat "Using Node ..." as the prompt, leaving the cursor on that line.
if (Get-Command Set-FnmOnLoad -ErrorAction SilentlyContinue) {
    $global:__DotfilesFnmPwd = $PWD.ProviderPath
    $global:__DotfilesPromptBeforeFnm = $function:prompt
    function global:prompt {
        $prefix = ''
        $here = $PWD.ProviderPath
        if ($here -ne $global:__DotfilesFnmPwd) {
            $global:__DotfilesFnmPwd = $here
            try {
                $fnmMsg = & fnm use --silent-if-unchanged 2>&1 | Out-String
                if ($fnmMsg -and $fnmMsg.Trim()) {
                    # Must be part of prompt()'s return value. Write-Host during
                    # prompt() is ignored by PSReadLine, so the cursor stays on
                    # the "Using Node …" line (enter and leave both hit this).
                    $prefix = $fnmMsg.TrimEnd() + "`n"
                }
            } catch {
                Write-Warning "fnm use failed: $($_.Exception.Message)"
            }
        }
        $inner = ''
        if ($null -ne $global:__DotfilesPromptBeforeFnm) {
            $inner = -join @(& $global:__DotfilesPromptBeforeFnm)
        }
        return $prefix + $inner
    }
}

if (Get-Module -ListAvailable PSReadLine) {
    try {
        $psrl = @{
            HistorySearchCursorMovesToEnd = $true
            EditMode                      = 'Emacs'
            BellStyle                     = 'None'
        }
        if ($Host.UI.SupportsVirtualTerminal -and $env:TERM -ne 'dumb') {
            $psrl.PredictionSource = 'History'
            $psrl.PredictionViewStyle = 'InlineView'
        } else {
            $psrl.PredictionSource = 'None'
        }
        Set-PSReadLineOption @psrl
        Set-PSReadLineKeyHandler -Key 'Tab' -Function MenuComplete
    } catch {
        Write-Warning "PSReadLine setup skipped: $($_.Exception.Message)"
    }
}
