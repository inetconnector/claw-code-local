@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ClawCode-Ollama.ps1" -Release -OllamaModel "qwen2.5-coder:32b"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" (
    echo Installation failed with exit code %EXITCODE%.
    echo 32B can be too large for 16 GB VRAM depending on quantization and CPU offload.
    echo Use RUN-INSTALL-LOCAL-OLLAMA-14B-DEFAULT.bat or RUN-INSTALL-LOCAL-OLLAMA-7B-FALLBACK.bat if this fails.
) else (
    echo Installation finished.
    echo Open a new PowerShell window and run:
    echo claw --version
    echo claw doctor
    echo ollama list
    echo claw --model qwen2.5-coder:32b prompt "Say hello in one short sentence."
)
echo.
pause
exit /b %EXITCODE%
