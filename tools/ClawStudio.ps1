#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Speech

$StudioRoot = Join-Path $env:LOCALAPPDATA "Programs\ClawCode\studio"
$SettingsPath = Join-Path $StudioRoot "settings.json"
$DefaultClawPath = Join-Path $env:LOCALAPPDATA "Programs\ClawCode\bin\claw.exe"

if (-not (Test-Path -LiteralPath $StudioRoot)) {
    New-Item -ItemType Directory -Path $StudioRoot -Force | Out-Null
}

$script:CurrentProcess = $null
$script:ActiveOutputControl = $null
$script:StdOutPath = ""
$script:StdErrPath = ""
$script:StdOutPosition = 0L
$script:StdErrPosition = 0L
$script:StdOutWriter = $null
$script:StdErrWriter = $null
$script:ProjectPath = ""
$script:CurrentThreadTitle = "Claw Code installieren"
$script:StudioErrorLogPath = Join-Path $StudioRoot "studio-errors.log"
$script:RunStartedAt = $null
$script:CurrentRunnerPath = ""
$script:SpeechRecognizer = $null
$script:IsSpeechListening = $false
$script:SpinnerFrames = @('|','/','-','\')
$script:SpinnerIndex = 0
$script:ApprovalPending = $false
$script:ApprovalForSession = $false
$script:LastCommandArguments = @()
$script:LastCommandLabel = ""

$script:Theme = @{
    Window = "#171717"
    Sidebar = "#202428"
    SidebarSoft = "#262B30"
    Panel = "#1E1E1E"
    PanelSoft = "#252526"
    Border = "#33373D"
    Foreground = "#F3F4F6"
    Muted = "#A1A1AA"
    Accent = "#FFFFFF"
    AccentSoft = "#2F3640"
    Blue = "#60A5FA"
    Green = "#34D399"
    Yellow = "#FBBF24"
    Red = "#F87171"
    UserBubble = "#2A2A2D"
    AssistantBubble = "#202124"
    Composer = "#2B2B2E"
}

$script:Language = if ([System.Globalization.CultureInfo]::CurrentUICulture.Name -like "de*") { "de" } else { "en" }
$script:Strings = @{
    de = @{
        NewChat = "Neuer Chat"
        Search = "Suche"
        Plugins = "Plugins"
        Automations = "Automatisierungen"
        Projects = "Projekte"
        Settings = "Einstellungen"
        ChooseProject = "Projekt waehlen"
        OpenExplorer = "Im Explorer oeffnen"
        ResetChat = "Chat zuruecksetzen"
        StartNewChat = "Neuen Chat starten"
        LocalWork = "Lokal arbeiten"
        Ready = "Bereit"
        Running = "Laeuft"
        NeedsAttention = "Fehler"
        File = "Datei"
        Edit = "Bearbeiten"
        View = "Anzeigen"
        Window = "Fenster"
        Help = "Hilfe"
        Exit = "Beenden"
        PasteClipboard = "Zwischenablage einfuegen"
        AttachFiles = "Dateien anfuegen"
        ClearPrompt = "Prompt leeren"
        Minimize = "Minimieren"
        MaxRestore = "Maximieren / Wiederherstellen"
        RunDoctor = "Doctor ausfuehren"
        ShowVersion = "Version anzeigen"
        PromptEmpty = ""
        SystemReady = "Claw Studio ist bereit. Waehle einen Projektordner und nutze den Composer unten wie einen Chat-Eingabebereich."
        TipReady = "Starte in einem echten Repo-Ordner, nicht im ganzen Benutzerverzeichnis. Enter sendet, Shift+Enter macht einen Zeilenumbruch."
        SettingsReady = "Einstellungen sind bereit. Waehle unten Modell und Berechtigungsmodus."
        ProjectSwitched = "Projekt gewechselt zu {0}."
        ClipboardEmpty = "Die Zwischenablage ist leer oder enthaelt keinen Text."
        FilesAttached = "{0} Datei(en) zum Prompt-Kontext hinzugefuegt."
        FreshChat = "Neuer Chat gestartet."
        FreshProjectChat = "Neuer Projekt-Chat gestartet."
        ChatReset = "Chat zurueckgesetzt. Einstellungen wurden beibehalten."
        TaskStartFailed = "Aufgabe konnte nicht gestartet werden: {0}"
        ProcessOk = "Prozess erfolgreich beendet."
        ProcessFail = "Prozess mit Exit-Code {0} beendet."
        Working = "arbeitet gerade..."
        Finished = "fertig"
        Failed = "mit Fehler beendet"
        JustCreated = "gerade erstellt"
        Prepared = "vorbereitet"
        Configure = "einstellungen"
        MissingClaw = "claw.exe wurde nicht gefunden. Fuehre zuerst setup.bat aus und starte Claw Studio danach neu."
        ChooseValidProject = "Waehle zuerst einen gueltigen Projektordner."
        BroadFolder = "Dieser Ordner ist sehr allgemein. Waehle nach Moeglichkeit einen echten Projektordner.`n`nTrotzdem fortfahren?"
        TaskAlreadyRunning = "Es laeuft bereits eine Aufgabe. Stoppe sie zuerst oder warte, bis sie beendet ist."
        OpenedTerminal = "Interaktives Terminal im aktuellen Projekt geoeffnet."
        CloseWhileRunning = "Es laeuft noch eine Aufgabe. Claw Studio trotzdem schliessen?"
        ChooseProjectFolder = "Projektordner waehlen, in dem Claw arbeiten soll"
        ChooseFiles = "Dateien fuer den Prompt-Kontext waehlen"
        RepoAnalyze = "Repo analysieren"
        BuildInvestigate = "Build-Probleme untersuchen"
        NextFix = "Naechsten Fix vorbereiten"
        InstallTitle = "Claw Code installieren"
        PasteTooltip = "Zwischenablage in den Prompt einfuegen."
        Terminal = "Terminal"
        ProcessingSince = "In Bearbeitung seit {0}s"
        Thinking = "Denke nach"
        UiError = "UI-Fehler in {0}: {1}"
        InternalError = "interner Fehler"
        RunningIn = "Arbeite in {0}"
        StartFailed = "Start fehlgeschlagen"
        Stop = "Stop"
        Workspace = "Workspace"
        BranchDetails = "Branch-Details"
        Sources = "Quellen"
        OpenVSCode = "VS Code"
        OpenTerminalShort = "Terminal"
        Changes = "Aenderungen"
        CliDoctor = "CLI-Doctor"
        WebSearch = "Internetsuche"
        Added = "Hinzugefuegt"
        Removed = "Entfernt"
        Changed = "Geaendert"
        NoRepo = "Kein Git-Repo"
        ThreadMenu = "Thread-Menue"
        StartDictation = "Spracheingabe starten"
        StopDictation = "Spracheingabe stoppen"
        DictationReady = "Spracheingabe aktiv."
        DictationStopped = "Spracheingabe beendet."
        DictationUnavailable = "Spracheingabe ist auf diesem System nicht verfuegbar."
        ApproveOnce = "Ja, einmal"
        ApproveSession = "Ja, fuer Sitzung"
        Deny = "Ablehnen"
        ApprovalNeeded = "Genehmigung erforderlich"
        ApprovalDetected = "Diese Aktion braucht erweiterte Rechte. Wie soll Claw fortfahren?"
        GitRemote = "Git-Remote"
        InitGitRepo = "Git-Repo anlegen"
        FetchBranches = "Branches holen"
        ShowBranches = "Branches"
        PushRepo = "Push"
        GitRepoCreated = "Git-Repo wurde angelegt."
        GitRemoteMissing = "Bitte zuerst eine Git-Remote-URL in den Einstellungen setzen."
        ApprovalDenied = "Genehmigung abgelehnt."
    }
    en = @{
        NewChat = "New Chat"
        Search = "Search"
        Plugins = "Plugins"
        Automations = "Automations"
        Projects = "Projects"
        Settings = "Settings"
        ChooseProject = "Choose project"
        OpenExplorer = "Open in Explorer"
        ResetChat = "Reset chat"
        StartNewChat = "Start new chat"
        LocalWork = "Local workspace"
        Ready = "Ready"
        Running = "Running"
        NeedsAttention = "Needs attention"
        File = "File"
        Edit = "Edit"
        View = "View"
        Window = "Window"
        Help = "Help"
        Exit = "Exit"
        PasteClipboard = "Paste clipboard"
        AttachFiles = "Attach files"
        ClearPrompt = "Clear prompt"
        Minimize = "Minimize"
        MaxRestore = "Maximize / Restore"
        RunDoctor = "Run doctor"
        ShowVersion = "Show version"
        PromptEmpty = ""
        SystemReady = "Claw Studio is ready. Pick a project folder, then use the composer below like a chat input."
        TipReady = "Start inside a real repo folder, not your whole user directory. Enter sends, Shift+Enter adds a new line."
        SettingsReady = "Settings are ready. Choose a model and permission mode below."
        ProjectSwitched = "Project switched to {0}."
        ClipboardEmpty = "Clipboard is empty or does not contain text."
        FilesAttached = "{0} file(s) added to the prompt context."
        FreshChat = "Started a fresh chat."
        FreshProjectChat = "Started a fresh project chat."
        ChatReset = "Chat reset. Settings stayed intact."
        TaskStartFailed = "Task could not be started: {0}"
        ProcessOk = "Process finished successfully."
        ProcessFail = "Process finished with exit code {0}."
        Working = "working..."
        Finished = "finished"
        Failed = "finished with error"
        JustCreated = "just created"
        Prepared = "prepared"
        Configure = "settings"
        MissingClaw = "claw.exe was not found. Run setup.bat first, then reopen Claw Studio."
        ChooseValidProject = "Choose a valid project folder first."
        BroadFolder = "That folder is very broad. Pick a real project folder instead when possible.`n`nContinue anyway?"
        TaskAlreadyRunning = "A task is already running. Stop it first or wait until it finishes."
        OpenedTerminal = "Opened an interactive terminal in the current project."
        CloseWhileRunning = "A task is still running. Close Claw Studio anyway?"
        ChooseProjectFolder = "Choose the project folder Claw should work in"
        ChooseFiles = "Choose files to reference in the prompt"
        RepoAnalyze = "Analyze repo"
        BuildInvestigate = "Inspect build issues"
        NextFix = "Prepare next fix"
        InstallTitle = "Install Claw Code"
        PasteTooltip = "Paste clipboard text into the prompt."
        Terminal = "Terminal"
        ProcessingSince = "Working for {0}s"
        Thinking = "Thinking"
        UiError = "UI error in {0}: {1}"
        InternalError = "internal error"
        RunningIn = "Working in {0}"
        StartFailed = "start failed"
        Stop = "Stop"
        Workspace = "Workspace"
        BranchDetails = "Branch details"
        Sources = "Sources"
        OpenVSCode = "VS Code"
        OpenTerminalShort = "Terminal"
        Changes = "Changes"
        CliDoctor = "CLI doctor"
        WebSearch = "Web search"
        Added = "Added"
        Removed = "Removed"
        Changed = "Changed"
        NoRepo = "No git repo"
        ThreadMenu = "Thread menu"
        StartDictation = "Start dictation"
        StopDictation = "Stop dictation"
        DictationReady = "Dictation is active."
        DictationStopped = "Dictation stopped."
        DictationUnavailable = "Speech input is not available on this system."
        ApproveOnce = "Yes, once"
        ApproveSession = "Yes, for session"
        Deny = "Deny"
        ApprovalNeeded = "Approval required"
        ApprovalDetected = "This action needs elevated permissions. How should Claw continue?"
        GitRemote = "Git remote"
        InitGitRepo = "Initialize git repo"
        FetchBranches = "Fetch branches"
        ShowBranches = "Branches"
        PushRepo = "Push"
        GitRepoCreated = "Git repo created."
        GitRemoteMissing = "Please set a git remote URL in settings first."
        ApprovalDenied = "Approval denied."
    }
}

function T {
    param(
        [string]$Key,
        [object[]]$FormatArgs
    )

    $languageTable = $script:Strings[$script:Language]
    $fallbackTable = $script:Strings["en"]
    $text = if ($languageTable.ContainsKey($Key)) { $languageTable[$Key] } elseif ($fallbackTable.ContainsKey($Key)) { $fallbackTable[$Key] } else { $Key }
    if ($FormatArgs -and $FormatArgs.Count -gt 0) {
        return [string]::Format($text, $FormatArgs)
    }
    return $text
}

function Get-Settings {
    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        return @{}
    }

    try {
        $raw = Get-Content -LiteralPath $SettingsPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @{}
        }

        $data = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        $table = @{}
        foreach ($property in $data.PSObject.Properties) {
            $table[$property.Name] = $property.Value
        }
        return $table
    } catch {
        return @{}
    }
}

