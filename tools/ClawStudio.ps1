#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$StudioRoot = Join-Path $env:LOCALAPPDATA "Programs\ClawCode\studio"
$SettingsPath = Join-Path $StudioRoot "settings.json"
$SessionsPath = Join-Path $StudioRoot "sessions.json"
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
$script:ProjectPath = ""
$script:CurrentThreadTitle = "Install Claw Code"
$script:AttachedFiles = New-Object System.Collections.Generic.List[string]
$script:ThreadTitles = New-Object System.Collections.Generic.List[string]
$script:SpinnerFrames = @("|", "/", "-", "\")
$script:SpinnerIndex = 0
$script:Sessions = New-Object System.Collections.Generic.List[object]
$script:CurrentSessionId = ""
$script:CurrentAssistantMessage = $null
$script:LastPromptText = ""
$script:LeftPanelExpanded = $true
$script:RightPanelExpanded = $true
$script:RunWasCancelled = $false
$script:IsAssistantPlaceholderActive = $false
$script:AssistantPlaceholderFrames = @("Arbeitet   ", "Arbeitet.  ", "Arbeitet.. ", "Arbeitet...")
$script:AssistantPlaceholderIndex = 0
$script:ProjectSnapshotBeforeRun = @{}
$script:LastChangedFiles = @()
$script:LastChangeSummary = "No file changes tracked yet."
$script:ActiveRailSection = "projects"

$script:Theme = @{
    Window = "#111315"
    Canvas = "#17191C"
    Sidebar = "#1A1F24"
    SidebarSoft = "#21272D"
    SidebarHover = "#2A3138"
    Border = "#2A3138"
    BorderSoft = "#23292F"
    Foreground = "#F5F7FA"
    Muted = "#AAB3BD"
    MutedSoft = "#7B8794"
    Bubble = "#1D2329"
    BubbleUser = "#263247"
    Composer = "#1D2126"
    Card = "#1B2025"
    ReadyBg = "#163A2B"
    ReadyFg = "#98E1BA"
    RunBg = "#473515"
    RunFg = "#F2D07B"
    ErrorBg = "#4F1F24"
    ErrorFg = "#F7A6AE"
    Accent = "#E7EBF0"
    AccentSoft = "#C7D2DE"
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
        [string]$PermissionMode
    )

    $payload = [ordered]@{
        projectPath = $ProjectPath
        model = $Model
        permissionMode = $PermissionMode
    }

    ($payload | ConvertTo-Json) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
}

function New-SessionTitleFromPrompt {
    param([string]$Prompt)

    $clean = ($Prompt -replace "\s+", " ").Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return "New chat"
    }

    if ($clean.Length -gt 48) {
        return $clean.Substring(0, 48).Trim() + "..."
    }

    return $clean
}

function Get-SessionById {
    param([string]$Id)

    foreach ($session in $script:Sessions) {
        if ([string]$session.id -eq $Id) {
            return $session
        }
    }

    return $null
}

function Save-Sessions {
    $payload = [ordered]@{
        currentSessionId = $script:CurrentSessionId
        sessions = @($script:Sessions)
    }

    ($payload | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $SessionsPath -Encoding UTF8
}

function New-SessionRecord {
    param(
        [string]$Title = "New chat",
        [string]$ProjectPath = "",
        [string]$PromptDraft = ""
    )

    return [ordered]@{
        id = [guid]::NewGuid().ToString("N")
        title = $Title
        projectPath = $ProjectPath
        promptDraft = $PromptDraft
        lastPrompt = ""
        updatedAt = [DateTime]::UtcNow.ToString("o")
        messages = @()
    }
}

function Add-MessageToSession {
    param(
        [string]$SessionId,
        [string]$Role,
        [string]$Text,
        [string]$RoleColor,
        [bool]$IsUser = $false,
        [bool]$UseMono = $false
    )

    $session = Get-SessionById -Id $SessionId
    if ($null -eq $session) {
        return $null
    }

    $messages = @($session.messages)
    $message = [ordered]@{
        role = $Role
        text = $Text
        roleColor = $RoleColor
        isUser = $IsUser
        useMono = $UseMono
    }

    $session.messages = @($messages + @($message))
    $session.updatedAt = [DateTime]::UtcNow.ToString("o")
    Save-Sessions
    return $message
}

function Update-SessionDraft {
    param([string]$Text)

    $session = Get-SessionById -Id $script:CurrentSessionId
    if ($null -eq $session) {
        return
    }

    $session.promptDraft = $Text
    $session.updatedAt = [DateTime]::UtcNow.ToString("o")
    Save-Sessions
}

function Render-SessionMessages {
    $ConversationStack.Children.Clear()
    $script:CurrentAssistantMessage = $null

    $session = Get-SessionById -Id $script:CurrentSessionId
    if ($null -eq $session) {
        return
    }

    foreach ($message in @($session.messages)) {
        Add-Conversation -Role ([string]$message.role) -Text ([string]$message.text) -RoleColor ([string]$message.roleColor) -IsUser:([bool]$message.isUser) -UseMono:([bool]$message.useMono) | Out-Null
    }
}

function Start-NewSession {
    param(
        [string]$Title = "New chat",
        [bool]$Persist = $true
    )

    $session = New-SessionRecord -Title $Title -ProjectPath $script:ProjectPath -PromptDraft ""
    $script:Sessions.Insert(0, $session)
    $script:CurrentSessionId = [string]$session.id
    Update-ThreadTitle -Title $Title
    if ($PromptTextBox) {
        $PromptTextBox.Text = ""
    }
    Render-SessionMessages
    Refresh-ThreadList -Filter $(if ($SearchTextBox -and $SearchTextBox.Text -ne "Suche") { $SearchTextBox.Text } else { "" })
    if ($Persist) {
        Save-Sessions
    }
}

function Initialize-Sessions {
    $script:Sessions.Clear()

    if (Test-Path -LiteralPath $SessionsPath) {
        try {
            $raw = Get-Content -LiteralPath $SessionsPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $data = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
                foreach ($session in @($data.sessions)) {
                    $script:Sessions.Add([ordered]@{
                        id = [string]$session.id
                        title = [string]$session.title
                        projectPath = [string]$session.projectPath
                        promptDraft = [string]$session.promptDraft
                        lastPrompt = [string]$session.lastPrompt
                        updatedAt = [string]$session.updatedAt
                        messages = @($session.messages)
                    }) | Out-Null
                }
                $script:CurrentSessionId = [string]$data.currentSessionId
            }
        } catch {
        }
    }

    if ($script:Sessions.Count -eq 0) {
        $session = New-SessionRecord -Title "New chat" -ProjectPath $script:ProjectPath -PromptDraft "Analyze this repository. Explain the architecture, build flow, dependencies, risky areas, and the first improvement you would make."
        $session.messages = @(
            [ordered]@{ role = "System"; text = "Claw Studio is ready. Pick a project folder, then use the composer below like a chat input."; roleColor = $script:Theme.Muted; isUser = $false; useMono = $false },
            [ordered]@{ role = "Tip"; text = "Start inside a real repo folder, not your whole user directory. Press Ctrl+Enter to send. Try /help for session commands."; roleColor = $script:Theme.RunFg; isUser = $false; useMono = $false }
        )
        $script:Sessions.Add($session) | Out-Null
        $script:CurrentSessionId = [string]$session.id
        Save-Sessions
    }

    if ([string]::IsNullOrWhiteSpace($script:CurrentSessionId) -or $null -eq (Get-SessionById -Id $script:CurrentSessionId)) {
        $script:CurrentSessionId = [string]$script:Sessions[0].id
    }
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

    return "openai/qwen2.5-coder:14b"
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

function Get-ProjectSnapshot {
    param([string]$Path)

    $snapshot = @{}
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $snapshot
    }

    $skipSegments = @("\.git\", "\node_modules\", "\.venv\", "\bin\", "\obj\", "\target\")
    try {
        foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue) {
            $full = [string]$file.FullName
            $skip = $false
            foreach ($segment in $skipSegments) {
                if ($full.IndexOf($segment, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $skip = $true
                    break
                }
            }
            if ($skip) {
                continue
            }

            $snapshot[$full] = ($file.LastWriteTimeUtc.Ticks.ToString() + ":" + $file.Length.ToString())
        }
    } catch {
    }

    return $snapshot
}

function Get-RelativeProjectPath {
    param(
        [string]$Root,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    try {
        $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
        $pathFull = [System.IO.Path]::GetFullPath($Path)
        if ($pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $pathFull.Substring($rootFull.Length)
        }
    } catch {
    }

    return $Path
}

function Get-ProjectChangeSet {
    param(
        [hashtable]$Before,
        [hashtable]$After,
        [string]$Root
    )

    $changes = New-Object System.Collections.Generic.List[string]

    foreach ($path in $After.Keys) {
        if (-not $Before.ContainsKey($path)) {
            $changes.Add("[new] " + (Get-RelativeProjectPath -Root $Root -Path $path)) | Out-Null
        } elseif ($Before[$path] -ne $After[$path]) {
            $changes.Add("[changed] " + (Get-RelativeProjectPath -Root $Root -Path $path)) | Out-Null
        }
    }

    foreach ($path in $Before.Keys) {
        if (-not $After.ContainsKey($path)) {
            $changes.Add("[deleted] " + (Get-RelativeProjectPath -Root $Root -Path $path)) | Out-Null
        }
    }

    return @($changes)
}

function Get-TextBetweenJsonFences {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $match = [regex]::Match($Text, '```json\s*(\{[\s\S]*?\})\s*```')
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    $trimmed = $Text.Trim()
    if ($trimmed.StartsWith("{") -and $trimmed.EndsWith("}")) {
        return $trimmed
    }

    return ""
}

function Get-MessageFromToolJson {
    param([string]$JsonText)

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        return ""
    }

    try {
        $obj = ConvertFrom-Json -InputObject $JsonText -ErrorAction Stop
        if ($null -eq $obj) {
            return ""
        }

        $name = [string]$obj.name
        if ($name -eq "SendUserMessage" -and $obj.arguments -and $obj.arguments.PSObject.Properties["message"]) {
            return [string]$obj.arguments.message
        }
    } catch {
    }

    return ""
}

function Resolve-ProjectFilePath {
    param(
        [string]$Root,
        [string]$ToolPath
    )

    if ([string]::IsNullOrWhiteSpace($ToolPath)) {
        return ""
    }

    if ([System.IO.Path]::IsPathRooted($ToolPath)) {
        return $ToolPath
    }

    return (Join-Path $Root $ToolPath)
}

function Invoke-LocalToolFallback {
    param(
        [string]$WorkspaceRoot,
        [string]$JsonText
    )

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        return $null
    }

    try {
        $toolCall = ConvertFrom-Json -InputObject $JsonText -ErrorAction Stop
    } catch {
        return $null
    }

    $toolName = [string]$toolCall.name
    $args = $toolCall.arguments
    if ([string]::IsNullOrWhiteSpace($toolName) -or $null -eq $args) {
        return $null
    }

    switch ($toolName) {
        "edit_file" {
            $targetPath = Resolve-ProjectFilePath -Root $WorkspaceRoot -ToolPath ([string]$args.path)
            if ([string]::IsNullOrWhiteSpace($targetPath) -or -not (Test-Path -LiteralPath $targetPath)) {
                return @{ Success = $false; Summary = "Fallback edit_file failed: target path not found."; Tool = $toolName }
            }

            $content = Get-Content -LiteralPath $targetPath -Raw
            $oldString = [string]$args.old_string
            $newString = [string]$args.new_string
            $replaceAll = $false
            if ($args.PSObject.Properties["replace_all"]) {
                $replaceAll = [bool]$args.replace_all
            }

            if ([string]::IsNullOrEmpty($oldString)) {
                return @{ Success = $false; Summary = "Fallback edit_file failed: old_string was empty."; Tool = $toolName }
            }

            if ($content.IndexOf($oldString, [System.StringComparison]::Ordinal) -lt 0) {
                return @{ Success = $false; Summary = "Fallback edit_file failed: old_string not found in target file."; Tool = $toolName }
            }

            if ($replaceAll) {
                $updated = $content.Replace($oldString, $newString)
            } else {
                $index = $content.IndexOf($oldString, [System.StringComparison]::Ordinal)
                $updated = $content.Substring(0, $index) + $newString + $content.Substring($index + $oldString.Length)
            }
            Set-Content -LiteralPath $targetPath -Value $updated -Encoding UTF8
            return @{ Success = $true; Summary = ("Applied fallback edit_file to " + (Get-RelativeProjectPath -Root $WorkspaceRoot -Path $targetPath)); Tool = $toolName }
        }
        "write_file" {
            $targetPath = Resolve-ProjectFilePath -Root $WorkspaceRoot -ToolPath ([string]$args.file_path)
            if ([string]::IsNullOrWhiteSpace($targetPath)) {
                $targetPath = Resolve-ProjectFilePath -Root $WorkspaceRoot -ToolPath ([string]$args.path)
            }
            if ([string]::IsNullOrWhiteSpace($targetPath)) {
                return @{ Success = $false; Summary = "Fallback write_file failed: no target path."; Tool = $toolName }
            }

            $parent = Split-Path -Parent $targetPath
            if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }

            $content = [string]$args.content
            Set-Content -LiteralPath $targetPath -Value $content -Encoding UTF8
            return @{ Success = $true; Summary = ("Applied fallback write_file to " + (Get-RelativeProjectPath -Root $WorkspaceRoot -Path $targetPath)); Tool = $toolName }
        }
        default {
            return @{ Success = $false; Summary = ("No local fallback implemented for " + $toolName); Tool = $toolName }
        }
    }
}

