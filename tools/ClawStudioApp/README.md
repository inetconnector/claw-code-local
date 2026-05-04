# Claw Studio App

Native WPF/Visual-Studio-Projekt für die Claw-Studio-Oberfläche.

## Öffnen im Designer

1. Visual Studio 2022 öffnen.
2. `tools/ClawStudioApp/ClawStudioApp.csproj` öffnen.
3. `MainWindow.xaml` im XAML-Designer bearbeiten.

## Build

```powershell
dotnet build tools\ClawStudioApp\ClawStudioApp.csproj -c Release
```

## Start

```powershell
dotnet run --project tools\ClawStudioApp\ClawStudioApp.csproj -c Release
```

Die App speichert Einstellungen unter `%LOCALAPPDATA%\Programs\ClawCode\studio\settings.json` und ruft standardmäßig `%LOCALAPPDATA%\Programs\ClawCode\bin\claw.exe` auf.