function Save-Settings {
    param(
        [string]$ProjectPath,
        [string]$Model,
        [string]$PermissionMode,
        [string]$GitRemoteUrl = ""
    )

    $payload = [ordered]@{
        projectPath = $ProjectPath
        model = $Model
        permissionMode = $PermissionMode
        gitRemoteUrl = $GitRemoteUrl
    }

    ($payload | ConvertTo-Json) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
}

function Get-DefaultGitRemoteUrl {
    $settings = Get-Settings
    if ($settings.ContainsKey("gitRemoteUrl") -and -not [string]::IsNullOrWhiteSpace([string]$settings.gitRemoteUrl)) {
        return [string]$settings.gitRemoteUrl
    }

    return ""
}

function Find-ClawBinary {
    if (Test-Path -LiteralPath $DefaultClawPath) {
        return $DefaultClawPath
    }

    $command = Get-Command "claw" -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
        return $command.Source
    }

    return ""
}

function Find-CommandBinary {
    param([string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
        return $command.Source
    }

    return $Name
}

function Get-DefaultProjectPath {
    $settings = Get-Settings
    if ($settings.ContainsKey("projectPath") -and -not [string]::IsNullOrWhiteSpace([string]$settings.projectPath) -and (Test-Path -LiteralPath $settings.projectPath)) {
        return [string]$settings.projectPath
    }

    $sourcePath = Join-Path $env:USERPROFILE "source"
    if (Test-Path -LiteralPath $sourcePath) {
        return $sourcePath
    }

    return $env:USERPROFILE
}

function Get-DefaultModel {
    $settings = Get-Settings
    if ($settings.ContainsKey("model") -and -not [string]::IsNullOrWhiteSpace([string]$settings.model)) {
        return [string]$settings.model
    }

    return "openai/qwen2.5-coder:7b"
}

function Get-DefaultPermissionMode {
    $settings = Get-Settings
    if ($settings.ContainsKey("permissionMode") -and -not [string]::IsNullOrWhiteSpace([string]$settings.permissionMode)) {
        return [string]$settings.permissionMode
    }

    return "workspace-write"
}

function Test-BroadProjectPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $true
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $userProfile = [System.IO.Path]::GetFullPath($env:USERPROFILE)
    $desktop = [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE "Desktop"))
    $documents = [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE "Documents"))
    $driveRoot = [System.IO.Path]::GetPathRoot($fullPath)

    return ($fullPath -ieq $userProfile -or $fullPath -ieq $desktop -or $fullPath -ieq $documents -or $fullPath -ieq $driveRoot)
}

function ConvertTo-ArgumentString {
    param([string[]]$Arguments)

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($argument in $Arguments) {
        $value = [string]$argument
        if ([string]::IsNullOrEmpty($value)) {
            $parts.Add('""') | Out-Null
            continue
        }

        if ($value -notmatch '[\s"]') {
            $parts.Add($value) | Out-Null
            continue
        }

        $escaped = $value.Replace('\', '\\').Replace('"', '\"')
        $parts.Add('"' + $escaped + '"') | Out-Null
    }

    return ($parts -join " ")
}

function ConvertTo-PowerShellStringLiteral {
    param([string]$Value)

    if ($null -eq $Value) {
        return '$null'
    }

    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function Read-NewText {
    param(
        [string]$Path,
        [ref]$Position
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($Position.Value -gt $stream.Length) {
            $Position.Value = 0L
        }

        $stream.Seek($Position.Value, [System.IO.SeekOrigin]::Begin) | Out-Null
        $reader = New-Object System.IO.StreamReader($stream)
        try {
            $text = $reader.ReadToEnd()
            $Position.Value = $stream.Position
            return $text
        } finally {
            $reader.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Sanitize-UiText {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }

    $clean = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, "\u001B\[[0-?]*[ -/]*[@-~]", "")
    $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, "\u009B[0-?]*[ -/]*[@-~]", "")
    $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, "\u001B\][^\u0007]*(\u0007|\u001B\\)", "")
    $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, "[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]", "")
    $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, "(?m)^\[[0-9;]*m", "")
    $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, "(?m)^\[[0-9]+[A-Z]", "")
    $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, "(?m)^\[[0-9;]*m", "")
    $clean = $clean -replace "�", ""
    return $clean
}

function Write-StudioErrorLog {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    try {
        "[{0}] {1}" -f ([DateTime]::Now.ToString("s")), $Message | Add-Content -LiteralPath $script:StudioErrorLogPath -Encoding UTF8
    } catch {
    }
}

function Get-GitBranch {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return "master"
    }

    try {
        $branch = (& git -C $Path branch --show-current 2>$null | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($branch)) {
            return "master"
        }
        return $branch
    } catch {
        return "master"
    }
}

