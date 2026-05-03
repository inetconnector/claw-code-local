Claw Code Local Ollama Installer

Zweck
Dieses Paket installiert Claw Code lokal für Windows und richtet standardmäßig Ollama ein.

Für deinen Rechner
Da du eine Grafikkarte mit 16 GB VRAM hast, ist qwen2.5-coder:14b als Standard gesetzt.
Das ist der bessere Standard als 7B, weil es für Code-Aufgaben deutlich leistungsfähiger sein kann.
7B bleibt als Fallback enthalten.
32B ist nur als experimentelle Option enthalten, weil es trotz 16 GB VRAM je nach Quantisierung und CPU-Offload eng werden kann.

Standard
- Claw Code wird aus https://github.com/ultraworkers/claw-code.git gebaut.
- Standardmodell: qwen2.5-coder:14b
- Lokaler OpenAI-kompatibler Endpunkt: http://127.0.0.1:11434/v1
- OPENAI_API_KEY wird lokal auf local-dev-token gesetzt.
- claw.exe wird nach %LOCALAPPDATA%\Programs\ClawCode\bin kopiert und zum User-PATH hinzugefügt.

Schnellstart
1. ZIP entpacken.
2. RUN-INSTALL-LOCAL-OLLAMA-14B-DEFAULT.bat doppelklicken.
3. Wenn Visual Studio Build Tools fehlen und der Build scheitert, die BAT erneut als Administrator starten.
4. Danach ein neues PowerShell-Fenster öffnen.

Test
claw --version
claw doctor
ollama list
claw --model qwen2.5-coder:14b prompt "Say hello in one short sentence."

Fallback
Wenn 14B zu langsam ist oder nicht sauber läuft:
RUN-INSTALL-LOCAL-OLLAMA-7B-FALLBACK.bat

Experimentell
Wenn du 32B testen willst:
RUN-INSTALL-LOCAL-OLLAMA-32B-EXPERIMENTAL.bat

Direkter PowerShell-Aufruf
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Install-ClawCode-Ollama.ps1 -Release

Anderes Modell
.\Install-ClawCode-Ollama.ps1 -Release -OllamaModel "qwen2.5-coder:7b"
.\Install-ClawCode-Ollama.ps1 -Release -OllamaModel "qwen2.5-coder:32b"

Anthropic statt Ollama
.\Install-ClawCode-Ollama.ps1 -Release -NoOllama -AnthropicApiKey "sk-ant-DEIN_KEY"

Hinweis
Das Skript ist idempotent. Es kann mehrfach ausgeführt werden. Vorhandene Installationen werden geprüft, fehlende Komponenten ergänzt, das Repository wird aktualisiert und die Binary wird nur ersetzt, wenn sie anders ist.
