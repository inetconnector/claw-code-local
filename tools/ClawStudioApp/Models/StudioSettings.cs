using System.IO;
namespace ClawStudio.Models;

public sealed class StudioSettings
{
    public string ClawPath { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "ClawCode", "bin", "claw.exe");
    public string ProjectPath { get; set; } = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    public string Model { get; set; } = "openai/qwen2.5-coder:7b";
    public string PermissionMode { get; set; } = "workspace-write";
    public string GitRemote { get; set; } = string.Empty;
}