function Get-ConfiguredEnvironmentValue {
    param(
        [string]$Name,
        [string]$Fallback = ""
    )

    foreach ($scope in @("Process", "User", "Machine")) {
        $value = [Environment]::GetEnvironmentVariable($Name, $scope)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return $Fallback
}

function Get-AvailableClawModels {
    $models = New-Object System.Collections.Generic.List[string]

    try {
        $lines = & ollama list 2>$null
        foreach ($line in $lines) {
            $trimmed = ([string]$line).Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -like "NAME*") {
                continue
            }

            $name = ($trimmed -split '\s+')[0]
            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            if ($name -notmatch '^[^/]+/.+') {
                $name = "openai/$name"
            }

            if (-not $models.Contains($name)) {
                $models.Add($name) | Out-Null
            }
        }
    } catch {
    }

    if ($models.Count -eq 0) {
        foreach ($fallback in @(
            "openai/qwen2.5-coder:7b",
            "openai/qwen2.5-coder:14b",
            "openai/qwen2.5-coder:32b",
            "openai/llama3.2"
        )) {
            if (-not $models.Contains($fallback)) {
                $models.Add($fallback) | Out-Null
            }
        }
    }

    return ,$models.ToArray()
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claw Studio"
        Width="1600"
        Height="920"
        MinWidth="1280"
        MinHeight="780"
        Background="#171717"
        WindowState="Maximized"
        WindowStyle="None"
        WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="40"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="#A1A1AA"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>

    <Style x:Key="CompactIconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="28"/>
      <Setter Property="Height" Value="28"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="#8E98A4"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonBorder"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1"
                    CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center"
                                VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#2A3138"/>
                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#3A4148"/>
                <Setter Property="Foreground" Value="#F3F4F6"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#252B33"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="#5B6470"/>
                <Setter Property="Opacity" Value="0.7"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="WindowControlButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="46"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="#C5CAD3"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#2A3138"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#252B33"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="CloseWindowButtonStyle" TargetType="Button" BasedOn="{StaticResource WindowControlButtonStyle}">
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#C42B1C"/>
          <Setter Property="Foreground" Value="#FFFFFF"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
          <Setter Property="Background" Value="#A61D12"/>
          <Setter Property="Foreground" Value="#FFFFFF"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style x:Key="MenuHostStyle" TargetType="Menu">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="#B8BEC8"/>
      <Setter Property="ItemContainerStyle">
        <Setter.Value>
          <Style TargetType="MenuItem">
            <Setter Property="Foreground" Value="#D4D4D8"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Padding" Value="10,4"/>
            <Setter Property="Margin" Value="0,0,2,0"/>
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="MenuItem">
                  <Border x:Name="ItemBorder" Background="{TemplateBinding Background}" CornerRadius="6">
                    <Grid>
                      <ContentPresenter x:Name="HeaderHost"
                                        ContentSource="Header"
                                        Margin="{TemplateBinding Padding}"
                                        RecognizesAccessKey="True"/>
                      <Popup x:Name="PART_Popup"
                             Placement="Bottom"
                             AllowsTransparency="True"
                             Focusable="False"
                             IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}}">
                        <Border Background="#2A2A2D"
                                BorderBrush="#3A4148"
                                BorderThickness="1"
                                CornerRadius="10"
                                Padding="6"
                                Margin="0,8,0,0">
                          <StackPanel IsItemsHost="True"/>
                        </Border>
                      </Popup>
                    </Grid>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsHighlighted" Value="True">
                      <Setter TargetName="ItemBorder" Property="Background" Value="#2A3138"/>
                      <Setter Property="Foreground" Value="#F3F4F6"/>
                    </Trigger>
                    <Trigger Property="IsSubmenuOpen" Value="True">
                      <Setter TargetName="ItemBorder" Property="Background" Value="#2A3138"/>
                      <Setter Property="Foreground" Value="#F3F4F6"/>
                    </Trigger>
                    <Trigger Property="Role" Value="SubmenuItem">
                      <Setter Property="Padding" Value="12,8"/>
                    </Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </Setter.Value>
            </Setter>
          </Style>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="NavTextButtonStyle" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="#D4D4D8"/>
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Margin" Value="0,14,0,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                              VerticalAlignment="Center"/>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Foreground" Value="#F3F4F6"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter Property="Foreground" Value="#F3F4F6"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="GhostButtonStyle" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="#3A4148"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Foreground" Value="#D4D4D8"/>
      <Setter Property="Padding" Value="12,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonBorder"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center"
                                VerticalAlignment="Center"
                                Margin="8,0"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#2F3640"/>
                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#4B5563"/>
                <Setter Property="Foreground" Value="#F3F4F6"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#252B33"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#262B31"/>
                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#353C44"/>
                <Setter Property="Foreground" Value="#6B7280"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Background" Value="#F3F4F6"/>
      <Setter Property="BorderBrush" Value="#F3F4F6"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Foreground" Value="#171717"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonBorder"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="10">
              <ContentPresenter HorizontalAlignment="Center"
                                VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#D1D5DB"/>
                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#D1D5DB"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#4B5563"/>
                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#4B5563"/>
                <Setter Property="Foreground" Value="#E5E7EB"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="SidebarButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="40"/>
      <Setter Property="Background" Value="#2A2F35"/>
      <Setter Property="Foreground" Value="#F3F4F6"/>
      <Setter Property="BorderBrush" Value="#3A4148"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonBorder"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}">
              <ContentPresenter HorizontalAlignment="Center"
                                VerticalAlignment="Center"
                                Margin="10,0"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#313841"/>
                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#4B5563"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#252B33"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#4B5563"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="ButtonBorder" Property="Background" Value="#2A3138"/>
                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#38414A"/>
                <Setter Property="Foreground" Value="#C9CDD3"/>
                <Setter Property="Opacity" Value="0.9"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="ThreadListItemStyle" TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="#E5E7EB"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,3"/>
      <Setter Property="Margin" Value="0,1,0,1"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="ItemBorder"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}">
              <ContentPresenter VerticalAlignment="Center"
                                HorizontalAlignment="Stretch"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="ItemBorder" Property="Background" Value="#2A3138"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="ItemBorder" Property="Background" Value="#23303B"/>
                <Setter TargetName="ItemBorder" Property="BorderBrush" Value="#355066"/>
              </Trigger>
              <MultiTrigger>
                <MultiTrigger.Conditions>
                  <Condition Property="IsSelected" Value="True"/>
                  <Condition Property="Selector.IsSelectionActive" Value="False"/>
                </MultiTrigger.Conditions>
                <Setter TargetName="ItemBorder" Property="Background" Value="#23303B"/>
                <Setter TargetName="ItemBorder" Property="BorderBrush" Value="#355066"/>
              </MultiTrigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="ThreadListStyle" TargetType="ListBox">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Foreground" Value="#E5E7EB"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBox">
            <Border Background="{TemplateBinding Background}">
              <ScrollViewer Focusable="False"
                            Padding="0"
                            Background="Transparent"
                            HorizontalScrollBarVisibility="Disabled"
                            VerticalScrollBarVisibility="Auto">
                <ItemsPresenter/>
              </ScrollViewer>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="ComboToggleButtonStyle" TargetType="ToggleButton">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="{x:Null}"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border Background="Transparent">
              <ContentPresenter/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ComboBox">
      <Setter Property="Background" Value="#2A2F35"/>
      <Setter Property="Foreground" Value="#F3F4F6"/>
      <Setter Property="BorderBrush" Value="#3A4148"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,4,36,4"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <Border x:Name="OuterBorder"
                      Background="{TemplateBinding Background}"
                      BorderBrush="{TemplateBinding BorderBrush}"
                      BorderThickness="{TemplateBinding BorderThickness}"
                      CornerRadius="6"/>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="34"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0"
                           Margin="{TemplateBinding Padding}"
                           VerticalAlignment="Center"
                           HorizontalAlignment="Left"
                           Text="{TemplateBinding SelectionBoxItem}"
                           TextTrimming="CharacterEllipsis"
                           Foreground="{TemplateBinding Foreground}"/>
                <ToggleButton Grid.ColumnSpan="2"
                              Style="{StaticResource ComboToggleButtonStyle}"
                              Background="Transparent"
                              BorderBrush="{x:Null}"
                              Focusable="False"
                              ClickMode="Press"
                              IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                  <Grid>
                    <Border Grid.Column="1"
                            HorizontalAlignment="Right"
                            Width="34"
                            Background="#343B44"
                            CornerRadius="0,6,6,0"/>
                    <TextBlock Text="&#xE70D;"
                               FontFamily="Segoe MDL2 Assets"
                               FontSize="10"
                               Foreground="#D4D4D8"
                               VerticalAlignment="Center"
                               HorizontalAlignment="Right"
                               Margin="0,0,12,0"/>
                  </Grid>
                </ToggleButton>
                <Popup x:Name="Popup"
                       Placement="Bottom"
                       AllowsTransparency="True"
                       Focusable="False"
                       IsOpen="{TemplateBinding IsDropDownOpen}"
                       PopupAnimation="Fade">
                  <Border Margin="0,6,0,0"
                          MinWidth="{TemplateBinding ActualWidth}"
                          MaxHeight="{TemplateBinding MaxDropDownHeight}"
                          Background="#252B33"
                          BorderBrush="#3A4148"
                          BorderThickness="1"
                          CornerRadius="8">
                    <ScrollViewer Background="Transparent"
                                  CanContentScroll="True"
                                  HorizontalScrollBarVisibility="Disabled"
                                  VerticalScrollBarVisibility="Auto">
                      <ItemsPresenter/>
                    </ScrollViewer>
                  </Border>
                </Popup>
              </Grid>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="OuterBorder" Property="BorderBrush" Value="#4B5563"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocusWithin" Value="True">
                <Setter TargetName="OuterBorder" Property="BorderBrush" Value="#4B5563"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="OuterBorder" Property="Background" Value="#2A3138"/>
                <Setter TargetName="OuterBorder" Property="BorderBrush" Value="#38414A"/>
                <Setter Property="Foreground" Value="#D1D5DB"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Background" Value="#2A3138"/>
          <Setter Property="Foreground" Value="#D1D5DB"/>
          <Setter Property="BorderBrush" Value="#38414A"/>
          <Setter Property="Opacity" Value="1"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#F3F4F6"/>
      <Setter Property="Background" Value="#252B33"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,8"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="ItemBorder"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                VerticalAlignment="Center"
                                Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="ItemBorder" Property="Background" Value="#334155"/>
                <Setter TargetName="ItemBorder" Property="BorderBrush" Value="#475569"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="ItemBorder" Property="Background" Value="#1D4ED8"/>
                <Setter TargetName="ItemBorder" Property="BorderBrush" Value="#2563EB"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="ItemBorder" Property="Background" Value="#252B33"/>
                <Setter Property="Foreground" Value="#9CA3AF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid Background="#171717">
    <Grid.RowDefinitions>
      <RowDefinition Height="40"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <Border x:Name="TitleBar" Grid.Row="0" Background="#202428" BorderBrush="#2A2F33" BorderThickness="0,0,0,1">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="10,0,12,0">
          <Button x:Name="BackNavButton" Content="&#xE72B;" Width="28" Height="28" Background="Transparent" BorderBrush="Transparent" Foreground="#AEB6C2" FontFamily="Segoe MDL2 Assets" Cursor="Hand"/>
          <Button x:Name="ForwardNavButton" Content="&#xE72A;" Width="28" Height="28" Margin="4,0,10,0" Background="Transparent" BorderBrush="Transparent" Foreground="#AEB6C2" FontFamily="Segoe MDL2 Assets" Cursor="Hand"/>
          <TextBlock Text="&#xE8A7;" FontFamily="Segoe MDL2 Assets" Foreground="#D8DEE8" FontSize="12" VerticalAlignment="Center"/>
          <TextBlock Text="Claw Studio" Foreground="#D8DEE8" FontSize="13" FontWeight="SemiBold" Margin="8,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <Menu Grid.Column="1" x:Name="WindowMenuBar" Style="{StaticResource MenuHostStyle}" VerticalAlignment="Center">
          <MenuItem Header="Datei">
            <MenuItem x:Name="MenuNewChat" Header="Neuer Chat"/>
            <MenuItem x:Name="MenuChooseProject" Header="Projekt waehlen"/>
            <MenuItem x:Name="MenuOpenExplorer" Header="Im Explorer oeffnen"/>
            <Separator/>
            <MenuItem x:Name="MenuExit" Header="Beenden"/>
          </MenuItem>
          <MenuItem Header="Bearbeiten">
            <MenuItem x:Name="MenuPasteClipboard" Header="Zwischenablage einfuegen"/>
            <MenuItem x:Name="MenuAttachFiles" Header="Dateien anfuegen"/>
            <MenuItem x:Name="MenuClearPrompt" Header="Prompt leeren"/>
          </MenuItem>
          <MenuItem Header="Anzeigen">
            <MenuItem x:Name="MenuShowSearch" Header="Suche"/>
            <MenuItem x:Name="MenuShowPlugins" Header="Plugins"/>
            <MenuItem x:Name="MenuShowAutomation" Header="Automatisierungen"/>
            <MenuItem x:Name="MenuShowSettings" Header="Einstellungen"/>
          </MenuItem>
          <MenuItem Header="Fenster">
            <MenuItem x:Name="MenuMinimize" Header="Minimieren"/>
            <MenuItem x:Name="MenuToggleMaximize" Header="Maximieren / Wiederherstellen"/>
          </MenuItem>
          <MenuItem Header="Hilfe">
            <MenuItem x:Name="MenuDoctor" Header="Doctor ausfuehren"/>
            <MenuItem x:Name="MenuVersion" Header="Version anzeigen"/>
          </MenuItem>
        </Menu>
        <StackPanel Grid.Column="2" Orientation="Horizontal">
          <Button x:Name="MinimizeWindowButton" Content="&#xE921;" Style="{StaticResource WindowControlButtonStyle}"/>
          <Button x:Name="MaximizeWindowButton" Content="&#xE922;" Style="{StaticResource WindowControlButtonStyle}"/>
          <Button x:Name="CloseWindowButton" Content="&#xE8BB;" Style="{StaticResource CloseWindowButtonStyle}"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Row="1">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="72"/>
      <ColumnDefinition Width="320"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <Border Grid.Column="0" Background="#1F2428" BorderBrush="#2A2F33" BorderThickness="0,0,1,0">
      <DockPanel Margin="0">
        <StackPanel DockPanel.Dock="Top" Margin="12,14,12,0">
          <Button x:Name="LogoButton" Content="&#xE8A7;" Height="34" Margin="0,0,0,16" Background="Transparent" BorderBrush="Transparent" Foreground="#E5E7EB" FontFamily="Segoe MDL2 Assets" FontSize="16" Cursor="Hand"/>
          <Button x:Name="NewChatNavButton" Content="&#xE70F;" Style="{StaticResource IconButtonStyle}" Foreground="#E5E7EB"/>
          <Button x:Name="SearchNavButton" Content="&#xE721;" Style="{StaticResource IconButtonStyle}"/>
          <Button x:Name="PluginsNavButton" Content="&#xE943;" Style="{StaticResource IconButtonStyle}"/>
          <Button x:Name="AutomationNavButton" Content="&#xE823;" Style="{StaticResource IconButtonStyle}"/>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom" Margin="12,0,12,16">
          <Button x:Name="SettingsNavButton" Content="&#xE713;" Height="40" Background="Transparent" BorderBrush="Transparent" Foreground="#A1A1AA" FontFamily="Segoe MDL2 Assets" FontSize="15" Cursor="Hand"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <Border Grid.Column="1" Background="#21262B" BorderBrush="#2A2F33" BorderThickness="0,0,1,0">
      <Grid Margin="16,14,16,14">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0">
          <Button x:Name="NewChatTextButton" Content="Neuer Chat" Background="Transparent" BorderBrush="Transparent" Foreground="#E5E7EB" FontSize="16" FontWeight="SemiBold" HorizontalContentAlignment="Left" Padding="0" Cursor="Hand" FocusVisualStyle="{x:Null}"/>
          <Button x:Name="SearchTextButton" Content="Suche" Style="{StaticResource NavTextButtonStyle}"/>
          <Button x:Name="PluginsTextButton" Content="Plugins" Style="{StaticResource NavTextButtonStyle}"/>
          <Button x:Name="AutomationTextButton" Content="Automatisierungen" Style="{StaticResource NavTextButtonStyle}"/>
        </StackPanel>

        <StackPanel Grid.Row="1" Margin="0,28,0,0">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Projekte" Foreground="#71717A" FontSize="14" FontWeight="SemiBold"/>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
              <Button x:Name="ProjectAttachButton" Content="&#xE8B7;" Style="{StaticResource CompactIconButtonStyle}" ToolTip="Projekt waehlen"/>
              <Button x:Name="ProjectOpenButton" Content="&#xE838;" Style="{StaticResource CompactIconButtonStyle}" ToolTip="Im Explorer oeffnen"/>
              <Button x:Name="NewThreadButton" Content="&#xE710;" Style="{StaticResource CompactIconButtonStyle}" ToolTip="Neuen Chat starten"/>
              <Button x:Name="RemoveThreadButton" Content="&#xE74D;" Style="{StaticResource CompactIconButtonStyle}" Margin="0,0,0,0" ToolTip="Chat zuruecksetzen"/>
            </StackPanel>
          </Grid>
          <Border Background="#2A3138" CornerRadius="14" Padding="14,10" Margin="0,12,0,0">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock x:Name="ProjectNameText" Text="claw" Foreground="#E5E7EB" FontSize="18" FontWeight="SemiBold"/>
                <TextBlock x:Name="ProjectPathText" Text="C:\Users\frede\Desktop\claw" Foreground="#A1A1AA" FontSize="12" Margin="0,4,0,0" TextWrapping="Wrap"/>
              </StackPanel>
              <Button x:Name="ProjectChooseButton" Grid.Column="1" Content="&#xE70F;" Width="28" Height="28" Margin="12,0,0,0" Background="Transparent" BorderBrush="Transparent" Foreground="#D4D4D8" FontFamily="Segoe MDL2 Assets" Cursor="Hand"/>
            </Grid>
          </Border>
        </StackPanel>

        <Grid Grid.Row="2" Margin="0,18,0,0">
          <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <ListBox x:Name="ThreadList" Grid.Row="0"
                    Style="{StaticResource ThreadListStyle}"
                    FontSize="14"
                    ItemContainerStyle="{StaticResource ThreadListItemStyle}"
                    ScrollViewer.VerticalScrollBarVisibility="Auto">
            <ListBoxItem Content="Claw Code installieren" IsSelected="True"/>
            <ListBoxItem Content="Repo analysieren"/>
            <ListBoxItem Content="Build-Probleme untersuchen"/>
            <ListBoxItem Content="Naechsten Fix vorbereiten"/>
          </ListBox>
        </Grid>

        <StackPanel Grid.Row="3" Margin="0,14,0,0">
          <TextBlock Text="Einstellungen" Foreground="#71717A" FontSize="13" FontWeight="SemiBold"/>
          <ComboBox x:Name="ModelComboBox" Margin="0,10,0,8" Height="36" Background="#2A2F35" Foreground="#F3F4F6" BorderBrush="#3A4148" SelectedIndex="1">
            <ComboBoxItem Content="openai/qwen2.5-coder:7b"/>
            <ComboBoxItem Content="openai/qwen2.5-coder:14b"/>
            <ComboBoxItem Content="openai/qwen2.5-coder:32b"/>
            <ComboBoxItem Content="openai/llama3.2"/>
          </ComboBox>
          <ComboBox x:Name="PermissionComboBox" Height="36" Background="#2A2F35" Foreground="#F3F4F6" BorderBrush="#3A4148" SelectedIndex="1">
            <ComboBoxItem Content="read-only"/>
            <ComboBoxItem Content="workspace-write"/>
            <ComboBoxItem Content="danger-full-access"/>
          </ComboBox>
          <TextBlock x:Name="GitRemoteLabel" Text="Git-Remote" Foreground="#71717A" FontSize="13" FontWeight="SemiBold" Margin="0,12,0,6"/>
          <TextBox x:Name="GitRemoteTextBox" Height="36" Background="#2A2F35" Foreground="#F3F4F6" BorderBrush="#3A4148" Padding="10,6"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Column="2" Background="#171717">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="340"/>
      </Grid.ColumnDefinitions>

      <Grid Grid.Column="0" Background="#171717">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#171717" Padding="28,18,20,14">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel>
              <StackPanel Orientation="Horizontal">
                <TextBlock x:Name="ThreadTitleText" Text="Claw Code installieren" Foreground="#F3F4F6" FontSize="21" FontWeight="SemiBold" VerticalAlignment="Center"/>
                <Button x:Name="ThreadMoreButton" Content="&#xE712;" Width="28" Height="28" Margin="8,0,0,0" Background="Transparent" BorderBrush="Transparent" Foreground="#8E98A4" FontFamily="Segoe MDL2 Assets" ToolTip="Thread-Menue" Cursor="Hand"/>
              </StackPanel>
              <TextBlock x:Name="ThreadSubtitleText" Text="5m 2s lang gearbeitet" Foreground="#A1A1AA" FontSize="13" Margin="0,8,0,0"/>
              <StackPanel Orientation="Horizontal" Margin="0,6,0,0" Visibility="Collapsed" x:Name="WorkMetaPanel">
                <TextBlock x:Name="SpinnerText" Text="|" Foreground="#8E98A4" FontSize="13" Margin="0,0,8,0"/>
                <TextBlock x:Name="WorkMetaText" Text="In Bearbeitung seit 0s" Foreground="#D4D4D8" FontSize="13"/>
              </StackPanel>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top">
              <Border x:Name="StatusPill" Background="#1F4A34" CornerRadius="14" Padding="14,8" Margin="0,0,12,0">
                <TextBlock x:Name="StatusPillText" Text="Ready" Foreground="#86EFAC" FontWeight="SemiBold"/>
              </Border>
              <Button x:Name="HeaderRunButton" Content="&#xE768;" Width="36" Height="36" Background="#2A2F35" BorderBrush="#3A4148" Foreground="#F3F4F6" FontFamily="Segoe MDL2 Assets"/>
            </StackPanel>
          </Grid>
        </Border>

        <ScrollViewer x:Name="ConversationScrollViewer" Grid.Row="1" Margin="28,0,20,18" VerticalScrollBarVisibility="Auto" Background="Transparent">
          <StackPanel x:Name="ConversationStack"/>
        </ScrollViewer>

        <Border Grid.Row="2" Margin="28,0,20,18" Background="#2B2B2E" CornerRadius="24" Padding="18,14,18,12" BorderBrush="#3A4148" BorderThickness="1">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <DockPanel Grid.Row="0" LastChildFill="True">
              <Button x:Name="AttachButton" Content="&#xE710;" Width="36" Height="36" Margin="0,0,12,0" Background="#3A3A3F" BorderBrush="#4A4A4F" Foreground="#F3F4F6" FontFamily="Segoe MDL2 Assets" FontSize="15"/>
              <TextBox x:Name="PromptTextBox"
                       Background="Transparent"
                       Foreground="#F3F4F6"
                       CaretBrush="#F3F4F6"
                       SelectionBrush="#334155"
                       SelectionOpacity="0.9"
                       BorderThickness="0"
                       AcceptsReturn="True"
                       TextWrapping="Wrap"
                       VerticalScrollBarVisibility="Auto"
                       FontSize="15"
                       MinHeight="84"/>
            </DockPanel>

            <Grid Grid.Row="1" Margin="0,12,0,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>

              <ComboBox x:Name="FooterPermissionComboBox" Grid.Column="0" Width="170" Height="34" Background="#2A2F35" Foreground="#F3F4F6" BorderBrush="#3A4148" Margin="0,0,12,0"/>
              <Button x:Name="TerminalButton" Grid.Column="1" Content="Terminal" Width="96" Height="34" Style="{StaticResource GhostButtonStyle}" Margin="0,0,12,0"/>
              <TextBlock x:Name="ModelFooterText" Grid.Column="3" Text="5.4 Mittel" VerticalAlignment="Center" Foreground="#D4D4D8" Margin="0,0,14,0"/>
              <Button x:Name="MicButton" Grid.Column="4" Content="&#xE77F;" Width="30" Height="30" Background="Transparent" BorderBrush="Transparent" Foreground="#A1A1AA" FontFamily="Segoe MDL2 Assets" ToolTip="Paste clipboard text into the prompt." Margin="0,0,10,0"/>
              <Button x:Name="SendButton" Grid.Column="5" Content="&#xE724;" Width="42" Height="42" Style="{StaticResource PrimaryButtonStyle}" Foreground="#171717" FontFamily="Segoe MDL2 Assets" FontSize="16" FontWeight="Bold" Margin="0,0,0,0"/>
            </Grid>
            <Border x:Name="ApprovalPanel" Grid.Row="2" Margin="0,14,0,0" Background="#1F2227" BorderBrush="#3A4148" BorderThickness="1" CornerRadius="14" Padding="14" Visibility="Collapsed">
              <StackPanel>
                <TextBlock x:Name="ApprovalTitleText" Text="Genehmigung erforderlich" Foreground="#F3F4F6" FontSize="14" FontWeight="SemiBold"/>
                <TextBlock x:Name="ApprovalBodyText" Text="Diese Aktion braucht erweiterte Rechte. Wie soll Claw fortfahren?" Foreground="#D4D4D8" Margin="0,8,0,0" TextWrapping="Wrap"/>
                <WrapPanel Margin="0,12,0,0">
                  <Button x:Name="ApproveOnceButton" Content="Ja, einmal" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,0,10,10" Padding="12,0"/>
                  <Button x:Name="ApproveSessionButton" Content="Ja, fuer Sitzung" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,0,10,10" Padding="12,0"/>
                  <Button x:Name="DenyApprovalButton" Content="Ablehnen" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,0,10,10" Padding="12,0"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </Grid>
        </Border>

        <Border Grid.Row="3" Background="#171717" Padding="28,0,20,14">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" x:Name="WorkspaceModeText" Text="Lokal arbeiten" Foreground="#D4D4D8" Margin="0,0,18,0"/>
            <TextBlock Grid.Column="1" x:Name="BranchText" Text="master" Foreground="#D4D4D8" Margin="0,0,18,0"/>
            <TextBlock Grid.Column="2" x:Name="BinaryPathText" Text="claw.exe" Foreground="#71717A"/>
          </Grid>
        </Border>
      </Grid>

      <Border Grid.Column="1" Background="#171717" BorderBrush="#262B31" BorderThickness="1,0,0,0" Padding="12,18,18,18">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Background="Transparent">
          <StackPanel>
            <Border Background="#1F2227" BorderBrush="#30343B" BorderThickness="1" CornerRadius="18" Padding="16" Margin="0,0,0,14">
              <StackPanel>
                <TextBlock x:Name="WorkspaceCardTitle" Text="Workspace" Foreground="#A1A1AA" FontSize="13" FontWeight="SemiBold"/>
                <TextBlock x:Name="SidebarProjectNameText" Text="claw" Foreground="#F3F4F6" FontSize="20" FontWeight="SemiBold" Margin="0,10,0,0"/>
                <TextBlock x:Name="SidebarProjectPathText" Text="C:\Users\frede\Desktop\claw" Foreground="#8E98A4" FontSize="12" Margin="0,6,0,0" TextWrapping="Wrap"/>
                <WrapPanel Margin="0,14,0,0">
                  <Button x:Name="OpenVSCodeButton" Content="VS Code" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,0,10,10" Padding="12,0"/>
                  <Button x:Name="OpenExplorerSideButton" Content="Explorer" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,0,10,10" Padding="12,0"/>
                  <Button x:Name="OpenTerminalSideButton" Content="Terminal" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,0,10,10" Padding="12,0"/>
                </WrapPanel>
              </StackPanel>
            </Border>

            <Border Background="#1F2227" BorderBrush="#30343B" BorderThickness="1" CornerRadius="18" Padding="16" Margin="0,0,0,14">
              <StackPanel>
                <TextBlock x:Name="BranchDetailsTitle" Text="Branch-Details" Foreground="#A1A1AA" FontSize="13" FontWeight="SemiBold"/>
                <Grid Margin="0,14,0,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock x:Name="BranchStatusChangedLabel" Text="Geaendert" Foreground="#D4D4D8"/>
                  <TextBlock x:Name="BranchStatusChangedValue" Grid.Column="1" Text="0" Foreground="#86EFAC"/>
                </Grid>
                <Grid Margin="0,10,0,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock x:Name="BranchStatusAddedLabel" Text="Hinzugefuegt" Foreground="#D4D4D8"/>
                  <TextBlock x:Name="BranchStatusAddedValue" Grid.Column="1" Text="0" Foreground="#86EFAC"/>
                </Grid>
                <Grid Margin="0,10,0,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock x:Name="BranchStatusRemovedLabel" Text="Entfernt" Foreground="#D4D4D8"/>
                  <TextBlock x:Name="BranchStatusRemovedValue" Grid.Column="1" Text="0" Foreground="#F87171"/>
                </Grid>
                <WrapPanel Margin="0,14,0,0">
                  <Button x:Name="ShowChangesButton" Content="Aenderungen" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,0,10,10" Padding="12,0"/>
                  <Button x:Name="DoctorSideButton" Content="CLI-Doctor" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,0,10,10" Padding="12,0"/>
                  <Button x:Name="InitGitButton" Content="Git-Repo anlegen" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,0,10,10" Padding="12,0"/>
                  <Button x:Name="FetchBranchesButton" Content="Branches holen" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,0,10,10" Padding="12,0"/>
                  <Button x:Name="ShowBranchesButton" Content="Branches" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,0,10,10" Padding="12,0"/>
                  <Button x:Name="PushRepoButton" Content="Push" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,0,10,10" Padding="12,0"/>
                </WrapPanel>
              </StackPanel>
            </Border>

            <Border Background="#1F2227" BorderBrush="#30343B" BorderThickness="1" CornerRadius="18" Padding="16">
              <StackPanel>
                <TextBlock x:Name="SourcesTitle" Text="Quellen" Foreground="#A1A1AA" FontSize="13" FontWeight="SemiBold"/>
                <Button x:Name="WebSearchButton" Content="Internetsuche" Style="{StaticResource GhostButtonStyle}" Height="34" Margin="0,14,0,0" Padding="12,0"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </Border>
    </Grid>
    </Grid>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