function Try-HandleJsonOutputFallback {
    param(
        [string]$WorkspaceRoot,
        [string]$StdOutPath
    )

    if ([string]::IsNullOrWhiteSpace($StdOutPath) -or -not (Test-Path -LiteralPath $StdOutPath)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $StdOutPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }

        $payload = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        if ($null -eq $payload) {
            return $null
        }

        $toolUses = @($payload.tool_uses)
        $toolResults = @($payload.tool_results)
        $message = [string]$payload.message

        if ($toolUses.Count -gt 0 -or $toolResults.Count -gt 0) {
            return @{ Mode = "native"; Message = $message; Summary = "Native tool execution detected." }
        }

        $jsonSnippet = Get-TextBetweenJsonFences -Text $message
        if ([string]::IsNullOrWhiteSpace($jsonSnippet)) {
            $trimmedMessage = $message.Trim()
            if ($trimmedMessage.StartsWith("{") -and $trimmedMessage.EndsWith("}")) {
                $jsonSnippet = $trimmedMessage
            }
        }

        $userMessage = Get-MessageFromToolJson -JsonText $jsonSnippet
        if (-not [string]::IsNullOrWhiteSpace($userMessage)) {
            return @{ Mode = "tool_message"; Message = $userMessage; Summary = "Parsed SendUserMessage output." }
        }

        if ([string]::IsNullOrWhiteSpace($jsonSnippet)) {
            return @{ Mode = "text"; Message = $message; Summary = "No tool JSON detected." }
        }

        $fallback = Invoke-LocalToolFallback -WorkspaceRoot $WorkspaceRoot -JsonText $jsonSnippet
        if ($null -eq $fallback) {
            return @{ Mode = "text"; Message = $message; Summary = "Could not parse tool JSON for fallback." }
        }

        return @{
            Mode = "fallback"
            Message = $message
            Summary = [string]$fallback.Summary
            Success = [bool]$fallback.Success
            Tool = [string]$fallback.Tool
        }
    } catch {
        return @{ Mode = "error"; Message = ""; Summary = ("JSON output parse failed: " + $_.Exception.Message) }
    }
}

function Invoke-ExternalCapture {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$WorkingDirectory = ""
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Arguments = ConvertTo-ArgumentString -Arguments $Arguments

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [ordered]@{
        ExitCode = $process.ExitCode
        StdOut = $stdout
        StdErr = $stderr
    }
}

