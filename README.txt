Claw Code Local Ollama Auto Setup

Folder structure
The root folder contains only:
- setup.bat
- README.txt

Everything else is inside:
- tools\

Start
1. Extract the ZIP into a clean folder.
2. Double-click setup.bat.
3. The window stays open.
4. A log file is written automatically to logs\.

Automatic model selection by GPU VRAM
The setup detects the largest available GPU and selects:

- under 12 GB VRAM: qwen2.5-coder:7b
- 12 to 19 GB VRAM: qwen2.5-coder:14b
- 20 GB VRAM or more: qwen2.5-coder:32b

With 16 GB VRAM, it automatically selects:

qwen2.5-coder:14b

What is checked or installed automatically
- Git
- Rust/Rustup/Cargo
- Visual C++ Build Tools
- Ollama
- the selected Ollama model
- Claw Code from https://github.com/ultraworkers/claw-code.git
- claw.exe build
- installation to %LOCALAPPDATA%\Programs\ClawCode\bin
- user PATH entry
- claw --version
- claw doctor

Fix in v7
Native programs such as rustup, git and cargo are now launched through a dedicated process runner.
Their stderr output is displayed and logged, but it no longer kills the installer just because PowerShell has ErrorActionPreference set to Stop.

After successful installation
Open a new PowerShell window and run:

claw --version
claw doctor
ollama list

Test with the selected model, usually this on a 16 GB VRAM GPU:

claw --model qwen2.5-coder:14b prompt "Say hello in one short sentence."

Manual model selection
Optional helper:

tools\manual-model-setup.bat

Normally, setup.bat is enough.

Notes
The setup is idempotent. You can run it multiple times. Existing components are checked and are not installed twice unnecessarily.
