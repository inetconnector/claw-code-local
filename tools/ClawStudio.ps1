#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$StudioRoot = Join-Path $env:LOCALAPPDATA "Programs\ClawCode\studio"
$SettingsPath = Join-Path $StudioRoot "settings.json"
$DefaultClawPath = Join-Path $env:LOCALAPPDATA "Programs\ClawCode\bin\claw.exe"

if (-not (Test-Path -LiteralPath $StudioRoot)) {
    New-Item -ItemType Directory -Path $StudioRoot -Force | Out-Null
}

$script:CurrentProcess = $null
$script:ActiveOutputBox = $null
$script:StdOutPath = ""
$script:StdErrPath = ""
$script:StdOutPosition = 0L
$script:StdErrPosition = 0L

$script:Colors = @{
    Window = [System.Drawing.Color]::FromArgb(20, 24, 31)
    Sidebar = [System.Drawing.Color]::FromArgb(14, 17, 22)
    Panel = [System.Drawing.Color]::FromArgb(24, 29, 38)
    PanelSoft = [System.Drawing.Color]::FromArgb(31, 37, 48)
    Border = [System.Drawing.Color]::FromArgb(54, 64, 82)
    Foreground = [System.Drawing.Color]::FromArgb(232, 237, 243)
    Muted = [System.Drawing.Color]::FromArgb(144, 156, 175)
    Accent = [System.Drawing.Color]::FromArgb(97, 168, 255)
    AccentSoft = [System.Drawing.Color]::FromArgb(39, 64, 99)
    Success = [System.Drawing.Color]::FromArgb(92, 214, 128)
    Warning = [System.Drawing.Color]::FromArgb(255, 195, 86)
    Error = [System.Drawing.Color]::FromArgb(255, 117, 117)
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

function New-FlatButton {
    param(
        [string]$Text,
        [int]$Width = 120,
        [int]$Height = 36,
        [System.Drawing.Color]$BackColor = $script:Colors.PanelSoft,
        [System.Drawing.Color]$ForeColor = $script:Colors.Foreground
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Size = New-Object System.Drawing.Size($Width, $Height)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.BorderColor = $script:Colors.Border
    $button.BackColor = $BackColor
    $button.ForeColor = $ForeColor
    $button.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5, [System.Drawing.FontStyle]::Regular)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.UseVisualStyleBackColor = $false
    return $button
}

function New-SectionLabel {
    param([string]$Text)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.ForeColor = $script:Colors.Muted
    $label.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
    $label.AutoSize = $true
    return $label
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Claw Studio"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1420, 920)
$form.MinimumSize = New-Object System.Drawing.Size(1160, 760)
$form.BackColor = $script:Colors.Window
$form.ForeColor = $script:Colors.Foreground
$form.KeyPreview = $true

$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Dock = [System.Windows.Forms.DockStyle]::Left
$sidebar.Width = 292
$sidebar.BackColor = $script:Colors.Sidebar
$sidebar.Padding = New-Object System.Windows.Forms.Padding(18, 18, 18, 18)
$form.Controls.Add($sidebar)

$mainPanel = New-Object System.Windows.Forms.Panel
$mainPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainPanel.BackColor = $script:Colors.Window
$mainPanel.Padding = New-Object System.Windows.Forms.Padding(18, 18, 18, 18)
$form.Controls.Add($mainPanel)

$brandLabel = New-Object System.Windows.Forms.Label
$brandLabel.Text = "Claw Studio"
$brandLabel.ForeColor = $script:Colors.Foreground
$brandLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 18)
$brandLabel.AutoSize = $true
$brandLabel.Location = New-Object System.Drawing.Point(0, 0)
$sidebar.Controls.Add($brandLabel)

$brandSubLabel = New-Object System.Windows.Forms.Label
$brandSubLabel.Text = "Closer to Codex: chat first, project scoped, less setup noise."
$brandSubLabel.ForeColor = $script:Colors.Muted
$brandSubLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$brandSubLabel.MaximumSize = New-Object System.Drawing.Size(240, 0)
$brandSubLabel.AutoSize = $true
$brandSubLabel.Location = New-Object System.Drawing.Point(0, 38)
$sidebar.Controls.Add($brandSubLabel)

$threadsSection = New-Object System.Windows.Forms.Panel
$threadsSection.BackColor = $script:Colors.Panel
$threadsSection.Location = New-Object System.Drawing.Point(0, 96)
$threadsSection.Size = New-Object System.Drawing.Size(254, 184)
$threadsSection.Padding = New-Object System.Windows.Forms.Padding(12)
$sidebar.Controls.Add($threadsSection)

$threadsLabel = New-SectionLabel "THREADS"
$threadsLabel.Location = New-Object System.Drawing.Point(12, 12)
$threadsSection.Controls.Add($threadsLabel)

$threadList = New-Object System.Windows.Forms.ListBox
$threadList.Location = New-Object System.Drawing.Point(12, 38)
$threadList.Size = New-Object System.Drawing.Size(224, 95)
$threadList.BackColor = $script:Colors.PanelSoft
$threadList.ForeColor = $script:Colors.Foreground
$threadList.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$threadList.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$threadList.Items.AddRange(@(
    "Current session",
    "Analyze repository",
    "Bug hunt",
    "README draft"
))
$threadList.SelectedIndex = 0
$threadsSection.Controls.Add($threadList)

$newThreadButton = New-FlatButton -Text "New Thread" -Width 108 -Height 34
$newThreadButton.Location = New-Object System.Drawing.Point(12, 142)
$threadsSection.Controls.Add($newThreadButton)

$reuseThreadButton = New-FlatButton -Text "Reuse Prompt" -Width 108 -Height 34
$reuseThreadButton.Location = New-Object System.Drawing.Point(128, 142)
$threadsSection.Controls.Add($reuseThreadButton)

$projectSection = New-Object System.Windows.Forms.Panel
$projectSection.BackColor = $script:Colors.Panel
$projectSection.Location = New-Object System.Drawing.Point(0, 294)
$projectSection.Size = New-Object System.Drawing.Size(254, 154)
$projectSection.Padding = New-Object System.Windows.Forms.Padding(12)
$sidebar.Controls.Add($projectSection)

$projectSectionLabel = New-SectionLabel "PROJECT"
$projectSectionLabel.Location = New-Object System.Drawing.Point(12, 12)
$projectSection.Controls.Add($projectSectionLabel)

$projectPathLabel = New-Object System.Windows.Forms.Label
$projectPathLabel.Text = Get-DefaultProjectPath
$projectPathLabel.ForeColor = $script:Colors.Foreground
$projectPathLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$projectPathLabel.MaximumSize = New-Object System.Drawing.Size(224, 0)
$projectPathLabel.AutoSize = $true
$projectPathLabel.Location = New-Object System.Drawing.Point(12, 36)
$projectSection.Controls.Add($projectPathLabel)

$projectBrowseButton = New-FlatButton -Text "Choose Project" -Width 108 -Height 34
$projectBrowseButton.Location = New-Object System.Drawing.Point(12, 102)
$projectSection.Controls.Add($projectBrowseButton)

$projectOpenButton = New-FlatButton -Text "Open Folder" -Width 104 -Height 34
$projectOpenButton.Location = New-Object System.Drawing.Point(128, 102)
$projectSection.Controls.Add($projectOpenButton)

$settingsSection = New-Object System.Windows.Forms.Panel
$settingsSection.BackColor = $script:Colors.Panel
$settingsSection.Location = New-Object System.Drawing.Point(0, 462)
$settingsSection.Size = New-Object System.Drawing.Size(254, 170)
$settingsSection.Padding = New-Object System.Windows.Forms.Padding(12)
$sidebar.Controls.Add($settingsSection)

$settingsSectionLabel = New-SectionLabel "RUN SETTINGS"
$settingsSectionLabel.Location = New-Object System.Drawing.Point(12, 12)
$settingsSection.Controls.Add($settingsSectionLabel)

$modelLabel = New-SectionLabel "MODEL"
$modelLabel.Location = New-Object System.Drawing.Point(12, 38)
$settingsSection.Controls.Add($modelLabel)

$modelComboBox = New-Object System.Windows.Forms.ComboBox
$modelComboBox.Location = New-Object System.Drawing.Point(12, 58)
$modelComboBox.Size = New-Object System.Drawing.Size(224, 30)
$modelComboBox.DropDownStyle = "DropDown"
$modelComboBox.BackColor = $script:Colors.PanelSoft
$modelComboBox.ForeColor = $script:Colors.Foreground
$modelComboBox.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$modelComboBox.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
[void]$modelComboBox.Items.Add("openai/qwen2.5-coder:7b")
[void]$modelComboBox.Items.Add("openai/qwen2.5-coder:14b")
[void]$modelComboBox.Items.Add("openai/qwen2.5-coder:32b")
[void]$modelComboBox.Items.Add("openai/llama3.2")
$modelComboBox.Text = Get-DefaultModel
$settingsSection.Controls.Add($modelComboBox)

$permissionLabel = New-SectionLabel "PERMISSION"
$permissionLabel.Location = New-Object System.Drawing.Point(12, 100)
$settingsSection.Controls.Add($permissionLabel)

$permissionComboBox = New-Object System.Windows.Forms.ComboBox
$permissionComboBox.Location = New-Object System.Drawing.Point(12, 120)
$permissionComboBox.Size = New-Object System.Drawing.Size(224, 30)
$permissionComboBox.DropDownStyle = "DropDownList"
$permissionComboBox.BackColor = $script:Colors.PanelSoft
$permissionComboBox.ForeColor = $script:Colors.Foreground
$permissionComboBox.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$permissionComboBox.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
[void]$permissionComboBox.Items.Add("read-only")
[void]$permissionComboBox.Items.Add("workspace-write")
[void]$permissionComboBox.Items.Add("danger-full-access")
$permissionComboBox.SelectedItem = Get-DefaultPermissionMode
$settingsSection.Controls.Add($permissionComboBox)

$actionsSection = New-Object System.Windows.Forms.Panel
$actionsSection.BackColor = $script:Colors.Panel
$actionsSection.Location = New-Object System.Drawing.Point(0, 646)
$actionsSection.Size = New-Object System.Drawing.Size(254, 246)
$actionsSection.Padding = New-Object System.Windows.Forms.Padding(12)
$sidebar.Controls.Add($actionsSection)

$actionsLabel = New-SectionLabel "QUICK ACTIONS"
$actionsLabel.Location = New-Object System.Drawing.Point(12, 12)
$actionsSection.Controls.Add($actionsLabel)

$analyzeButton = New-FlatButton -Text "Analyze Repository" -Width 224 -Height 38
$analyzeButton.Location = New-Object System.Drawing.Point(12, 38)
$actionsSection.Controls.Add($analyzeButton)

$bugsButton = New-FlatButton -Text "Find Bugs" -Width 224 -Height 38
$bugsButton.Location = New-Object System.Drawing.Point(12, 84)
$actionsSection.Controls.Add($bugsButton)

$improveButton = New-FlatButton -Text "Plan Improvements" -Width 224 -Height 38
$improveButton.Location = New-Object System.Drawing.Point(12, 130)
$actionsSection.Controls.Add($improveButton)

$doctorButton = New-FlatButton -Text "Run Doctor" -Width 108 -Height 34
$doctorButton.Location = New-Object System.Drawing.Point(12, 184)
$actionsSection.Controls.Add($doctorButton)

$versionButton = New-FlatButton -Text "Version" -Width 108 -Height 34
$versionButton.Location = New-Object System.Drawing.Point(128, 184)
$actionsSection.Controls.Add($versionButton)

$topBar = New-Object System.Windows.Forms.Panel
$topBar.Dock = [System.Windows.Forms.DockStyle]::Top
$topBar.Height = 76
$topBar.BackColor = $script:Colors.Window
$mainPanel.Controls.Add($topBar)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Current Thread"
$titleLabel.ForeColor = $script:Colors.Foreground
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 18)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(0, 0)
$topBar.Controls.Add($titleLabel)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = "Use a project folder, then talk to Claw like an agent instead of filling a form."
$subtitleLabel.ForeColor = $script:Colors.Muted
$subtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$subtitleLabel.AutoSize = $true
$subtitleLabel.Location = New-Object System.Drawing.Point(2, 34)
$topBar.Controls.Add($subtitleLabel)

