@echo off
setlocal EnableDelayedExpansion
set "ROOT=%~1"
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

rem Stay in the caller's cwd so `windows\**<Tab>` lists `windows\foo` (pwd-relative).
dirx.exe /b /s /X:d /a:-s-h --bare-relative --utf8 "!ROOT!"