function Set-SelectedComboValue {
    param(
        $ComboBox,
        [string]$Value
    )

    if ($null -eq $ComboBox -or [string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    for ($i = 0; $i -lt $ComboBox.Items.Count; $i++) {
        if ([string]$ComboBox.Items[$i].Content -eq $Value) {
            $ComboBox.SelectedIndex = $i
            return $true
        }
    }

    return $false
}

function Export-CurrentSession {
    $session = Get-SessionById -Id $script:CurrentSessionId
    if ($null -eq $session) {
        return ""
    }

    $exportDir = Join-Path $StudioRoot "exports"
    if (-not (Test-Path -LiteralPath $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    }

    $safeTitle = (($session.title -replace '[\\/:*?"<>|]', '-') -replace '\s+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeTitle)) {
        $safeTitle = "session"
    }

    $path = Join-Path $exportDir ($safeTitle + "-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".md")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# " + [string]$session.title) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("Project: " + [string]$session.projectPath) | Out-Null
    $lines.Add("Updated: " + [string]$session.updatedAt) | Out-Null
    $lines.Add("") | Out-Null
    foreach ($message in @($session.messages)) {
        $lines.Add("## " + [string]$message.role) | Out-Null
        $lines.Add([string]$message.text) | Out-Null
        $lines.Add("") | Out-Null
    }
    ($lines -join "`r`n") | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Get-SessionApproxTokenCount {
    param($Session)

    if ($null -eq $Session) {
        return 0
    }

    $charCount = 0
    foreach ($message in @($Session.messages)) {
        $charCount += ([string]$message.text).Length
    }

    return [int][Math]::Ceiling($charCount / 4.0)
}

function Format-SessionCost {
    param([int]$TokenCount)

    $usd = $TokenCount * 0.000003
    return ('$' + $usd.ToString('0.0000'))
}

function Handle-SlashCommand {
    param([string]$Prompt)

    if ([string]::IsNullOrWhiteSpace($Prompt) -or -not $Prompt.StartsWith("/")) {
        return $false
    }

    $trimmed = $Prompt.Trim()
    $parts = @($trimmed -split "\s+")
    $command = $parts[0].ToLowerInvariant()
    $args = @()
    if ($parts.Count -gt 1) {
        $args = $parts[1..($parts.Count - 1)]
    }

    switch ($command) {
        "/help" {
            $text = @(
                "Available slash commands:"
                "/help"
                "/status"
                "/compact"
                "/clear"
                "/cost"
                "/model [value]"
                "/permissions [value]"
                "/resume <session-path>"
                "/config [env|hooks|model]"
                "/memory"
                "/diff"
                "/version"
                "/export"
                "/session list"
                "/session switch <id|title>"
                "/init"
            ) -join "`r`n"
            Add-Conversation -Role "System" -Text $text -RoleColor $script:Theme.Muted | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text $text -RoleColor $script:Theme.Muted | Out-Null
            return $true
        }
        "/status" {
            $session = Get-SessionById -Id $script:CurrentSessionId
            $text = @(
                "Session: " + [string]$session.title
                "Project: " + $script:ProjectPath
                "Messages: " + @($session.messages).Count
                "Model: " + (Get-ComboValue -ComboBox $ModelComboBox)
                "Permissions: " + (Get-ComboValue -ComboBox $PermissionComboBox)
                "Tracked file changes: " + $script:LastChangedFiles.Count
                "Running: " + [string]($script:CurrentProcess -and -not $script:CurrentProcess.HasExited)
            ) -join "`r`n"
            Add-Conversation -Role "Status" -Text $text -RoleColor $script:Theme.AccentSoft | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Status" -Text $text -RoleColor $script:Theme.AccentSoft | Out-Null
            return $true
        }
        "/compact" {
            $session = Get-SessionById -Id $script:CurrentSessionId
            if ($null -eq $session) {
                return $true
            }

            $messages = @($session.messages)
            if ($messages.Count -le 5) {
                $text = "Conversation is already compact enough."
            } else {
                $preserved = @($messages | Select-Object -Last 4)
                $older = @($messages | Select-Object -First ($messages.Count - 4))
                $summaryLines = New-Object System.Collections.Generic.List[string]
                foreach ($message in $older) {
                    $line = ([string]$message.role + ": " + ([string]$message.text -replace "\s+", " ").Trim())
                    if ($line.Length -gt 160) {
                        $line = $line.Substring(0, 160).Trim() + "..."
                    }
                    $summaryLines.Add("- " + $line) | Out-Null
                }
                $summaryText = "Compacted summary:`r`n" + ($summaryLines -join "`r`n")
                $session.messages = @(
                    [ordered]@{
                        role = "Summary"
                        text = $summaryText
                        roleColor = $script:Theme.AccentSoft
                        isUser = $false
                        useMono = $false
                    }
                ) + $preserved
                $session.updatedAt = [DateTime]::UtcNow.ToString("o")
                Save-Sessions
                Render-SessionMessages
                Refresh-SessionMeta
                $text = "Conversation compacted. Preserved the latest 4 messages and summarized older context."
            }
            Add-Conversation -Role "System" -Text $text -RoleColor $script:Theme.AccentSoft | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text $text -RoleColor $script:Theme.AccentSoft | Out-Null
            return $true
        }
        "/clear" {
            $session = Get-SessionById -Id $script:CurrentSessionId
            if ($null -ne $session) {
                $session.messages = @()
                $session.lastPrompt = ""
                $session.updatedAt = [DateTime]::UtcNow.ToString("o")
                Save-Sessions
            }
            $ConversationStack.Children.Clear()
            Add-Conversation -Role "System" -Text "Conversation cleared." -RoleColor $script:Theme.Muted | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text "Conversation cleared." -RoleColor $script:Theme.Muted | Out-Null
            Refresh-SessionMeta
            return $true
        }
        "/cost" {
            $session = Get-SessionById -Id $script:CurrentSessionId
            $tokens = Get-SessionApproxTokenCount -Session $session
            $text = @(
                "Approximate usage"
                "Input/output tokens: " + $tokens
                "Estimated cost: " + (Format-SessionCost -TokenCount $tokens)
                "Cache read/write: not tracked in this local Studio wrapper"
            ) -join "`r`n"
            Add-Conversation -Role "Cost" -Text $text -RoleColor $script:Theme.RunFg -UseMono:$true | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Cost" -Text $text -RoleColor $script:Theme.RunFg -UseMono:$true | Out-Null
            return $true
        }
        "/model" {
            if ($args.Count -eq 0) {
                $text = "Current model: " + (Get-ComboValue -ComboBox $ModelComboBox)
            } elseif (Set-SelectedComboValue -ComboBox $ModelComboBox -Value ($args -join " ")) {
                $text = "Model switched to: " + (Get-ComboValue -ComboBox $ModelComboBox)
            } else {
                $text = "Model not found in picker: " + ($args -join " ")
            }
            Add-Conversation -Role "System" -Text $text -RoleColor $script:Theme.AccentSoft | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text $text -RoleColor $script:Theme.AccentSoft | Out-Null
            Refresh-SessionMeta
            return $true
        }
        "/permissions" {
            if ($args.Count -eq 0) {
                $text = "Current permission mode: " + (Get-ComboValue -ComboBox $PermissionComboBox)
            } elseif (Set-SelectedComboValue -ComboBox $PermissionComboBox -Value ($args -join " ")) {
                $text = "Permission mode switched to: " + (Get-ComboValue -ComboBox $PermissionComboBox)
            } else {
                $text = "Permission mode not found in picker: " + ($args -join " ")
            }
            Add-Conversation -Role "System" -Text $text -RoleColor $script:Theme.AccentSoft | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text $text -RoleColor $script:Theme.AccentSoft | Out-Null
            Refresh-SessionMeta
            return $true
        }
        "/resume" {
            if ($args.Count -eq 0) {
                $text = "Usage: /resume <session-path>"
                Add-Conversation -Role "System" -Text $text -RoleColor $script:Theme.ErrorFg | Out-Null
                Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text $text -RoleColor $script:Theme.ErrorFg | Out-Null
                return $true
            }

            $path = ($args -join " ")
            if (-not (Test-Path -LiteralPath $path)) {
                $text = "Session file not found: " + $path
                Add-Conversation -Role "System" -Text $text -RoleColor $script:Theme.ErrorFg | Out-Null
                Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text $text -RoleColor $script:Theme.ErrorFg | Out-Null
                return $true
            }

            try {
                $raw = Get-Content -LiteralPath $path -Raw
                $title = [System.IO.Path]::GetFileNameWithoutExtension($path)
                Start-NewSession -Title ("Resumed: " + $title) -Persist:$false
                Add-Conversation -Role "Resume" -Text $raw -RoleColor $script:Theme.AccentSoft -UseMono:$true | Out-Null
                Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Resume" -Text $raw -RoleColor $script:Theme.AccentSoft -UseMono:$true | Out-Null
                Refresh-SessionMeta
            } catch {
                $text = "Could not resume session: " + $_.Exception.Message
                Add-Conversation -Role "System" -Text $text -RoleColor $script:Theme.ErrorFg | Out-Null
                Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text $text -RoleColor $script:Theme.ErrorFg | Out-Null
            }
            return $true
        }
        "/config" {
            $sub = $(if ($args.Count -gt 0) { $args[0].ToLowerInvariant() } else { "" })
            switch ($sub) {
                "env" {
                    $text = @(
                        "Environment"
                        "ANTHROPIC_BASE_URL=" + [string]$env:ANTHROPIC_BASE_URL
                        "ANTHROPIC_MODEL=" + [string]$env:ANTHROPIC_MODEL
                        "RUSTY_CLAUDE_PERMISSION_MODE=" + [string]$env:RUSTY_CLAUDE_PERMISSION_MODE
                        "CLAUDE_CONFIG_HOME=" + [string]$env:CLAUDE_CONFIG_HOME
                    ) -join "`r`n"
                }
                "hooks" {
                    $text = "Hooks are not yet wired in this local Studio wrapper."
                }
                "model" {
                    $text = @(
                        "Model config"
                        "Selected model: " + (Get-ComboValue -ComboBox $ModelComboBox)
                        "Permission mode: " + (Get-ComboValue -ComboBox $PermissionComboBox)
                    ) -join "`r`n"
                }
                default {
                    $text = @(
                        "Config summary"
                        "Project: " + $script:ProjectPath
                        "Model: " + (Get-ComboValue -ComboBox $ModelComboBox)
                        "Permissions: " + (Get-ComboValue -ComboBox $PermissionComboBox)
                        "Use /config env, /config hooks, or /config model for more detail."
                    ) -join "`r`n"
                }
            }
            Add-Conversation -Role "Config" -Text $text -RoleColor $script:Theme.AccentSoft -UseMono:$true | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Config" -Text $text -RoleColor $script:Theme.AccentSoft -UseMono:$true | Out-Null
            return $true
        }
        "/memory" {
            $session = Get-SessionById -Id $script:CurrentSessionId
            $recent = @($session.messages | Select-Object -Last 3 | ForEach-Object { [string]$_.role })
            $text = @(
                "Memory snapshot"
                "Session memory entries: " + @($session.messages).Count
                "Project memory: current folder " + $script:ProjectPath
                "Global memory: not persisted yet"
                "Recently active roles: " + ($recent -join ", ")
            ) -join "`r`n"
            Add-Conversation -Role "Memory" -Text $text -RoleColor $script:Theme.AccentSoft -UseMono:$true | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Memory" -Text $text -RoleColor $script:Theme.AccentSoft -UseMono:$true | Out-Null
            return $true
        }
        "/diff" {
            $result = Invoke-ExternalCapture -Executable "git" -Arguments @("-C", $script:ProjectPath, "status", "--short")
            if (-not [string]::IsNullOrWhiteSpace($result.StdOut)) {
                $text = $result.StdOut.Trim()
            } elseif ($script:LastChangedFiles.Count -gt 0) {
                $text = ($script:LastChangedFiles -join "`r`n")
            } else {
                $text = "No uncommitted changes."
            }
            Add-Conversation -Role "Diff" -Text $text -RoleColor $script:Theme.RunFg -UseMono:$true | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Diff" -Text $text -RoleColor $script:Theme.RunFg -UseMono:$true | Out-Null
            return $true
        }
        "/version" {
            $clawBinary = Find-ClawBinary
            $result = Invoke-ExternalCapture -Executable $clawBinary -Arguments @("--version") -WorkingDirectory $script:ProjectPath
            $text = if ([string]::IsNullOrWhiteSpace($result.StdOut)) { "No version output." } else { $result.StdOut.Trim() }
            Add-Conversation -Role "System" -Text $text -RoleColor $script:Theme.AccentSoft -UseMono:$true | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text $text -RoleColor $script:Theme.AccentSoft -UseMono:$true | Out-Null
            return $true
        }
        "/export" {
            $path = Export-CurrentSession
            $text = "Session exported to " + $path
            Add-Conversation -Role "System" -Text $text -RoleColor $script:Theme.ReadyFg | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text $text -RoleColor $script:Theme.ReadyFg | Out-Null
            return $true
        }
        "/session" {
            if ($args.Count -eq 0 -or $args[0] -eq "list") {
                $titles = @($script:Sessions | ForEach-Object { ([string]$_.id).Substring(0, 8) + "  " + [string]$_.title })
                $text = "Sessions:`r`n- " + ($titles -join "`r`n- ")
                Add-Conversation -Role "System" -Text $text -RoleColor $script:Theme.AccentSoft | Out-Null
                Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text $text -RoleColor $script:Theme.AccentSoft | Out-Null
                return $true
            }
            if ($args[0] -eq "switch" -and $args.Count -gt 1) {
                $target = ($args[1..($args.Count - 1)] -join " ")
                foreach ($session in @($script:Sessions)) {
                    if ([string]$session.title -eq $target -or ([string]$session.id).StartsWith($target)) {
                        $script:CurrentSessionId = [string]$session.id
                        $script:CurrentThreadTitle = [string]$session.title
                        Render-SessionMessages
                        $PromptTextBox.Text = [string]$session.promptDraft
                        Refresh-ProjectState
                        Refresh-SessionMeta
                        Refresh-ThreadList
                        return $true
                    }
                }
                Add-Conversation -Role "System" -Text ("Session not found: " + $target) -RoleColor $script:Theme.ErrorFg | Out-Null
                Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text ("Session not found: " + $target) -RoleColor $script:Theme.ErrorFg | Out-Null
                return $true
            }
            return $true
        }
        "/init" {
            Refresh-ProjectState
            $text = "Project context refreshed for " + $script:ProjectPath
            Add-Conversation -Role "System" -Text $text -RoleColor $script:Theme.ReadyFg | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text $text -RoleColor $script:Theme.ReadyFg | Out-Null
            return $true
        }
        default {
            Add-Conversation -Role "System" -Text ("Unknown slash command: " + $command) -RoleColor $script:Theme.ErrorFg | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text ("Unknown slash command: " + $command) -RoleColor $script:Theme.ErrorFg | Out-Null
            return $true
        }
    }
}

function Get-AttachmentPromptBlock {
    if ($script:AttachedFiles.Count -eq 0) {
        return ""
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Attached files:") | Out-Null
    foreach ($path in $script:AttachedFiles) {
        $lines.Add("- $path") | Out-Null
    }

    return ($lines -join "`r`n")
}

function Apply-AttachmentsToPrompt {
    $attachmentBlock = Get-AttachmentPromptBlock
    if ([string]::IsNullOrWhiteSpace($attachmentBlock)) {
        return
    }

    $currentPrompt = $PromptTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($currentPrompt)) {
        $PromptTextBox.Text = $attachmentBlock + "`r`n`r`nDescribe what you want to do with these files."
        return
    }

    $cleanPrompt = [regex]::Replace($currentPrompt, "(?s)\r?\n\r?\nAttached files:\r?\n(?:- .+\r?\n?)*$", "")
    $PromptTextBox.Text = $cleanPrompt.TrimEnd() + "`r`n`r`n" + $attachmentBlock
}

function Refresh-ThreadList {
    param([string]$Filter = "")

    $ThreadList.Items.Clear()
    $script:ThreadTitles.Clear()
    foreach ($session in @($script:Sessions)) {
        $title = [string]$session.title
        $script:ThreadTitles.Add($title) | Out-Null
        if ([string]::IsNullOrWhiteSpace($Filter) -or $title.IndexOf($Filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            [void]$ThreadList.Items.Add($title)
        }
    }

    if ($ThreadList.Items.Count -gt 0) {
        if ($ThreadList.Items.Contains($script:CurrentThreadTitle)) {
            $ThreadList.SelectedItem = $script:CurrentThreadTitle
        } else {
            $ThreadList.SelectedIndex = 0
        }
    }
}

function Add-ThreadTitle {
    param([string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return
    }

    $session = Get-SessionById -Id $script:CurrentSessionId
    if ($null -ne $session) {
        $session.title = $Title
        $session.updatedAt = [DateTime]::UtcNow.ToString("o")
        Save-Sessions
    }

    for ($i = 0; $i -lt $script:Sessions.Count; $i++) {
        if ([string]$script:Sessions[$i].id -eq $script:CurrentSessionId) {
            $selectedSession = $script:Sessions[$i]
            $script:Sessions.RemoveAt($i)
            $script:Sessions.Insert(0, $selectedSession)
            break
        }
    }

    Refresh-ThreadList -Filter $(if ($SearchTextBox -and $SearchTextBox.Text -ne "Suche") { $SearchTextBox.Text } else { "" })
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claw Studio"
        Width="1600"
        Height="920"
        MinWidth="1320"
        MinHeight="800"
        Background="#111315"
        WindowState="Maximized"
        WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI">
  <Window.Resources>
    <SolidColorBrush x:Key="ComboBackgroundBrush" Color="#21272D"/>
    <SolidColorBrush x:Key="ComboBorderBrush" Color="#2A3138"/>
    <SolidColorBrush x:Key="ComboForegroundBrush" Color="#F5F7FA"/>
    <SolidColorBrush x:Key="ComboItemHoverBrush" Color="#2A3138"/>
    <SolidColorBrush x:Key="ComboItemSelectedBrush" Color="#323A42"/>
    <SolidColorBrush x:Key="ButtonHoverBrush" Color="#2A3138"/>
    <SolidColorBrush x:Key="SidebarButtonBrush" Color="#21272D"/>
    <SolidColorBrush x:Key="SidebarButtonHoverBrush" Color="#2A3138"/>
    <SolidColorBrush x:Key="SidebarButtonPressedBrush" Color="#323A42"/>
    <SolidColorBrush x:Key="RailButtonSelectedBrush" Color="#2B333B"/>
    <SolidColorBrush x:Key="RailButtonSelectedBorderBrush" Color="#3A424B"/>
    <SolidColorBrush x:Key="SelectedThreadBrush" Color="#28303A"/>
    <SolidColorBrush x:Key="PanelBrush" Color="#1B2025"/>
    <SolidColorBrush x:Key="PanelBorderBrush" Color="#23292F"/>
    <SolidColorBrush x:Key="SelectionBrush" Color="#3A424B"/>
    <SolidColorBrush x:Key="MenuItemHoverBrush" Color="#2A3138"/>
    <SolidColorBrush x:Key="MenuItemPressedBrush" Color="#323A42"/>
    <SolidColorBrush x:Key="MenuItemBorderBrush" Color="#3A424B"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#323A42"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#F5F7FA"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightBrushKey}" Color="#2B333B"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightTextBrushKey}" Color="#F5F7FA"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.ControlBrushKey}" Color="#1B2025"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.ControlTextBrushKey}" Color="#F5F7FA"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.MenuBrushKey}" Color="#1B2025"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.MenuTextBrushKey}" Color="#F5F7FA"/>

    <Style TargetType="TextBlock">
      <Setter Property="TextOptions.TextFormattingMode" Value="Display"/>
      <Setter Property="TextOptions.TextRenderingMode" Value="ClearType"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
    </Style>

    <Style TargetType="Button">
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="SelectionBrush" Value="{StaticResource SelectionBrush}"/>
      <Setter Property="SelectionOpacity" Value="0.7"/>
      <Setter Property="CaretBrush" Value="#F5F7FA"/>
      <Setter Property="ContextMenu">
        <Setter.Value>
          <ContextMenu/>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ContextMenu">
      <Setter Property="Background" Value="#1B2025"/>
      <Setter Property="BorderBrush" Value="#23292F"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Foreground" Value="#F5F7FA"/>
    </Style>

    <Style TargetType="MenuItem">
      <Setter Property="Foreground" Value="#F5F7FA"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="MenuItem">
            <Border x:Name="Root" Background="{TemplateBinding Background}" BorderBrush="Transparent" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter ContentSource="Header"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="Root" Property="Background" Value="{StaticResource MenuItemHoverBrush}"/>
                <Setter TargetName="Root" Property="BorderBrush" Value="{StaticResource MenuItemBorderBrush}"/>
              </Trigger>
              <Trigger Property="IsSubmenuOpen" Value="True">
                <Setter TargetName="Root" Property="Background" Value="{StaticResource MenuItemPressedBrush}"/>
                <Setter TargetName="Root" Property="BorderBrush" Value="{StaticResource MenuItemBorderBrush}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="#7B8794"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="SidebarButtonStyle" TargetType="Button">
      <Setter Property="Background" Value="{StaticResource SidebarButtonBrush}"/>
      <Setter Property="BorderBrush" Value="{StaticResource ComboBorderBrush}"/>
      <Setter Property="Foreground" Value="#F3F4F6"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Padding" Value="12,0,12,0"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Root" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="12">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Root" Property="Background" Value="{StaticResource ButtonHoverBrush}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Root" Property="Background" Value="{StaticResource SidebarButtonPressedBrush}"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Root" Property="Background" Value="{StaticResource SidebarButtonPressedBrush}"/>
                <Setter TargetName="Root" Property="BorderBrush" Value="{StaticResource ComboBorderBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="RailButtonStyle" TargetType="Button">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="#D4D4D8"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Root" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="12">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Root" Property="Background" Value="{StaticResource SidebarButtonHoverBrush}"/>
                <Setter TargetName="Root" Property="BorderBrush" Value="{StaticResource SidebarButtonHoverBrush}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Root" Property="Background" Value="{StaticResource SidebarButtonPressedBrush}"/>
                <Setter TargetName="Root" Property="BorderBrush" Value="{StaticResource ComboBorderBrush}"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Root" Property="Background" Value="{StaticResource SidebarButtonPressedBrush}"/>
                <Setter TargetName="Root" Property="BorderBrush" Value="{StaticResource ComboBorderBrush}"/>
              </Trigger>
              <Trigger Property="IsFocused" Value="True">
                <Setter TargetName="Root" Property="Background" Value="{StaticResource SidebarButtonPressedBrush}"/>
                <Setter TargetName="Root" Property="BorderBrush" Value="{StaticResource ComboBorderBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="GhostButtonStyle" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="#AAB3BD"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Root" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="12" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Root" Property="Background" Value="#20262B"/>
                <Setter Property="Foreground" Value="#F5F7FA"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="PanelCardStyle" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource PanelBrush}"/>
      <Setter Property="BorderBrush" Value="{StaticResource PanelBorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="18"/>
      <Setter Property="Padding" Value="16,14"/>
    </Style>

    <Style x:Key="ComposerIconButtonStyle" TargetType="Button">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Background" Value="#21272D"/>
      <Setter Property="BorderBrush" Value="#2A3138"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Foreground" Value="#C7D2DE"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Root" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Root" Property="Background" Value="#2A3138"/>
                <Setter TargetName="Root" Property="BorderBrush" Value="#3A424B"/>
                <Setter Property="Foreground" Value="#F5F7FA"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Root" Property="Background" Value="#323A42"/>
                <Setter TargetName="Root" Property="BorderBrush" Value="#3A424B"/>
                <Setter Property="Foreground" Value="#F5F7FA"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Root" Property="Background" Value="#323A42"/>
                <Setter TargetName="Root" Property="BorderBrush" Value="#3A424B"/>
                <Setter Property="Foreground" Value="#F5F7FA"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="{StaticResource ComboForegroundBrush}"/>
      <Setter Property="Background" Value="{StaticResource ComboBackgroundBrush}"/>
      <Setter Property="BorderBrush" Value="{StaticResource ComboBorderBrush}"/>
      <Setter Property="Padding" Value="10,6"/>
    </Style>

    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="{StaticResource ComboForegroundBrush}"/>
      <Setter Property="Background" Value="{StaticResource ComboBackgroundBrush}"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Style.Triggers>
        <Trigger Property="IsHighlighted" Value="True">
          <Setter Property="Background" Value="{StaticResource ComboItemHoverBrush}"/>
          <Setter Property="Foreground" Value="#FFFFFF"/>
        </Trigger>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="{StaticResource ComboItemSelectedBrush}"/>
          <Setter Property="Foreground" Value="#FFFFFF"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="#E5E7EB"/>
      <Setter Property="Padding" Value="10,8"/>
      <Setter Property="Margin" Value="0,2,0,2"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="ItemBorder" Background="Transparent" CornerRadius="10" Padding="{TemplateBinding Padding}">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="ItemBorder" Property="Background" Value="#2B333B"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="ItemBorder" Property="Background" Value="{StaticResource SelectedThreadBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid Background="#111315">
    <Grid.RowDefinitions>
      <RowDefinition Height="34"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <Grid.ColumnDefinitions>
      <ColumnDefinition x:Name="LeftSidebarColumn" Width="380"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition x:Name="RightSidebarColumn" Width="300"/>
    </Grid.ColumnDefinitions>

    <Border Grid.Row="0" Grid.ColumnSpan="3" Background="#1A1F24" BorderBrush="#23292F" BorderThickness="0,0,0,1">
      <Menu x:Name="MainMenu" Background="#1A1F24" Foreground="#AAB3BD" BorderThickness="0" Padding="10,2,0,0">
        <MenuItem x:Name="MenuFile" Header="_File">
          <MenuItem x:Name="MenuChooseProject" Header="Choose project folder"/>
          <MenuItem x:Name="MenuOpenProject" Header="Open in Explorer"/>
          <Separator/>
          <MenuItem x:Name="MenuExit" Header="Exit"/>
        </MenuItem>
        <MenuItem x:Name="MenuEdit" Header="_Edit">
          <MenuItem x:Name="MenuNewChat" Header="New chat"/>
          <MenuItem x:Name="MenuResetChat" Header="Reset chat"/>
        </MenuItem>
        <MenuItem x:Name="MenuView" Header="_View">
          <MenuItem x:Name="MenuFocusSearch" Header="Focus search"/>
          <MenuItem x:Name="MenuFocusComposer" Header="Focus composer"/>
        </MenuItem>
        <MenuItem x:Name="MenuWindow" Header="_Window">
          <MenuItem x:Name="MenuOpenTerminal" Header="Open terminal"/>
        </MenuItem>
        <MenuItem x:Name="MenuHelp" Header="_Help">
          <MenuItem x:Name="MenuRunDoctor" Header="Run doctor"/>
        </MenuItem>
      </Menu>
    </Border>

    <Border x:Name="LeftSidebarPanel" Grid.Row="1" Grid.Column="0" Background="#1A1F24" BorderBrush="#23292F" BorderThickness="0,0,1,0">
      <Grid Margin="0,12,14,16">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="72"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" BorderBrush="#23292F" BorderThickness="0,0,1,0" Margin="0,0,12,0">
          <StackPanel Margin="0,4,0,0">
            <Button x:Name="RailNewChatButton" Style="{StaticResource RailButtonStyle}" Width="40" Height="40" Margin="16,0,16,10" FontFamily="Segoe MDL2 Assets" FontSize="16" Content="&#xE70F;"/>
            <Button x:Name="RailSearchButton" Style="{StaticResource RailButtonStyle}" Width="40" Height="40" Margin="16,0,16,10" FontFamily="Segoe MDL2 Assets" FontSize="16" Content="&#xE721;"/>
            <Button x:Name="RailPluginsButton" Style="{StaticResource RailButtonStyle}" Width="40" Height="40" Margin="16,0,16,10" FontFamily="Segoe MDL2 Assets" FontSize="16" Content="&#xE943;"/>
            <Button x:Name="RailAutomationButton" Style="{StaticResource RailButtonStyle}" Width="40" Height="40" Margin="16,0,16,24" FontFamily="Segoe MDL2 Assets" FontSize="16" Content="&#xE823;"/>
            <TextBlock Text=" " Height="10"/>
            <Button x:Name="RailProjectsButton" Style="{StaticResource RailButtonStyle}" Width="40" Height="40" Margin="16,0,16,10" Foreground="#A1A1AA" FontFamily="Segoe MDL2 Assets" FontSize="16" Content="&#xE8B7;"/>
          </StackPanel>
        </Border>

        <Grid Grid.Column="1">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

        <StackPanel Grid.Row="0">
          <Button x:Name="NewChatButton" Content="Neuer Chat" HorizontalContentAlignment="Left" Height="38" Background="Transparent" BorderBrush="Transparent" Foreground="#F5F7FA" FontSize="15" FontWeight="SemiBold" Padding="8,0,0,0"/>
          <Border Background="#21272D" CornerRadius="14" Height="42" Margin="0,10,0,0" Padding="14,0,14,0">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBox x:Name="SearchTextBox" Background="Transparent" BorderThickness="0" Foreground="#F5F7FA" FontSize="14" VerticalContentAlignment="Center" Text="Search"/>
              <Border Grid.Column="1" Background="#2A3138" CornerRadius="10" Padding="8,4" VerticalAlignment="Center">
                <TextBlock Text="Ctrl+G" Foreground="#C7D2DE" FontSize="12"/>
              </Border>
            </Grid>
          </Border>
          <Button x:Name="PluginsButton" Content="Plugins" HorizontalContentAlignment="Left" Height="36" Background="Transparent" BorderBrush="Transparent" Foreground="#DCE3EA" FontSize="15" Padding="8,0,0,0" Margin="0,8,0,0"/>
          <Button x:Name="AutomationButton" Content="Automationen" HorizontalContentAlignment="Left" Height="36" Background="Transparent" BorderBrush="Transparent" Foreground="#DCE3EA" FontSize="15" Padding="8,0,0,0"/>
        </StackPanel>

        <StackPanel Grid.Row="1" Margin="0,22,0,0">
          <Grid Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Projekte" Foreground="#7B8794" FontSize="13" FontWeight="SemiBold" Margin="8,0,0,0" VerticalAlignment="Center"/>
            <Button x:Name="ProjectHeaderNewButton" Grid.Column="1" Style="{StaticResource GhostButtonStyle}" Width="28" Height="24" Margin="6,0,0,0" FontFamily="Segoe MDL2 Assets" FontSize="12" Content="&#xE710;" ToolTip="Projekt auswählen"/>
            <Button x:Name="ProjectHeaderOpenButton" Grid.Column="2" Style="{StaticResource GhostButtonStyle}" Width="28" Height="24" Margin="6,0,0,0" FontFamily="Segoe MDL2 Assets" FontSize="12" Content="&#xE8B7;" ToolTip="Im Explorer öffnen"/>
            <Button x:Name="ProjectHeaderMenuButton" Grid.Column="3" Style="{StaticResource GhostButtonStyle}" Width="28" Height="24" Margin="6,0,0,0" FontFamily="Segoe MDL2 Assets" FontSize="12" Content="&#xE712;" ToolTip="Projekt-Menü"/>
          </Grid>
          <Border Style="{StaticResource PanelCardStyle}" Margin="0,0,0,12">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock x:Name="ProjectNameText" Text="claw" Foreground="#F5F7FA" FontSize="18" FontWeight="SemiBold"/>
                <TextBlock x:Name="ProjectPathText" Text="C:\Users\frede\Desktop\claw" Foreground="#AAB3BD" FontSize="12" Margin="0,6,0,0" TextWrapping="Wrap"/>
              </StackPanel>
              <Button x:Name="ProjectMenuButton" Grid.Column="1" Style="{StaticResource GhostButtonStyle}" Width="32" Height="28" Margin="8,0,0,0" Foreground="#C7D2DE" Content="..." ToolTip="Projekt-Menü"/>
              <Button x:Name="ProjectEditButton" Grid.Column="2" Style="{StaticResource GhostButtonStyle}" Width="32" Height="28" Margin="8,0,0,0" Foreground="#C7D2DE" FontFamily="Segoe MDL2 Assets" FontSize="14" Content="&#xE8A7;" ToolTip="Projekt auswählen"/>
            </Grid>
          </Border>
        </StackPanel>

        <ListBox x:Name="ThreadList"
                 Grid.Row="2"
                 Background="Transparent"
                 BorderThickness="0"
                 Foreground="#DCE3EA"
                  FontSize="14"
                 ScrollViewer.VerticalScrollBarVisibility="Auto"/>

        <Grid Grid.Row="3" Margin="0,10,0,0">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Grid Grid.Row="0" Margin="0,0,0,6">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Letzte Aktionen" Foreground="#7B8794" FontSize="12" FontWeight="SemiBold" Margin="8,0,0,0" VerticalAlignment="Center"/>
            <Button x:Name="RecentApplyButton" Grid.Column="1" Style="{StaticResource GhostButtonStyle}" Width="28" Height="24" Margin="6,0,0,0" FontFamily="Segoe MDL2 Assets" FontSize="12" Content="&#xE73E;" ToolTip="Aktion übernehmen"/>
            <Button x:Name="RecentArchiveButton" Grid.Column="2" Style="{StaticResource GhostButtonStyle}" Width="28" Height="24" Margin="6,0,0,0" FontFamily="Segoe MDL2 Assets" FontSize="12" Content="&#xE74D;" ToolTip="Aktion archivieren"/>
            <Button x:Name="RecentDeleteButton" Grid.Column="3" Style="{StaticResource GhostButtonStyle}" Width="28" Height="24" Margin="6,0,0,0" FontFamily="Segoe MDL2 Assets" FontSize="12" Content="&#xE74D;" ToolTip="Aktion löschen"/>
          </Grid>
          <StackPanel Grid.Row="1" Margin="0,14,0,0" Visibility="Collapsed">
            <TextBlock Text="Settings" Foreground="#7B8794" FontSize="13" FontWeight="SemiBold" Margin="10,0,0,8"/>
            <ComboBox x:Name="ModelComboBox" Height="42" Background="#21272D" Foreground="#F5F7FA" BorderBrush="#2A3138" Margin="0,0,0,10">
            <ComboBoxItem Content="openai/qwen2.5-coder:7b"/>
            <ComboBoxItem Content="openai/qwen2.5-coder:14b"/>
            <ComboBoxItem Content="openai/qwen2.5-coder:32b"/>
            <ComboBoxItem Content="openai/llama3.2"/>
            </ComboBox>
            <ComboBox x:Name="PermissionComboBox" Height="42" Background="#21272D" Foreground="#F5F7FA" BorderBrush="#2A3138">
            <ComboBoxItem Content="read-only"/>
            <ComboBoxItem Content="workspace-write"/>
            <ComboBoxItem Content="danger-full-access"/>
            </ComboBox>
          </StackPanel>
        </Grid>
        </Grid>
      </Grid>
    </Border>

    <Grid Grid.Row="1" Grid.Column="1" Background="#17191C">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Background="#17191C" Padding="32,22,32,16">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Button Grid.Column="0" x:Name="ToggleLeftPanelButton" Width="34" Height="34" Margin="0,0,14,0" Background="#21272D" BorderBrush="#23292F" Foreground="#F5F7FA" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Content="&#xE76B;"/>
          <StackPanel Grid.Column="1">
            <DockPanel LastChildFill="False">
              <TextBlock x:Name="ThreadTitleText" Text="Install Claw Code" Foreground="#F5F7FA" FontSize="18" FontWeight="SemiBold" Margin="0,0,10,0"/>
              <Button x:Name="ThreadMenuButton" Style="{StaticResource GhostButtonStyle}" Width="30" Height="24" FontFamily="Segoe MDL2 Assets" FontSize="12" Content="&#xE712;" ToolTip="Chat-Menü"/>
            </DockPanel>
            <TextBlock x:Name="ThreadSubtitleText" Text="ready" Foreground="#AAB3BD" FontSize="12" Margin="0,6,0,0"/>
          </StackPanel>
          <Border Grid.Column="2" x:Name="StatusPill" Background="#184A34" CornerRadius="16" Padding="16,7" Margin="0,0,12,0" VerticalAlignment="Center">
            <TextBlock x:Name="StatusPillText" Text="Ready" Foreground="#8EF0B2" FontWeight="SemiBold" FontSize="13"/>
          </Border>
          <Button Grid.Column="3" x:Name="RetryButton" Content="Retry" Width="58" Height="34" Margin="0,0,10,0" Background="Transparent" BorderBrush="#23292F" Foreground="#C7D2DE" FontSize="12" VerticalAlignment="Center"/>
          <Button Grid.Column="4" x:Name="StopButton" Content="Stop" Width="54" Height="34" Margin="0,0,10,0" Background="Transparent" BorderBrush="#23292F" Foreground="#F7A6AE" FontSize="12" VerticalAlignment="Center"/>
          <Button Grid.Column="5" x:Name="HeaderRunButton" Content=">" Width="34" Height="34" Margin="0,0,10,0" Background="#21272D" BorderBrush="#23292F" Foreground="#F5F7FA" FontSize="15" VerticalAlignment="Center"/>
          <Button Grid.Column="6" x:Name="ToggleRightPanelButton" Width="34" Height="34" Background="#21272D" BorderBrush="#23292F" Foreground="#F5F7FA" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Content="&#xE76C;"/>
        </Grid>
      </Border>

      <ScrollViewer x:Name="ConversationScrollViewer" Grid.Row="1" Margin="32,0,32,20" VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="ConversationStack"/>
      </ScrollViewer>

      <Border Grid.Row="2" Margin="32,0,32,18" Background="#1D2126" CornerRadius="24" BorderBrush="#23292F" BorderThickness="1" Padding="20,18,20,16">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <TextBox x:Name="PromptTextBox"
                   Grid.Row="0"
                   Background="Transparent"
                   Foreground="#F5F7FA"
                   BorderThickness="0"
                   AcceptsReturn="True"
                   TextWrapping="Wrap"
                   VerticalScrollBarVisibility="Auto"
                   FontSize="15"
                   MinHeight="72"/>

          <Grid Grid.Row="1" Margin="0,12,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <Button x:Name="AttachButton" Grid.Column="0" Content="+" Width="34" Height="34" Background="#21272D" BorderBrush="#2A3138" Foreground="#F5F7FA" FontSize="18"/>
            <Button x:Name="PermissionPickerButton" Grid.Column="1" Width="172" Height="34" Margin="12,0,0,0" Background="Transparent" BorderBrush="Transparent" Foreground="#AAB3BD" HorizontalContentAlignment="Left" Padding="6,0,6,0" Content="Standard permissions" FontSize="13"/>
            <Button x:Name="ModelPickerButton" Grid.Column="3" Height="32" VerticalAlignment="Center" Background="Transparent" BorderBrush="Transparent" Foreground="#C7D2DE" Margin="0,0,12,0" FontSize="13" HorizontalContentAlignment="Right" Padding="8,0,8,0" Content="openai/qwen2.5-coder:14b"/>
            <Button x:Name="EffortPickerButton" Grid.Column="4" Height="32" VerticalAlignment="Center" Background="Transparent" BorderBrush="Transparent" Foreground="#C7D2DE" Margin="0,0,8,0" FontSize="13" HorizontalContentAlignment="Right" Padding="8,0,8,0" Content="5.4 Medium"/>
            <Button x:Name="MicButton" Grid.Column="5" Style="{StaticResource ComposerIconButtonStyle}" Width="30" Height="30" FontFamily="Segoe MDL2 Assets" FontSize="14" Content="&#xE720;" ToolTip="Paste clipboard text into the prompt"/>
            <Button x:Name="SendButton" Grid.Column="6" Width="42" Height="42" Background="#F5F7FA" BorderBrush="#F5F7FA" Foreground="#111315" FontFamily="Segoe MDL2 Assets" FontWeight="Bold" FontSize="16" Content="&#xE724;"/>
          </Grid>
        </Grid>
      </Border>

      <Border Grid.Row="3" Background="#17191C" Padding="32,0,32,14">
        <StackPanel Orientation="Horizontal">
          <TextBlock x:Name="WorkspaceModeText" Text="Local workspace" Foreground="#AAB3BD" FontSize="12" Margin="0,0,18,0"/>
          <TextBlock x:Name="BranchText" Text="master" Foreground="#AAB3BD" FontSize="12" Margin="0,0,18,0"/>
          <TextBlock x:Name="BinaryPathText" Text="claw.exe" Foreground="#7B8794" FontSize="12"/>
        </StackPanel>
      </Border>
    </Grid>

    <Border x:Name="RightSidebarPanel" Grid.Row="1" Grid.Column="2" Background="#17191C" BorderBrush="#23292F" BorderThickness="1,0,0,0" Padding="18,22,18,18">
      <StackPanel>
        <TextBlock Text="Workspace" Foreground="#AAB3BD" FontSize="13" FontWeight="SemiBold"/>
        <TextBlock x:Name="RightProjectNameText" Text="claw" Foreground="#F5F7FA" FontSize="22" FontWeight="SemiBold" Margin="0,12,0,0"/>
        <TextBlock x:Name="RightProjectPathText" Text="C:\Users\frede\Desktop\claw" Foreground="#7B8794" FontSize="12" Margin="0,8,0,0" TextWrapping="Wrap"/>

        <Border Style="{StaticResource PanelCardStyle}" Margin="0,22,0,0">
          <StackPanel>
            <TextBlock Text="Fortschritt" Foreground="#AAB3BD" FontSize="13" FontWeight="SemiBold"/>
            <TextBlock x:Name="MessageCountText" Text="0 messages" Foreground="#F5F7FA" FontSize="16" Margin="0,10,0,0"/>
            <TextBlock x:Name="AttachmentCountText" Text="0 attachments" Foreground="#C7D2DE" FontSize="13" Margin="0,6,0,0"/>
            <TextBlock x:Name="ProgressText" Text="Idle" Foreground="#F2D07B" FontSize="13" Margin="0,6,0,0"/>
            <ProgressBar x:Name="ProgressBar" Height="8" Margin="0,10,0,0" Minimum="0" Maximum="100" Value="0"/>
            <TextBlock x:Name="LastPromptText" Text="No last prompt yet." Foreground="#7B8794" FontSize="12" Margin="0,10,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>

        <Border Style="{StaticResource PanelCardStyle}" Margin="0,16,0,0">
          <StackPanel>
            <TextBlock Text="Session" Foreground="#AAB3BD" FontSize="13" FontWeight="SemiBold"/>
            <TextBlock x:Name="SessionUpdatedText" Text="Not saved yet" Foreground="#F5F7FA" FontSize="14" Margin="0,10,0,0"/>
            <TextBlock x:Name="CurrentModelText" Text="openai/qwen2.5-coder:14b" Foreground="#C7D2DE" FontSize="12" Margin="0,8,0,0" TextWrapping="Wrap"/>
            <TextBlock x:Name="CurrentPermissionText" Text="workspace-write" Foreground="#C7D2DE" FontSize="12" Margin="0,6,0,0"/>
          </StackPanel>
        </Border>

        <Border Style="{StaticResource PanelCardStyle}" Margin="0,16,0,0">
          <StackPanel>
            <TextBlock Text="Dateien" Foreground="#AAB3BD" FontSize="13" FontWeight="SemiBold"/>
            <TextBlock x:Name="ChangeSummaryText" Text="No file changes tracked yet." Foreground="#F5F7FA" FontSize="13" Margin="0,10,0,0" TextWrapping="Wrap"/>
            <TextBlock x:Name="ChangedFilesText" Text="-" Foreground="#7B8794" FontSize="12" Margin="0,8,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
      </StackPanel>
    </Border>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

function Get-Control {
    param([string]$Name)
    return $window.FindName($Name)
}

$MainMenu = Get-Control "MainMenu"
$MenuChooseProject = Get-Control "MenuChooseProject"
$MenuOpenProject = Get-Control "MenuOpenProject"
$MenuExit = Get-Control "MenuExit"
$MenuNewChat = Get-Control "MenuNewChat"
$MenuResetChat = Get-Control "MenuResetChat"
$MenuFocusSearch = Get-Control "MenuFocusSearch"
$MenuFocusComposer = Get-Control "MenuFocusComposer"
$MenuOpenTerminal = Get-Control "MenuOpenTerminal"
$MenuRunDoctor = Get-Control "MenuRunDoctor"
$RailNewChatButton = Get-Control "RailNewChatButton"
$RailSearchButton = Get-Control "RailSearchButton"
$RailPluginsButton = Get-Control "RailPluginsButton"
$RailAutomationButton = Get-Control "RailAutomationButton"
$RailProjectsButton = Get-Control "RailProjectsButton"
$NewChatButton = Get-Control "NewChatButton"
$SearchTextBox = Get-Control "SearchTextBox"
$PluginsButton = Get-Control "PluginsButton"
$AutomationButton = Get-Control "AutomationButton"
$ProjectNameText = Get-Control "ProjectNameText"
$ProjectPathText = Get-Control "ProjectPathText"
$ProjectHeaderNewButton = Get-Control "ProjectHeaderNewButton"
$ProjectHeaderOpenButton = Get-Control "ProjectHeaderOpenButton"
$ProjectHeaderMenuButton = Get-Control "ProjectHeaderMenuButton"
$ProjectMenuButton = Get-Control "ProjectMenuButton"
$ProjectEditButton = Get-Control "ProjectEditButton"
$ProjectAttachButton = Get-Control "ProjectAttachButton"
$ProjectOpenButton = Get-Control "ProjectOpenButton"
$NewThreadProjectButton = Get-Control "NewThreadProjectButton"
$ResetThreadButton = Get-Control "ResetThreadButton"
$ThreadList = Get-Control "ThreadList"
$ThreadTitleText = Get-Control "ThreadTitleText"
$ThreadSubtitleText = Get-Control "ThreadSubtitleText"
$ConversationScrollViewer = Get-Control "ConversationScrollViewer"
$ConversationStack = Get-Control "ConversationStack"
$PromptTextBox = Get-Control "PromptTextBox"
$AttachButton = Get-Control "AttachButton"
$ModelComboBox = Get-Control "ModelComboBox"
$PermissionComboBox = Get-Control "PermissionComboBox"
$PermissionPickerButton = Get-Control "PermissionPickerButton"
$TerminalButton = Get-Control "TerminalButton"
$ModelPickerButton = Get-Control "ModelPickerButton"
$EffortPickerButton = Get-Control "EffortPickerButton"
$MicButton = Get-Control "MicButton"
$SendButton = Get-Control "SendButton"
$WorkspaceModeText = Get-Control "WorkspaceModeText"
$BranchText = Get-Control "BranchText"
$BinaryPathText = Get-Control "BinaryPathText"
$LeftSidebarColumn = Get-Control "LeftSidebarColumn"
$RightSidebarColumn = Get-Control "RightSidebarColumn"
$LeftSidebarPanel = Get-Control "LeftSidebarPanel"
$RightSidebarPanel = Get-Control "RightSidebarPanel"
$ToggleLeftPanelButton = Get-Control "ToggleLeftPanelButton"
$ToggleRightPanelButton = Get-Control "ToggleRightPanelButton"
$RetryButton = Get-Control "RetryButton"
$StopButton = Get-Control "StopButton"
$RightProjectNameText = Get-Control "RightProjectNameText"
$RightProjectPathText = Get-Control "RightProjectPathText"
$MessageCountText = Get-Control "MessageCountText"
$AttachmentCountText = Get-Control "AttachmentCountText"
$ProgressText = Get-Control "ProgressText"
$ProgressBar = Get-Control "ProgressBar"
$LastPromptText = Get-Control "LastPromptText"
$SessionUpdatedText = Get-Control "SessionUpdatedText"
$CurrentModelText = Get-Control "CurrentModelText"
$CurrentPermissionText = Get-Control "CurrentPermissionText"
$ChangeSummaryText = Get-Control "ChangeSummaryText"
$ChangedFilesText = Get-Control "ChangedFilesText"
$RecentApplyButton = Get-Control "RecentApplyButton"
$RecentArchiveButton = Get-Control "RecentArchiveButton"
$RecentDeleteButton = Get-Control "RecentDeleteButton"
$ThreadMenuButton = Get-Control "ThreadMenuButton"
$ProjectChooseButton = Get-Control "ProjectEditButton"
$HeaderRunButton = Get-Control "HeaderRunButton"
$StatusPill = Get-Control "StatusPill"
$StatusPillText = Get-Control "StatusPillText"

$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Choose the project folder Claw should work in"

$fileDialog = New-Object System.Windows.Forms.OpenFileDialog
$fileDialog.Title = "Choose files to include in the prompt"
$fileDialog.Multiselect = $true
$fileDialog.CheckFileExists = $true
$fileDialog.CheckPathExists = $true

$dispatcherTimer = New-Object System.Windows.Threading.DispatcherTimer
$dispatcherTimer.Interval = [TimeSpan]::FromMilliseconds(250)

$projectMenu = New-Object System.Windows.Controls.ContextMenu
foreach ($label in @(
    "Choose project folder",
    "Open in Explorer",
    "New chat",
    "Reset chat"
)) {
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Header = $label
    if ($label -eq "Choose project folder") {
        $item.Add_Click({
            if (Test-Path -LiteralPath $script:ProjectPath) {
                $folderBrowser.SelectedPath = $script:ProjectPath
            }
            if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $script:ProjectPath = $folderBrowser.SelectedPath
                Save-CurrentSettings
                Refresh-ProjectState
            }
        })
    } elseif ($label -eq "Open in Explorer") {
        $item.Add_Click({
            if (Test-Path -LiteralPath $script:ProjectPath) {
                Start-Process explorer.exe -ArgumentList @($script:ProjectPath) | Out-Null
            }
        })
    } elseif ($label -eq "New chat") {
        $item.Add_Click({
            if ($NewChatButton) {
                $NewChatButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        })
    } elseif ($label -eq "Reset chat") {
        $item.Add_Click({
            if ($ResetThreadButton) {
                $ResetThreadButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        })
    } else {
        continue
    }
    [void]$projectMenu.Items.Add($item)
}
$ProjectMenuButton.ContextMenu = $projectMenu

$threadMenu = New-Object System.Windows.Controls.ContextMenu
foreach ($label in @(
    "Chat anheften",
    "Chat umbenennen",
    "Chat archivieren",
    "Arbeitsverzeichnis kopieren",
    "Sitzungs-ID kopieren",
    "Als Markdown kopieren",
    "Seitenchat öffnen",
    "Lokal forken",
    "Im Minifenster öffnen"
)) {
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Header = $label
    $item.Add_Click({
        param($sender, $eventArgs)
        $selected = [string]$sender.Header

        switch ($selected) {
            "Chat anheften" {
                Add-Conversation -Role "Status" -Text "Chat pinned (local placeholder)." -RoleColor $script:Theme.AccentSoft | Out-Null
                Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Status" -Text "Chat pinned (local placeholder)." -RoleColor $script:Theme.AccentSoft | Out-Null
            }
            "Chat umbenennen" {
                if ($PromptTextBox) {
                    $PromptTextBox.Text = "/session switch " + $script:CurrentThreadTitle
                    $PromptTextBox.Focus() | Out-Null
                }
            }
            "Chat archivieren" {
                $session = Get-SessionById -Id $script:CurrentSessionId
                if ($null -ne $session) {
                    $session.title = "[Archiviert] " + [string]$session.title
                    $session.updatedAt = [DateTime]::UtcNow.ToString("o")
                    Save-Sessions
                    Refresh-ThreadList
                    Refresh-SessionMeta
                }
            }
            "Arbeitsverzeichnis kopieren" {
                Set-ClipboardSafe -Text $script:ProjectPath
            }
            "Sitzungs-ID kopieren" {
                Set-ClipboardSafe -Text $script:CurrentSessionId
            }
            "Als Markdown kopieren" {
                $path = Export-CurrentSession
                if (Test-Path -LiteralPath $path) {
                    $md = Get-Content -LiteralPath $path -Raw
                    Set-ClipboardSafe -Text $md
                }
            }
            "Seitenchat öffnen" {
                Add-Conversation -Role "Status" -Text "Seitenchat ist in dieser lokalen Version noch nicht separat verfügbar." -RoleColor $script:Theme.Muted | Out-Null
            }
            "Lokal forken" {
                Start-NewSession -Title ("Fork: " + $script:CurrentThreadTitle)
                Add-Conversation -Role "System" -Text "Created local fork of this chat." -RoleColor $script:Theme.ReadyFg | Out-Null
                Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text "Created local fork of this chat." -RoleColor $script:Theme.ReadyFg | Out-Null
            }
            "Im Minifenster öffnen" {
                Add-Conversation -Role "Status" -Text "Minifenster ist in dieser lokalen Version noch nicht verfügbar." -RoleColor $script:Theme.Muted | Out-Null
            }
        }
    })
    [void]$threadMenu.Items.Add($item)
}
if ($ThreadMenuButton) {
    $ThreadMenuButton.ContextMenu = $threadMenu
}

$attachMenu = New-Object System.Windows.Controls.ContextMenu

$attachFileMenuItem = New-Object System.Windows.Controls.MenuItem
$attachFileMenuItem.Header = "Add files"
$attachMenu.Items.Add($attachFileMenuItem) | Out-Null

$clearAttachMenuItem = New-Object System.Windows.Controls.MenuItem
$clearAttachMenuItem.Header = "Clear attachments"
$attachMenu.Items.Add($clearAttachMenuItem) | Out-Null

$chooseProjectMenuItem = New-Object System.Windows.Controls.MenuItem
$chooseProjectMenuItem.Header = "Choose project folder"
$attachMenu.Items.Add($chooseProjectMenuItem) | Out-Null

$AttachButton.ContextMenu = $attachMenu

$permissionMenu = New-Object System.Windows.Controls.ContextMenu
if ($PermissionPickerButton) {
    $PermissionPickerButton.ContextMenu = $permissionMenu
}

$modelMenu = New-Object System.Windows.Controls.ContextMenu
if ($ModelPickerButton) {
    $ModelPickerButton.ContextMenu = $modelMenu
}

$effortMenu = New-Object System.Windows.Controls.ContextMenu
foreach ($label in @("5.4 Medium", "5.4 Fast", "5.4 Deep")) {
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Header = $label
    $item.Add_Click({
        param($sender, $eventArgs)
        $EffortPickerButton.Content = [string]$sender.Header
    })
    [void]$effortMenu.Items.Add($item)
}
if ($EffortPickerButton) {
    $EffortPickerButton.ContextMenu = $effortMenu
}

function Get-ComboValue {
    param($ComboBox)
    if ($ComboBox.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) {
        return [string]$ComboBox.SelectedItem.Content
    }
    return [string]$ComboBox.Text
}

function Sync-PermissionCombo {
    $permissionMenu.Items.Clear()
    foreach ($item in $PermissionComboBox.Items) {
        $menuItem = New-Object System.Windows.Controls.MenuItem
        $menuItem.Header = [string]$item.Content
        $menuItem.Add_Click({
            param($sender, $eventArgs)
            $selected = [string]$sender.Header
            for ($index = 0; $index -lt $PermissionComboBox.Items.Count; $index++) {
                if ([string]$PermissionComboBox.Items[$index].Content -eq $selected) {
                    $PermissionComboBox.SelectedIndex = $index
                    break
                }
            }
        })
        [void]$permissionMenu.Items.Add($menuItem)
    }
    $PermissionPickerButton.Content = Get-ComboValue -ComboBox $PermissionComboBox
}

function Sync-ModelMenu {
    $modelMenu.Items.Clear()
    foreach ($item in $ModelComboBox.Items) {
        $menuItem = New-Object System.Windows.Controls.MenuItem
        $menuItem.Header = [string]$item.Content
        $menuItem.Add_Click({
            param($sender, $eventArgs)
            $selected = [string]$sender.Header
            for ($index = 0; $index -lt $ModelComboBox.Items.Count; $index++) {
                if ([string]$ModelComboBox.Items[$index].Content -eq $selected) {
                    $ModelComboBox.SelectedIndex = $index
                    break
                }
            }
        })
        [void]$modelMenu.Items.Add($menuItem)
    }
    $ModelPickerButton.Content = Get-ComboValue -ComboBox $ModelComboBox
}

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

function Set-ProgressState {
    param(
        [string]$Label,
        [double]$Value = 0,
        [bool]$Indeterminate = $false
    )

    if ($ProgressText) {
        $ProgressText.Text = $Label
    }
    if ($ProgressBar) {
        $ProgressBar.IsIndeterminate = $Indeterminate
        if (-not $Indeterminate) {
            $ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Value))
        }
    }
}

function Set-RunIndicator {
    param(
        [bool]$Running,
        [string]$StatusText = "Ready"
    )

    if ($Running) {
        $frame = $script:SpinnerFrames[$script:SpinnerIndex % $script:SpinnerFrames.Count]
        $script:SpinnerIndex++
        if ($HeaderRunButton) {
            $HeaderRunButton.Content = $frame
        }
        if ($StatusPillText) {
            $StatusPillText.Text = "$StatusText $frame"
        }
        return
    }

    $script:SpinnerIndex = 0
    if ($HeaderRunButton) {
        $HeaderRunButton.Content = ">"
    }
}

function Refresh-SessionMeta {
    $session = Get-SessionById -Id $script:CurrentSessionId
    if ($null -eq $session) {
        return
    }

    if ($RightProjectNameText) {
        $RightProjectNameText.Text = $ProjectNameText.Text
    }
    if ($RightProjectPathText) {
        $RightProjectPathText.Text = $script:ProjectPath
    }
    if ($MessageCountText) {
        $MessageCountText.Text = ("{0} messages" -f @($session.messages).Count)
    }
    if ($AttachmentCountText) {
        $AttachmentCountText.Text = ("{0} attachments" -f $script:AttachedFiles.Count)
    }
    if ($LastPromptText) {
        if ([string]::IsNullOrWhiteSpace([string]$session.lastPrompt)) {
            $LastPromptText.Text = "No last prompt yet."
        } else {
            $LastPromptText.Text = [string]$session.lastPrompt
        }
    }
    if ($SessionUpdatedText) {
        $SessionUpdatedText.Text = "Updated " + ([string]$session.updatedAt)
    }
    if ($CurrentModelText) {
        $CurrentModelText.Text = Get-ComboValue -ComboBox $ModelComboBox
    }
    if ($CurrentPermissionText) {
        $CurrentPermissionText.Text = Get-ComboValue -ComboBox $PermissionComboBox
    }
    if ($ChangeSummaryText) {
        $ChangeSummaryText.Text = $script:LastChangeSummary
    }
    if ($ChangedFilesText) {
        if ($script:LastChangedFiles.Count -eq 0) {
            $ChangedFilesText.Text = "-"
        } else {
            $preview = @($script:LastChangedFiles | Select-Object -First 8)
            $suffix = ""
            if ($script:LastChangedFiles.Count -gt $preview.Count) {
                $suffix = "`r`n... +" + ($script:LastChangedFiles.Count - $preview.Count) + " more"
            }
            $ChangedFilesText.Text = (($preview -join "`r`n") + $suffix)
        }
    }
}

function Apply-SidebarState {
    if ($LeftSidebarColumn) {
        $LeftSidebarColumn.Width = $(if ($script:LeftPanelExpanded) { [System.Windows.GridLength]::new(380) } else { [System.Windows.GridLength]::new(0) })
    }
    if ($RightSidebarColumn) {
        $RightSidebarColumn.Width = $(if ($script:RightPanelExpanded) { [System.Windows.GridLength]::new(300) } else { [System.Windows.GridLength]::new(0) })
    }
    if ($ToggleLeftPanelButton) {
        $ToggleLeftPanelButton.Content = $(if ($script:LeftPanelExpanded) { [char]0xE76B } else { [char]0xE76C })
    }
    if ($ToggleRightPanelButton) {
        $ToggleRightPanelButton.Content = $(if ($script:RightPanelExpanded) { [char]0xE76C } else { [char]0xE76B })
    }
}

function Set-ClipboardSafe {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    try {
        [System.Windows.Clipboard]::SetText($Text)
    } catch {
        [System.Windows.MessageBox]::Show("Clipboard access failed: $($_.Exception.Message)", "Claw Studio") | Out-Null
    }
}

function Set-RailSelection {
    param([string]$Section)

    $script:ActiveRailSection = $Section
    $selectedBackground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2B333B")
    $selectedBorder = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3A424B")
    $transparent = [System.Windows.Media.BrushConverter]::new().ConvertFromString("Transparent")
    $muted = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#AAB3BD")
    $bright = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F5F7FA")

    $railMap = @(
        @{ Name = "new"; Button = $RailNewChatButton },
        @{ Name = "search"; Button = $RailSearchButton },
        @{ Name = "plugins"; Button = $RailPluginsButton },
        @{ Name = "automation"; Button = $RailAutomationButton },
        @{ Name = "projects"; Button = $RailProjectsButton }
    )

    foreach ($item in $railMap) {
        $button = $item.Button
        if ($null -eq $button) {
            continue
        }

        $button.Background = $transparent
        $button.BorderBrush = $transparent
        $button.Foreground = $muted

        if ($item.Name -eq $Section) {
            $button.Background = $selectedBackground
            $button.BorderBrush = $selectedBorder
            $button.Foreground = $bright
        }
    }
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

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = [System.Windows.Thickness]::new(0,0,0,22)

    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = [System.Windows.CornerRadius]::new(22)
    $border.Padding = [System.Windows.Thickness]::new(22,18,22,18)
    $border.MaxWidth = $(if ($IsUser) { 720 } else { 860 })
    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if ($IsUser) { $script:Theme.BubbleUser } else { $script:Theme.Bubble }))
    $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($script:Theme.BorderSoft)
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $border.HorizontalAlignment = $(if ($IsUser) { "Right" } else { "Left" })

    $stack = New-Object System.Windows.Controls.StackPanel

    $roleBlock = New-Object System.Windows.Controls.TextBlock
    $roleBlock.Text = $Role
    $roleBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($RoleColor)
    $roleBlock.FontWeight = "SemiBold"
    $roleBlock.FontSize = 12
    $stack.Children.Add($roleBlock) | Out-Null

    $bodyBlock = New-Object System.Windows.Controls.TextBlock
    $bodyBlock.Text = $Text
    $bodyBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($script:Theme.Foreground)
    $bodyBlock.TextWrapping = "Wrap"
    $bodyBlock.Margin = [System.Windows.Thickness]::new(0,8,0,0)
    $bodyBlock.FontSize = 14
    $bodyBlock.LineHeight = 22
    if ($UseMono) {
        $bodyBlock.FontFamily = "Cascadia Mono"
        $bodyBlock.FontSize = 13
        $bodyBlock.LineHeight = 20
    }
    $stack.Children.Add($bodyBlock) | Out-Null

    $border.Child = $stack
    $grid.Children.Add($border) | Out-Null

    return @{
        Container = $grid
        TextBlock = $bodyBlock
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
    $displayTitle = [string]$script:AssistantPlaceholderFrames[0]
    $message = Add-Conversation -Role "Claw" -Text $displayTitle -RoleColor $script:Theme.Accent -UseMono:$false
    $script:ActiveOutputControl = $message.TextBlock
    $script:CurrentAssistantMessage = Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Claw" -Text $displayTitle -RoleColor $script:Theme.Accent -UseMono:$false
    $script:IsAssistantPlaceholderActive = $true
    $script:AssistantPlaceholderIndex = 0
    Refresh-SessionMeta
}

function Append-StreamText {
    param([string]$Text)

    if ($script:ActiveOutputControl -and -not [string]::IsNullOrEmpty($Text)) {
        $wasPlaceholder = $script:IsAssistantPlaceholderActive
        if ($wasPlaceholder) {
            $script:ActiveOutputControl.Text = $Text
            $script:IsAssistantPlaceholderActive = $false
        } else {
            $script:ActiveOutputControl.Text += $Text
        }
        if ($script:CurrentAssistantMessage) {
            if ($wasPlaceholder) {
                $script:CurrentAssistantMessage.text = $Text
            } else {
                $script:CurrentAssistantMessage.text = [string]$script:CurrentAssistantMessage.text + $Text
            }
            $session = Get-SessionById -Id $script:CurrentSessionId
            if ($null -ne $session) {
                $session.updatedAt = [DateTime]::UtcNow.ToString("o")
                Save-Sessions
            }
        }
        Set-ProgressState -Label "Streaming output" -Value 65 -Indeterminate $true
        Scroll-To-Bottom
    }
}

function Refresh-ProjectState {
    $leaf = Split-Path -Leaf $script:ProjectPath
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        $leaf = "claw"
    }
    $ProjectNameText.Text = $leaf
    $ProjectPathText.Text = $script:ProjectPath
    $BranchText.Text = Get-GitBranch -Path $script:ProjectPath
    $BinaryPathText.Text = Find-ClawBinary
    $ModelPickerButton.Content = Get-ComboValue -ComboBox $ModelComboBox
    $PermissionPickerButton.Content = Get-ComboValue -ComboBox $PermissionComboBox
    $session = Get-SessionById -Id $script:CurrentSessionId
    if ($null -ne $session) {
        $session.projectPath = $script:ProjectPath
        $session.updatedAt = [DateTime]::UtcNow.ToString("o")
        Save-Sessions
    }
    Refresh-SessionMeta
}

function Save-CurrentSettings {
    Save-Settings -ProjectPath $script:ProjectPath -Model (Get-ComboValue -ComboBox $ModelComboBox) -PermissionMode (Get-ComboValue -ComboBox $PermissionComboBox)
}

function Set-ControlEnabled {
    param(
        $Control,
        [bool]$Enabled
    )

    if ($null -eq $Control) {
        return
    }

    $property = $Control.PSObject.Properties["IsEnabled"]
    if ($null -ne $property) {
        $Control.IsEnabled = $Enabled
    }
}

function Set-UiBusy {
    param([bool]$Busy)

    Set-ControlEnabled -Control $ProjectChooseButton -Enabled (-not $Busy)
    Set-ControlEnabled -Control $ProjectMenuButton -Enabled (-not $Busy)
    Set-ControlEnabled -Control $ProjectOpenButton -Enabled (-not $Busy)
    Set-ControlEnabled -Control $NewThreadProjectButton -Enabled (-not $Busy)
    Set-ControlEnabled -Control $ResetThreadButton -Enabled (-not $Busy)
    Set-ControlEnabled -Control $ModelComboBox -Enabled (-not $Busy)
    Set-ControlEnabled -Control $PermissionComboBox -Enabled (-not $Busy)
    Set-ControlEnabled -Control $PermissionPickerButton -Enabled (-not $Busy)
    Set-ControlEnabled -Control $ModelPickerButton -Enabled (-not $Busy)
    Set-ControlEnabled -Control $EffortPickerButton -Enabled (-not $Busy)
    Set-ControlEnabled -Control $ThreadList -Enabled (-not $Busy)
    Set-ControlEnabled -Control $SendButton -Enabled (-not $Busy)
    Set-ControlEnabled -Control $TerminalButton -Enabled (-not $Busy)
    Set-ControlEnabled -Control $HeaderRunButton -Enabled (-not $Busy)
    Set-ControlEnabled -Control $RetryButton -Enabled (-not $Busy)
    Set-ControlEnabled -Control $StopButton -Enabled $Busy
}

function Update-ThreadTitle {
    param([string]$Title)
    $script:CurrentThreadTitle = $Title
    $ThreadTitleText.Text = $Title
    Add-ThreadTitle -Title $Title
}

function Validate-RunContext {
    $clawBinary = Find-ClawBinary
    if ([string]::IsNullOrWhiteSpace($clawBinary) -or -not (Test-Path -LiteralPath $clawBinary)) {
        [System.Windows.MessageBox]::Show("claw.exe was not found. Run setup.bat first, then reopen Claw Studio.", "Claw Studio") | Out-Null
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($script:ProjectPath) -or -not (Test-Path -LiteralPath $script:ProjectPath)) {
        [System.Windows.MessageBox]::Show("Choose a valid project folder first.", "Claw Studio") | Out-Null
        return $false
    }

    if (Test-BroadProjectPath -Path $script:ProjectPath) {
        $result = [System.Windows.MessageBox]::Show("That folder is too broad. Pick a real repo folder instead when possible.`n`nContinue anyway?", "Claw Studio", "YesNo", "Warning")
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
        [string]$PromptText,
        [string]$ProgressLabel = "Running task"
    )

    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        [System.Windows.MessageBox]::Show("A task is already running. Stop it first or wait until it finishes.", "Claw Studio") | Out-Null
        return
    }

    $script:ProjectSnapshotBeforeRun = Get-ProjectSnapshot -Path $WorkingDirectory
    $script:LastChangedFiles = @()
    $script:LastChangeSummary = "Tracking file changes for this run..."

    $script:StdOutPath = Join-Path $StudioRoot ("stdout-" + [guid]::NewGuid().ToString("N") + ".log")
    $script:StdErrPath = Join-Path $StudioRoot ("stderr-" + [guid]::NewGuid().ToString("N") + ".log")
    $script:StdOutPosition = 0L
    $script:StdErrPosition = 0L
    "" | Set-Content -LiteralPath $script:StdOutPath -Encoding UTF8
    "" | Set-Content -LiteralPath $script:StdErrPath -Encoding UTF8

    Add-Conversation -Role "You" -Text $PromptText -RoleColor $script:Theme.Foreground -IsUser:$true | Out-Null
    Add-MessageToSession -SessionId $script:CurrentSessionId -Role "You" -Text $PromptText -RoleColor $script:Theme.Foreground -IsUser:$true | Out-Null
    $session = Get-SessionById -Id $script:CurrentSessionId
    if ($null -ne $session) {
        $session.lastPrompt = $PromptText
        if ($session.title -eq "New chat" -or $session.title -eq "Install Claw Code") {
            $session.title = New-SessionTitleFromPrompt -Prompt $PromptText
            $ThreadTitleText.Text = $session.title
            $script:CurrentThreadTitle = $session.title
        }
        $session.updatedAt = [DateTime]::UtcNow.ToString("o")
        Save-Sessions
    }
    Start-AssistantStream -Title "Running in $WorkingDirectory"

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Arguments = ConvertTo-ArgumentString -Arguments $Arguments

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $process.EnableRaisingEvents = $true

    $outWriter = [System.IO.StreamWriter]::new($script:StdOutPath, $true, [System.Text.Encoding]::UTF8)
    $errWriter = [System.IO.StreamWriter]::new($script:StdErrPath, $true, [System.Text.Encoding]::UTF8)

    $outHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $eventArgs)
        if ($null -ne $eventArgs.Data) {
            $outWriter.WriteLine($eventArgs.Data)
            $outWriter.Flush()
        }
    }

    $errHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $eventArgs)
        if ($null -ne $eventArgs.Data) {
            $errWriter.WriteLine($eventArgs.Data)
            $errWriter.Flush()
        }
    }

    $process.add_OutputDataReceived($outHandler)
    $process.add_ErrorDataReceived($errHandler)
    $process.add_Exited({
        try {
            $outWriter.Flush()
            $errWriter.Flush()
        } catch {
        }
        $outWriter.Dispose()
        $errWriter.Dispose()
    })

    [void]$process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    $script:CurrentProcess = $process
    $script:LastPromptText = $PromptText
    Set-UiBusy -Busy $true
    Set-Status -Text "Running" -ForegroundHex $script:Theme.RunFg -BackgroundHex $script:Theme.RunBg
    Set-RunIndicator -Running $true -StatusText "Running"
    Set-ProgressState -Label $ProgressLabel -Value 20 -Indeterminate $true
    $ThreadSubtitleText.Text = "running..."
    Refresh-ThreadList -Filter $(if ($SearchTextBox -and $SearchTextBox.Text -ne "Suche") { $SearchTextBox.Text } else { "" })
    Refresh-SessionMeta
    $dispatcherTimer.Start()
}

