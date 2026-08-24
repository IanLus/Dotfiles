@echo off
setlocal EnableExtensions

rem Shim so fzf `--preview "less {}"` matches common_env when Git usr\bin is off PATH.
if not defined GIT exit /b 1
if not exist "%GIT%\usr\bin\less.exe" exit /b 1
"%GIT%\usr\bin\less.exe" %*
