@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Thin wrapper: shared logic lives in %DOTDIR%\fzf\vgs.lua (cmd, not Git bash).
rem   (no args)             pick and open
rem   list|path|preview|open|open-file   forwarded to vgs.lua

set "LUA="
for /f "delims=" %%P in ('where.exe lua 2^>nul') do (
	set "LUA=%%P"
	goto :have_lua
)
echo vgs: lua.exe not found 1>&2
exit /b 1

:have_lua
set "VGS_LUA="
if defined DOTDIR if exist "%DOTDIR%\fzf\vgs.lua" set "VGS_LUA=%DOTDIR%\fzf\vgs.lua"
if not defined VGS_LUA (
	if not defined CLINK_PROFILE set "CLINK_PROFILE=%~dp0"
	for %%I in ("%CLINK_PROFILE%\..\..\fzf\vgs.lua") do set "VGS_LUA=%%~fI"
)
if not exist "!VGS_LUA!" (
	echo vgs: fzf\vgs.lua not found 1>&2
	exit /b 1
)

if /i "%~1" == "list" goto :lua
if /i "%~1" == "path" goto :lua
if /i "%~1" == "preview" goto :lua
if /i "%~1" == "open" goto :lua
if /i "%~1" == "open-file" goto :lua
goto :pick

:lua
"!LUA!" "!VGS_LUA!" %*
exit /b !ERRORLEVEL!

:pick
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
	echo vgs: not a git repository 1>&2
	exit /b 1
)

set "LIST=%TEMP%\clink-vgs-!RANDOM!!RANDOM!.lst"
set "SEL=%TEMP%\clink-vgs-!RANDOM!!RANDOM!.sel"
"!LUA!" "!VGS_LUA!" list > "!LIST!"
if not exist "!LIST!" exit /b 1
for %%A in ("!LIST!") do if %%~zA==0 (
	echo vgs: working tree clean 1>&2
	del "!LIST!" 2>nul
	exit /b 0
)

set "ERR=0"
< "!LIST!" fzf.exe --ansi --nth=2.. --reverse --height 80% --preview-window=50% --preview "fzf-vgs.cmd preview {}" --bind "ctrl-/:change-preview-window(down|hidden|)" > "!SEL!"
set "ERR=!ERRORLEVEL!"
if not !ERR! == 0 goto :cleanup
if not exist "!SEL!" goto :cleanup
for %%A in ("!SEL!") do if %%~zA==0 goto :cleanup

"!LUA!" "!VGS_LUA!" open-file "!SEL!"
set "ERR=!ERRORLEVEL!"

:cleanup
del "!LIST!" 2>nul
del "!SEL!" 2>nul
exit /b !ERR!
