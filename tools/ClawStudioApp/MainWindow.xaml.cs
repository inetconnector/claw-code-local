using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using ClawStudio.Models;
using ClawStudio.Services;
using Forms = System.Windows.Forms;

namespace ClawStudio;

public partial class MainWindow : Window
{
    private readonly SettingsService _settingsService = new();
    private readonly ProcessService _processService = new();
    private readonly GitService _gitService = new();
    private readonly DispatcherTimer _spinnerTimer = new();
    private readonly string[] _spinnerFrames = ["|", "/", "-", "\\"];
    private StudioSettings _settings;
    private CancellationTokenSource? _runCts;
    private string _lastPrompt = string.Empty;
    private string[] _lastCommandArguments = [];
    private string _lastCommandLabel = string.Empty;
    private int _spinnerIndex;
    private System.Windows.Controls.TextBox? _activeAssistantBubble;

    public MainWindow()
    {
        InitializeComponent();
        _settings = _settingsService.Load();
        EnsureFooterPermissionItems();
        LoadSettingsIntoUi();
        WireEvents();
        AddConversation("Claw", "Willkommen in Claw Studio. Wähle ein Projekt und sende einen Prompt.", false);
        Loaded += (_, _) => Dispatcher.BeginInvoke(new Action(() =>
        {
            PromptTextBox.Focus();
            Keyboard.Focus(PromptTextBox);
        }), DispatcherPriority.ApplicationIdle);

        _spinnerTimer.Interval = TimeSpan.FromMilliseconds(140);
        _spinnerTimer.Tick += (_, _) => SpinnerText.Text = _spinnerFrames[_spinnerIndex++ % _spinnerFrames.Length];
    }

    private void WireEvents()
    {
        SendButton.Click += async (_, _) => await SendPromptAsync();
        HeaderRunButton.Click += async (_, _) => await SendPromptAsync();
        CopyAllButton.Click += (_, _) => CopyWholeScreenToClipboard();
        PromptTextBox.PreviewKeyDown += PromptTextBox_PreviewKeyDown;

        ProjectChooseButton.Click += (_, _) => OpenProjectPicker();
        ProjectAttachButton.Click += (_, _) => OpenProjectPicker();
        ProjectOpenButton.Click += (_, _) => OpenExplorer();
        ProjectCardBorder.MouseLeftButtonDown += (_, e) => { if (e.ClickCount == 2) OpenExplorer(); };
        BuildProjectContextMenu();
        OpenExplorerSideButton.Click += (_, _) => OpenExplorer();
        OpenTerminalSideButton.Click += (_, _) => OpenTerminal();
        TerminalButton.Click += (_, _) => OpenTerminal();
        OpenVSCodeButton.Click += (_, _) => OpenVSCode();

        NewChatNavButton.Click += (_, _) => NewChat();
        NewChatTextButton.Click += (_, _) => NewChat();
        NewThreadButton.Click += (_, _) => NewChat();
        RemoveThreadButton.Click += (_, _) => NewChat();
        SearchNavButton.Click += (_, _) => PreparePlaceholderView("Suche", "Suche ist vorbereitet.");
        SearchTextButton.Click += (_, _) => PreparePlaceholderView("Suche", "Suche ist vorbereitet.");
        PluginsNavButton.Click += (_, _) => PreparePlaceholderView("Plugins", "Plugins-Ansicht ist vorbereitet.");
        PluginsTextButton.Click += (_, _) => PreparePlaceholderView("Plugins", "Plugins-Ansicht ist vorbereitet.");
        AutomationNavButton.Click += (_, _) => PreparePlaceholderView("Automatisierungen", "Automatisierungen sind vorbereitet.");
        AutomationTextButton.Click += (_, _) => PreparePlaceholderView("Automatisierungen", "Automatisierungen sind vorbereitet.");
        SettingsNavButton.Click += (_, _) => PreparePlaceholderView("Einstellungen", "Einstellungen links ändern.");
        LogoButton.Click += (_, _) => ToggleWindowState();

        AnalyzeButtons();

        ApproveOnceButton.Click += async (_, _) => await RunClawAsync(_lastPrompt, skipPermissions: true);
        ApproveSessionButton.Click += async (_, _) =>
        {
            SetComboText(PermissionComboBox, "danger-full-access");
            SetComboText(FooterPermissionComboBox, "danger-full-access");
            SaveSettingsFromUi();
            await RunClawAsync(_lastPrompt, skipPermissions: true);
        };
        DenyApprovalButton.Click += (_, _) => { ApprovalPanel.Visibility = Visibility.Collapsed; AddConversation("Claw", "Genehmigung abgelehnt.", false); };

        InitGitButton.Click += async (_, _) => await RunGitAsync((output, ct) => _gitService.InitAsync(_settings.ProjectPath, output, ct), "git init");
        FetchBranchesButton.Click += async (_, _) => await RunGitAsync((output, ct) => _gitService.FetchAsync(_settings.ProjectPath, output, ct), "git fetch --all --prune");
        ShowBranchesButton.Click += async (_, _) => await RunGitAsync((output, ct) => _gitService.BranchesAsync(_settings.ProjectPath, output, ct), "git branch -a -vv");
        PushRepoButton.Click += async (_, _) => { SaveSettingsFromUi(); await RunGitAsync((output, ct) => _gitService.PushAsync(_settings.ProjectPath, _settings.GitRemote, output, ct), "git push"); };
        ShowChangesButton.Click += async (_, _) => await RunProcessAsync("git", "status --short", _settings.ProjectPath, "git status --short");
        DoctorSideButton.Click += async (_, _) => await RunRawClawAsync("doctor", "claw doctor");
        WebSearchButton.Click += (_, _) => InsertText("Search the web for current documentation and summarize the relevant findings for this project.");

        MicButton.Click += (_, _) => StartDictation();
        AttachButton.Click += (_, _) => AttachFilesToPrompt();

        MinimizeWindowButton.Click += (_, _) => WindowState = WindowState.Minimized;
        MaximizeWindowButton.Click += (_, _) => ToggleWindowState();
        CloseWindowButton.Click += (_, _) => Close();
        TitleBar.MouseLeftButtonDown += (_, e) => { if (e.ClickCount == 2) ToggleWindowState(); else DragMove(); };

        MenuNewChat.Click += (_, _) => NewChat();
        MenuChooseProject.Click += (_, _) => OpenProjectPicker();
        MenuOpenExplorer.Click += (_, _) => OpenExplorer();
        MenuExit.Click += (_, _) => Close();
        MenuPasteClipboard.Click += (_, _) => InsertClipboardIntoPrompt();
        MenuAttachFiles.Click += (_, _) => AttachFilesToPrompt();
        MenuClearPrompt.Click += (_, _) => PromptTextBox.Clear();
        MenuShowSearch.Click += (_, _) => PreparePlaceholderView("Suche", "Suche ist vorbereitet.");
        MenuShowPlugins.Click += (_, _) => PreparePlaceholderView("Plugins", "Plugins-Ansicht ist vorbereitet.");
        MenuShowAutomation.Click += (_, _) => PreparePlaceholderView("Automatisierungen", "Automatisierungen sind vorbereitet.");
        MenuShowSettings.Click += (_, _) => PreparePlaceholderView("Einstellungen", "Einstellungen links ändern.");
        MenuMinimize.Click += (_, _) => WindowState = WindowState.Minimized;
        MenuToggleMaximize.Click += (_, _) => ToggleWindowState();
        MenuDoctor.Click += async (_, _) => await RunRawClawAsync("doctor", "claw doctor");
        MenuVersion.Click += async (_, _) => await RunRawClawAsync("--version", "claw --version");

        BackNavButton.Click += (_, _) => AddConversation("Claw", "Navigation zurück ist vorbereitet.", false);
        ForwardNavButton.Click += (_, _) => AddConversation("Claw", "Navigation vorwärts ist vorbereitet.", false);
        ThreadMoreButton.Click += (_, _) => AddConversation("Claw", "Thread-Menü ist vorbereitet.", false);

        ModelComboBox.SelectionChanged += (_, _) => UpdateFooterText();
        PermissionComboBox.SelectionChanged += (_, _) => SyncFooterPermissionFromMain();
        FooterPermissionComboBox.SelectionChanged += (_, _) => SyncMainPermissionFromFooter();
        ThreadList.SelectionChanged += (_, _) => OnThreadSelected();
    }


