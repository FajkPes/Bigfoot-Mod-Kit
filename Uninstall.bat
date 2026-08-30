@echo off
setlocal
title Bigfoot Mod Kit - uninstall
echo.
echo === Removing the mod ===
echo.

rem full path to find.exe: a shell with its own find on PATH (Git Bash, MSYS)
rem would make this guard fail open and let the copy run over a live game
tasklist /FI "IMAGENAME eq Bigfoot-Win64-Shipping.exe" 2>nul | "%SystemRoot%\System32\find.exe" /I "Bigfoot-Win64" >nul
if not errorlevel 1 (
  echo ERROR: The game is running. Close it and run the uninstaller again.
  pause
  exit /b 1
)
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_find-game.ps1"`) do set "GAME=%%P"
if not defined GAME (
  echo ERROR: Could not find the game installation.
  pause
  exit /b 1
)

echo Removing from: %GAME%
if not exist "%GAME%\BigfootModKit.installed" (
  echo ERROR: The Bigfoot Mod Kit installation marker was not found.
  echo Nothing was changed, because the existing loader may belong to another mod setup.
  pause
  exit /b 1
)

for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "STAMP=%%T"
set "BACKUP=%GAME%\BigfootModKit-Backup-%STAMP%"
mkdir "%BACKUP%"
if errorlevel 1 (
  echo ERROR: Could not create the backup folder.
  pause
  exit /b 1
)

if exist "%GAME%\ue4ss" (
  move "%GAME%\ue4ss" "%BACKUP%\ue4ss" >nul
  if errorlevel 1 goto :backupfailed
)
if exist "%GAME%\dwmapi.dll" (
  move "%GAME%\dwmapi.dll" "%BACKUP%\dwmapi.dll" >nul
  if errorlevel 1 goto :backupfailed
)
move "%GAME%\BigfootModKit.installed" "%BACKUP%\BigfootModKit.installed" >nul
if errorlevel 1 goto :backupfailed
for %%F in ("%GAME%\BigfootTweaks_*.ini" "%GAME%\BigfootDump_*.txt") do if exist "%%~F" move "%%~F" "%BACKUP%\" >nul

echo.
echo Done. The mod is disabled and its files were preserved at:
echo   %BACKUP%
echo The game's own files were never touched.
echo.
pause
exit /b 0

:backupfailed
echo.
echo ERROR: A file could not be moved. Nothing was deleted.
echo Any files already moved are preserved at:
echo   %BACKUP%
echo Close programs using the files, then complete the backup manually.
pause
exit /b 1

rem Created by FajkPes with assistance from ChatGPT Codex and Claude Code.
