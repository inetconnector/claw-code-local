@echo off
setlocal EnableExtensions
title Claw Code Local Ollama Manual Model Setup
cd /d "%~dp0.."

echo.
echo Select model:
echo 1 = qwen2.5-coder:7b
echo 2 = qwen2.5-coder:14b
echo 3 = qwen2.5-coder:32b
echo.
set /p CHOICE=Choice [1-3, default 2]:

if "%CHOICE%"=="1" set "MODEL=qwen2.5-coder:7b"
if "%CHOICE%"=="3" set "MODEL=qwen2.5-coder:32b"
if not defined MODEL set "MODEL=qwen2.5-coder:14b"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs" >nul 2>nul
set "LOGFILE=%~dp0..\logs\claw-code-install-manual-%DATE:~-4%-%DATE:~3,2%-%DATE:~0,2%_%TIME:~0,2%-%TIME:~3,2%-%TIME:~6,2%.log"
set "LOGFILE=%LOGFILE: =0%"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Transcript -Path $env:LOGFILE -Append | Out-Null; & '%~dp0Install-ClawCode-Ollama.ps1' -Release -OllamaModel '%MODEL%'; $code = $LASTEXITCODE; if ($null -eq $code) { $code = 0 } } catch { Write-Host ''; Write-Host '[FATAL]' $_.Exception.Message; $code = 1 } finally { try { Stop-Transcript | Out-Null } catch { } }; exit $code"

set "CLAW_BIN=%LOCALAPPDATA%\Programs\ClawCode\bin\claw.exe"
set "PATH=%LOCALAPPDATA%\Programs\ClawCode\bin;%PATH%"

echo.
echo Exit code: %ERRORLEVEL%
echo Log: %LOGFILE%
echo Test:
echo "%CLAW_BIN%" --model openai/%MODEL% prompt "Say hello in one short sentence."
echo.
cmd /k
