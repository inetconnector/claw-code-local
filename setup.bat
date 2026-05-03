@echo off
setlocal EnableExtensions
title Claw Code Local Ollama Auto Setup
cd /d "%~dp0"

if not exist "%~dp0tools" (
    echo [ERROR] tools folder is missing.
    echo Please extract the complete ZIP again.
    echo.
    cmd /k
    exit /b 1
)

if not exist "%~dp0logs" mkdir "%~dp0logs" >nul 2>nul
set "LOGFILE=%~dp0logs\claw-code-install-%DATE:~-4%-%DATE:~3,2%-%DATE:~0,2%_%TIME:~0,2%-%TIME:~3,2%-%TIME:~6,2%.log"
set "LOGFILE=%LOGFILE: =0%"

echo ============================================================
echo Claw Code Local Ollama Auto Setup
echo Root stays clean: only setup.bat and README.txt are here.
echo Tools folder: %~dp0tools
echo Log: %LOGFILE%
echo.
echo The model will be selected automatically by detected GPU VRAM:
echo   under 12 GB   - qwen2.5-coder:7b
echo   12 to 19 GB   - qwen2.5-coder:14b
echo   20 GB or more - qwen2.5-coder:32b
echo ============================================================
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Transcript -Path $env:LOGFILE -Append | Out-Null; & '%~dp0tools\Install-ClawCode-Ollama.ps1' -Release -OllamaModel 'auto'; $code = $LASTEXITCODE; if ($null -eq $code) { $code = 0 } } catch { Write-Host ''; Write-Host '[FATAL]' $_.Exception.Message; $code = 1 } finally { try { Stop-Transcript | Out-Null } catch { } }; exit $code"

set "EXITCODE=%ERRORLEVEL%"
echo.
echo ============================================================
echo Installer finished with exit code %EXITCODE%.
echo Log file:
echo %LOGFILE%
echo ============================================================
echo.
echo This window will NOT close automatically.
echo.
if "%EXITCODE%"=="0" (
    echo Installation complete. Open a new PowerShell window and test:
    echo   claw --version
    echo   claw doctor
    echo   ollama list
    echo   claw --model qwen2.5-coder:14b prompt "Say hello in one short sentence."
) else (
    echo An error occurred. Use this output or the log file for troubleshooting.
)
echo.
cmd /k
