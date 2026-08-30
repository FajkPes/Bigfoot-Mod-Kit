@echo off
setlocal
title Bigfoot Mod Kit - install
echo.
echo === Installing the Bigfoot mod ===
echo.

call "%~dp0_check-runtime.bat"
if errorlevel 1 exit /b 1

rem full path to find.exe: a shell with its own find on PATH (Git Bash, MSYS)
rem would make this guard fail open and let the copy run over a live game
tasklist /FI "IMAGENAME eq Bigfoot-Win64-Shipping.exe" 2>nul | "%SystemRoot%\System32\find.exe" /I "Bigfoot-Win64" >nul
if not errorlevel 1 (
  echo ERROR: The game is running. Close it and run the installer again.
  echo.
  pause
  exit /b 1
)
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_find-game.ps1"`) do set "GAME=%%P"

if not defined GAME (
  echo ERROR: Could not find a Bigfoot installation.
  echo Check that the game is installed through Steam.
  echo.
  pause
  exit /b 1
)

echo Game found:
echo   %GAME%
echo.

if not exist "%GAME%\Bigfoot-Win64-Shipping.exe" (
  echo ERROR: Bigfoot-Win64-Shipping.exe is missing from that path.
  pause
  exit /b 1
)

if exist "%GAME%\dwmapi.dll" (
  echo ERROR: A proxy loader already exists at:
  echo   %GAME%\dwmapi.dll
  echo The installer will not overwrite an existing mod loader.
  echo Remove or back up the existing installation manually, then try again.
  pause
  exit /b 1
)
if exist "%GAME%\ue4ss" (
  echo ERROR: An existing UE4SS folder was found at:
  echo   %GAME%\ue4ss
  echo The installer will not merge with or overwrite another UE4SS setup.
  echo Back it up manually, then try again.
  pause
  exit /b 1
)

>"%GAME%\BigfootModKit.installed" echo Bigfoot Mod Kit v1.0.0 installation marker
if not exist "%GAME%\BigfootModKit.installed" (
  echo ERROR: The game folder is not writable. Try running this file as administrator.
  pause
  exit /b 1
)

echo Copying mod files...
xcopy "%~dp0GameFiles\*" "%GAME%\" /E /I /Y >nul
if errorlevel 1 (
  echo ERROR while copying. Try running this file as administrator.
  pause
  exit /b 1
)

echo.
echo Done. Installed:
echo   dwmapi.dll   ... the UE4SS loader
echo   ue4ss\       ... the loader and the BigfootTweaks mod
echo.
echo No game file was overwritten. The game still starts without the mod.
echo To disable and back up the installation, run Uninstall.bat
echo.
pause

rem Created by FajkPes with assistance from ChatGPT Codex and Claude Code.
