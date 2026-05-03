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
$script:CurrentThreadTitle = "Claw Code installieren"

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

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claw Studio"
        Width="1600"
        Height="920"
        MinWidth="1280"
        MinHeight="780"
        Background="#171717"
        WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI">
  <Grid Background="#171717">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="72"/>
      <ColumnDefinition Width="320"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <Border Grid.Column="0" Background="#1F2428" BorderBrush="#2A2F33" BorderThickness="0,0,1,0">
      <DockPanel Margin="0">
        <StackPanel DockPanel.Dock="Top" Margin="12,14,12,0">
          <Button x:Name="LogoButton" Content="◧" Height="34" Margin="0,0,0,16" Background="Transparent" BorderBrush="Transparent" Foreground="#E5E7EB" FontSize="16" Cursor="Hand"/>
          <Button x:Name="NewChatNavButton" Content="✎" Height="40" Margin="0,0,0,8" Background="Transparent" BorderBrush="Transparent" Foreground="#E5E7EB" FontSize="16" Cursor="Hand"/>
          <Button x:Name="SearchNavButton" Content="⌕" Height="40" Margin="0,0,0,8" Background="Transparent" BorderBrush="Transparent" Foreground="#A1A1AA" FontSize="16" Cursor="Hand"/>
          <Button x:Name="PluginsNavButton" Content="◫" Height="40" Margin="0,0,0,8" Background="Transparent" BorderBrush="Transparent" Foreground="#A1A1AA" FontSize="16" Cursor="Hand"/>
          <Button x:Name="AutomationNavButton" Content="◷" Height="40" Margin="0,0,0,8" Background="Transparent" BorderBrush="Transparent" Foreground="#A1A1AA" FontSize="16" Cursor="Hand"/>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom" Margin="12,0,12,16">
          <Button x:Name="SettingsNavButton" Content="⚙" Height="40" Background="Transparent" BorderBrush="Transparent" Foreground="#A1A1AA" FontSize="15" Cursor="Hand"/>
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
          <TextBlock Text="Neuer Chat" Foreground="#E5E7EB" FontSize="16" FontWeight="SemiBold"/>
          <TextBlock Text="Suche" Foreground="#D4D4D8" FontSize="16" Margin="0,14,0,0"/>
          <TextBlock Text="Plugins" Foreground="#D4D4D8" FontSize="16" Margin="0,14,0,0"/>
          <TextBlock Text="Automatisierungen" Foreground="#D4D4D8" FontSize="16" Margin="0,14,0,0"/>
        </StackPanel>

        <StackPanel Grid.Row="1" Margin="0,28,0,0">
          <TextBlock Text="Projekte" Foreground="#71717A" FontSize="14" FontWeight="SemiBold"/>
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
              <Button x:Name="ProjectChooseButton" Grid.Column="1" Content="✎" Width="28" Height="28" Margin="12,0,0,0" Background="Transparent" BorderBrush="Transparent" Foreground="#D4D4D8" Cursor="Hand"/>
            </Grid>
          </Border>
        </StackPanel>

        <Grid Grid.Row="2" Margin="0,18,0,0">
          <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <ListBox x:Name="ThreadList" Grid.Row="0"
                   Background="Transparent"
                   BorderThickness="0"
                   Foreground="#E5E7EB"
                   FontSize="14"
                   ScrollViewer.VerticalScrollBarVisibility="Auto">
            <ListBoxItem Content="Claw Code installieren" IsSelected="True"/>
            <ListBoxItem Content="Erstelle Lead-Lag-Analysetool"/>
            <ListBoxItem Content="Refaktorieren AstroModNet..."/>
            <ListBoxItem Content="Watchface nach Bild ergänz..."/>
          </ListBox>

          <StackPanel Grid.Row="1" Margin="0,16,0,0">
            <Button x:Name="ProjectAttachButton" Content="Projekt anheften" Height="40" Margin="0,0,0,8" Background="#2A2F35" BorderBrush="#3A4148" Foreground="#F3F4F6"/>
            <Button x:Name="ProjectOpenButton" Content="Im Explorer öffnen" Height="40" Margin="0,0,0,8" Background="#2A2F35" BorderBrush="#3A4148" Foreground="#F3F4F6"/>
            <Button x:Name="NewThreadButton" Content="Neuen Chat starten" Height="40" Margin="0,0,0,8" Background="#2A2F35" BorderBrush="#3A4148" Foreground="#F3F4F6"/>
            <Button x:Name="RemoveThreadButton" Content="Chat zurücksetzen" Height="40" Background="#2A2F35" BorderBrush="#3A4148" Foreground="#F3F4F6"/>
          </StackPanel>
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
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Column="2" Background="#171717">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Background="#171717" Padding="28,18,28,14">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel>
            <TextBlock x:Name="ThreadTitleText" Text="Claw Code installieren" Foreground="#F3F4F6" FontSize="21" FontWeight="SemiBold"/>
            <TextBlock x:Name="ThreadSubtitleText" Text="5m 2s lang gearbeitet" Foreground="#A1A1AA" FontSize="13" Margin="0,8,0,0"/>
          </StackPanel>
          <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top">
            <Border x:Name="StatusPill" Background="#1F4A34" CornerRadius="14" Padding="14,8" Margin="0,0,12,0">
              <TextBlock x:Name="StatusPillText" Text="Ready" Foreground="#86EFAC" FontWeight="SemiBold"/>
            </Border>
            <Button x:Name="HeaderRunButton" Content="▶" Width="36" Height="36" Background="#2A2F35" BorderBrush="#3A4148" Foreground="#F3F4F6"/>
          </StackPanel>
        </Grid>
      </Border>

      <ScrollViewer x:Name="ConversationScrollViewer" Grid.Row="1" Margin="28,0,28,18" VerticalScrollBarVisibility="Auto" Background="Transparent">
        <StackPanel x:Name="ConversationStack"/>
      </ScrollViewer>

      <Border Grid.Row="2" Margin="28,0,28,18" Background="#2B2B2E" CornerRadius="24" Padding="18,14,18,12" BorderBrush="#3A4148" BorderThickness="1">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <DockPanel Grid.Row="0" LastChildFill="True">
            <Button x:Name="AttachButton" Content="+" Width="36" Height="36" Margin="0,0,12,0" Background="#3A3A3F" BorderBrush="#4A4A4F" Foreground="#F3F4F6" FontSize="18"/>
            <TextBox x:Name="PromptTextBox"
                     Background="Transparent"
                     Foreground="#F3F4F6"
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
            <Button x:Name="TerminalButton" Grid.Column="1" Content="Terminal" Width="96" Height="34" Background="Transparent" BorderBrush="Transparent" Foreground="#A1A1AA"/>
            <TextBlock x:Name="ModelFooterText" Grid.Column="3" Text="5.4 Mittel" VerticalAlignment="Center" Foreground="#D4D4D8" Margin="0,0,14,0"/>
            <Button x:Name="MicButton" Grid.Column="4" Content="◌" Width="30" Height="30" Background="Transparent" BorderBrush="Transparent" Foreground="#A1A1AA"/>
            <Button x:Name="SendButton" Grid.Column="5" Content="↑" Width="42" Height="42" Background="#F3F4F6" BorderBrush="#F3F4F6" Foreground="#171717" FontSize="18" FontWeight="Bold" Margin="0,0,0,0"/>
          </Grid>
        </Grid>
      </Border>

      <Border Grid.Row="3" Background="#171717" Padding="28,0,28,14">
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
$NewChatNavButton = Get-Control "NewChatNavButton"
$SearchNavButton = Get-Control "SearchNavButton"
$PluginsNavButton = Get-Control "PluginsNavButton"
$AutomationNavButton = Get-Control "AutomationNavButton"
$SettingsNavButton = Get-Control "SettingsNavButton"
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
$ConversationScrollViewer = Get-Control "ConversationScrollViewer"
$ConversationStack = Get-Control "ConversationStack"
$PromptTextBox = Get-Control "PromptTextBox"
$SendButton = Get-Control "SendButton"
$AttachButton = Get-Control "AttachButton"
$ModelComboBox = Get-Control "ModelComboBox"
$PermissionComboBox = Get-Control "PermissionComboBox"
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