$statusPill = New-Object System.Windows.Forms.Label
$statusPill.Text = " Ready "
$statusPill.ForeColor = $script:Colors.Success
$statusPill.BackColor = [System.Drawing.Color]::FromArgb(22, 54, 38)
$statusPill.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$statusPill.AutoSize = $true
$statusPill.Padding = New-Object System.Windows.Forms.Padding(10, 6, 10, 6)
$statusPill.Location = New-Object System.Drawing.Point(960, 12)
$topBar.Controls.Add($statusPill)

$metaLabel = New-Object System.Windows.Forms.Label
$metaLabel.Text = "Model: $($modelComboBox.Text)   |   Mode: $($permissionComboBox.SelectedItem)"
$metaLabel.ForeColor = $script:Colors.Muted
$metaLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$metaLabel.AutoSize = $true
$metaLabel.Location = New-Object System.Drawing.Point(760, 46)
$topBar.Controls.Add($metaLabel)

$conversationPanel = New-Object System.Windows.Forms.Panel
$conversationPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$conversationPanel.BackColor = $script:Colors.Panel
$conversationPanel.Padding = New-Object System.Windows.Forms.Padding(1)
$mainPanel.Controls.Add($conversationPanel)

$conversationScrollPanel = New-Object System.Windows.Forms.Panel
$conversationScrollPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$conversationScrollPanel.BackColor = $script:Colors.Panel
$conversationScrollPanel.AutoScroll = $true
$conversationPanel.Controls.Add($conversationScrollPanel)

$conversationFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$conversationFlow.Dock = [System.Windows.Forms.DockStyle]::Top
$conversationFlow.AutoSize = $true
$conversationFlow.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$conversationFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$conversationFlow.WrapContents = $false
$conversationFlow.Padding = New-Object System.Windows.Forms.Padding(18, 18, 18, 18)
$conversationFlow.BackColor = $script:Colors.Panel
$conversationScrollPanel.Controls.Add($conversationFlow)

$composerPanel = New-Object System.Windows.Forms.Panel
$composerPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$composerPanel.Height = 196
$composerPanel.BackColor = $script:Colors.Window
$composerPanel.Padding = New-Object System.Windows.Forms.Padding(0, 18, 0, 0)
$mainPanel.Controls.Add($composerPanel)

$composerContainer = New-Object System.Windows.Forms.Panel
$composerContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
$composerContainer.BackColor = $script:Colors.Panel
$composerContainer.Padding = New-Object System.Windows.Forms.Padding(14)
$composerPanel.Controls.Add($composerContainer)

$promptTextBox = New-Object System.Windows.Forms.TextBox
$promptTextBox.Multiline = $true
$promptTextBox.AcceptsReturn = $true
$promptTextBox.AcceptsTab = $true
$promptTextBox.ScrollBars = "Vertical"
$promptTextBox.BackColor = $script:Colors.Panel
$promptTextBox.ForeColor = $script:Colors.Foreground
$promptTextBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$promptTextBox.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$promptTextBox.Location = New-Object System.Drawing.Point(14, 14)
$promptTextBox.Size = New-Object System.Drawing.Size(780, 116)
$promptTextBox.Text = "Summarize this repository. Explain the architecture, build flow, and the first improvement you would make."
$composerContainer.Controls.Add($promptTextBox)