function Get-Control {
    param([string]$Name)
    return $window.FindName($Name)
}

$LogoButton = Get-Control "LogoButton"
$TitleBar = Get-Control "TitleBar"
$BackNavButton = Get-Control "BackNavButton"
$ForwardNavButton = Get-Control "ForwardNavButton"
$NewChatNavButton = Get-Control "NewChatNavButton"
$SearchNavButton = Get-Control "SearchNavButton"
$PluginsNavButton = Get-Control "PluginsNavButton"
$AutomationNavButton = Get-Control "AutomationNavButton"
$SettingsNavButton = Get-Control "SettingsNavButton"
$NewChatTextButton = Get-Control "NewChatTextButton"
$SearchTextButton = Get-Control "SearchTextButton"
$PluginsTextButton = Get-Control "PluginsTextButton"
$AutomationTextButton = Get-Control "AutomationTextButton"
$ProjectNameText = Get-Control "ProjectNameText"
$ProjectPathText = Get-Control "ProjectPathText"
$ProjectChooseButton = Get-Control "ProjectChooseButton"
$ProjectAttachButton = Get-Control "ProjectAttachButton"
$ProjectOpenButton = Get-Control "ProjectOpenButton"
$NewThreadButton = Get-Control "NewThreadButton"
$RemoveThreadButton = Get-Control "RemoveThreadButton"
$ThreadList = Get-Control "ThreadList"
$ThreadTitleText = Get-Control "ThreadTitleText"
$ThreadSubtitleText = Get-Control "ThreadSubtitleText"
$ThreadMoreButton = Get-Control "ThreadMoreButton"
$WorkMetaPanel = Get-Control "WorkMetaPanel"
$SpinnerText = Get-Control "SpinnerText"
$WorkMetaText = Get-Control "WorkMetaText"
$ConversationScrollViewer = Get-Control "ConversationScrollViewer"
$ConversationStack = Get-Control "ConversationStack"
$PromptTextBox = Get-Control "PromptTextBox"
$SendButton = Get-Control "SendButton"
$AttachButton = Get-Control "AttachButton"
$ModelComboBox = Get-Control "ModelComboBox"
$PermissionComboBox = Get-Control "PermissionComboBox"
$GitRemoteLabel = Get-Control "GitRemoteLabel"
$GitRemoteTextBox = Get-Control "GitRemoteTextBox"
$FooterPermissionComboBox = Get-Control "FooterPermissionComboBox"
$TerminalButton = Get-Control "TerminalButton"
$MicButton = Get-Control "MicButton"
$HeaderRunButton = Get-Control "HeaderRunButton"
$StatusPill = Get-Control "StatusPill"
$StatusPillText = Get-Control "StatusPillText"
$ModelFooterText = Get-Control "ModelFooterText"
$WorkspaceModeText = Get-Control "WorkspaceModeText"
$BranchText = Get-Control "BranchText"
$BinaryPathText = Get-Control "BinaryPathText"
$SidebarProjectNameText = Get-Control "SidebarProjectNameText"
$SidebarProjectPathText = Get-Control "SidebarProjectPathText"
$WorkspaceCardTitle = Get-Control "WorkspaceCardTitle"
$BranchDetailsTitle = Get-Control "BranchDetailsTitle"
$SourcesTitle = Get-Control "SourcesTitle"
$BranchStatusChangedLabel = Get-Control "BranchStatusChangedLabel"
$BranchStatusChangedValue = Get-Control "BranchStatusChangedValue"
$BranchStatusAddedLabel = Get-Control "BranchStatusAddedLabel"
$BranchStatusAddedValue = Get-Control "BranchStatusAddedValue"
$BranchStatusRemovedLabel = Get-Control "BranchStatusRemovedLabel"
$BranchStatusRemovedValue = Get-Control "BranchStatusRemovedValue"
$OpenVSCodeButton = Get-Control "OpenVSCodeButton"
$OpenExplorerSideButton = Get-Control "OpenExplorerSideButton"
$OpenTerminalSideButton = Get-Control "OpenTerminalSideButton"
$ShowChangesButton = Get-Control "ShowChangesButton"
$DoctorSideButton = Get-Control "DoctorSideButton"
$WebSearchButton = Get-Control "WebSearchButton"
$InitGitButton = Get-Control "InitGitButton"
$FetchBranchesButton = Get-Control "FetchBranchesButton"
$ShowBranchesButton = Get-Control "ShowBranchesButton"
$PushRepoButton = Get-Control "PushRepoButton"
$ApprovalPanel = Get-Control "ApprovalPanel"
$ApprovalTitleText = Get-Control "ApprovalTitleText"
$ApprovalBodyText = Get-Control "ApprovalBodyText"
$ApproveOnceButton = Get-Control "ApproveOnceButton"
$ApproveSessionButton = Get-Control "ApproveSessionButton"
$DenyApprovalButton = Get-Control "DenyApprovalButton"
$MenuNewChat = Get-Control "MenuNewChat"
$MenuChooseProject = Get-Control "MenuChooseProject"
$MenuOpenExplorer = Get-Control "MenuOpenExplorer"
$MenuExit = Get-Control "MenuExit"
$MenuPasteClipboard = Get-Control "MenuPasteClipboard"
$MenuAttachFiles = Get-Control "MenuAttachFiles"
$MenuClearPrompt = Get-Control "MenuClearPrompt"
$MenuShowSearch = Get-Control "MenuShowSearch"
$MenuShowPlugins = Get-Control "MenuShowPlugins"
$MenuShowAutomation = Get-Control "MenuShowAutomation"
$MenuShowSettings = Get-Control "MenuShowSettings"
$MenuMinimize = Get-Control "MenuMinimize"
$MenuToggleMaximize = Get-Control "MenuToggleMaximize"
$MenuDoctor = Get-Control "MenuDoctor"
$MenuVersion = Get-Control "MenuVersion"
$MinimizeWindowButton = Get-Control "MinimizeWindowButton"
$MaximizeWindowButton = Get-Control "MaximizeWindowButton"
$CloseWindowButton = Get-Control "CloseWindowButton"