$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Choose the project folder Claw should work in"

$dispatcherTimer = New-Object System.Windows.Threading.DispatcherTimer
$dispatcherTimer.Interval = [TimeSpan]::FromMilliseconds(250)

function Get-ComboValue {
    param($ComboBox)
    if ($ComboBox.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) {
        return [string]$ComboBox.SelectedItem.Content
    }
    return [string]$ComboBox.Text
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

    $body = New-Object System.Windows.Controls.TextBlock
    $body.Text = $Text
    $body.TextWrapping = "Wrap"
    $body.Margin = [System.Windows.Thickness]::new(0,8,0,0)
    $body.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($script:Theme.Foreground)
    $body.FontSize = 14
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

    if ($script:ActiveOutputControl -and -not [string]::IsNullOrEmpty($Text)) {
        $script:ActiveOutputControl.Text += $Text
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
    $ModelFooterText.Text = "$(Get-ComboValue -ComboBox $ModelComboBox)"
}

function Save-CurrentSettings {
    Save-Settings -ProjectPath $script:ProjectPath -Model (Get-ComboValue -ComboBox $ModelComboBox) -PermissionMode (Get-ComboValue -ComboBox $PermissionComboBox)
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

function Update-ThreadTitle {
    param([string]$Title)
    $script:CurrentThreadTitle = $Title
    $ThreadTitleText.Text = $Title
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
        $result = [System.Windows.MessageBox]::Show("That folder is very broad. Pick a real project folder instead when possible.`n`nContinue anyway?", "Claw Studio", "YesNo", "Warning")
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
        [System.Windows.MessageBox]::Show("A task is already running. Stop it first or wait until it finishes.", "Claw Studio") | Out-Null
        return
    }

    $script:StdOutPath = Join-Path $StudioRoot ("stdout-" + [guid]::NewGuid().ToString("N") + ".log")
    $script:StdErrPath = Join-Path $StudioRoot ("stderr-" + [guid]::NewGuid().ToString("N") + ".log")
    $script:StdOutPosition = 0L
    $script:StdErrPosition = 0L
    "" | Set-Content -LiteralPath $script:StdOutPath -Encoding UTF8
    "" | Set-Content -LiteralPath $script:StdErrPath -Encoding UTF8

    Add-Conversation -Role "You" -Text $Label -RoleColor $script:Theme.Blue -IsUser:$true | Out-Null
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
    Set-UiBusy -Busy $true
    Set-Status -Text "Running" -ForegroundHex $script:Theme.Yellow -BackgroundHex "#493912"
    $ThreadSubtitleText.Text = "arbeitet gerade..."
    $dispatcherTimer.Start()
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
    Start-Command -Executable (Find-ClawBinary) -Arguments $Arguments -WorkingDirectory $script:ProjectPath -Label $PromptText
}

$settings = Get-Settings
$script:ProjectPath = Get-DefaultProjectPath

$modelValue = Get-DefaultModel
for ($i = 0; $i -lt $ModelComboBox.Items.Count; $i++) {
    if ([string]$ModelComboBox.Items[$i].Content -eq $modelValue) {
        $ModelComboBox.SelectedIndex = $i
        break
    }
}

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
$ThreadSubtitleText.Text = "bereit"
Add-Conversation -Role "System" -Text "Claw Studio is ready. Pick a project folder, then use the composer below like a chat input." -RoleColor $script:Theme.Muted | Out-Null
Add-Conversation -Role "Tip" -Text "Start inside a real repo folder, not your whole user directory. Press Ctrl+Enter to send." -RoleColor $script:Theme.Yellow | Out-Null

$dispatcherTimer.Add_Tick({
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
        $script:ActiveOutputControl = $null
        if ($exitCode -eq 0) {
            Add-Conversation -Role "Status" -Text "Process finished successfully." -RoleColor $script:Theme.Green | Out-Null
            Set-Status -Text "Ready" -ForegroundHex $script:Theme.Green -BackgroundHex "#1F4A34"
            $ThreadSubtitleText.Text = "fertig"
        } else {
            Add-Conversation -Role "Status" -Text "Process finished with exit code $exitCode." -RoleColor $script:Theme.Red | Out-Null
            Set-Status -Text "Needs attention" -ForegroundHex $script:Theme.Red -BackgroundHex "#5A1F24"
            $ThreadSubtitleText.Text = "beendet mit Fehler"
        }
        Set-UiBusy -Busy $false
        $script:CurrentProcess.Dispose()
        $script:CurrentProcess = $null
    }
})