$composerHint = New-Object System.Windows.Forms.Label
$composerHint.Text = "Enter for newline, Ctrl+Enter to run"
$composerHint.ForeColor = $script:Colors.Muted
$composerHint.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$composerHint.AutoSize = $true
$composerHint.Location = New-Object System.Drawing.Point(14, 140)
$composerContainer.Controls.Add($composerHint)

$sendButton = New-FlatButton -Text "Send Prompt" -Width 150 -Height 42 -BackColor $script:Colors.AccentSoft
$sendButton.Location = New-Object System.Drawing.Point(828, 18)
$composerContainer.Controls.Add($sendButton)

$clearButton = New-FlatButton -Text "Clear Thread" -Width 150 -Height 36
$clearButton.Location = New-Object System.Drawing.Point(828, 68)
$composerContainer.Controls.Add($clearButton)

$readmeButton = New-FlatButton -Text "Draft README" -Width 150 -Height 36
$readmeButton.Location = New-Object System.Drawing.Point(828, 112)
$composerContainer.Controls.Add($readmeButton)

$terminalButton = New-FlatButton -Text "Terminal" -Width 96 -Height 36
$terminalButton.Location = New-Object System.Drawing.Point(986, 18)
$composerContainer.Controls.Add($terminalButton)

$ollamaButton = New-FlatButton -Text "Ollama" -Width 96 -Height 36
$ollamaButton.Location = New-Object System.Drawing.Point(986, 62)
$composerContainer.Controls.Add($ollamaButton)

$stopButton = New-FlatButton -Text "Stop" -Width 96 -Height 36 -BackColor ([System.Drawing.Color]::FromArgb(74, 41, 47)) -ForeColor $script:Colors.Error
$stopButton.Location = New-Object System.Drawing.Point(986, 106)
$stopButton.Enabled = $false
$composerContainer.Controls.Add($stopButton)

$clawPathLabel = New-Object System.Windows.Forms.Label
$clawPathLabel.Text = Find-ClawBinary
$clawPathLabel.ForeColor = $script:Colors.Muted
$clawPathLabel.Font = New-Object System.Drawing.Font("Consolas", 8.75)
$clawPathLabel.AutoEllipsis = $true
$clawPathLabel.Size = New-Object System.Drawing.Size(320, 32)
$clawPathLabel.Location = New-Object System.Drawing.Point(828, 152)
$composerContainer.Controls.Add($clawPathLabel)

$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Choose the project folder Claw should work in"

$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 250

