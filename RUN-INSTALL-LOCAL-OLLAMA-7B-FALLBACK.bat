@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ClawCode-Ollama.ps1" -Release -OllamaModel "qwen2.5-coder:7b"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" (
    echo Installation failed with exit code %EXITCODE%.
    echo Rerun this file after fixing the reported problem.
) else (
    echo Installation finished.
    echo Open a new PowerShell window and run:
    echo claw --version
    echo claw doctor
    echo ollama list
    echo claw --model qwen2.5-coder:7b prompt "Say hello in one short sentence."
)
echo.
pause
exit /b %EXITCODE%