$sendAction = {
    $prompt = $PromptTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($prompt)) {
        return
    }

    Run-ClawCommand -Arguments @(
        "--model", (Get-ComboValue -ComboBox $ModelComboBox),
        "--permission-mode", (Get-ComboValue -ComboBox $PermissionComboBox),
        "prompt", $prompt
    ) -PromptText $prompt
}

$SendButton.Add_Click({ & $sendAction })
$HeaderRunButton.Add_Click({ & $sendAction })
$NewChatNavButton.Add_Click({
    $ConversationStack.Children.Clear()
    Update-ThreadTitle -Title "Neuer Chat"
    $ThreadSubtitleText.Text = "gerade erstellt"
    Add-Conversation -Role "System" -Text "Started a fresh chat." -RoleColor $script:Theme.Muted | Out-Null
})
$NewThreadButton.Add_Click({
    $ConversationStack.Children.Clear()
    Update-ThreadTitle -Title "Neuer Chat in $($ProjectNameText.Text)"
    $ThreadSubtitleText.Text = "gerade erstellt"
    Add-Conversation -Role "System" -Text "Started a fresh project chat." -RoleColor $script:Theme.Muted | Out-Null
})
$RemoveThreadButton.Add_Click({
    $ConversationStack.Children.Clear()
    Add-Conversation -Role "System" -Text "Chat reset. Settings stayed intact." -RoleColor $script:Theme.Muted | Out-Null
})
$ProjectChooseButton.Add_Click({
    if (Test-Path -LiteralPath $script:ProjectPath) {
        $folderBrowser.SelectedPath = $script:ProjectPath
    }
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:ProjectPath = $folderBrowser.SelectedPath
        Save-CurrentSettings
        Refresh-ProjectState
    }
})
$ProjectAttachButton.Add_Click({
    [System.Windows.MessageBox]::Show("Project pinning is not implemented yet. The current project path is already active.", "Claw Studio") | Out-Null
})
$ProjectOpenButton.Add_Click({
    if (Test-Path -LiteralPath $script:ProjectPath) {
        Start-Process explorer.exe -ArgumentList @($script:ProjectPath) | Out-Null
    }
})
$ThreadList.Add_SelectionChanged({
    if ($ThreadList.SelectedItem -and $ThreadList.SelectedItem.Content) {
        Update-ThreadTitle -Title ([string]$ThreadList.SelectedItem.Content)
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
$PromptTextBox.Add_KeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Enter -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        $_.Handled = $true
        & $sendAction
    }
})
$TerminalButton.Add_Click({
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
    Add-Conversation -Role "Status" -Text "Opened an interactive terminal in the current project." -RoleColor $script:Theme.Green | Out-Null
})
$AttachButton.Add_Click({
    [System.Windows.MessageBox]::Show("File attachment UI is not wired yet. Use the project folder as the main context for now.", "Claw Studio") | Out-Null
})
$MicButton.Add_Click({
    [System.Windows.MessageBox]::Show("Voice input is not implemented yet.", "Claw Studio") | Out-Null
})
$SearchNavButton.Add_Click({
    $PromptTextBox.Text = "Search this repository for the main entry points and explain how the code is organized."
})
$PluginsNavButton.Add_Click({
    $PromptTextBox.Text = "List the likely extension points, plugin systems, or integration surfaces in this repository."
})
$AutomationNavButton.Add_Click({
    $PromptTextBox.Text = "Look for recurring workflows in this repository that would benefit from automation."
})
$SettingsNavButton.Add_Click({
    [System.Windows.MessageBox]::Show("Settings are currently stored locally in the Claw Studio settings.json file.", "Claw Studio") | Out-Null
})
$LogoButton.Add_Click({
    $window.WindowState = $(if ($window.WindowState -eq "Maximized") { "Normal" } else { "Maximized" })
})
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