function Append-Conversation {
    param(
        [string]$Role,
        [string]$Text,
        [System.Drawing.Color]$RoleColor = $script:Colors.Accent,
        [bool]$IsUser = $false
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    $availableWidth = [int]$conversationScrollPanel.ClientSize.Width
    if ($availableWidth -le 0) {
        $availableWidth = 980
    }

    $wrapWidth = [int][Math]::Max(($availableWidth - 40), 760)
    $bubbleWrap = New-Object System.Windows.Forms.Panel
    $bubbleWrap.Width = $wrapWidth
    $bubbleWrap.Height = 10
    $bubbleWrap.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
    $bubbleWrap.BackColor = $script:Colors.Panel

    $bubble = New-Object System.Windows.Forms.Panel
    $bubbleWidth = [int][Math]::Min([Math]::Max([int]($wrapWidth * 0.72), 460), 860)
    $bubble.Width = $bubbleWidth
    $bubble.BackColor = $(if ($IsUser) { $script:Colors.AccentSoft } else { $script:Colors.PanelSoft })
    $bubble.Padding = New-Object System.Windows.Forms.Padding(14, 12, 14, 12)
    $bubble.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $bubbleX = 0
    if ($IsUser) {
        $bubbleX = [int]($wrapWidth - $bubbleWidth - 8)
        if ($bubbleX -lt 0) {
            $bubbleX = 0
        }
    }
    $bubble.Location = New-Object System.Drawing.Point($bubbleX, 0)

    $roleLabel = New-Object System.Windows.Forms.Label
    $roleLabel.Text = $Role
    $roleLabel.ForeColor = $RoleColor
    $roleLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $roleLabel.AutoSize = $true
    $roleLabel.Location = New-Object System.Drawing.Point(14, 12)
    $bubble.Controls.Add($roleLabel)

    $bodyLabel = New-Object System.Windows.Forms.Label
    $bodyLabel.Text = $Text
    $bodyLabel.ForeColor = $script:Colors.Foreground
    $bodyLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $bodyMaxWidth = [int]($bubbleWidth - 32)
    if ($bodyMaxWidth -lt 120) {
        $bodyMaxWidth = 120
    }
    $bodyLabel.MaximumSize = New-Object System.Drawing.Size($bodyMaxWidth, 0)
    $bodyLabel.AutoSize = $true
    $bodyLabel.Location = New-Object System.Drawing.Point(14, 36)
    $bubble.Controls.Add($bodyLabel)

    $bubble.Height = [int]($bodyLabel.Bottom + 14)
    $bubbleWrap.Height = $bubble.Height
    $bubbleWrap.Controls.Add($bubble)
    $conversationFlow.Controls.Add($bubbleWrap)
    $conversationScrollPanel.ScrollControlIntoView($bubbleWrap)
}

function Start-AssistantStream {
    param([string]$Title)

    $availableWidth = [int]$conversationScrollPanel.ClientSize.Width
    if ($availableWidth -le 0) {
        $availableWidth = 980
    }

    $wrapWidth = [int][Math]::Max(($availableWidth - 40), 760)
    $bubbleWrap = New-Object System.Windows.Forms.Panel
    $bubbleWrap.Width = $wrapWidth
    $bubbleWrap.Height = 220
    $bubbleWrap.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
    $bubbleWrap.BackColor = $script:Colors.Panel

    $bubble = New-Object System.Windows.Forms.Panel
    $bubbleWidth = [int][Math]::Min([Math]::Max([int]($wrapWidth * 0.78), 520), 920)
    $bubble.Width = $bubbleWidth
    $bubble.Height = 220
    $bubble.BackColor = $script:Colors.PanelSoft
    $bubble.Padding = New-Object System.Windows.Forms.Padding(14, 12, 14, 12)
    $bubble.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $bubble.Location = New-Object System.Drawing.Point(0, 0)

    $roleLabel = New-Object System.Windows.Forms.Label
    $roleLabel.Text = "Claw"
    $roleLabel.ForeColor = $script:Colors.Success
    $roleLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $roleLabel.AutoSize = $true
    $roleLabel.Location = New-Object System.Drawing.Point(14, 12)
    $bubble.Controls.Add($roleLabel)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Title
    $titleLabel.ForeColor = $script:Colors.Muted
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $titleLabel.AutoSize = $true
    $titleLabel.Location = New-Object System.Drawing.Point(62, 13)
    $bubble.Controls.Add($titleLabel)

    $outputBox = New-Object System.Windows.Forms.TextBox
    $outputBox.Multiline = $true
    $outputBox.ScrollBars = "Vertical"
    $outputBox.ReadOnly = $true
    $outputBox.WordWrap = $true
    $outputBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $outputBox.BackColor = $script:Colors.PanelSoft
    $outputBox.ForeColor = $script:Colors.Foreground
    $outputBox.Font = New-Object System.Drawing.Font("Cascadia Mono", 9.25)
    $outputBox.Location = New-Object System.Drawing.Point(14, 40)
    $outputWidth = [int]($bubbleWidth - 32)
    if ($outputWidth -lt 120) {
        $outputWidth = 120
    }
    $outputBox.Size = New-Object System.Drawing.Size($outputWidth, 160)
    $bubble.Controls.Add($outputBox)

    $bubbleWrap.Controls.Add($bubble)
    $conversationFlow.Controls.Add($bubbleWrap)
    $conversationScrollPanel.ScrollControlIntoView($bubbleWrap)
    $script:ActiveOutputBox = $outputBox
}

function Append-StreamText {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return
    }

    if ($script:ActiveOutputBox) {
        $script:ActiveOutputBox.AppendText($Text)
        $script:ActiveOutputBox.SelectionStart = $script:ActiveOutputBox.TextLength
        $script:ActiveOutputBox.ScrollToCaret()
    }
}