function Run-ClawCommand {
    param(
        [string[]]$Arguments,
        [string]$PromptText,
        [string]$ProgressLabel = "Running task"
    )

    if (-not (Validate-RunContext)) {
        return
    }

    Save-CurrentSettings
    Refresh-ProjectState
    Start-Command -Executable (Find-ClawBinary) -Arguments $Arguments -WorkingDirectory $script:ProjectPath -PromptText $PromptText -ProgressLabel $ProgressLabel
}

function Stop-CurrentRun {
    if (-not $script:CurrentProcess -or $script:CurrentProcess.HasExited) {
        return
    }

    $script:RunWasCancelled = $true
    try {
        $script:CurrentProcess.Kill()
    } catch {
    }
}

function Finalize-RunChangeTracking {
    $after = Get-ProjectSnapshot -Path $script:ProjectPath
    $changes = Get-ProjectChangeSet -Before $script:ProjectSnapshotBeforeRun -After $after -Root $script:ProjectPath
    $script:LastChangedFiles = @($changes)

    if ($changes.Count -eq 0) {
        $script:LastChangeSummary = "No project files changed in the last run."
        return "No project files changed."
    }

    $newCount = @($changes | Where-Object { $_.StartsWith("[new]") }).Count
    $changedCount = @($changes | Where-Object { $_.StartsWith("[changed]") }).Count
    $deletedCount = @($changes | Where-Object { $_.StartsWith("[deleted]") }).Count
    $script:LastChangeSummary = ("{0} file change(s): {1} new, {2} changed, {3} deleted" -f $changes.Count, $newCount, $changedCount, $deletedCount)
    return $script:LastChangeSummary
}