$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Choose the project folder Claw should work in"

$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.Title = "Choose files to reference in the prompt"
$openFileDialog.Multiselect = $true
$openFileDialog.Filter = "All files (*.*)|*.*"

$dispatcherTimer = New-Object System.Windows.Threading.DispatcherTimer
$dispatcherTimer.Interval = [TimeSpan]::FromMilliseconds(250)

$WorkspaceCardTitle.Text = T "Workspace"
$BranchDetailsTitle.Text = T "BranchDetails"
$SourcesTitle.Text = T "Sources"
$BranchStatusChangedLabel.Text = T "Changed"
$BranchStatusAddedLabel.Text = T "Added"
$BranchStatusRemovedLabel.Text = T "Removed"
$OpenVSCodeButton.Content = T "OpenVSCode"
$OpenExplorerSideButton.Content = T "OpenExplorer"
$OpenTerminalSideButton.Content = T "OpenTerminalShort"
$ShowChangesButton.Content = T "Changes"
$DoctorSideButton.Content = T "CliDoctor"
$WebSearchButton.Content = T "WebSearch"
$ThreadMoreButton.ToolTip = T "ThreadMenu"
$MicButton.ToolTip = T "StartDictation"
$GitRemoteLabel.Text = T "GitRemote"
$InitGitButton.Content = T "InitGitRepo"
$FetchBranchesButton.Content = T "FetchBranches"
$ShowBranchesButton.Content = T "ShowBranches"
$PushRepoButton.Content = T "PushRepo"
$ApprovalTitleText.Text = T "ApprovalNeeded"
$ApprovalBodyText.Text = T "ApprovalDetected"
$ApproveOnceButton.Content = T "ApproveOnce"
$ApproveSessionButton.Content = T "ApproveSession"
$DenyApprovalButton.Content = T "Deny"
Update-MicButtonState

function Get-ComboValue {
    param($ComboBox)
    if ($ComboBox.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) {
        return [string]$ComboBox.SelectedItem.Content
    }
    return [string]$ComboBox.Text
}

function Populate-ModelComboBox {
    param([string]$PreferredModel)

    $availableModels = Get-AvailableClawModels
    $ModelComboBox.Items.Clear()

    foreach ($model in $availableModels) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = $model
        [void]$ModelComboBox.Items.Add($item)
    }

    $selectedModel = $PreferredModel
    if ([string]::IsNullOrWhiteSpace($selectedModel) -or $availableModels -notcontains $selectedModel) {
        $selectedModel = if ($availableModels.Count -gt 0) { $availableModels[0] } else { "openai/qwen2.5-coder:7b" }
    }

    for ($i = 0; $i -lt $ModelComboBox.Items.Count; $i++) {
        if ([string]$ModelComboBox.Items[$i].Content -eq $selectedModel) {
            $ModelComboBox.SelectedIndex = $i
            break
        }
    }
}

function Set-ListSelectionByText {
    param(
        [System.Windows.Controls.ListBox]$ListBox,
        [string]$Content
    )

    foreach ($item in $ListBox.Items) {
        if ([string]$item.Tag -eq $Content) {
            $ListBox.SelectedItem = $item
            return
        }
    }
}

function Remove-ThreadItem {
    param([System.Windows.Controls.ListBoxItem]$Item)

    if ($null -eq $Item) {
        return
    }

    $wasSelected = ($ThreadList.SelectedItem -eq $Item)
    $ThreadList.Items.Remove($Item)

    if ($wasSelected) {
        if ($ThreadList.Items.Count -gt 0) {
            $ThreadList.SelectedIndex = 0
        } else {
            Update-ThreadTitle -Title (T "NewChat")
            $ThreadSubtitleText.Text = ""
        }
    }
}

function New-ThreadListItem {
    param([string]$Title)

    $entry = New-Object System.Windows.Controls.ListBoxItem
    $entry.Tag = $Title

    $grid = New-Object System.Windows.Controls.Grid
    $column1 = New-Object System.Windows.Controls.ColumnDefinition
    $column2 = New-Object System.Windows.Controls.ColumnDefinition
    $column2.Width = [System.Windows.GridLength]::Auto
    [void]$grid.ColumnDefinitions.Add($column1)
    [void]$grid.ColumnDefinitions.Add($column2)

    $text = New-Object System.Windows.Controls.TextBlock
    $text.Text = $Title
    $text.VerticalAlignment = "Center"
    $text.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E5E7EB")
    $text.TextTrimming = "CharacterEllipsis"
    [void]$grid.Children.Add($text)

    $deleteButton = New-Object System.Windows.Controls.Button
    $deleteButton.Content = [char]0xE74D
    $deleteButton.FontFamily = "Segoe MDL2 Assets"
    $deleteButton.FontSize = 11
    $deleteButton.Width = 24
    $deleteButton.Height = 24
    $deleteButton.Margin = [System.Windows.Thickness]::new(10,0,0,0)
    $deleteButton.ToolTip = "Entfernen"
    $deleteButton.Background = [System.Windows.Media.Brushes]::Transparent
    $deleteButton.BorderBrush = [System.Windows.Media.Brushes]::Transparent
    $deleteButton.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7C8793")
    $deleteButton.Cursor = "Hand"
    [System.Windows.Controls.Grid]::SetColumn($deleteButton, 1)
    $deleteButton.Add_Click({
        param($sender, $eventArgs)
        $eventArgs.Handled = $true
        Remove-ThreadItem -Item $entry
    })
    [void]$grid.Children.Add($deleteButton)

    $entry.Content = $grid
    return $entry
}

function Ensure-ThreadItem {
    param([string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return
    }

    foreach ($item in $ThreadList.Items) {
        if ([string]$item.Tag -eq $Title) {
            $ThreadList.SelectedItem = $item
            return
        }
    }

    $entry = New-ThreadListItem -Title $Title
    [void]$ThreadList.Items.Insert(0, $entry)
    $ThreadList.SelectedItem = $entry
}

function Sync-PermissionCombo {
    $FooterPermissionComboBox.Items.Clear()
    foreach ($item in $PermissionComboBox.Items) {
        $copy = New-Object System.Windows.Controls.ComboBoxItem
        $copy.Content = $item.Content
        [void]$FooterPermissionComboBox.Items.Add($copy)
    }
    $FooterPermissionComboBox.SelectedIndex = $PermissionComboBox.SelectedIndex
}

Sync-PermissionCombo

$ThreadList.Items.Clear()
foreach ($title in @(
    (T "InstallTitle"),
    (T "RepoAnalyze"),
    (T "BuildInvestigate"),
    (T "NextFix")
)) {
    [void]$ThreadList.Items.Add((New-ThreadListItem -Title $title))
}
$ThreadList.SelectedIndex = 0

function Set-Status {
    param(
        [string]$Text,
        [string]$ForegroundHex,
        [string]$BackgroundHex
    )

    $StatusPillText.Text = $Text
    $StatusPill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($BackgroundHex)
    $StatusPillText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($ForegroundHex)
}

function Scroll-To-Bottom {
    $window.Dispatcher.Invoke([action]{
        $ConversationScrollViewer.ScrollToEnd()
    }, [System.Windows.Threading.DispatcherPriority]::Background)
}

function New-MessageBubble {
    param(
        [string]$Role,
        [string]$Text,
        [string]$RoleColor,
        [bool]$IsUser = $false,
        [bool]$UseMono = $false
    )

    $outer = New-Object System.Windows.Controls.Grid
    $outer.Margin = [System.Windows.Thickness]::new(0,0,0,16)

    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = [System.Windows.CornerRadius]::new(18)
    $border.Padding = [System.Windows.Thickness]::new(18,14,18,14)
    $border.MaxWidth = 900
    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if ($IsUser) { $script:Theme.UserBubble } else { $script:Theme.AssistantBubble }))
    $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($script:Theme.Border)
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $border.HorizontalAlignment = $(if ($IsUser) { "Right" } else { "Left" })

    $stack = New-Object System.Windows.Controls.StackPanel

    $roleBlock = New-Object System.Windows.Controls.TextBlock
    $roleBlock.Text = $Role
    $roleBlock.FontWeight = "SemiBold"
    $roleBlock.FontSize = 13
    $roleBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($RoleColor)
    $stack.Children.Add($roleBlock) | Out-Null

    $body = New-Object System.Windows.Controls.TextBox
    $body.Text = $Text
    $body.TextWrapping = "Wrap"
    $body.Margin = [System.Windows.Thickness]::new(0,8,0,0)
    $body.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($script:Theme.Foreground)
    $body.FontSize = 14
    $body.Background = [System.Windows.Media.Brushes]::Transparent
    $body.BorderThickness = [System.Windows.Thickness]::new(0)
    $body.IsReadOnly = $true
    $body.IsReadOnlyCaretVisible = $true
    $body.AcceptsReturn = $true
    $body.VerticalScrollBarVisibility = "Disabled"
    $body.HorizontalScrollBarVisibility = "Disabled"
    $body.SelectionBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#334155")
    $body.SelectionOpacity = 0.95
    $body.Cursor = "IBeam"
    if ($UseMono) {
        $body.FontFamily = "Cascadia Mono"
    }
    $stack.Children.Add($body) | Out-Null

    $border.Child = $stack
    $outer.Children.Add($border) | Out-Null
    return @{
        Container = $outer
        TextBlock = $body
    }
}