function Set-Status {
    param(
        [string]$Text,
        [System.Drawing.Color]$Foreground,
        [System.Drawing.Color]$Background
    )

    $statusPill.Text = " $Text "
    $statusPill.ForeColor = $Foreground
    $statusPill.BackColor = $Background
}

function Refresh-Meta {
    $metaLabel.Text = "Model: $($modelComboBox.Text)   |   Mode: $($permissionComboBox.SelectedItem)"
    $projectPathLabel.Text = $projectTextBox
}

function Set-UiBusy {
    param([bool]$Busy)

    $projectBrowseButton.Enabled = -not $Busy
    $projectOpenButton.Enabled = -not $Busy
    $modelComboBox.Enabled = -not $Busy
    $permissionComboBox.Enabled = -not $Busy
    $analyzeButton.Enabled = -not $Busy
    $bugsButton.Enabled = -not $Busy
    $improveButton.Enabled = -not $Busy
    $doctorButton.Enabled = -not $Busy
    $versionButton.Enabled = -not $Busy
    $terminalButton.Enabled = -not $Busy
    $ollamaButton.Enabled = -not $Busy
    $sendButton.Enabled = -not $Busy
    $readmeButton.Enabled = -not $Busy
    $clearButton.Enabled = -not $Busy
    $stopButton.Enabled = $Busy
}

function Update-ProjectPath {
    param([string]$Path)

    $script:ProjectPath = $Path
    $projectPathLabel.Text = $Path
    Save-Settings -ProjectPath $Path -Model $modelComboBox.Text.Trim() -PermissionMode ([string]$permissionComboBox.SelectedItem)
}

