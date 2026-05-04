using System.IO;
using System.Text.Json;
using ClawStudio.Models;

namespace ClawStudio.Services;

public sealed class SettingsService
{
    private readonly string _settingsPath;
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public SettingsService()
    {
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "ClawCode", "studio");
        Directory.CreateDirectory(root);
        _settingsPath = Path.Combine(root, "settings.json");
    }

    public StudioSettings Load()
    {
        try
        {
            if (!File.Exists(_settingsPath)) return new StudioSettings();
            return JsonSerializer.Deserialize<StudioSettings>(File.ReadAllText(_settingsPath), JsonOptions) ?? new StudioSettings();
        }
        catch
        {
            return new StudioSettings();
        }
    }

    public void Save(StudioSettings settings)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_settingsPath)!);
        File.WriteAllText(_settingsPath, JsonSerializer.Serialize(settings, JsonOptions));
    }
}
