@echo off
setlocal EnableExtensions

rem Custom fzf preview script (based on chrisant996/clink-fzf).
rem Depends on: bat, chafa, eza (all on PATH).
rem Set CLINK_FZF_PREVIEW_SIXELS=1 for sixel image preview in supported terminals.

if "%~1" == "" goto :end

rem Strip fzf description suffix (at least 4 spaces before description).
set __ARG=%~1
set __DELIMITED=%__ARG:    =	%
for /f "tokens=1,2 delims=	" %%a in ("%__DELIMITED%") do (
    set "__FILE=%%a"
    set __ARG="%%a"
)

if "%__FILE%" == "" goto :end

rem Directory: list contents with eza (same as less/lessfilter.sh).
if exist %__ARG%\ (
    eza --git -ahl --color=always --icons=always %__ARG%
    goto :end
)

for %%F in (%__ARG%) do set "__EXT=%%~xF"
if not defined CLINK_PROFILE set "CLINK_PROFILE=%~dp0"

rem Binaries, aliases, Lua commands, builtins: resolve only this name (same as `which`).
if /i "%__EXT%" == ".exe" goto :preview_which
if /i "%__EXT%" == ".com" goto :preview_which
if /i "%__EXT%" == ".dll" goto :preview_which

if not exist %__ARG% goto :preview_which

rem Image preview via chafa.
if x%__ARG:~1,1% == x- goto :try_file
set __CHAFA_OPTS=
if not x%CLINK_FZF_PREVIEW_SIXELS% == x set __CHAFA_OPTS=-f sixels
2>nul chafa %__CHAFA_OPTS% %__ARG%
if not errorlevel 1 goto :end

rem Text file preview via bat.
:try_file
bat --force-colorization --style=numbers,changes --line-range=:500 -- %__ARG%
goto :end

:preview_which
set "LUA="
for /f "delims=" %%P in ('where.exe lua 2^>nul') do (
    set "LUA=%%P"
    goto :preview_which_lua
)
:preview_which_lua
if defined LUA (
    "%LUA%" "%~dp0functions\which.lua" "%__FILE%" 2>nul
    if not errorlevel 1 goto :end
)
where.exe "%__FILE%" 2>nul
if errorlevel 1 (
    if exist %__ARG% echo %__FILE%
)

:end
