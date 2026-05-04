@echo off
setlocal EnableExtensions
set "APP_DIR=%LOCALAPPDATA%\Programs\ClawCode\studio\ClawStudioApp"
set "APP_CSPROJ=%APP_DIR%\ClawStudioApp.csproj"
set "APP_EXE=%APP_DIR%\bin\Release\net8.0-windows\ClawStudio.exe"
set "FALLBACK_PS1=%LOCALAPPDATA%\Programs\ClawCode\studio\ClawStudio.ps1"

if not exist "%APP_CSPROJ%" (
    echo [ERROR] Native Claw Studio project is not installed.
    echo Run setup.bat first, then try again.
    echo.
    cmd /k
    exit /b 1
)

where dotnet >nul 2>nul
if errorlevel 1 (
    echo [ERROR] .NET SDK was not found. Install .NET 8 SDK or Visual Studio 2022 with .NET desktop development.
    echo Project: %APP_CSPROJ%
    echo.
    if exist "%FALLBACK_PS1%" (
        echo Starting the legacy PowerShell UI as fallback.
        start "" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%FALLBACK_PS1%"
        exit /b 0
    )
    cmd /k
    exit /b 1
)

echo Building/starting Claw Studio...
dotnet build "%APP_CSPROJ%" -c Release --nologo
if errorlevel 1 (
    echo.
    echo [ERROR] Build failed. Open this project in Visual Studio for designer/build diagnostics:
    echo %LOCALAPPDATA%\Programs\ClawCode\studio\ClawStudioApp.sln
    echo.
    cmd /k
    exit /b 1
)

if not exist "%APP_EXE%" (
    echo.
    echo [ERROR] Claw Studio build finished, but the EXE was not found:
    echo %APP_EXE%
    echo.
    cmd /k
    exit /b 1
)

echo Starting Claw Studio GUI...
start "" "%APP_EXE%"
exit /b 0