$script:ProjectPath = Get-DefaultProjectPath
Initialize-Sessions

$modelValue = Get-DefaultModel
$permissionValue = Get-DefaultPermissionMode

for ($i = 0; $i -lt $ModelComboBox.Items.Count; $i++) {
    if ([string]$ModelComboBox.Items[$i].Content -eq $modelValue) {
        $ModelComboBox.SelectedIndex = $i
        break
    }
}

for ($i = 0; $i -lt $PermissionComboBox.Items.Count; $i++) {
    if ([string]$PermissionComboBox.Items[$i].Content -eq $permissionValue) {
        $PermissionComboBox.SelectedIndex = $i
        break
    }
}

Sync-PermissionCombo
Sync-ModelMenu
Refresh-ProjectState
Apply-SidebarState
Set-RailSelection -Section "projects"
Update-ThreadTitle -Title ([string](Get-SessionById -Id $script:CurrentSessionId).title)
Refresh-ThreadList
Render-SessionMessages
$ThreadSubtitleText.Text = "ready"
$PromptTextBox.Text = [string](Get-SessionById -Id $script:CurrentSessionId).promptDraft
if ([string]::IsNullOrWhiteSpace($PromptTextBox.Text)) {
    $PromptTextBox.Text = "Analyze this repository. Explain the architecture, build flow, dependencies, risky areas, and the first improvement you would make."
}
Set-ProgressState -Label "Idle" -Value 0
Refresh-SessionMeta

