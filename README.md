# Claw Code Local Ollama Auto Setup

Windows-first bootstrap package for running [Claw Code](https://github.com/ultraworkers/claw-code) with a local [Ollama](https://ollama.com/) backend and a bundled desktop wrapper called **Claw Studio**.

This repository is designed for a practical local setup:

- install or verify Git, Rust, Visual C++ Build Tools, and Ollama
- clone or update `ultraworkers/claw-code`
- build `claw.exe` from source
- configure Claw for Ollama through the OpenAI-compatible endpoint
- install a local GUI launcher for project-scoped usage
- create Start menu and Desktop shortcuts for Claw Studio

## Why this exists

Claw Code is a CLI agent, not a native Windows desktop app. This package turns the setup into a repeatable Windows workflow and adds a lightweight GUI wrapper so the tool is easier to launch and use locally.

The installer is intentionally **idempotent**:

- if a dependency is already installed, it is reused
- if the repo already exists, it is updated in place
- if the model is already available in Ollama, it is not pulled again
- if Claw is already built, it is rebuilt only when needed

## Current state

This repo currently provides:

- `setup.bat` as the main entrypoint
- `tools/Install-ClawCode-Ollama.ps1` as the installer/bootstrapper
- `tools/ClawStudio.ps1` as the desktop GUI wrapper
- `tools/launch-claw-studio.bat` as the GUI launcher
- `tools/manual-model-setup.bat` as a manual helper
- `tools/generate-claw-studio-icon.ps1` as an icon generator script for Claw Studio assets

The GUI is meant to feel closer to a chat-oriented coding tool than a plain terminal wrapper:

- project-scoped usage instead of starting from a broad folder
- model and permission mode selection
- thread-style quick prompts
- chat-style conversation area
- live streamed Claw output
- buttons for doctor, version, Ollama listing, and interactive terminal launch

## What gets installed

When `setup.bat` completes successfully, the following are installed or configured:

- `claw.exe` under:
  - `%LOCALAPPDATA%\Programs\ClawCode\bin\claw.exe`
- Claw Studio under:
  - `%LOCALAPPDATA%\Programs\ClawCode\studio\ClawStudio.ps1`
- GUI launcher under:
  - `%LOCALAPPDATA%\Programs\ClawCode\bin\claw-studio.bat`
- user environment variables for local Ollama:
  - `OPENAI_BASE_URL=http://127.0.0.1:11434/v1`
  - `OPENAI_API_KEY=local-dev-token`
- Windows shortcuts:
  - `Desktop\Claw Studio.lnk`
  - `Start Menu\Programs\Claw Studio.lnk`

## Requirements

Target environment:

- Windows
- PowerShell 5.1 or later
- WinGet available

The installer can install most dependencies automatically:

- Git
- Rust / rustup / cargo
- Ollama

It also checks for:

- Visual Studio C++ Build Tools

If Build Tools are missing, the script warns and can install them when elevation is available.

## Quick start

1. Extract this package into a clean folder.
2. Double-click `setup.bat`.
3. Let the installer finish.
4. Start Claw Studio from:
   - `claw-studio.bat`
   - the Desktop shortcut
   - the Start menu shortcut

The installer keeps the console window open and writes a timestamped log to:

```text
logs\
```

## Default model selection

The installer selects the Ollama model automatically based on the **largest detected GPU VRAM**.

Policy:

- under 12 GB VRAM:
  - `qwen2.5-coder:7b`
- 12 to 19 GB VRAM:
  - `qwen2.5-coder:14b`
- 20 GB VRAM or more:
  - `qwen2.5-coder:32b`

On systems with NVIDIA GPUs, VRAM detection prefers `nvidia-smi` because Windows adapter reporting is often inaccurate for mobile GPUs.

## Claw and Ollama model syntax

Claw Code expects models in `provider/model` form.

For Ollama, this package uses the **OpenAI-compatible router**:

```text
openai/qwen2.5-coder:14b
```

Example:

```powershell
claw --model openai/qwen2.5-coder:14b prompt "Say hello in one short sentence."
```

## Repository layout

Top level:

- `setup.bat`
- `README.md`
- `LICENSE`
- `tools\`
- `logs\` after runs

Tools folder:

- `tools/Install-ClawCode-Ollama.ps1`
- `tools/ClawStudio.ps1`
- `tools/launch-claw-studio.bat`
- `tools/manual-model-setup.bat`
- `tools/generate-claw-studio-icon.ps1`
- `tools/manifest.json`

## How installation works

The installer performs these steps:

1. verifies Git
2. verifies Rust / cargo / rustup
3. checks Visual C++ Build Tools
4. verifies or installs Ollama
5. auto-selects an Ollama model by GPU VRAM
6. ensures the local OpenAI-compatible endpoint variables are set
7. clones or updates the Claw Code repository
8. builds `claw.exe` from source with Cargo
9. installs `claw.exe` into a user-local bin directory
10. installs Claw Studio
11. creates Windows shortcuts
12. runs `claw --version`
13. runs `claw doctor`

The automatic final prompt test against Ollama is intentionally skipped by default so the setup does not appear stuck during first model load.

## Claw Studio

Claw Studio is the local GUI wrapper included in this package.

Goals:

- make Claw easier to start on Windows
- reduce the chance of launching from an overly broad folder
- make common tasks feel more like a chat-based coding tool

Current features:

- choose a project folder
- choose model and permission mode
- thread-style quick actions
- send custom prompts with `Ctrl+Enter`
- stream Claw output inside the app
- open an interactive terminal session for the same project
- show local Ollama model availability

Important usage note:

Claw should be started **inside a real project folder**, not from a broad location like `C:\Users\<name>`.

## Useful commands

After installation, open a new PowerShell window and use:

```powershell
claw --version
claw doctor
claw-studio.bat
ollama list
claw --model openai/qwen2.5-coder:14b prompt "summarize this folder"
```

If `claw` is not visible in an older terminal session yet, use:

```powershell
"%LOCALAPPDATA%\Programs\ClawCode\bin\claw.exe" --version
```

## Manual model selection

If you want to bypass automatic VRAM-based selection, use:

```text
tools\manual-model-setup.bat
```

Normally, `setup.bat` is enough.

## Troubleshooting

### The setup window closes too fast

This package is built to keep the window open after execution. If something still fails, use the generated log file in `logs\`.

### `claw` is not found after installation

Open a new PowerShell or CMD window, or run Claw with the full path:

```powershell
"%LOCALAPPDATA%\Programs\ClawCode\bin\claw.exe" --version
```

### `claw doctor` warns about auth variables

That is expected for a local Ollama setup. Claw still warns that Anthropic-style auth variables are not present, even though Ollama is configured through:

- `OPENAI_BASE_URL`
- `OPENAI_API_KEY`

### The final model prompt seems to hang

Large local models, especially `qwen2.5-coder:14b` and above, can take time on first load. This is one reason the installer skips the automatic prompt test by default.

### Claw warns about broad folders

That is expected and desirable. Choose a real repository or project folder instead of running from a broad user directory.

### GUI changes do not appear after an update

Run `setup.bat` again. The installer copies the latest repo version of `ClawStudio.ps1` into:

```text
%LOCALAPPDATA%\Programs\ClawCode\studio
```

## Notes about Claw Code itself

- official repo:
  - https://github.com/ultraworkers/claw-code
- do **not** use:
  - `cargo install claw-code`

This package follows the upstream recommendation to build from source instead of using the deprecated crate path.

## Development notes

This repository currently contains active installer and GUI work. Depending on when you use it, some files may still be evolving:

- `tools/ClawStudio.ps1`
- `tools/Install-ClawCode-Ollama.ps1`
- `tools/generate-claw-studio-icon.ps1`

If you commit or publish changes, review those files together because the installer, launcher, GUI, and shortcuts are intentionally coupled.

## License

This repository is licensed under the MIT License. See [LICENSE](LICENSE).
