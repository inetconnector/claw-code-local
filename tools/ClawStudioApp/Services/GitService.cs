namespace ClawStudio.Services;

public sealed class GitService
{
    private readonly ProcessService _processes = new();

    public Task<int> InitAsync(string cwd, Action<string> output, CancellationToken ct) =>
        _processes.RunAsync("git", "init", cwd, output, ct);

    public Task<int> FetchAsync(string cwd, Action<string> output, CancellationToken ct) =>
        _processes.RunAsync("git", "fetch --all --prune", cwd, output, ct);

    public Task<int> BranchesAsync(string cwd, Action<string> output, CancellationToken ct) =>
        _processes.RunAsync("git", "branch -a -vv", cwd, output, ct);

    public async Task<int> PushAsync(string cwd, string remote, Action<string> output, CancellationToken ct)
    {
        if (!string.IsNullOrWhiteSpace(remote))
        {
            await _processes.RunAsync("git", $"remote remove origin", cwd, _ => { }, CancellationToken.None).ConfigureAwait(false);
            var code = await _processes.RunAsync("git", $"remote add origin \"{remote}\"", cwd, output, ct).ConfigureAwait(false);
            if (code != 0) return code;
        }
        return await _processes.RunAsync("git", "push -u origin HEAD", cwd, output, ct).ConfigureAwait(false);
    }
}
