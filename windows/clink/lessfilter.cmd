@echo off
setlocal EnableExtensions

rem Windows entry for less/lessfilter.sh (same as Linux LESSOPEN).
rem Prepend Git usr\bin so `file` is GNU file, not missing / WSL bash.

if "%~1" == "" exit /b 1
if not defined GIT exit /b 1

set "GIT_USR=%GIT%\usr\bin"
if not exist "%GIT_USR%\bash.exe" exit /b 1
set "PATH=%GIT_USR%;%PATH%"

set "FILTER=%DOTDIR%\less\lessfilter.sh"
if not exist "%FILTER%" set "FILTER=%~dp0..\..\less\lessfilter.sh"
if not exist "%FILTER%" exit /b 1

"%GIT_USR%\bash.exe" "%FILTER%" "%~1"