function Add-Conversation {
    param(
        [string]$Role,
        [string]$Text,
        [string]$RoleColor,
        [bool]$IsUser = $false,
        [bool]$UseMono = $false
    )

    $message = New-MessageBubble -Role $Role -Text $Text -RoleColor $RoleColor -IsUser:$IsUser -UseMono:$UseMono
    $ConversationStack.Children.Add($message.Container) | Out-Null
    Scroll-To-Bottom
    return $message
}

function Start-AssistantStream {
    param([string]$Title)

    $message = Add-Conversation -Role "Claw" -Text "$Title`r`n" -RoleColor $script:Theme.Green -UseMono:$true
    $script:ActiveOutputControl = $message.TextBlock
}

function Append-StreamText {
    param([string]$Text)

    $safeText = Sanitize-UiText -Text $Text
    if ($script:ActiveOutputControl -and -not [string]::IsNullOrEmpty($safeText)) {
        $script:ActiveOutputControl.Text += $safeText
        Scroll-To-Bottom
    }

    if ($safeText -match "Permission approval required") {
        Handle-ApprovalRequired
    }
}

function Get-GitChangeSummary {
    param([string]$Path)

    $summary = @{
        Changed = 0
        Added = 0
        Removed = 0
        IsRepo = $false
    }

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $summary
    }

    try {
        $inside = git -C $Path rev-parse --is-inside-work-tree 2>$null
        if (-not $inside -or ($inside | Select-Object -First 1).Trim() -ne "true") {
            return $summary
        }
        $summary.IsRepo = $true

        $lines = git -C $Path status --short 2>$null
        foreach ($line in @($lines)) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 2) {
                continue
            }

            $x = $line.Substring(0,1)
            $y = $line.Substring(1,1)
            foreach ($status in @($x, $y)) {
                switch ($status) {
                    "A" { $summary.Added++ }
                    "M" { $summary.Changed++ }
                    "D" { $summary.Removed++ }
                    "R" { $summary.Changed++ }
                    "C" { $summary.Added++ }
                    "U" { $summary.Changed++ }
                }
            }
        }
    } catch {
    }

    return $summary
}

function Move-ThreadSelection {
    param([int]$Offset)

    if ($ThreadList.Items.Count -eq 0) {
        return
    }

    $currentIndex = $ThreadList.SelectedIndex
    if ($currentIndex -lt 0) {
        $currentIndex = 0
    }

    $nextIndex = [math]::Min($ThreadList.Items.Count - 1, [math]::Max(0, $currentIndex + $Offset))
    $ThreadList.SelectedIndex = $nextIndex
    $ThreadList.ScrollIntoView($ThreadList.SelectedItem)
}

function Open-InVSCode {
    if ([string]::IsNullOrWhiteSpace($script:ProjectPath) -or -not (Test-Path -LiteralPath $script:ProjectPath)) {
        return
    }

    $codeCommand = Get-Command code -ErrorAction SilentlyContinue
    if ($codeCommand -and -not [string]::IsNullOrWhiteSpace($codeCommand.Source)) {
        Start-Process -FilePath $codeCommand.Source -ArgumentList @($script:ProjectPath) | Out-Null
        return
    }

    Start-Process explorer.exe -ArgumentList @($script:ProjectPath) | Out-Null
}

function Update-MicButtonState {
    if ($script:IsSpeechListening) {
        $MicButton.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
        $MicButton.ToolTip = T "StopDictation"
    } else {
        $MicButton.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A1A1AA")
        $MicButton.ToolTip = T "StartDictation"
    }
}

function Ensure-SpeechRecognizer {
    if ($script:SpeechRecognizer) {
        return $true
    }

    try {
        $recognizer = New-Object System.Speech.Recognition.SpeechRecognitionEngine
        $recognizer.SetInputToDefaultAudioDevice()
        $recognizer.LoadGrammar([System.Speech.Recognition.DictationGrammar]::new())
        $recognizer.add_SpeechRecognized({
            param($sender, $eventArgs)
            $text = $eventArgs.Result.Text
            if ([string]::IsNullOrWhiteSpace($text)) {
                return
            }

            $window.Dispatcher.Invoke([action]{
                if (-not [string]::IsNullOrWhiteSpace($PromptTextBox.Text) -and -not $PromptTextBox.Text.EndsWith(" ") -and -not $PromptTextBox.Text.EndsWith("`n")) {
                    $PromptTextBox.Text += " "
                }
                $PromptTextBox.Text += $text.Trim()
                Focus-Composer
            })
        })
        $script:SpeechRecognizer = $recognizer
        return $true
    } catch {
        Add-Conversation -Role "Status" -Text (T "DictationUnavailable") -RoleColor $script:Theme.Yellow | Out-Null
        return $false
    }
}

function Toggle-Dictation {
    if (-not (Ensure-SpeechRecognizer)) {
        return
    }

    try {
        if ($script:IsSpeechListening) {
            $script:SpeechRecognizer.RecognizeAsyncStop()
            $script:IsSpeechListening = $false
            Update-MicButtonState
            Add-Conversation -Role "Status" -Text (T "DictationStopped") -RoleColor $script:Theme.Muted | Out-Null
            return
        }

        $script:SpeechRecognizer.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Multiple)
        $script:IsSpeechListening = $true
        Update-MicButtonState
        Add-Conversation -Role "Status" -Text (T "DictationReady") -RoleColor $script:Theme.Green | Out-Null
    } catch {
        Handle-StudioException -Context "Dictation" -Exception $_.Exception
    }
}

function Refresh-ProjectState {
    $leaf = Split-Path -Leaf $script:ProjectPath
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        $leaf = "claw"
    }
    $ProjectNameText.Text = $leaf
    $ProjectPathText.Text = $script:ProjectPath
    $SidebarProjectNameText.Text = $leaf
    $SidebarProjectPathText.Text = $script:ProjectPath
    $BranchText.Text = Get-GitBranch -Path $script:ProjectPath
    $BinaryPathText.Text = Find-ClawBinary
    $ModelFooterText.Text = "$(Get-ComboValue -ComboBox $ModelComboBox)"

    $status = Get-GitChangeSummary -Path $script:ProjectPath
    if ($status.IsRepo) {
        $BranchStatusChangedValue.Text = [string]$status.Changed
        $BranchStatusAddedValue.Text = [string]$status.Added
        $BranchStatusRemovedValue.Text = [string]$status.Removed
    } else {
        $BranchStatusChangedValue.Text = T "NoRepo"
        $BranchStatusAddedValue.Text = "-"
        $BranchStatusRemovedValue.Text = "-"
    }
}

function Focus-Composer {
    $PromptTextBox.Focus() | Out-Null
    $PromptTextBox.CaretIndex = $PromptTextBox.Text.Length
}

function Update-WorkMeta {
    if ($null -eq $WorkMetaText -or $null -eq $WorkMetaPanel) {
        return
    }

    if ($script:CurrentProcess -and $script:RunStartedAt) {
        $seconds = [math]::Max(0, [int]([DateTime]::Now - $script:RunStartedAt).TotalSeconds)
        $script:SpinnerIndex = ($script:SpinnerIndex + 1) % $script:SpinnerFrames.Count
        $SpinnerText.Text = $script:SpinnerFrames[$script:SpinnerIndex]
        $WorkMetaText.Text = T "ProcessingSince" @($seconds)
        $WorkMetaPanel.Visibility = "Visible"
        return
    }

    $WorkMetaPanel.Visibility = "Collapsed"
}

function Handle-StudioException {
    param(
        [string]$Context,
        [System.Exception]$Exception
    )

    $message = if ($Exception) { $Exception.Message } else { "Unknown error" }
    Write-StudioErrorLog -Message ("{0}: {1}" -f $Context, $message)

    try {
        if ($dispatcherTimer) { $dispatcherTimer.Stop() }
    } catch {
    }

    try {
        if ($script:StdOutWriter) { $script:StdOutWriter.Dispose() }
        if ($script:StdErrWriter) { $script:StdErrWriter.Dispose() }
    } catch {
    }

    $script:StdOutWriter = $null
    $script:StdErrWriter = $null
    $script:ActiveOutputControl = $null
    $script:RunStartedAt = $null
    if (-not [string]::IsNullOrWhiteSpace($script:CurrentRunnerPath) -and (Test-Path -LiteralPath $script:CurrentRunnerPath)) {
        Remove-Item -LiteralPath $script:CurrentRunnerPath -Force -ErrorAction SilentlyContinue
    }
    $script:CurrentRunnerPath = ""
    $script:CurrentProcess = $null

    try {
        Set-UiBusy -Busy $false
        Set-Status -Text (T "NeedsAttention") -ForegroundHex $script:Theme.Red -BackgroundHex "#5A1F24"
        $ThreadSubtitleText.Text = T "InternalError"
        Update-WorkMeta
        Add-Conversation -Role "Status" -Text (T "UiError" @($Context, $message)) -RoleColor $script:Theme.Red | Out-Null
    } catch {
        Write-StudioErrorLog -Message ("Secondary UI error while handling exception: {0}" -f $_.Exception.Message)
    }
}

function Handle-ApprovalRequired {
    if ($script:ApprovalPending) {
        return
    }

    $dispatcherTimer.Stop()
    try {
        if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
            $script:CurrentProcess.Kill()
        }
    } catch {
    }

    $script:CurrentProcess = $null
    $script:RunStartedAt = $null
    Set-UiBusy -Busy $false
    Update-WorkMeta
    Set-Status -Text (T "ApprovalNeeded") -ForegroundHex $script:Theme.Yellow -BackgroundHex "#493912"
    $ThreadSubtitleText.Text = T "ApprovalNeeded"
    Set-ApprovalState -Visible $true
}

function Open-ProjectPicker {
    if (Test-Path -LiteralPath $script:ProjectPath) {
        $folderBrowser.SelectedPath = $script:ProjectPath
    }
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:ProjectPath = $folderBrowser.SelectedPath
        Save-CurrentSettings
        Refresh-ProjectState
        Add-Conversation -Role "Status" -Text (T "ProjectSwitched" @($script:ProjectPath)) -RoleColor $script:Theme.Green | Out-Null
    }
}

function Prepare-SearchView {
    Update-ThreadTitle -Title (T "RepoAnalyze")
    $ThreadSubtitleText.Text = T "Prepared"
    $PromptTextBox.Text = "Search this repository for the main entry points, main screens, and the code that wires the app together."
    Focus-Composer
}

function Prepare-PluginsView {
    Update-ThreadTitle -Title (T "BuildInvestigate")
    $ThreadSubtitleText.Text = T "Prepared"
    $PromptTextBox.Text = "Inspect this project for build issues, missing dependencies, brittle scripts, and Windows-specific pitfalls."
    Focus-Composer
}

