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

Important Claw/Ollama syntax
Claw Code expects provider/model syntax.
For Ollama, use the OpenAI-compatible router prefix:

openai/qwen2.5-coder:14b

So the correct test command is:

claw --model openai/qwen2.5-coder:14b prompt "Say hello in one short sentence."

If the current CMD window still does not find claw, use the full path:

"%LOCALAPPDATA%\Programs\ClawCode\bin\claw.exe" --version

Fix in v10
- Ollama tests now use openai/<model>, for example openai/qwen2.5-coder:14b.
- setup.bat refreshes PATH inside the current CMD window after installation.
- The test instructions use the full claw.exe path as a fallback.

Fix in v9
- cargo build, cargo clean, cargo test and ollama pull use live console output.
- NVIDIA VRAM detection uses nvidia-smi first.

After successful installation
Open a new PowerShell window and run:

claw --version
claw doctor
ollama list
claw --model openai/qwen2.5-coder:14b prompt "Say hello in one short sentence."

Manual model selection
Optional helper:

tools\manual-model-setup.bat

Normally, setup.bat is enough.
