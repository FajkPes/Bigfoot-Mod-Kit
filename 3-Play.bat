@echo off
setlocal
title Bigfoot - launch with mods
echo Launching Bigfoot through Steam, plus the Mod Manager...

call "%~dp0_check-runtime.bat"
if errorlevel 1 exit /b 1

for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_find-game.ps1"`) do set "GAME=%%P"
if defined GAME (
  if not exist "%GAME%\dwmapi.dll" (
    echo.
    echo WARNING: The mod is not installed. Run 1-Install.bat first.
    echo.
    pause
    exit /b 1
  )
)

start "" "steam://rungameid/509980"
start "" "%~dp0BigfootModManager\BigfootModManager.exe"
exit /b 0

rem Created by FajkPes with assistance from ChatGPT Codex and Claude Code.
