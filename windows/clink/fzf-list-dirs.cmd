@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "ROOT=%~1"
if "!ROOT!"=="" set "ROOT=."
call set "ROOT=!ROOT!"
if "!ROOT!"=="" set "ROOT=."

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

if "!ROOT!"=="." goto cwd
if "!ROOT:~1,1!"==":" goto abs
if /i "!ROOT:~0,2!."=="\\." goto abs
dirx.exe /b /s /X:d /a:d-s-h --bare-relative --utf8 "!ROOT!"
goto :eof

:cwd
dirx.exe /b /s /X:d /a:d-s-h --bare-relative --utf8
goto :eof

:abs
cd /d "!ROOT!" || exit /b 1
dirx.exe /b /s /X:d /a:d-s-h --bare-relative --utf8