function Prepare-AutomationView {
    Update-ThreadTitle -Title (T "NextFix")
    $ThreadSubtitleText.Text = T "Prepared"
    $PromptTextBox.Text = "Review the current app UX and suggest the next three concrete fixes with the highest user impact."
    Focus-Composer
}

function Open-SettingsView {
    $ThreadSubtitleText.Text = T "Configure"
    $ModelComboBox.Focus() | Out-Null
    Add-Conversation -Role "Status" -Text (T "SettingsReady") -RoleColor $script:Theme.Blue | Out-Null
}

function Insert-ClipboardIntoPrompt {
    try {
        $clipText = [System.Windows.Clipboard]::GetText()
    } catch {
        $clipText = ""
    }

    if ([string]::IsNullOrWhiteSpace($clipText)) {
        Add-Conversation -Role "Status" -Text (T "ClipboardEmpty") -RoleColor $script:Theme.Yellow | Out-Null
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($PromptTextBox.Text)) {
        $PromptTextBox.Text += "`r`n"
    }
    $PromptTextBox.Text += $clipText.Trim()
    Focus-Composer
}

function Attach-FilesToPrompt {
    if (Test-Path -LiteralPath $script:ProjectPath) {
        $openFileDialog.InitialDirectory = $script:ProjectPath
    }

    if ($openFileDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    $selectedPaths = @($openFileDialog.FileNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($selectedPaths.Count -eq 0) {
        return
    }

    $pathsText = ($selectedPaths | ForEach-Object { "- $_" }) -join "`r`n"
    $block = "Use these files as context:`r`n$pathsText"
    if (-not [string]::IsNullOrWhiteSpace($PromptTextBox.Text)) {
        $PromptTextBox.Text += "`r`n`r`n"
    }
    $PromptTextBox.Text += $block
    Focus-Composer
    Add-Conversation -Role "Status" -Text (T "FilesAttached" @($selectedPaths.Count)) -RoleColor $script:Theme.Green | Out-Null
}

function Save-CurrentSettings {
    Save-Settings -ProjectPath $script:ProjectPath -Model (Get-ComboValue -ComboBox $ModelComboBox) -PermissionMode (Get-ComboValue -ComboBox $PermissionComboBox) -GitRemoteUrl $GitRemoteTextBox.Text
}

function Set-UiBusy {
    param([bool]$Busy)

    $ProjectChooseButton.IsEnabled = -not $Busy
    $ProjectOpenButton.IsEnabled = -not $Busy
    $NewThreadButton.IsEnabled = -not $Busy
    $ThreadList.IsEnabled = -not $Busy
    $ModelComboBox.IsEnabled = -not $Busy
    $PermissionComboBox.IsEnabled = -not $Busy
    $FooterPermissionComboBox.IsEnabled = -not $Busy
    $SendButton.IsEnabled = -not $Busy
    $TerminalButton.IsEnabled = -not $Busy
    $HeaderRunButton.IsEnabled = -not $Busy
}

function Set-ApprovalState {
    param([bool]$Visible)

    $script:ApprovalPending = $Visible
    $ApprovalPanel.Visibility = $(if ($Visible) { "Visible" } else { "Collapsed" })
}

function Update-ThreadTitle {
    param([string]$Title)
    $script:CurrentThreadTitle = $Title
    $ThreadTitleText.Text = $Title
    Ensure-ThreadItem -Title $Title
}

function Toggle-WindowState {
    if ($window.WindowState -eq [System.Windows.WindowState]::Maximized) {
        $window.WindowState = [System.Windows.WindowState]::Normal
    } else {
        $window.WindowState = [System.Windows.WindowState]::Maximized
    }
}

function Validate-RunContext {
    $clawBinary = Find-ClawBinary
    if ([string]::IsNullOrWhiteSpace($clawBinary) -or -not (Test-Path -LiteralPath $clawBinary)) {
        [System.Windows.MessageBox]::Show((T "MissingClaw"), "Claw Studio") | Out-Null
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($script:ProjectPath) -or -not (Test-Path -LiteralPath $script:ProjectPath)) {
        [System.Windows.MessageBox]::Show((T "ChooseValidProject"), "Claw Studio") | Out-Null
        return $false
    }

    if (Test-BroadProjectPath -Path $script:ProjectPath) {
        $result = [System.Windows.MessageBox]::Show((T "BroadFolder"), "Claw Studio", "YesNo", "Warning")
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
            return $false
        }
    }

    return $true
}

function Start-Command {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$Label
    )

    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        [System.Windows.MessageBox]::Show((T "TaskAlreadyRunning"), "Claw Studio") | Out-Null
        return
    }

    $script:StdOutPath = Join-Path $StudioRoot ("stdout-" + [guid]::NewGuid().ToString("N") + ".log")
    $script:StdErrPath = Join-Path $StudioRoot ("stderr-" + [guid]::NewGuid().ToString("N") + ".log")
    $runnerPath = Join-Path $StudioRoot ("runner-" + [guid]::NewGuid().ToString("N") + ".ps1")
    $script:CurrentRunnerPath = $runnerPath
    $script:StdOutPosition = 0L
    $script:StdErrPosition = 0L
    "" | Set-Content -LiteralPath $script:StdOutPath -Encoding UTF8
    "" | Set-Content -LiteralPath $script:StdErrPath -Encoding UTF8

    Add-Conversation -Role "You" -Text $Label -RoleColor $script:Theme.Blue -IsUser:$true | Out-Null
    Start-AssistantStream -Title (T "RunningIn" @($WorkingDirectory))

    $argumentListLiteral = "@(" + (($Arguments | ForEach-Object { ConvertTo-PowerShellStringLiteral -Value ([string]$_) }) -join ", ") + ")"
    $runnerScript = @"