$dispatcherTimer.Add_Tick({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        Set-RunIndicator -Running $true -StatusText "Running"
        if ($script:ActiveOutputControl -and $script:IsAssistantPlaceholderActive) {
            $script:AssistantPlaceholderIndex = ($script:AssistantPlaceholderIndex + 1) % $script:AssistantPlaceholderFrames.Count
            $frame = [string]$script:AssistantPlaceholderFrames[$script:AssistantPlaceholderIndex]
            $script:ActiveOutputControl.Text = $frame
            if ($script:CurrentAssistantMessage) {
                $script:CurrentAssistantMessage.text = $frame
            }
        }
    }

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
        $exitCode = $script:CurrentProcess.ExitCode
        $jsonFallback = Try-HandleJsonOutputFallback -WorkspaceRoot $script:ProjectPath -StdOutPath $script:StdOutPath
        if ($script:ActiveOutputControl -and $jsonFallback -and -not [string]::IsNullOrWhiteSpace([string]$jsonFallback.Message)) {
            $script:ActiveOutputControl.Text = [string]$jsonFallback.Message
        }
        if ($script:CurrentAssistantMessage -and $jsonFallback -and -not [string]::IsNullOrWhiteSpace([string]$jsonFallback.Message)) {
            $script:CurrentAssistantMessage.text = [string]$jsonFallback.Message
            $session = Get-SessionById -Id $script:CurrentSessionId
            if ($null -ne $session) {
                $session.updatedAt = [DateTime]::UtcNow.ToString("o")
                Save-Sessions
            }
        }
        $script:ActiveOutputControl = $null
        $script:IsAssistantPlaceholderActive = $false
        $changeText = Finalize-RunChangeTracking

        if ($script:RunWasCancelled) {
            Add-Conversation -Role "Status" -Text "Process stopped by user." -RoleColor $script:Theme.RunFg | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Status" -Text "Process stopped by user." -RoleColor $script:Theme.RunFg | Out-Null
            Set-Status -Text "Stopped" -ForegroundHex $script:Theme.RunFg -BackgroundHex $script:Theme.RunBg
            Set-RunIndicator -Running $false
            Set-ProgressState -Label "Stopped" -Value 0
            $ThreadSubtitleText.Text = "stopped"
        } elseif ($exitCode -eq 0) {
            Add-Conversation -Role "Status" -Text "Process finished successfully." -RoleColor $script:Theme.ReadyFg | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Status" -Text "Process finished successfully." -RoleColor $script:Theme.ReadyFg | Out-Null
            if ($jsonFallback -and $jsonFallback.Mode -eq "fallback") {
                Add-Conversation -Role "Tool Fallback" -Text ([string]$jsonFallback.Summary) -RoleColor $script:Theme.RunFg | Out-Null
                Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Tool Fallback" -Text ([string]$jsonFallback.Summary) -RoleColor $script:Theme.RunFg | Out-Null
            }
            Add-Conversation -Role "Files" -Text $changeText -RoleColor $script:Theme.AccentSoft | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Files" -Text $changeText -RoleColor $script:Theme.AccentSoft | Out-Null
            Set-Status -Text "Ready" -ForegroundHex $script:Theme.ReadyFg -BackgroundHex $script:Theme.ReadyBg
            Set-RunIndicator -Running $false
            Set-ProgressState -Label "Completed" -Value 100
            $ThreadSubtitleText.Text = "done"
        } else {
            Add-Conversation -Role "Status" -Text "Process finished with exit code $exitCode." -RoleColor $script:Theme.ErrorFg | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Status" -Text "Process finished with exit code $exitCode." -RoleColor $script:Theme.ErrorFg | Out-Null
            Add-Conversation -Role "Files" -Text $changeText -RoleColor $script:Theme.AccentSoft | Out-Null
            Add-MessageToSession -SessionId $script:CurrentSessionId -Role "Files" -Text $changeText -RoleColor $script:Theme.AccentSoft | Out-Null
            Set-Status -Text "Needs attention" -ForegroundHex $script:Theme.ErrorFg -BackgroundHex $script:Theme.ErrorBg
            Set-RunIndicator -Running $false
            Set-ProgressState -Label "Failed" -Value 100
            $ThreadSubtitleText.Text = "finished with error"
        }

        Set-UiBusy -Busy $false
        $script:RunWasCancelled = $false
        Refresh-SessionMeta
        $script:CurrentProcess.Dispose()
        $script:CurrentProcess = $null
    }
})