    private void BuildProjectContextMenu()
    {
        var menu = new ContextMenu();
        MenuItem Item(string header, RoutedEventHandler handler)
        {
            var item = new MenuItem { Header = header };
            item.Click += handler;
            return item;
        }
        menu.Items.Add(Item("Projekt anheften", (_, _) => PinProject()));
        menu.Items.Add(Item("Im Explorer öffnen", (_, _) => OpenExplorer()));
        menu.Items.Add(Item("Permanenten Worktree erstellen", (_, _) => CreatePermanentWorktree()));
        menu.Items.Add(Item("Projekt umbenennen", (_, _) => RenameProject()));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Chats archivieren", (_, _) => ArchiveChats()));
        menu.Items.Add(Item("Entfernen", (_, _) => RemoveProject()));
        ProjectCardBorder.ContextMenu = menu;
    }

    private void AnalyzeButtons()
    {
        WorkspaceCardTitle.MouseLeftButtonDown += (_, _) => InsertText("Analyze this repository. Explain the architecture, build flow, dependencies, risky areas, and the first improvement you would make.");
        // Dedicated buttons from the PS1 layout.
        FindName("InitGitButton");
        // Names are available as fields because they come from the original XAML.
        AddPromptButton(BranchStatusChangedValue, "Show changed files and explain what changed.");
        AddPromptButton(BranchStatusAddedValue, "Show newly added files and explain whether they belong in git.");
        AddPromptButton(BranchStatusRemovedValue, "Show removed files and explain whether this is expected.");
        // Workspace quick actions.
        if (FindName("DoctorSideButton") is System.Windows.Controls.Button) { }
        SidebarProjectNameText.MouseLeftButtonDown += (_, _) => InsertText("Analyze this repository. Explain the architecture, build flow, dependencies, risky areas, and the first improvement you would make.");
    }

    private void AddPromptButton(TextBlock block, string text)
    {
        block.Cursor = System.Windows.Input.Cursors.Hand;
        block.MouseLeftButtonDown += (_, _) => InsertText(text);
    }

    private void EnsureFooterPermissionItems()
    {
        if (FooterPermissionComboBox.Items.Count == 0)
        {
            foreach (ComboBoxItem item in PermissionComboBox.Items)
            {
                FooterPermissionComboBox.Items.Add(new ComboBoxItem { Content = item.Content });
            }
        }
    }

    private void LoadSettingsIntoUi()
    {
        SetComboText(ModelComboBox, _settings.Model);
        SetComboText(PermissionComboBox, _settings.PermissionMode);
        SetComboText(FooterPermissionComboBox, _settings.PermissionMode);
        GitRemoteTextBox.Text = _settings.GitRemote;
        UpdateProjectLabels();
        UpdateFooterText();
        SetReady();
    }

    private void SaveSettingsFromUi()
    {
        _settings.Model = GetComboText(ModelComboBox);
        _settings.PermissionMode = GetComboText(PermissionComboBox);
        _settings.GitRemote = GitRemoteTextBox.Text.Trim();
        _settingsService.Save(_settings);
    }

