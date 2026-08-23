@echo off
setlocal EnableDelayedExpansion
set "ROOT=%~1"
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

dirx.exe /b /s /X:d /a:d-s-h --bare-relative --utf8 "!ROOT!"
