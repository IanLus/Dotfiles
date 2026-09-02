@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Ctrl+T / ** listing. --reload keeps alt-h / alt-i; otherwise reset.
rem State: hidden= / ignore= / root=  (FZF_FD_STATE or %TEMP%\fzf-fd-%USERNAME%.txt)

if not defined FZF_FD_STATE set "FZF_FD_STATE=%TEMP%\fzf-fd-%USERNAME%.txt"
for %%I in ("%FZF_FD_STATE%") do if not exist "%%~dpI" mkdir "%%~dpI" 2>nul

set "RELOAD=0"
set "ROOT="
if /i "%~1"=="--reload" (
	set "RELOAD=1"
	set "ROOT=%~2"
) else (
	set "ROOT=%~1"
)

set "HIDDEN=0"
set "IGNORE=0"
if "!RELOAD!"=="1" if exist "%FZF_FD_STATE%" (
	for /f "usebackq tokens=1* delims== eol=" %%A in ("%FZF_FD_STATE%") do (
		if /i "%%A"=="hidden" set "HIDDEN=%%B"
		if /i "%%A"=="ignore" set "IGNORE=%%B"
		if /i "%%A"=="root" if "!ROOT!"=="" set "ROOT=%%B"
	)
)

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

if not "!RELOAD!"=="1" (
	> "%FZF_FD_STATE%" (
		echo hidden=0
		echo ignore=0
		echo root=!ROOT!
	)
)

set "DIRX_ATTR=/a:-s-h"
set "DIRX_SKIP=/X:d"
set "DIRX_GIT=--git-ignore"
set "DIRX_DOT=--hide-dot-files"
if "!HIDDEN!"=="1" (
	set "DIRX_ATTR=/a:-s"
	set "DIRX_SKIP="
	set "DIRX_DOT="
)
if "!IGNORE!"=="1" (
	set "DIRX_GIT="
)
set "DIRX=dirx.exe /b /s !DIRX_SKIP! !DIRX_ATTR! !DIRX_GIT! !DIRX_DOT! -I .git --bare-relative --utf8"
set "LISTOUT=%FZF_FD_STATE%.lst"
rem dirx --git-ignore writes `debug: glob` to stdout. Filter via a file so this
rem script can itself be piped to fzf (a pipe inside a piped .cmd drops output).

if "!ROOT!"=="." goto cwd
if "!ROOT:~1,1!"==":" goto abs
if /i "!ROOT:~0,2!."=="\\." goto abs
!DIRX! "!ROOT!" > "%LISTOUT%"
goto emit

:cwd
!DIRX! > "%LISTOUT%"
goto emit

:abs
cd /d "!ROOT!" || exit /b 1
!DIRX! > "%LISTOUT%"
goto emit

:emit
if exist "%LISTOUT%" (
	findstr /v /b /c:"debug: " "%LISTOUT%"
	del /q "%LISTOUT%" 2>nul
)