    private void UpdateProjectLabels()
    {
        var path = Directory.Exists(_settings.ProjectPath) ? _settings.ProjectPath : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        _settings.ProjectPath = path;
        var name = new DirectoryInfo(path).Name;
        if (string.IsNullOrWhiteSpace(name)) name = path;
        ProjectNameText.Text = name;
        ProjectPathText.Text = path;
        SidebarProjectNameText.Text = name;
        SidebarProjectPathText.Text = path;
        ThreadSubtitleText.Text = path;
        WorkspaceModeText.Text = GetComboText(PermissionComboBox);
        BranchText.Text = GetBranchSummary(path);
        BinaryPathText.Text = _settings.ClawPath;
    }

    private static string GetComboText(System.Windows.Controls.ComboBox combo)
    {
        if (combo.SelectedItem is ComboBoxItem item) return item.Content?.ToString() ?? string.Empty;
        return combo.Text ?? string.Empty;
    }

    private static void SetComboText(System.Windows.Controls.ComboBox combo, string value)
    {
        foreach (var item in combo.Items.OfType<ComboBoxItem>())
        {
            if (string.Equals(item.Content?.ToString(), value, StringComparison.OrdinalIgnoreCase))
            {
                combo.SelectedItem = item;
                return;
            }
        }
        combo.Text = value;
    }

    private void SyncFooterPermissionFromMain()
    {
        SetComboText(FooterPermissionComboBox, GetComboText(PermissionComboBox));
        WorkspaceModeText.Text = GetComboText(PermissionComboBox);
    }

    private void SyncMainPermissionFromFooter()
    {
        SetComboText(PermissionComboBox, GetComboText(FooterPermissionComboBox));
        WorkspaceModeText.Text = GetComboText(PermissionComboBox);
    }

    private void UpdateFooterText()
    {
        ModelFooterText.Text = GetComboText(ModelComboBox).Replace("openai/", string.Empty);
    }

    private void OpenProjectPicker()
    {
        using var dialog = new Forms.FolderBrowserDialog
        {
            Description = "Projektordner wählen, in dem Claw arbeiten soll",
            UseDescriptionForTitle = true,
            SelectedPath = Directory.Exists(_settings.ProjectPath) ? _settings.ProjectPath : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        };
        if (dialog.ShowDialog() == Forms.DialogResult.OK)
        {
            _settings.ProjectPath = dialog.SelectedPath;
            SaveSettingsFromUi();
            UpdateProjectLabels();
            AddConversation("Claw", "Projekt gewählt: " + _settings.ProjectPath, false);
        }
    }

    private void OpenExplorer()
    {
        if (Directory.Exists(_settings.ProjectPath)) Process.Start("explorer.exe", _settings.ProjectPath);
    }

    private void OpenTerminal()
    {
        if (Directory.Exists(_settings.ProjectPath))
        {
            Process.Start(new ProcessStartInfo("cmd.exe") { WorkingDirectory = _settings.ProjectPath, UseShellExecute = true });
        }
    }

    private void OpenVSCode()
    {
        if (Directory.Exists(_settings.ProjectPath))
        {
            try { Process.Start(new ProcessStartInfo("code", $"\"{_settings.ProjectPath}\"") { UseShellExecute = true }); }
            catch { AddConversation("Claw", "VS Code konnte nicht gestartet werden. Prüfe, ob `code` im PATH ist.", false); }
        }
    }


    private void OnThreadSelected()
    {
        if (ThreadList.SelectedItem is not ListBoxItem item || item.Content is null) return;
        var taskTitle = item.Content.ToString() ?? "Neuer Chat";
        UpdateThreadTitle(taskTitle);
        if (IsCurrentChatEmpty() && string.IsNullOrWhiteSpace(PromptTextBox.Text))
        {
            PromptTextBox.Text = TaskPromptFor(taskTitle);
            PromptTextBox.Focus();
            PromptTextBox.CaretIndex = PromptTextBox.Text.Length;
        }
    }

    private bool IsCurrentChatEmpty()
    {
        if (ConversationStack.Children.Count == 0) return true;
        if (ConversationStack.Children.Count == 1 && ConversationStack.Children[0] is Border border && border.Child is StackPanel stack && stack.Children.Count >= 2)
        {
            var text = (stack.Children[1] as System.Windows.Controls.TextBox)?.Text ?? string.Empty;
            return text.Contains("Neuer Chat gestartet", StringComparison.OrdinalIgnoreCase) || text.Contains("Willkommen in Claw Studio", StringComparison.OrdinalIgnoreCase);
        }
        return false;
    }

    private static string TaskPromptFor(string title) => title switch
    {
        "Claw Code installieren" => "Installiere bzw. prüfe Claw Code in diesem Projekt. Lege fehlende Konfigurationen an und melde, was geändert wurde.",
        "Repo analysieren" => "Analysiere dieses Repository. Erkläre Architektur, Build-Flow, Abhängigkeiten, Risiken und die nächsten sinnvollen Schritte.",
        "Build-Probleme untersuchen" => "Untersuche die Build-Probleme in diesem Projekt. Führe passende Prüfungen aus, behebe die Ursache direkt in den Dateien und fasse die Änderungen zusammen.",
        "Naechsten Fix vorbereiten" => "Bereite den nächsten sinnvollen Fix in diesem Projekt vor. Prüfe den aktuellen Stand, ändere die nötigen Dateien und fasse die Änderung zusammen.",
        _ => title
    };

    private static string MakeChatTitle(string prompt)
    {
        var clean = Regex.Replace(prompt.Trim(), "\\s+", " ");
        if (clean.Length <= 42) return clean;
        return clean.Substring(0, 42).TrimEnd() + "…";
    }

    private void PinProject()
    {
        AddConversation("Claw", "Projekt angeheftet: " + _settings.ProjectPath, false);
    }

