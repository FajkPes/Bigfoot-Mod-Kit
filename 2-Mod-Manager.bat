@echo off
setlocal
title Bigfoot Mod Manager
call "%~dp0_check-runtime.bat"
if errorlevel 1 exit /b 1
start "" "%~dp0BigfootModManager\BigfootModManager.exe"
exit /b 0

rem Created by FajkPes with assistance from ChatGPT Codex and Claude Code.
