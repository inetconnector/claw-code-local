@echo off
setlocal EnableExtensions
set "NATIVE_LAUNCHER=%LOCALAPPDATA%\Programs\ClawCode\studio\build-run-claw-studio.bat"
set "STUDIO_SCRIPT=%LOCALAPPDATA%\Programs\ClawCode\studio\ClawStudio.ps1"

if exist "%NATIVE_LAUNCHER%" (
    call "%NATIVE_LAUNCHER%"
    exit /b %ERRORLEVEL%
)

if not exist "%STUDIO_SCRIPT%" (
    echo [ERROR] Claw Studio is not installed yet.
    echo Run setup.bat first, then try again.
    echo.
    cmd /k
    exit /b 1
)

start "" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%STUDIO_SCRIPT%"
exit /b 0