function Validate-RunContext {
    $clawBinary = Find-ClawBinary
    $clawPathLabel.Text = $clawBinary

    if ([string]::IsNullOrWhiteSpace($clawBinary) -or -not (Test-Path -LiteralPath $clawBinary)) {
        [System.Windows.Forms.MessageBox]::Show(
            "claw.exe was not found. Run setup.bat first, then reopen Claw Studio.",
            "Claw Studio",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }

    $projectPath = [string]$script:ProjectPath
    if ([string]::IsNullOrWhiteSpace($projectPath) -or -not (Test-Path -LiteralPath $projectPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Choose a valid project folder first.",
            "Claw Studio",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }

    if (Test-BroadProjectPath -Path $projectPath) {
        $choice = [System.Windows.Forms.MessageBox]::Show(
            "That folder is too broad. Pick a real project folder instead when possible.`n`nContinue anyway?",
            "Claw Studio",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
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
        [System.Windows.Forms.MessageBox]::Show(
            "A task is already running. Stop it first or wait until it finishes.",
            "Claw Studio",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    $script:StdOutPath = Join-Path $StudioRoot ("stdout-" + [guid]::NewGuid().ToString("N") + ".log")
    $script:StdErrPath = Join-Path $StudioRoot ("stderr-" + [guid]::NewGuid().ToString("N") + ".log")
    $script:StdOutPosition = 0L
    $script:StdErrPosition = 0L
    "" | Set-Content -LiteralPath $script:StdOutPath -Encoding UTF8
    "" | Set-Content -LiteralPath $script:StdErrPath -Encoding UTF8

    Append-Conversation -Role "Task" -Text "$Label`r`nProject: $WorkingDirectory`r`nCommand: $Executable $($Arguments -join ' ')" -RoleColor $script:Colors.Warning
    Start-AssistantStream -Title $Label

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
    Set-UiBusy -Busy $true
    Set-Status -Text "Running" -Foreground $script:Colors.Warning -Background ([System.Drawing.Color]::FromArgb(59, 47, 20))
    $pollTimer.Start()
}

function Run-ClawCommand {
    param(
        [string[]]$Arguments,
        [string]$Label
    )

    if (-not (Validate-RunContext)) {
        return
    }

    $projectPath = [System.IO.Path]::GetFullPath([string]$script:ProjectPath)
    Save-Settings -ProjectPath $projectPath -Model $modelComboBox.Text.Trim() -PermissionMode ([string]$permissionComboBox.SelectedItem)
    Start-Command -Executable (Find-ClawBinary) -Arguments $Arguments -WorkingDirectory $projectPath -Label $Label
}

$script:ProjectPath = Get-DefaultProjectPath
$projectPathLabel.Text = $script:ProjectPath
$metaLabel.Text = "Model: $($modelComboBox.Text)   |   Mode: $($permissionComboBox.SelectedItem)"
$clawPathLabel.Text = Find-ClawBinary

$pollTimer.Add_Tick({
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
        $pollTimer.Stop()
        $exitCode = $script:CurrentProcess.ExitCode
        Append-Conversation -Role "Status" -Text "Process finished with exit code $exitCode." -RoleColor ($(if ($exitCode -eq 0) { $script:Colors.Success } else { $script:Colors.Error }))
        $script:ActiveOutputBox = $null
        if ($exitCode -eq 0) {
            Set-Status -Text "Ready" -Foreground $script:Colors.Success -Background ([System.Drawing.Color]::FromArgb(22, 54, 38))
        } else {
            Set-Status -Text "Needs attention" -Foreground $script:Colors.Error -Background ([System.Drawing.Color]::FromArgb(68, 33, 39))
        }
        Set-UiBusy -Busy $false
        $script:CurrentProcess.Dispose()
        $script:CurrentProcess = $null
    }
})

$projectBrowseButton.Add_Click({
    if (Test-Path -LiteralPath $script:ProjectPath) {
        $folderBrowser.SelectedPath = $script:ProjectPath
    }

    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Update-ProjectPath -Path $folderBrowser.SelectedPath
    }
})

$projectOpenButton.Add_Click({
    if (Test-Path -LiteralPath $script:ProjectPath) {
        Start-Process explorer.exe -ArgumentList @($script:ProjectPath) | Out-Null
    }
})

$modelComboBox.Add_TextChanged({
    Save-Settings -ProjectPath $script:ProjectPath -Model $modelComboBox.Text.Trim() -PermissionMode ([string]$permissionComboBox.SelectedItem)
    $metaLabel.Text = "Model: $($modelComboBox.Text)   |   Mode: $($permissionComboBox.SelectedItem)"
})

$permissionComboBox.Add_SelectedIndexChanged({
    Save-Settings -ProjectPath $script:ProjectPath -Model $modelComboBox.Text.Trim() -PermissionMode ([string]$permissionComboBox.SelectedItem)
    $metaLabel.Text = "Model: $($modelComboBox.Text)   |   Mode: $($permissionComboBox.SelectedItem)"
})

$sendAction = {
    $prompt = $promptTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($prompt)) {
        return
    }

    Append-Conversation -Role "You" -Text $prompt -RoleColor $script:Colors.Accent -IsUser $true
    $threadList.SelectedIndex = 0
    Run-ClawCommand -Arguments @(
        "--model", $modelComboBox.Text.Trim(),
        "--permission-mode", [string]$permissionComboBox.SelectedItem,
        "prompt", $prompt
    ) -Label "Custom prompt"
}

$sendButton.Add_Click($sendAction)

$promptTextBox.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        $_.Handled = $true
        & $sendAction
    }
})

$analyzeButton.Add_Click({
    $promptTextBox.Text = "Analyze this repository. Explain the architecture, build flow, dependencies, risky areas, and the first improvement you would make."
    & $sendAction
})

$bugsButton.Add_Click({
    $promptTextBox.Text = "Review this project for likely bugs, fragile flows, missing validation, and missing tests. Prioritize the most important findings first."
    & $sendAction
})

$improveButton.Add_Click({
    $promptTextBox.Text = "Create a short plan for the highest-value improvement in this repository, then explain why that order makes sense."
    & $sendAction
})

$readmeButton.Add_Click({
    $promptTextBox.Text = "Draft or improve the README for this repository. Cover purpose, install, run, and the key developer commands."
    & $sendAction
})