$sendAction = {
    try {
        $prompt = $PromptTextBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($prompt)) {
            return
        }

        if (Handle-SlashCommand -Prompt $prompt) {
            $PromptTextBox.Text = ""
            Update-SessionDraft -Text ""
            Refresh-SessionMeta
            return
        }

        $executionPrompt = @(
            "Work directly in the current project folder."
            "If the request asks for changes, edit the files instead of only describing them."
            "Show progress while working, then summarize what changed."
            ""
            $prompt
        ) -join "`r`n"

        Run-ClawCommand -Arguments @(
            "--model", (Get-ComboValue -ComboBox $ModelComboBox),
            "--permission-mode", (Get-ComboValue -ComboBox $PermissionComboBox),
            "--output-format", "json",
            "prompt", $executionPrompt
        ) -PromptText $prompt -ProgressLabel "Planning and editing files"
    } catch {
        [System.Windows.MessageBox]::Show(
            ("Send failed.`n`n" + $_.Exception.Message),
            "Claw Studio"
        ) | Out-Null
    }
}

if ($SendButton) { $SendButton.Add_Click({ & $sendAction }) }
if ($HeaderRunButton) { $HeaderRunButton.Add_Click({ & $sendAction }) }
if ($RetryButton) { $RetryButton.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($script:LastPromptText)) {
        $PromptTextBox.Text = $script:LastPromptText
        & $sendAction
    }
}) }
if ($StopButton) { $StopButton.Add_Click({ Stop-CurrentRun }) }
if ($ToggleLeftPanelButton) { $ToggleLeftPanelButton.Add_Click({
    $script:LeftPanelExpanded = -not $script:LeftPanelExpanded
    Apply-SidebarState
}) }
if ($ToggleRightPanelButton) { $ToggleRightPanelButton.Add_Click({
    $script:RightPanelExpanded = -not $script:RightPanelExpanded
    Apply-SidebarState
}) }
if ($MenuChooseProject) { $MenuChooseProject.Add_Click({ if ($ProjectChooseButton) { $ProjectChooseButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }) }
if ($MenuOpenProject) { $MenuOpenProject.Add_Click({ if ($ProjectOpenButton) { $ProjectOpenButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }) }
if ($MenuExit) { $MenuExit.Add_Click({ $window.Close() }) }
if ($MenuNewChat) { $MenuNewChat.Add_Click({ if ($NewChatButton) { $NewChatButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }) }
if ($MenuResetChat) { $MenuResetChat.Add_Click({ if ($ResetThreadButton) { $ResetThreadButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }) }
if ($MenuFocusSearch) { $MenuFocusSearch.Add_Click({ if ($SearchTextBox) { $SearchTextBox.Focus() | Out-Null } }) }
if ($MenuFocusComposer) { $MenuFocusComposer.Add_Click({ if ($PromptTextBox) { $PromptTextBox.Focus() | Out-Null } }) }
if ($MenuOpenTerminal) { $MenuOpenTerminal.Add_Click({ if ($TerminalButton) { $TerminalButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }) }
if ($MenuRunDoctor) { $MenuRunDoctor.Add_Click({
    $PromptTextBox.Text = "Run doctor for this project and explain any warnings."
    & $sendAction
}) }
if ($RailNewChatButton) { $RailNewChatButton.Add_Click({ Set-RailSelection -Section "new"; if ($NewChatButton) { $NewChatButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }) }
if ($RailSearchButton) { $RailSearchButton.Add_Click({ Set-RailSelection -Section "search"; if ($SearchTextBox) { $SearchTextBox.Focus() | Out-Null } }) }
if ($RailPluginsButton) { $RailPluginsButton.Add_Click({ Set-RailSelection -Section "plugins"; if ($PluginsButton) { $PluginsButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }) }
if ($RailAutomationButton) { $RailAutomationButton.Add_Click({ Set-RailSelection -Section "automation"; if ($AutomationButton) { $AutomationButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }) }
if ($RailProjectsButton) { $RailProjectsButton.Add_Click({ Set-RailSelection -Section "projects"; if ($ThreadList) { $ThreadList.Focus() | Out-Null } }) }
if ($NewChatButton) { $NewChatButton.Add_Click({
    Start-NewSession -Title "New chat"
    $ThreadSubtitleText.Text = "just created"
    Add-Conversation -Role "System" -Text "Started a fresh chat." -RoleColor $script:Theme.Muted | Out-Null
    Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text "Started a fresh chat." -RoleColor $script:Theme.Muted | Out-Null
    Refresh-SessionMeta
}) }
if ($SearchTextBox) { $SearchTextBox.Add_GotFocus({
    if ($SearchTextBox.Text -eq "Suche") {
        $SearchTextBox.Text = ""
    }
}) }
if ($SearchTextBox) { $SearchTextBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($SearchTextBox.Text)) {
        $SearchTextBox.Text = "Suche"
        Refresh-ThreadList
    }
}) }
if ($SearchTextBox) { $SearchTextBox.Add_TextChanged({
    if ($null -eq $SearchTextBox) {
        return
    }

    $filter = $SearchTextBox.Text
    if ($filter -eq "Suche") {
        $filter = ""
    }
    Refresh-ThreadList -Filter $filter
}) }
if ($ProjectChooseButton) { $ProjectChooseButton.Add_Click({
    if (Test-Path -LiteralPath $script:ProjectPath) {
        $folderBrowser.SelectedPath = $script:ProjectPath
    }
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:ProjectPath = $folderBrowser.SelectedPath
        Save-CurrentSettings
        Refresh-ProjectState
    }
}) }
if ($ProjectMenuButton) { $ProjectMenuButton.Add_Click({
    if ($ProjectMenuButton.ContextMenu) { $ProjectMenuButton.ContextMenu.IsOpen = $true }
}) }
if ($ProjectHeaderNewButton) { $ProjectHeaderNewButton.Add_Click({
    if ($ProjectChooseButton) { $ProjectChooseButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
}) }
if ($ProjectHeaderOpenButton) { $ProjectHeaderOpenButton.Add_Click({
    if ($ProjectOpenButton) { $ProjectOpenButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
}) }
if ($ProjectHeaderMenuButton) { $ProjectHeaderMenuButton.Add_Click({
    if ($ProjectMenuButton.ContextMenu) { $ProjectMenuButton.ContextMenu.IsOpen = $true }
}) }
if ($ThreadMenuButton) { $ThreadMenuButton.Add_Click({
    if ($ThreadMenuButton.ContextMenu) { $ThreadMenuButton.ContextMenu.IsOpen = $true }
}) }
if ($ProjectAttachButton) { $ProjectAttachButton.Add_Click({
    [System.Windows.MessageBox]::Show("Project pinning is not implemented yet. The current project path is already active.", "Claw Studio") | Out-Null
}) }
if ($ProjectOpenButton) { $ProjectOpenButton.Add_Click({
    if (Test-Path -LiteralPath $script:ProjectPath) {
        Start-Process explorer.exe -ArgumentList @($script:ProjectPath) | Out-Null
    }
}) }
if ($ProjectEditButton) { $ProjectEditButton.Add_Click({
    if (Test-Path -LiteralPath $script:ProjectPath) {
        Start-Process explorer.exe -ArgumentList @($script:ProjectPath) | Out-Null
    }
}) }
if ($NewThreadProjectButton) { $NewThreadProjectButton.Add_Click({
    Start-NewSession -Title "New chat in $($ProjectNameText.Text)"
    $ThreadSubtitleText.Text = "just created"
    Add-Conversation -Role "System" -Text "Started a fresh project chat." -RoleColor $script:Theme.Muted | Out-Null
    Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text "Started a fresh project chat." -RoleColor $script:Theme.Muted | Out-Null
    Refresh-SessionMeta
}) }
if ($ResetThreadButton) { $ResetThreadButton.Add_Click({
    $ConversationStack.Children.Clear()
    $script:AttachedFiles.Clear()
    $session = Get-SessionById -Id $script:CurrentSessionId
    if ($null -ne $session) {
        $session.messages = @()
        $session.promptDraft = ""
        $session.lastPrompt = ""
        $session.updatedAt = [DateTime]::UtcNow.ToString("o")
        Save-Sessions
    }
    Add-Conversation -Role "System" -Text "Chat reset. Settings stayed intact." -RoleColor $script:Theme.Muted | Out-Null
    Add-MessageToSession -SessionId $script:CurrentSessionId -Role "System" -Text "Chat reset. Settings stayed intact." -RoleColor $script:Theme.Muted | Out-Null
    Refresh-SessionMeta
}) }
if ($RecentApplyButton) { $RecentApplyButton.Add_Click({
    if ($SendButton) { $SendButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
}) }
if ($RecentArchiveButton) { $RecentArchiveButton.Add_Click({
    if ($ThreadMenuButton.ContextMenu) {
        foreach ($item in $ThreadMenuButton.ContextMenu.Items) {
            if ($item -is [System.Windows.Controls.MenuItem] -and [string]$item.Header -eq "Chat archivieren") {
                $item.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.MenuItem]::ClickEvent)))
                break
            }
        }
    }
}) }
if ($RecentDeleteButton) { $RecentDeleteButton.Add_Click({
    if ($ResetThreadButton) { $ResetThreadButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
}) }
if ($PluginsButton) { $PluginsButton.Add_Click({
    $PromptTextBox.Text = "List the likely extension points, plugin systems, or integration surfaces in this repository."
}) }
if ($AutomationButton) { $AutomationButton.Add_Click({
    $PromptTextBox.Text = "Look for recurring workflows in this repository that would benefit from automation."
}) }
if ($ThreadList) { $ThreadList.Add_SelectionChanged({
    if ($ThreadList.SelectedItem) {
        $selectedTitle = [string]$ThreadList.SelectedItem
        foreach ($session in @($script:Sessions)) {
            if ([string]$session.title -eq $selectedTitle) {
                $script:CurrentSessionId = [string]$session.id
                $script:CurrentThreadTitle = [string]$session.title
                $ThreadTitleText.Text = [string]$session.title
                if (-not [string]::IsNullOrWhiteSpace([string]$session.projectPath) -and (Test-Path -LiteralPath [string]$session.projectPath)) {
                    $script:ProjectPath = [string]$session.projectPath
                }
                Refresh-ProjectState
                Render-SessionMessages
                $PromptTextBox.Text = [string]$session.promptDraft
                Refresh-SessionMeta
                Save-Sessions
                break
            }
        }
    }
}) }
if ($ModelComboBox) { $ModelComboBox.Add_SelectionChanged({
    $ModelPickerButton.Content = Get-ComboValue -ComboBox $ModelComboBox
    Save-CurrentSettings
    Refresh-SessionMeta
}) }
if ($PermissionComboBox) { $PermissionComboBox.Add_SelectionChanged({
    $PermissionPickerButton.Content = Get-ComboValue -ComboBox $PermissionComboBox
    Save-CurrentSettings
    Refresh-SessionMeta
}) }
if ($PermissionPickerButton) { $PermissionPickerButton.Add_Click({
    if ($PermissionPickerButton.ContextMenu) { $PermissionPickerButton.ContextMenu.IsOpen = $true }
}) }
if ($ModelPickerButton) { $ModelPickerButton.Add_Click({
    if ($ModelPickerButton.ContextMenu) { $ModelPickerButton.ContextMenu.IsOpen = $true }
}) }
if ($EffortPickerButton) { $EffortPickerButton.Add_Click({
    if ($EffortPickerButton.ContextMenu) { $EffortPickerButton.ContextMenu.IsOpen = $true }
}) }
if ($PromptTextBox) { $PromptTextBox.Add_KeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Enter -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        $_.Handled = $true
        & $sendAction
    }
}) }
if ($PromptTextBox) { $PromptTextBox.Add_TextChanged({
    if ($null -ne $PromptTextBox) {
        Update-SessionDraft -Text $PromptTextBox.Text
    }
}) }
if ($TerminalButton) { $TerminalButton.Add_Click({
    if (-not (Validate-RunContext)) {
        return
    }

    $clawBinary = Find-ClawBinary
    $command = "Set-Location -LiteralPath '{0}'; & '{1}' --model '{2}' --permission-mode '{3}'" -f `
        $script:ProjectPath.Replace("'", "''"), `
        $clawBinary.Replace("'", "''"), `
        (Get-ComboValue -ComboBox $ModelComboBox).Replace("'", "''"), `
        (Get-ComboValue -ComboBox $PermissionComboBox).Replace("'", "''")

    Start-Process powershell.exe -ArgumentList @("-NoExit", "-Command", $command) -WorkingDirectory $script:ProjectPath | Out-Null
    Add-Conversation -Role "Status" -Text "Opened an interactive terminal in the current project." -RoleColor $script:Theme.ReadyFg | Out-Null
}) }
if ($AttachButton) { $AttachButton.Add_Click({
    if ($AttachButton.ContextMenu) { $AttachButton.ContextMenu.IsOpen = $true }
}) }
$attachFileMenuItem.Add_Click({
    if (Test-Path -LiteralPath $script:ProjectPath) {
        $fileDialog.InitialDirectory = $script:ProjectPath
    } else {
        $fileDialog.InitialDirectory = $env:USERPROFILE
    }

    if ($fileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:AttachedFiles.Clear()
        foreach ($selectedFile in $fileDialog.FileNames) {
            if (-not [string]::IsNullOrWhiteSpace($selectedFile)) {
                $script:AttachedFiles.Add($selectedFile) | Out-Null
            }
        }

        Apply-AttachmentsToPrompt
        Add-Conversation -Role "System" -Text ("Attached {0} file(s) to the current prompt." -f $script:AttachedFiles.Count) -RoleColor $script:Theme.Muted | Out-Null
        Refresh-SessionMeta
    }
})
$clearAttachMenuItem.Add_Click({
    $script:AttachedFiles.Clear()
    $PromptTextBox.Text = [regex]::Replace($PromptTextBox.Text, "(?s)\r?\n\r?\nAttached files:\r?\n(?:- .+\r?\n?)*$", "")
    Add-Conversation -Role "System" -Text "Cleared the attached files from the current prompt." -RoleColor $script:Theme.Muted | Out-Null
    Refresh-SessionMeta
})
$chooseProjectMenuItem.Add_Click({
    if (Test-Path -LiteralPath $script:ProjectPath) {
        $folderBrowser.SelectedPath = $script:ProjectPath
    }
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:ProjectPath = $folderBrowser.SelectedPath
        Save-CurrentSettings
        Refresh-ProjectState
    }
})
if ($MicButton) { $MicButton.Add_Click({
    [System.Windows.MessageBox]::Show("Voice input is not implemented yet.", "Claw Studio") | Out-Null
}) }
$window.Add_Closing({
    Save-CurrentSettings
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $result = [System.Windows.MessageBox]::Show("A task is still running. Close Claw Studio anyway?", "Claw Studio", "YesNo", "Warning")
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
