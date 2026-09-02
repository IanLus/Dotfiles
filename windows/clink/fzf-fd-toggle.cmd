@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem fzf transform for alt-h / alt-i: one action line, no file list.

if not defined FZF_FD_STATE set "FZF_FD_STATE=%TEMP%\fzf-fd-%USERNAME%.txt"
for %%I in ("%FZF_FD_STATE%") do if not exist "%%~dpI" mkdir "%%~dpI" 2>nul

set "CMD=%~1"
if /i not "!CMD!"=="hidden" if /i not "!CMD!"=="ignore" (
	echo usage: %~nx0 hidden^|ignore 1>&2
	exit /b 2
)

set "HIDDEN=0"
set "IGNORE=0"
set "ROOT=."
if exist "%FZF_FD_STATE%" (
	for /f "usebackq tokens=1* delims== eol=" %%A in ("%FZF_FD_STATE%") do (
		if /i "%%A"=="hidden" set "HIDDEN=%%B"
		if /i "%%A"=="ignore" set "IGNORE=%%B"
		if /i "%%A"=="root" set "ROOT=%%B"
	)
)

if /i "!CMD!"=="hidden" (
	set /a HIDDEN=1-HIDDEN
) else (
	set /a IGNORE=1-IGNORE
)

> "%FZF_FD_STATE%" (
	echo hidden=!HIDDEN!
	echo ignore=!IGNORE!
	echo root=!ROOT!
)

set "H=off"
set "I=off"
if "!HIDDEN!"=="1" set "H=on"
if "!IGNORE!"=="1" set "I=on"
echo change-header(alt-h: hidden !H! / alt-i: ignore !I!)+reload(fzf-list-files.cmd --reload)
exit /b 0
