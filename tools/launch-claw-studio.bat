@echo off
setlocal EnableExtensions
set "STUDIO_SCRIPT=%LOCALAPPDATA%\Programs\ClawCode\studio\ClawStudio.ps1"

if not exist "%STUDIO_SCRIPT%" (
    echo [ERROR] Claw Studio is not installed yet.
    echo Run setup.bat first, then try again.
    echo.
    cmd /k
    exit /b 1
)

start "" powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%STUDIO_SCRIPT%"
exit /b 0