    private void CreatePermanentWorktree()
    {
        try
        {
            var clawDir = Path.Combine(_settings.ProjectPath, ".claw");
            Directory.CreateDirectory(clawDir);
            var marker = Path.Combine(clawDir, "permanent-worktree.txt");
            File.WriteAllText(marker, "Permanent worktree enabled for Claw Studio." + Environment.NewLine, Encoding.UTF8);
            AddConversation("Claw", "Permanenter Worktree-Marker erstellt: " + marker, false);
        }
        catch (Exception ex)
        {
            AddConversation("Claw", "Permanenter Worktree konnte nicht erstellt werden: " + ex.Message, false);
        }
    }


    private string PromptForText(string title, string label, string defaultValue)
    {
        using var form = new Forms.Form
        {
            Text = title,
            Width = 420,
            Height = 150,
            StartPosition = Forms.FormStartPosition.CenterScreen,
            FormBorderStyle = Forms.FormBorderStyle.FixedDialog,
            MinimizeBox = false,
            MaximizeBox = false
        };
        var labelControl = new Forms.Label { Left = 12, Top = 14, Width = 380, Text = label };
        var textBox = new Forms.TextBox { Left = 12, Top = 40, Width = 380, Text = defaultValue };
        var okButton = new Forms.Button { Text = "OK", Left = 236, Width = 75, Top = 76, DialogResult = Forms.DialogResult.OK };
        var cancelButton = new Forms.Button { Text = "Abbrechen", Left = 317, Width = 75, Top = 76, DialogResult = Forms.DialogResult.Cancel };
        form.Controls.Add(labelControl);
        form.Controls.Add(textBox);
        form.Controls.Add(okButton);
        form.Controls.Add(cancelButton);
        form.AcceptButton = okButton;
        form.CancelButton = cancelButton;
        return form.ShowDialog() == Forms.DialogResult.OK ? textBox.Text : defaultValue;
    }

    private void RenameProject()
    {
        try
        {
            var current = _settings.ProjectPath;
            if (!Directory.Exists(current)) return;
            var currentName = new DirectoryInfo(current).Name;
            var newName = PromptForText("Projekt umbenennen", "Neuer Projektname:", currentName).Trim();
            if (string.IsNullOrWhiteSpace(newName) || string.Equals(newName, currentName, StringComparison.OrdinalIgnoreCase)) return;
            var parent = Directory.GetParent(current)?.FullName;
            if (string.IsNullOrWhiteSpace(parent)) return;
            var target = Path.Combine(parent, newName);
            Directory.Move(current, target);
            _settings.ProjectPath = target;
            SaveSettingsFromUi();
            UpdateProjectLabels();
            AddConversation("Claw", "Projekt umbenannt in: " + newName, false);
        }
        catch (Exception ex)
        {
            AddConversation("Claw", "Projekt konnte nicht umbenannt werden: " + ex.Message, false);
        }
    }