`$ErrorActionPreference = 'Continue'
`$OutputEncoding = [System.Text.UTF8Encoding]::new(`$false)
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new(`$false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(`$false)
`$env:OPENAI_BASE_URL = $(ConvertTo-PowerShellStringLiteral -Value (Get-ConfiguredEnvironmentValue -Name "OPENAI_BASE_URL" -Fallback "http://127.0.0.1:11434/v1"))
`$env:OPENAI_API_KEY = $(ConvertTo-PowerShellStringLiteral -Value (Get-ConfiguredEnvironmentValue -Name "OPENAI_API_KEY" -Fallback "local-dev-token"))
`$env:NO_COLOR = '1'
`$env:CLICOLOR = '0'
`$env:CLICOLOR_FORCE = '0'
`$env:TERM = 'dumb'
Set-Location -LiteralPath $(ConvertTo-PowerShellStringLiteral -Value $WorkingDirectory)
`$argumentList = $argumentListLiteral
& $(ConvertTo-PowerShellStringLiteral -Value $Executable) @argumentList 1>> $(ConvertTo-PowerShellStringLiteral -Value $script:StdOutPath) 2>> $(ConvertTo-PowerShellStringLiteral -Value $script:StdErrPath)
exit `$LASTEXITCODE
"@
    Set-Content -LiteralPath $runnerPath -Value $runnerScript -Encoding UTF8

    $process = New-Object System.Diagnostics.Process
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + (ConvertTo-ArgumentString -Arguments @($runnerPath))
    $process.StartInfo = $startInfo

    try {
        [void]$process.Start()
    } catch {
        try {
            if (Test-Path -LiteralPath $runnerPath) { Remove-Item -LiteralPath $runnerPath -Force -ErrorAction SilentlyContinue }
        } catch {
        }
        $script:CurrentRunnerPath = ""
        $script:StdOutWriter = $null
        $script:StdErrWriter = $null
        Add-Conversation -Role "Status" -Text (T "TaskStartFailed" @($_.Exception.Message)) -RoleColor $script:Theme.Red | Out-Null
        Set-Status -Text (T "NeedsAttention") -ForegroundHex $script:Theme.Red -BackgroundHex "#5A1F24"
        $ThreadSubtitleText.Text = T "StartFailed"
        Set-UiBusy -Busy $false
        Update-WorkMeta
        return
    }

    $script:CurrentProcess = $process
    $script:RunStartedAt = [DateTime]::Now
    Set-UiBusy -Busy $true
    Set-Status -Text (T "Running") -ForegroundHex $script:Theme.Yellow -BackgroundHex "#493912"
    $ThreadSubtitleText.Text = T "Thinking"
    Update-WorkMeta
    $dispatcherTimer.Start()
}

function Run-WorkspaceCommand {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($script:ProjectPath) -or -not (Test-Path -LiteralPath $script:ProjectPath)) {
        return
    }

    Set-ApprovalState -Visible $false
    Start-Command -Executable $Executable -Arguments $Arguments -WorkingDirectory $script:ProjectPath -Label $Label
}

function Run-ClawCommand {
    param(
        [string[]]$Arguments,
        [string]$PromptText
    )

    if (-not (Validate-RunContext)) {
        return
    }

    Save-CurrentSettings
    Refresh-ProjectState
    $script:LastCommandArguments = @($Arguments)
    if ($script:ApprovalForSession -and ($script:LastCommandArguments -notcontains "--dangerously-skip-permissions")) {
        $script:LastCommandArguments = @("--dangerously-skip-permissions") + $script:LastCommandArguments
    }
    $script:LastCommandLabel = $PromptText
    Set-ApprovalState -Visible $false
    Start-Command -Executable (Find-ClawBinary) -Arguments $script:LastCommandArguments -WorkingDirectory $script:ProjectPath -Label $PromptText
}

$settings = Get-Settings
$script:ProjectPath = Get-DefaultProjectPath
$GitRemoteTextBox.Text = Get-DefaultGitRemoteUrl

$modelValue = Get-DefaultModel
Populate-ModelComboBox -PreferredModel $modelValue

$permissionValue = Get-DefaultPermissionMode
for ($i = 0; $i -lt $PermissionComboBox.Items.Count; $i++) {
    if ([string]$PermissionComboBox.Items[$i].Content -eq $permissionValue) {
        $PermissionComboBox.SelectedIndex = $i
        break
    }
}
Sync-PermissionCombo

$PromptTextBox.Text = "Analyze this repository. Explain the architecture, build flow, dependencies, risky areas, and the first improvement you would make."
Refresh-ProjectState
Update-ThreadTitle -Title $script:CurrentThreadTitle
$ThreadSubtitleText.Text = T "Ready"
Add-Conversation -Role "System" -Text (T "SystemReady") -RoleColor $script:Theme.Muted | Out-Null
Add-Conversation -Role "Tip" -Text (T "TipReady") -RoleColor $script:Theme.Yellow | Out-Null

$dispatcherTimer.Add_Tick({
    try {
        Update-WorkMeta

        if ($script:StdOutPath) {
            $newOut = Read-NewText -Path $script:StdOutPath -Position ([ref]$script:StdOutPosition)
            if (-not [string]::IsNullOrEmpty($newOut)) {
                Append-StreamText -Text $newOut
            }
        }

        if ($script:StdErrPath) {
            $newErr = Read-NewText -Path $script:StdErrPath -Position ([ref]$script:StdErrPosition)
            if (-not [string]::IsNullOrEmpty($newErr)) {
                Append-StreamText -Text $newErr
            }
        }

        if ($script:CurrentProcess -and $script:CurrentProcess.HasExited) {
            $dispatcherTimer.Stop()
            $finishedProcess = $script:CurrentProcess
            $exitCode = $finishedProcess.ExitCode
            try {
                if ($script:StdOutWriter) { $script:StdOutWriter.Dispose() }
                if ($script:StdErrWriter) { $script:StdErrWriter.Dispose() }
            } catch {
            }
            $script:StdOutWriter = $null
            $script:StdErrWriter = $null
            $script:ActiveOutputControl = $null
            $script:RunStartedAt = $null
            if (-not [string]::IsNullOrWhiteSpace($script:CurrentRunnerPath) -and (Test-Path -LiteralPath $script:CurrentRunnerPath)) {
                Remove-Item -LiteralPath $script:CurrentRunnerPath -Force -ErrorAction SilentlyContinue
            }
            $script:CurrentRunnerPath = ""
            Update-WorkMeta
            if ($exitCode -eq 0) {
                Set-Status -Text (T "Ready") -ForegroundHex $script:Theme.Green -BackgroundHex "#1F4A34"
                $ThreadSubtitleText.Text = T "Finished"
            } else {
                Add-Conversation -Role "Status" -Text (T "ProcessFail" @($exitCode)) -RoleColor $script:Theme.Red | Out-Null
                Set-Status -Text (T "NeedsAttention") -ForegroundHex $script:Theme.Red -BackgroundHex "#5A1F24"
                $ThreadSubtitleText.Text = T "Failed"
            }
            Set-UiBusy -Busy $false
            $finishedProcess.Dispose()
            $script:CurrentProcess = $null
        }
    } catch {
        Handle-StudioException -Context "DispatcherTimer" -Exception $_.Exception
    }
})

$sendAction = {
    try {
        $prompt = $PromptTextBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($prompt)) {
            return
        }

        Run-ClawCommand -Arguments @(
            "--model", (Get-ComboValue -ComboBox $ModelComboBox),
            "--permission-mode", (Get-ComboValue -ComboBox $PermissionComboBox),
            "--compact",
            "--output-format", "text",
            "prompt", $prompt
        ) -PromptText $prompt
    } catch {
        Handle-StudioException -Context "SendAction" -Exception $_.Exception
    }
}

$SendButton.Add_Click({ & $sendAction })
$HeaderRunButton.Add_Click({ & $sendAction })
$newChatAction = {
    $ConversationStack.Children.Clear()
    Update-ThreadTitle -Title (T "NewChat")
    $ThreadSubtitleText.Text = T "JustCreated"
    $script:RunStartedAt = $null
    Update-WorkMeta
    $PromptTextBox.Text = ""
    Focus-Composer
    Add-Conversation -Role "System" -Text (T "FreshChat") -RoleColor $script:Theme.Muted | Out-Null
}
$NewChatNavButton.Add_Click({ & $newChatAction })
$NewChatTextButton.Add_Click({ & $newChatAction })
$NewThreadButton.Add_Click({
    $ConversationStack.Children.Clear()
    Update-ThreadTitle -Title ("{0} in {1}" -f (T "NewChat"), $ProjectNameText.Text)
    $ThreadSubtitleText.Text = T "JustCreated"
    $script:RunStartedAt = $null
    Update-WorkMeta
    $PromptTextBox.Text = ""
    Focus-Composer
    Add-Conversation -Role "System" -Text (T "FreshProjectChat") -RoleColor $script:Theme.Muted | Out-Null
})
$RemoveThreadButton.Add_Click({
    $ConversationStack.Children.Clear()
    $PromptTextBox.Text = ""
    $script:RunStartedAt = $null
    Update-WorkMeta
    Focus-Composer
    Add-Conversation -Role "System" -Text (T "ChatReset") -RoleColor $script:Theme.Muted | Out-Null
})
$ProjectChooseButton.Add_Click({ Open-ProjectPicker })
$ProjectAttachButton.Add_Click({
    Open-ProjectPicker
})
$ProjectOpenButton.Add_Click({
    if (Test-Path -LiteralPath $script:ProjectPath) {
        Start-Process explorer.exe -ArgumentList @($script:ProjectPath) | Out-Null
    }
})
$ThreadList.Add_SelectionChanged({
    if ($ThreadList.SelectedItem -and $ThreadList.SelectedItem.Tag) {
        Update-ThreadTitle -Title ([string]$ThreadList.SelectedItem.Tag)
    }
})
$ModelComboBox.Add_SelectionChanged({
    Save-CurrentSettings
    $ModelFooterText.Text = Get-ComboValue -ComboBox $ModelComboBox
})
$PermissionComboBox.Add_SelectionChanged({
    if ($FooterPermissionComboBox.SelectedIndex -ne $PermissionComboBox.SelectedIndex) {
        $FooterPermissionComboBox.SelectedIndex = $PermissionComboBox.SelectedIndex
    }
    Save-CurrentSettings
})
$FooterPermissionComboBox.Add_SelectionChanged({
    if ($PermissionComboBox.SelectedIndex -ne $FooterPermissionComboBox.SelectedIndex) {
        $PermissionComboBox.SelectedIndex = $FooterPermissionComboBox.SelectedIndex
    }
    Save-CurrentSettings
})
$PromptTextBox.Add_PreviewKeyDown({
    $modifiers = [System.Windows.Input.Keyboard]::Modifiers
    if ($_.Key -eq [System.Windows.Input.Key]::Enter -and -not ($modifiers -band [System.Windows.Input.ModifierKeys]::Shift)) {
        $_.Handled = $true
        & $sendAction
    }
})
$ApproveOnceButton.Add_Click({
    Set-ApprovalState -Visible $false
    if ($script:LastCommandArguments.Count -gt 0) {
        Start-Command -Executable (Find-ClawBinary) -Arguments (@("--dangerously-skip-permissions") + $script:LastCommandArguments) -WorkingDirectory $script:ProjectPath -Label $script:LastCommandLabel
    }
})
$ApproveSessionButton.Add_Click({
    $script:ApprovalForSession = $true
    Set-ApprovalState -Visible $false
    if ($script:LastCommandArguments.Count -gt 0) {
        $rerunArgs = @($script:LastCommandArguments)
        if ($rerunArgs -notcontains "--dangerously-skip-permissions") {
            $rerunArgs = @("--dangerously-skip-permissions") + $rerunArgs
        }
        Start-Command -Executable (Find-ClawBinary) -Arguments $rerunArgs -WorkingDirectory $script:ProjectPath -Label $script:LastCommandLabel
    }
})
$DenyApprovalButton.Add_Click({
    Set-ApprovalState -Visible $false
    Add-Conversation -Role "Status" -Text (T "ApprovalDenied") -RoleColor $script:Theme.Yellow | Out-Null
})
$InitGitButton.Add_Click({
    Run-WorkspaceCommand -Executable (Find-CommandBinary "git") -Arguments @("init") -Label "git init"
})
$FetchBranchesButton.Add_Click({
    Run-WorkspaceCommand -Executable (Find-CommandBinary "git") -Arguments @("fetch","--all","--prune") -Label "git fetch --all --prune"
})
$ShowBranchesButton.Add_Click({
    Run-WorkspaceCommand -Executable (Find-CommandBinary "git") -Arguments @("branch","-a") -Label "git branch -a"
})
$PushRepoButton.Add_Click({
    $remoteUrl = $GitRemoteTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
        Add-Conversation -Role "Status" -Text (T "GitRemoteMissing") -RoleColor $script:Theme.Yellow | Out-Null
        return
    }

    $gitBinary = Find-CommandBinary "git"
    if (-not (Test-Path -LiteralPath (Join-Path $script:ProjectPath ".git"))) {
        Run-WorkspaceCommand -Executable $gitBinary -Arguments @("init") -Label "git init"
        return
    }

    $branch = Get-GitBranch -Path $script:ProjectPath
    if ([string]::IsNullOrWhiteSpace($branch) -or $branch -eq "master") {
        $branch = "main"
    }

    $scriptBlock = @(
        '$ErrorActionPreference = "Stop"'
        ('Set-Location -LiteralPath {0}' -f (ConvertTo-PowerShellStringLiteral -Value $script:ProjectPath))
        ('if (-not (git remote | Select-String -SimpleMatch "origin" -Quiet)) { git remote add origin {0} } else { git remote set-url origin {0} }' -f (ConvertTo-PowerShellStringLiteral -Value $remoteUrl))
        ('git push -u origin {0}' -f $branch)
    ) -join '; '
    Run-WorkspaceCommand -Executable "powershell.exe" -Arguments @("-NoProfile","-Command",$scriptBlock) -Label "git push"
})
$TerminalButton.Add_Click({
    try {
        if (-not (Validate-RunContext)) {
            return
        }

        $clawBinary = Find-ClawBinary
        $command = "`$env:OPENAI_BASE_URL='{0}'; `$env:OPENAI_API_KEY='{1}'; Set-Location -LiteralPath '{2}'; & '{3}' --model '{4}' --permission-mode '{5}'" -f `
            (Get-ConfiguredEnvironmentValue -Name "OPENAI_BASE_URL" -Fallback "http://127.0.0.1:11434/v1").Replace("'", "''"), `
            (Get-ConfiguredEnvironmentValue -Name "OPENAI_API_KEY" -Fallback "local-dev-token").Replace("'", "''"), `
            $script:ProjectPath.Replace("'", "''"), `
            $clawBinary.Replace("'", "''"), `
            (Get-ComboValue -ComboBox $ModelComboBox).Replace("'", "''"), `
            (Get-ComboValue -ComboBox $PermissionComboBox).Replace("'", "''")

        Start-Process powershell.exe -ArgumentList @("-NoExit", "-Command", $command) -WorkingDirectory $script:ProjectPath | Out-Null
        Add-Conversation -Role "Status" -Text (T "OpenedTerminal") -RoleColor $script:Theme.Green | Out-Null
    } catch {
        Handle-StudioException -Context "TerminalButton" -Exception $_.Exception
    }
})
$AttachButton.Add_Click({
    Attach-FilesToPrompt
})
$SearchNavButton.Add_Click({ Prepare-SearchView })
$SearchTextButton.Add_Click({ Prepare-SearchView })
$PluginsNavButton.Add_Click({ Prepare-PluginsView })
$PluginsTextButton.Add_Click({ Prepare-PluginsView })
$AutomationNavButton.Add_Click({ Prepare-AutomationView })
$AutomationTextButton.Add_Click({ Prepare-AutomationView })
$SettingsNavButton.Add_Click({ Open-SettingsView })
$MicButton.Add_Click({ Toggle-Dictation })
$LogoButton.Add_Click({ Toggle-WindowState })
$TitleBar.Add_MouseLeftButtonDown({
    if ($_.ClickCount -ge 2) {
        Toggle-WindowState
        return
    }

    try {
        $window.DragMove()
    } catch {
    }
})
$MinimizeWindowButton.Add_Click({
    $window.WindowState = [System.Windows.WindowState]::Minimized
})
$MaximizeWindowButton.Add_Click({
    Toggle-WindowState
})
$CloseWindowButton.Add_Click({
    $window.Close()
})
$MenuNewChat.Add_Click({ & $newChatAction })
$MenuChooseProject.Add_Click({ Open-ProjectPicker })
$MenuOpenExplorer.Add_Click({
    if (Test-Path -LiteralPath $script:ProjectPath) {
        Start-Process explorer.exe -ArgumentList @($script:ProjectPath) | Out-Null
    }
})
$MenuExit.Add_Click({
    $window.Close()
})
$MenuPasteClipboard.Add_Click({ Insert-ClipboardIntoPrompt })
$MenuAttachFiles.Add_Click({ Attach-FilesToPrompt })
$MenuClearPrompt.Add_Click({
    $PromptTextBox.Clear()
    Focus-Composer
})
$MenuShowSearch.Add_Click({ Prepare-SearchView })
$MenuShowPlugins.Add_Click({ Prepare-PluginsView })
$MenuShowAutomation.Add_Click({ Prepare-AutomationView })
$MenuShowSettings.Add_Click({ Open-SettingsView })
$MenuMinimize.Add_Click({
    $window.WindowState = [System.Windows.WindowState]::Minimized
})
$MenuToggleMaximize.Add_Click({
    Toggle-WindowState
})
$MenuDoctor.Add_Click({
    Run-ClawCommand -Arguments @("doctor") -PromptText "claw doctor"
})
$MenuVersion.Add_Click({
    Run-ClawCommand -Arguments @("--version") -PromptText "claw --version"
})
$window.Dispatcher.add_UnhandledException({
    param($sender, $eventArgs)
    $eventArgs.Handled = $true
    Handle-StudioException -Context "Dispatcher" -Exception $eventArgs.Exception
})
[System.AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $eventArgs)
    $exceptionObject = $eventArgs.ExceptionObject
    $message = if ($exceptionObject -is [System.Exception]) { $exceptionObject.Message } else { [string]$exceptionObject }
    Write-StudioErrorLog -Message ("AppDomain: {0}" -f $message)
})
$window.Add_Closing({
    Save-CurrentSettings
    try {
        if ($script:SpeechRecognizer -and $script:IsSpeechListening) {
            $script:SpeechRecognizer.RecognizeAsyncCancel()
        }
    } catch {
    }

    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $result = [System.Windows.MessageBox]::Show((T "CloseWhileRunning"), "Claw Studio", "YesNo", "Warning")
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
            $_.Cancel = $true
            return
        }
        try {
            $script:CurrentProcess.Kill()
        } catch {
        }
    }
})

$window.ShowDialog() | Out-Null
