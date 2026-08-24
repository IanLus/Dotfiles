@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Readable paths -> eza/bat/chafa. Binaries, aliases, Lua commands -> which.

if "%~1" == "" goto :end

rem Strip fzf description suffix (at least 4 spaces before description).
set "__FILE=%~1"
set "__DELIMITED=%__FILE:    =	%"
for /f "tokens=1 delims=	" %%a in ("%__DELIMITED%") do set "__FILE=%%a"
if "!__FILE!" == "" goto :end
set "__FILE=%__FILE:/=\%"

rem Path completion after `dir\`: list items are relative to that directory.
if defined CLINK_FZF_PATH_PREFIX (
	if not exist "!__FILE!" if exist "!CLINK_FZF_PATH_PREFIX!\!__FILE!" (
		set "__FILE=!CLINK_FZF_PATH_PREFIX!\!__FILE!"
	)
)

rem Attribute first char is d for directories (junctions included). Do not use
rem "if exist path\": that is true for files whose parent is a junction
rem (pnpm node_modules), so eza prints the relative path instead of contents.
set "__ATTR="
set "__EXT="
for %%F in ("!__FILE!") do (
	set "__ATTR=%%~aF"
	set "__EXT=%%~xF"
)

if /i "!__ATTR:~0,1!" == "d" goto :preview_dir

set "__BIN="
if /i "!__EXT!" == ".exe" set "__BIN=1"
if /i "!__EXT!" == ".com" set "__BIN=1"
if /i "!__EXT!" == ".dll" set "__BIN=1"
if /i "!__EXT!" == ".sys" set "__BIN=1"
if /i "!__EXT!" == ".scr" set "__BIN=1"
if /i "!__EXT!" == ".pyd" set "__BIN=1"
if /i "!__EXT!" == ".cpl" set "__BIN=1"
if /i "!__EXT!" == ".ocx" set "__BIN=1"

if exist "!__FILE!" (
	if defined __BIN goto :preview_binary
	goto :preview_file
)

rem Missing path-like names are not commands.
for %%A in ("!__FILE!") do if /i not "%%~A" == "%%~nxA" goto :end
if "!__FILE:~1,1!" == ":" goto :end
if "!__FILE:~0,1!" == "." goto :end

goto :preview_command

:preview_dir
rem Same flags as less/lessfilter.sh, but invoked from cmd (no Git bash).
eza --git -ahl --color=always --icons=always -- "!__FILE!"
goto :end

:preview_file
if /i "!__EXT!" == ".png" goto :preview_image
if /i "!__EXT!" == ".jpg" goto :preview_image
if /i "!__EXT!" == ".jpeg" goto :preview_image
if /i "!__EXT!" == ".gif" goto :preview_image
if /i "!__EXT!" == ".webp" goto :preview_image
if /i "!__EXT!" == ".bmp" goto :preview_image
if /i "!__EXT!" == ".ico" goto :preview_image
if /i "!__EXT!" == ".tif" goto :preview_image
if /i "!__EXT!" == ".tiff" goto :preview_image
if /i "!__EXT!" == ".svg" goto :preview_image
if /i "!__EXT!" == ".avif" goto :preview_image
goto :preview_text

:preview_image
if "!__FILE:~0,1!" == "-" goto :preview_text
set "__CHAFA_OPTS="
if not "!CLINK_FZF_PREVIEW_SIXELS!" == "" set "__CHAFA_OPTS=-f sixels"
2>nul chafa !__CHAFA_OPTS! "!__FILE!"
if not errorlevel 1 goto :end

:preview_text
bat --force-colorization --style=numbers,changes --line-range=:500 -- "!__FILE!"
goto :end

:preview_binary
for %%I in ("!__FILE!") do echo %%~fI
goto :end

:preview_command
if not defined CLINK_PROFILE set "CLINK_PROFILE=%~dp0"
set "LUA="
for /f "delims=" %%P in ('where.exe lua 2^>nul') do (
	set "LUA=%%P"
	goto :preview_command_lua
)
:preview_command_lua
if not defined LUA goto :preview_which
set "__OUT=%TEMP%\clink-fzf-prev-!RANDOM!!RANDOM!.txt"
"!LUA!" "%~dp0functions\which.lua" --preview "!__FILE!" > "!__OUT!" 2>nul
if errorlevel 2 (
	del "!__OUT!" 2>nul
	goto :end
)
if errorlevel 1 (
	type "!__OUT!"
	del "!__OUT!" 2>nul
	goto :end
)
set /p __TARGET=<"!__OUT!"
del "!__OUT!" 2>nul
if not defined __TARGET goto :end
set "__FILE=!__TARGET!"
for %%F in ("!__FILE!") do set "__EXT=%%~xF"
goto :preview_file

:preview_which
where.exe "!__FILE!" 2>nul

:end
