@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "ROOT=%~1"
if "!ROOT!"=="" set "ROOT=."
call set "ROOT=!ROOT!"
if "!ROOT!"=="" set "ROOT=."

rem `"windows\"` would make dirx print `windows\\foo`. Trailing slashes must go.
:strip
if "!ROOT!"=="" set "ROOT=."
if "!ROOT:~-1!"=="\" (
	set "ROOT=!ROOT:~0,-1!"
	goto strip
)
if "!ROOT:~-1!"=="/" (
	set "ROOT=!ROOT:~0,-1!"
	goto strip
)

rem Relative ROOT (`windows`) is listed from cwd so fzf inserts `windows\foo`.
rem Absolute ROOT (`%DOTDIR%` expanded) must be cwd, or dirx prints full paths
rem and `**<Tab>` after `%DOTDIR%\` would insert `C:\...\file`.
if "!ROOT:~1,1!"==":" goto abs
if /i "!ROOT:~0,2!."=="\\." goto abs
dirx.exe /b /s /X:d /a:-s-h --bare-relative --utf8 "!ROOT!"
goto :eof

:abs
cd /d "!ROOT!" || exit /b 1
dirx.exe /b /s /X:d /a:-s-h --bare-relative --utf8