    private void ArchiveChats()
    {
        try
        {
            var clawDir = Path.Combine(_settings.ProjectPath, ".claw");
            Directory.CreateDirectory(clawDir);
            var file = Path.Combine(clawDir, "chat-archive-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".txt");
            File.WriteAllText(file, BuildWholeScreenText(), Encoding.UTF8);
            ConversationStack.Children.Clear();
            AddConversation("Claw", "Chats archiviert: " + file, false);
        }
        catch (Exception ex)
        {
            AddConversation("Claw", "Chats konnten nicht archiviert werden: " + ex.Message, false);
        }
    }

    private void RemoveProject()
    {
        _settings.ProjectPath = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        SaveSettingsFromUi();
        UpdateProjectLabels();
        NewChat();
        AddConversation("Claw", "Projekt aus der Seitenleiste entfernt. Wähle ein neues Projekt.", false);
    }

    private void NewChat()
    {
        ConversationStack.Children.Clear();
        PromptTextBox.Clear();
        UpdateThreadTitle("Neuer Chat");
        AddConversation("Claw", "Neuer Chat gestartet.", false);
        PromptTextBox.Focus();
        Keyboard.Focus(PromptTextBox);
    }

    private void UpdateThreadTitle(string title)
    {
        ThreadTitleText.Text = title;
    }

    private void PreparePlaceholderView(string title, string message)
    {
        UpdateThreadTitle(title);
        AddConversation("Claw", message, false);
    }

    private async Task SendPromptAsync()
    {
        var prompt = PromptTextBox.Text.Trim();
        if (prompt.Length == 0) return;
        if (string.Equals(ThreadTitleText.Text, "Neuer Chat", StringComparison.OrdinalIgnoreCase))
        {
            var title = MakeChatTitle(prompt);
            UpdateThreadTitle(title);
            if (ThreadList.SelectedItem is ListBoxItem selected) selected.Content = title;
        }
        PromptTextBox.Clear();
        await RunClawAsync(prompt);
    }

    private void PromptTextBox_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Enter && Keyboard.Modifiers != ModifierKeys.Shift)
        {
            e.Handled = true;
            _ = SendPromptAsync();
        }
    }

    private async Task RunClawAsync(string prompt, bool skipPermissions = false)
    {
        if (_runCts is not null)
        {
            AddConversation("Claw", "Es läuft bereits eine Aufgabe.", false);
            return;
        }

        SaveSettingsFromUi();
        if (!File.Exists(_settings.ClawPath))
        {
            AddConversation("Claw", "claw.exe wurde nicht gefunden. Bitte setup.bat ausführen.", false);
            return;
        }
        if (!Directory.Exists(_settings.ProjectPath))
        {
            AddConversation("Claw", "Bitte zuerst einen gültigen Projektordner wählen.", false);
            return;
        }

        _lastPrompt = prompt;
        _lastCommandLabel = prompt;
        _lastCommandArguments = ["--compact", "--output-format", "text", "--model", GetComboText(ModelComboBox), "--permission-mode", GetComboText(PermissionComboBox), "prompt", prompt];
        ApprovalPanel.Visibility = Visibility.Collapsed;
        _runCts = new CancellationTokenSource();
        SetBusy("Working");

        var effectivePrompt = BuildAgentPrompt(prompt);
        var args = $"--compact --output-format text --model \"{Escape(GetComboText(ModelComboBox))}\" --permission-mode {GetComboText(PermissionComboBox)} ";
        if (skipPermissions) args += "--dangerously-skip-permissions ";
        args += $"prompt \"{Escape(effectivePrompt)}\"";

        AddConversation("You", prompt, true);
        var assistant = AddConversation("Claw", "⏳ Arbeitet...", false, monospace: true);
        assistant.Tag = "loading";
        _activeAssistantBubble = assistant;
        try
        {
            var code = await _processService.RunAsync(_settings.ClawPath, args, _settings.ProjectPath, text => OnProcessOutput(text, assistant), _runCts.Token);
            ExecuteToolCallsFromAssistantOutput(assistant);
            if (code != 0 && await TryRecoverMissingModelAsync(assistant, prompt, GetComboText(PermissionComboBox), skipPermissions))
            {
                return;
            }
            if (code != 0) AppendToBubble(assistant, $"\nProzess mit Exit-Code {code} beendet.\n");
        }
        catch (OperationCanceledException)
        {
            AppendToBubble(assistant, "\nAufgabe abgebrochen.\n");
        }
        catch (Exception ex)
        {
            AppendToBubble(assistant, "\nStart fehlgeschlagen: " + ex.Message + "\n");
        }
        finally
        {
            if (ReferenceEquals(_activeAssistantBubble, assistant) && assistant.Text == "⏳ Arbeitet...")
            {
                assistant.Text = "Keine Ausgabe erhalten.";
            }
            _activeAssistantBubble = null;
            _runCts?.Dispose();
            _runCts = null;
            SetReady();
        }
    }

    private async Task RunRawClawAsync(string args, string label)
    {
        SaveSettingsFromUi();
        if (!File.Exists(_settings.ClawPath)) { AddConversation("Claw", "claw.exe wurde nicht gefunden.", false); return; }
        await RunProcessAsync(_settings.ClawPath, args, Directory.Exists(_settings.ProjectPath) ? _settings.ProjectPath : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), label);
    }

    private async Task RunProcessAsync(string fileName, string args, string workingDirectory, string label)
    {
        if (_runCts is not null) { AddConversation("Claw", "Es läuft bereits eine Aufgabe.", false); return; }
        _runCts = new CancellationTokenSource();
        SetBusy("Working");
        AddConversation("You", label, true);
        var assistant = AddConversation("Claw", "⏳ Arbeitet...", false, monospace: true);
        assistant.Tag = "loading";
        _activeAssistantBubble = assistant;
        try
        {
            var code = await _processService.RunAsync(fileName, args, workingDirectory, text => OnProcessOutput(text, assistant), _runCts.Token);
            if (code != 0) AppendToBubble(assistant, $"\nProzess mit Exit-Code {code} beendet.\n");
        }
        catch (Exception ex) { AppendToBubble(assistant, "\nFehler: " + ex.Message + "\n"); }
        finally { if ((ReferenceEquals(_activeAssistantBubble, assistant) || Equals(assistant.Tag, "loading")) && (assistant.Text ?? string.Empty).Contains("Arbeitet")) { assistant.Text = "Keine Ausgabe erhalten."; assistant.Tag = null; } _activeAssistantBubble = null; _runCts?.Dispose(); _runCts = null; SetReady(); }
    }

    private async Task RunGitAsync(Func<Action<string>, CancellationToken, Task<int>> action, string label)
    {
        if (!Directory.Exists(_settings.ProjectPath)) { AddConversation("Claw", "Bitte zuerst einen gültigen Projektordner wählen.", false); return; }
        if (_runCts is not null) { AddConversation("Claw", "Es läuft bereits eine Aufgabe.", false); return; }
        _runCts = new CancellationTokenSource();
        SetBusy("Git");
        AddConversation("You", label, true);
        var assistant = AddConversation("Claw", "⏳ Arbeitet...", false, monospace: true);
        assistant.Tag = "loading";
        _activeAssistantBubble = assistant;
        void Output(string t) => Dispatcher.Invoke(() => AppendToBubble(assistant, t));
        try
        {
            var code = await action(Output, _runCts.Token);
            var currentText = assistant.Text ?? string.Empty;
            if (code == 128 && currentText.Contains("dubious ownership", StringComparison.OrdinalIgnoreCase))
            {
                var safePath = _settings.ProjectPath.Replace("\\", "/");
                AppendToBubble(assistant, $"\nGit blockiert wegen Ownership/Safe-Directory. Ich setze jetzt automatisch:\n\ngit config --global --add safe.directory {safePath}\n");
                var fixCode = await _processService.RunAsync("git", $"config --global --add safe.directory \"{safePath}\"", _settings.ProjectPath, Output, _runCts.Token);
                if (fixCode == 0)
                {
                    AppendToBubble(assistant, "\nSafe-Directory gesetzt. Bitte den Git-Befehl erneut ausführen.\n");
                }
                else
                {
                    AppendToBubble(assistant, $"\nSafe-Directory-Fix fehlgeschlagen, Exit-Code {fixCode}.\n");
                }
            }
            else if (code == 128 && currentText.Contains("not a git repository", StringComparison.OrdinalIgnoreCase))
            {
                AppendToBubble(assistant, "\nHinweis: In diesem Ordner gibt es noch kein Git-Repo. Klicke auf \"Git-Repo anlegen\", wenn du hier Git initialisieren willst.\n");
            }
            if (code != 0) AppendToBubble(assistant, $"\nGit wurde mit Exit-Code {code} beendet.\n");
        }
        catch (Exception ex) { AppendToBubble(assistant, "\nGit-Fehler: " + ex.Message + "\n"); }
        finally { if ((ReferenceEquals(_activeAssistantBubble, assistant) || Equals(assistant.Tag, "loading")) && (assistant.Text ?? string.Empty).Contains("Arbeitet")) { assistant.Text = "Keine Ausgabe erhalten."; assistant.Tag = null; } _activeAssistantBubble = null; _runCts?.Dispose(); _runCts = null; SetReady(); UpdateProjectLabels(); }
    }

    private void OnProcessOutput(string text, System.Windows.Controls.TextBox assistant)
    {
        Dispatcher.Invoke(() =>
        {
            if (ReferenceEquals(_activeAssistantBubble, assistant) || Equals(assistant.Tag, "loading"))
            {
                assistant.Clear();
                assistant.Tag = null;
            }
            AppendToBubble(assistant, text);
            if (LooksLikeApprovalRequest(text))
            {
                ApprovalPanel.Visibility = Visibility.Visible;
                SetStatus("Approval", "#3A2D13", "#FBBF24");
                _runCts?.Cancel();
            }
        });
    }

    private static bool LooksLikeApprovalRequest(string text) => Regex.IsMatch(text, "permission approval|approval required|approve|genehmigung|berechtigung", RegexOptions.IgnoreCase);

    private System.Windows.Controls.TextBox AddConversation(string role, string text, bool user, bool monospace = false)
    {
        var outer = new Border
        {
            Margin = user ? new Thickness(90, 0, 0, 14) : new Thickness(0, 0, 90, 14),
            Padding = new Thickness(18, 14, 18, 14),
            CornerRadius = new CornerRadius(18),
            MaxWidth = 900,
            HorizontalAlignment = user ? System.Windows.HorizontalAlignment.Right : System.Windows.HorizontalAlignment.Left,
            Background = BrushFrom(user ? "#233044" : "#20242A"),
            BorderBrush = BrushFrom("#30343B"),
            BorderThickness = new Thickness(1)
        };
        var stack = new StackPanel();
        stack.Children.Add(new TextBlock
        {
            Text = role,
            Foreground = BrushFrom(user ? "#93C5FD" : "#86EFAC"),
            FontWeight = FontWeights.SemiBold
        });
        var body = new System.Windows.Controls.TextBox
        {
            Text = text,
            Margin = new Thickness(0, 8, 0, 0),
            Foreground = BrushFrom("#F3F4F6"),
            Background = System.Windows.Media.Brushes.Transparent,
            BorderThickness = new Thickness(0),
            IsReadOnly = true,
            TextWrapping = TextWrapping.Wrap,
            AcceptsReturn = true,
            FontFamily = new System.Windows.Media.FontFamily(monospace ? "Consolas" : "Segoe UI"),
            FontSize = monospace ? 13 : 14
        };
        stack.Children.Add(body);

        if (!user)
        {
            var actions = new WrapPanel { Margin = new Thickness(0, 12, 0, 0) };

            var copyButton = new System.Windows.Controls.Button
            {
                Content = new TextBlock
                {
                    Text = "",
                    FontFamily = new System.Windows.Media.FontFamily("Segoe MDL2 Assets"),
                    FontSize = 14,
                    Foreground = BrushFrom("#F3F4F6"),
                    HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                    VerticalAlignment = System.Windows.VerticalAlignment.Center
                },
                Width = 32,
                Height = 32,
                Margin = new Thickness(0, 0, 8, 0),
                Padding = new Thickness(0),
                Background = System.Windows.Media.Brushes.Transparent,
                Foreground = BrushFrom("#F3F4F6"),
                BorderBrush = System.Windows.Media.Brushes.Transparent,
                BorderThickness = new Thickness(1),
                Cursor = System.Windows.Input.Cursors.Hand,
                ToolTip = "Antwort kopieren"
            };
            if (TryFindResource("CompactIconButtonStyle") is Style compactIconButtonStyle) copyButton.Style = compactIconButtonStyle;
            copyButton.Click += (_, _) => CopyResponseToClipboard(body.Text ?? string.Empty);

            var readButton = new System.Windows.Controls.Button
            {
                Content = new TextBlock
                {
                    Text = "",
                    FontFamily = new System.Windows.Media.FontFamily("Segoe MDL2 Assets"),
                    FontSize = 14,
                    Foreground = BrushFrom("#F3F4F6"),
                    HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                    VerticalAlignment = System.Windows.VerticalAlignment.Center
                },
                Width = 32,
                Height = 32,
                Margin = new Thickness(0, 0, 8, 0),
                Padding = new Thickness(0),
                Background = System.Windows.Media.Brushes.Transparent,
                Foreground = BrushFrom("#F3F4F6"),
                BorderBrush = System.Windows.Media.Brushes.Transparent,
                BorderThickness = new Thickness(1),
                Cursor = System.Windows.Input.Cursors.Hand,
                ToolTip = "Vorlesen"
            };
            if (TryFindResource("CompactIconButtonStyle") is Style compactIconButtonStyle2) readButton.Style = compactIconButtonStyle2;
            readButton.Click += (_, _) => ReadResponseAloud(body.Text ?? string.Empty);

            actions.Children.Add(copyButton);
            actions.Children.Add(readButton);
            stack.Children.Add(actions);
        }

        outer.Child = stack;
        ConversationStack.Children.Add(outer);
        ConversationScrollViewer.ScrollToEnd();
        return body;
    }


    private static string BuildAgentPrompt(string userPrompt)
    {
        return "Du arbeitest im aktuell ausgewählten Projektordner. " +
               "Wenn der Benutzer etwas erstellen, ändern, reparieren, installieren oder vorbereiten möchte, dann ändere/erstelle die nötigen Dateien direkt im Projekt. " +
               "Gib nicht nur Beispielcode oder eine Erklärung aus. " +
               "Nach der Arbeit liste kurz die angelegten/geänderten Dateien und wie man es startet/testet.\n\n" +
               userPrompt;
    }


    private void ExecuteToolCallsFromAssistantOutput(System.Windows.Controls.TextBox assistant)
    {
        var raw = assistant.Text ?? string.Empty;
        var created = new List<string>();
        var messages = new List<string>();

        foreach (Match match in Regex.Matches(raw, "```json\\s*(\\{.*?\\})\\s*```", RegexOptions.Singleline | RegexOptions.IgnoreCase))
        {
            TryExecuteToolJson(match.Groups[1].Value, created, messages);
        }

        foreach (Match match in Regex.Matches(raw, "(?m)^\\s*(\\{\\s*\"name\"\\s*:\\s*\"(?:write_file|SendUserMessage)\".*?\\})\\s*$", RegexOptions.Singleline))
        {
            TryExecuteToolJson(match.Groups[1].Value, created, messages);
        }

        if (created.Count == 0 && messages.Count == 0) return;

        var summary = new StringBuilder();
        if (created.Count > 0)
        {
            summary.AppendLine("Dateien angelegt/geändert:");
            foreach (var file in created.Distinct(StringComparer.OrdinalIgnoreCase)) summary.AppendLine("- " + file);
            summary.AppendLine();
        }
        foreach (var message in messages.Where(m => !string.IsNullOrWhiteSpace(m)))
        {
            summary.AppendLine(message.Trim());
            summary.AppendLine();
        }

        assistant.Text = summary.ToString().TrimEnd();
        ConversationScrollViewer.ScrollToEnd();
        UpdateProjectLabels();
    }

    private void TryExecuteToolJson(string json, List<string> created, List<string> messages)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (!root.TryGetProperty("name", out var nameElement)) return;
            var name = nameElement.GetString() ?? string.Empty;
            if (!root.TryGetProperty("arguments", out var argsElement)) return;

            if (string.Equals(name, "write_file", StringComparison.OrdinalIgnoreCase))
            {
                if (!argsElement.TryGetProperty("path", out var pathElement)) return;
                if (!argsElement.TryGetProperty("content", out var contentElement)) return;
                var relativePath = pathElement.GetString() ?? string.Empty;
                var content = contentElement.GetString() ?? string.Empty;
                WriteProjectFile(relativePath, content);
                created.Add(relativePath);
            }
            else if (string.Equals(name, "SendUserMessage", StringComparison.OrdinalIgnoreCase))
            {
                if (argsElement.TryGetProperty("message", out var messageElement))
                {
                    messages.Add(messageElement.GetString() ?? string.Empty);
                }
            }
        }
        catch
        {
            // Ignore malformed tool JSON and leave the original assistant output visible.
        }
    }

    private void WriteProjectFile(string relativePath, string content)
    {
        if (string.IsNullOrWhiteSpace(relativePath)) throw new InvalidOperationException("write_file ohne Pfad.");
        var root = Path.GetFullPath(_settings.ProjectPath);
        var target = Path.GetFullPath(Path.Combine(root, relativePath));
        if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("write_file außerhalb des Projektordners blockiert: " + relativePath);
        }
        var dir = Path.GetDirectoryName(target);
        if (!string.IsNullOrWhiteSpace(dir)) Directory.CreateDirectory(dir);
        File.WriteAllText(target, content, Encoding.UTF8);
    }

    private async Task<bool> TryRecoverMissingModelAsync(System.Windows.Controls.TextBox assistant, string prompt, string permissionMode, bool skipPermissions)
    {
        var currentText = assistant.Text ?? string.Empty;
        var selectedModel = GetComboText(ModelComboBox);
        if (!currentText.Contains("not found", StringComparison.OrdinalIgnoreCase) || !currentText.Contains("model", StringComparison.OrdinalIgnoreCase)) return false;
        if (selectedModel.Contains("qwen2.5-coder:7b", StringComparison.OrdinalIgnoreCase)) return false;

        var fallbackModel = "openai/qwen2.5-coder:7b";
        AppendToBubble(assistant, $"\nModell {selectedModel} wurde lokal nicht gefunden. Versuche automatisch erneut mit {fallbackModel}.\n\n");
        SetComboText(ModelComboBox, fallbackModel);
        UpdateFooterText();
        SaveSettingsFromUi();

        var effectivePrompt = BuildAgentPrompt(prompt);
        var retryArgs = $"--compact --output-format text --model \"{Escape(fallbackModel)}\" --permission-mode {permissionMode} ";
        if (skipPermissions) retryArgs += "--dangerously-skip-permissions ";
        retryArgs += $"prompt \"{Escape(effectivePrompt)}\"";

        var retryCode = await _processService.RunAsync(_settings.ClawPath, retryArgs, _settings.ProjectPath, text => OnProcessOutput(text, assistant), _runCts!.Token);
        ExecuteToolCallsFromAssistantOutput(assistant);
        if (retryCode != 0) AppendToBubble(assistant, $"\nProzess mit Exit-Code {retryCode} beendet.\n");
        return true;
    }


    private void CopyResponseToClipboard(string text)
    {
        try
        {
            System.Windows.Clipboard.SetText(text ?? string.Empty);
            SetStatus("Kopiert", "#1E3A5F", "#BFDBFE");
        }
        catch (Exception ex)
        {
            AddConversation("Claw", "Antwort konnte nicht kopiert werden: " + ex.Message, false);
        }
    }

    private void ReadResponseAloud(string text)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "powershell",
                Arguments = "-NoProfile -WindowStyle Hidden -Command \"Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Speak([Console]::In.ReadToEnd())\"",
                UseShellExecute = false,
                RedirectStandardInput = true,
                CreateNoWindow = true
            };
            var process = Process.Start(psi);
            if (process is not null)
            {
                process.StandardInput.Write(text ?? string.Empty);
                process.StandardInput.Close();
            }
        }
        catch (Exception ex)
        {
            AddConversation("Claw", "Vorlesen konnte nicht gestartet werden: " + ex.Message, false);
        }
    }

    private void CopyWholeScreenToClipboard()
    {
        try
        {
            var text = BuildWholeScreenText();
            System.Windows.Clipboard.SetText(text);
            SetStatus("Kopiert", "#1E3A5F", "#BFDBFE");
            AddConversation("Claw", "Gesamter Screen-Inhalt wurde in die Zwischenablage kopiert.", false);
        }
        catch (Exception ex)
        {
            AddConversation("Claw", "Kopieren fehlgeschlagen: " + ex.Message, false);
        }
    }

    private string BuildWholeScreenText()
    {
        var sb = new StringBuilder();
        sb.AppendLine(ThreadTitleText.Text);
        sb.AppendLine(ThreadSubtitleText.Text);
        sb.AppendLine();
        sb.AppendLine($"Workspace: {SidebarProjectNameText.Text}");
        sb.AppendLine($"Pfad: {SidebarProjectPathText.Text}");
        sb.AppendLine($"Status: {StatusPillText.Text}");
        sb.AppendLine($"Modell: {GetComboText(ModelComboBox)}");
        sb.AppendLine($"Berechtigung: {GetComboText(PermissionComboBox)}");
        sb.AppendLine();
        sb.AppendLine("=== Conversation ===");
        foreach (var child in ConversationStack.Children.OfType<Border>())
        {
            if (child.Child is not StackPanel stack || stack.Children.Count < 2) continue;
            var role = (stack.Children[0] as TextBlock)?.Text ?? "Claw";
            var body = (stack.Children[1] as System.Windows.Controls.TextBox)?.Text ?? string.Empty;
            sb.AppendLine($"[{role}]");
            sb.AppendLine(body.TrimEnd());
            sb.AppendLine();
        }
        sb.AppendLine("=== Git ===");
        sb.AppendLine($"Geändert: {BranchStatusChangedValue.Text}");
        sb.AppendLine($"Hinzugefügt: {BranchStatusAddedValue.Text}");
        sb.AppendLine($"Entfernt: {BranchStatusRemovedValue.Text}");
        sb.AppendLine($"Branch: {BranchText.Text}");
        return sb.ToString();
    }

    private void AppendRaw(string text)
    {
        Dispatcher.Invoke(() => AddConversation("Claw", text, false, monospace: true));
    }

    private void AppendToBubble(System.Windows.Controls.TextBox box, string text)
    {
        box.AppendText(text);
        box.ScrollToEnd();
        ConversationScrollViewer.ScrollToEnd();
    }

    private static System.Windows.Media.Brush BrushFrom(string color) => (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFromString(color)!;

    private void SetBusy(string label)
    {
        WorkMetaPanel.Visibility = Visibility.Collapsed;
        _spinnerTimer.Stop();
        SetStatus("⏳ " + label, "#3A2D13", "#FDE68A");
        SetUiEnabled(false);
    }

    private void SetReady()
    {
        _spinnerTimer.Stop();
        WorkMetaPanel.Visibility = Visibility.Collapsed;
        SetStatus("Ready", "#1F4A34", "#86EFAC");
        SetUiEnabled(true);
    }

    private void SetStatus(string text, string background, string foreground)
    {
        StatusPill.Background = BrushFrom(background);
        StatusPillText.Foreground = BrushFrom(foreground);
        StatusPillText.Text = text;
    }

    private void SetUiEnabled(bool enabled)
    {
        ProjectChooseButton.IsEnabled = enabled;
        ProjectOpenButton.IsEnabled = enabled;
        NewThreadButton.IsEnabled = enabled;
        SendButton.IsEnabled = enabled;
        HeaderRunButton.IsEnabled = enabled;
        TerminalButton.IsEnabled = enabled;
    }

    private void InsertText(string text)
    {
        if (!string.IsNullOrWhiteSpace(PromptTextBox.Text)) PromptTextBox.Text += Environment.NewLine + Environment.NewLine;
        PromptTextBox.Text += text;
        PromptTextBox.Focus();
        PromptTextBox.CaretIndex = PromptTextBox.Text.Length;
    }

    private void InsertClipboardIntoPrompt()
    {
        if (System.Windows.Clipboard.ContainsText()) InsertText(System.Windows.Clipboard.GetText());
    }

    private void AttachFilesToPrompt()
    {
        var dialog = new Forms.OpenFileDialog
        {
            Title = "Dateien an Prompt anhängen",
            Multiselect = true,
            CheckFileExists = true
        };
        if (dialog.ShowDialog() != Forms.DialogResult.OK) return;
        foreach (var file in dialog.FileNames)
        {
            InsertText($"Attached file: {file}");
        }
    }

    private void ToggleWindowState()
    {
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
    }

    private void StartDictation()
    {
        SendWinH();
        PromptTextBox.Focus();
    }

    private string GetBranchSummary(string path)
    {
        try
        {
            if (!Directory.Exists(Path.Combine(path, ".git"))) return "kein Git-Repo";
            var psi = new ProcessStartInfo("git", "branch --show-current")
            {
                WorkingDirectory = path,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            using var process = Process.Start(psi);
            if (process is null) return "Git";
            var output = process.StandardOutput.ReadToEnd().Trim();
            process.WaitForExit(1200);
            return string.IsNullOrWhiteSpace(output) ? "Git" : output;
        }
        catch { return "Git"; }
    }

    private static string Escape(string value) => value.Replace("\\", "\\\\").Replace("\"", "\\\"");

    [DllImport("user32.dll")] private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    private const int KEYEVENTF_KEYUP = 0x0002;
    private const byte VK_LWIN = 0x5B;
    private const byte VK_H = 0x48;
    private static void SendWinH()
    {
        keybd_event(VK_LWIN, 0, 0, UIntPtr.Zero);
        keybd_event(VK_H, 0, 0, UIntPtr.Zero);
        keybd_event(VK_H, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}