$doctorButton.Add_Click({
    Append-Conversation -Role "You" -Text "Run doctor for this setup." -RoleColor $script:Colors.Accent -IsUser $true
    Run-ClawCommand -Arguments @("doctor") -Label "Run doctor"
})

$versionButton.Add_Click({
    Append-Conversation -Role "You" -Text "Show the installed Claw version." -RoleColor $script:Colors.Accent -IsUser $true
    Run-ClawCommand -Arguments @("--version") -Label "Show version"
})

$ollamaButton.Add_Click({
    $ollama = Get-Command "ollama" -ErrorAction SilentlyContinue
    if ($null -eq $ollama) {
        [System.Windows.Forms.MessageBox]::Show(
            "ollama.exe was not found in PATH.",
            "Claw Studio",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    Append-Conversation -Role "You" -Text "Show local Ollama models." -RoleColor $script:Colors.Accent -IsUser $true
    Start-Command -Executable $ollama.Source -Arguments @("list") -WorkingDirectory $script:ProjectPath -Label "List Ollama models"
})

$terminalButton.Add_Click({
    if (-not (Validate-RunContext)) {
        return
    }

    $clawBinary = Find-ClawBinary
    $projectPath = [System.IO.Path]::GetFullPath($script:ProjectPath)
    Save-Settings -ProjectPath $projectPath -Model $modelComboBox.Text.Trim() -PermissionMode ([string]$permissionComboBox.SelectedItem)

    $command = "Set-Location -LiteralPath '{0}'; & '{1}' --model '{2}' --permission-mode '{3}'" -f `
        $projectPath.Replace("'", "''"), `
        $clawBinary.Replace("'", "''"), `
        $modelComboBox.Text.Trim().Replace("'", "''"), `
        ([string]$permissionComboBox.SelectedItem).Replace("'", "''")

    Start-Process powershell.exe -ArgumentList @("-NoExit", "-Command", $command) -WorkingDirectory $projectPath | Out-Null
    Append-Conversation -Role "Status" -Text "Opened an interactive Claw terminal in $projectPath." -RoleColor $script:Colors.Success
})

$clearButton.Add_Click({
    $conversationFlow.Controls.Clear()
    Append-Conversation -Role "System" -Text "Thread cleared. Settings stayed intact." -RoleColor $script:Colors.Muted
})

$stopButton.Add_Click({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        try {
            $script:CurrentProcess.Kill()
            Append-Conversation -Role "Status" -Text "Stop requested." -RoleColor $script:Colors.Warning
        } catch {
            Append-Conversation -Role "Status" -Text ("Could not stop the running process: " + $_.Exception.Message) -RoleColor $script:Colors.Error
        }
    }
})

$newThreadButton.Add_Click({
    $conversationFlow.Controls.Clear()
    $threadList.SelectedIndex = 0
    $titleLabel.Text = "Current Thread"
    Append-Conversation -Role "System" -Text "Started a fresh thread. Settings stayed intact." -RoleColor $script:Colors.Muted
})

$reuseThreadButton.Add_Click({
    switch ($threadList.SelectedItem) {
        "Analyze repository" { $promptTextBox.Text = "Analyze this repository. Explain the architecture, build flow, dependencies, risky areas, and the first improvement you would make." }
        "Bug hunt" { $promptTextBox.Text = "Review this project for likely bugs, fragile flows, missing validation, and missing tests. Prioritize the most important findings first." }
        "README draft" { $promptTextBox.Text = "Draft or improve the README for this repository. Cover purpose, install, run, and the key developer commands." }
        default { $promptTextBox.Text = "Summarize this repository. Explain the architecture, build flow, and the first improvement you would make." }
    }
})

$threadList.Add_SelectedIndexChanged({
    if ($threadList.SelectedItem) {
        $titleLabel.Text = [string]$threadList.SelectedItem
    }
})

$form.Add_FormClosing({
    Save-Settings -ProjectPath $script:ProjectPath -Model $modelComboBox.Text.Trim() -PermissionMode ([string]$permissionComboBox.SelectedItem)
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $choice = [System.Windows.Forms.MessageBox]::Show(
            "A task is still running. Close Claw Studio anyway?",
            "Claw Studio",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
            $_.Cancel = $true
            return
        }

        try {
            $script:CurrentProcess.Kill()
        } catch {
        }
    }
})

Append-Conversation -Role "System" -Text "Claw Studio is ready. Pick a project folder on the left, then use the composer at the bottom like a chat input." -RoleColor $script:Colors.Muted
Append-Conversation -Role "Tip" -Text "Start inside a real repo folder, not your whole user directory. Use Ctrl+Enter to send." -RoleColor $script:Colors.Warning

[void]$form.ShowDialog()
