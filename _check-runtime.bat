@echo off
setlocal

where dotnet.exe >nul 2>nul
if errorlevel 1 goto :missing

dotnet --list-runtimes 2>nul | "%SystemRoot%\System32\findstr.exe" /B /C:"Microsoft.WindowsDesktop.App 10." >nul
if not errorlevel 1 exit /b 0

:missing
echo.
echo ERROR: Microsoft .NET 10 Desktop Runtime x64 is required.
echo Download it from Microsoft's official .NET 10 page:
echo   https://dotnet.microsoft.com/en-us/download/dotnet/10.0
echo.
choice /C YN /N /M "Open the official download page now? [Y/N] "
if errorlevel 2 exit /b 1
start "" "https://dotnet.microsoft.com/en-us/download/dotnet/10.0"
exit /b 1

rem Created by FajkPes with assistance from ChatGPT Codex and Claude Code.
