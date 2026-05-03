#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:USERPROFILE\source\claw-code",
    [string]$RepoUrl = "https://github.com/ultraworkers/claw-code.git",
    [switch]$Release,
    [switch]$NoUpdate,
    [switch]$ForceRebuild,
    [switch]$RunTests,
    [switch]$NoOllama,
    [string]$OllamaModel = "auto",
    [string]$AnthropicApiKey = "",
    [switch]$SkipVsBuildTools,
    [switch]$SkipDoctor
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$Global:BootstrapWarnings = New-Object System.Collections.Generic.List[string]
$Global:BootstrapActions = New-Object System.Collections.Generic.List[string]

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK]   $Message"
}

function Write-Warn {
    param([string]$Message)
    $Global:BootstrapWarnings.Add($Message) | Out-Null
    Write-Warning $Message
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "== $Message =="
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CommandExists {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Refresh-CurrentPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $paths = @()

    if (-not [string]::IsNullOrWhiteSpace($machinePath)) {
        $paths += $machinePath.Split(";")
    }

    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        $paths += $userPath.Split(";")
    }

    $paths = $paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    $env:Path = ($paths -join ";")
}

function Add-UserPath {
    param([string]$Directory)

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        return
    }

    $fullPath = [System.IO.Path]::GetFullPath($Directory)

    if (-not (Test-Path -LiteralPath $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
    }

    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $items = @()

    if (-not [string]::IsNullOrWhiteSpace($currentUserPath)) {
        $items = $currentUserPath.Split(";") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $alreadyExists = $false
    foreach ($item in $items) {
        try {
            if ([System.IO.Path]::GetFullPath($item.TrimEnd("\")) -ieq $fullPath.TrimEnd("\")) {
                $alreadyExists = $true
                break
            }
        } catch {
            if ($item -ieq $fullPath) {
                $alreadyExists = $true
                break
            }
        }
    }

    if (-not $alreadyExists) {
        $newItems = @($items) + @($fullPath)
        [Environment]::SetEnvironmentVariable("Path", ($newItems -join ";"), "User")
        $Global:BootstrapActions.Add("Added to user PATH: $fullPath") | Out-Null
        Write-Ok "Added to user PATH: $fullPath"
    } else {
        Write-Ok "User PATH already contains: $fullPath"
    }

    Refresh-CurrentPath
}

function Resolve-NativeCommandPath {
    param([Parameter(Mandatory=$true)][string]$FilePath)

    if ([System.IO.Path]::IsPathRooted($FilePath) -and (Test-Path -LiteralPath $FilePath)) {
        return $FilePath
    }

    $command = Get-Command $FilePath -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
        return $command.Source
    }

    return $FilePath
}

function Join-NativeArguments {
    param([string[]]$Arguments)

    $quoted = New-Object System.Collections.Generic.List[string]

    foreach ($arg in $Arguments) {
        if ($null -eq $arg) {
            $quoted.Add('""') | Out-Null
            continue
        }

        $value = [string]$arg

        if ($value.Length -eq 0) {
            $quoted.Add('""') | Out-Null
            continue
        }

        if ($value -notmatch '[\s"]') {
            $quoted.Add($value) | Out-Null
            continue
        }

        $escaped = $value.Replace('\', '\\').Replace('"', '\"')
        $quoted.Add('"' + $escaped + '"') | Out-Null
    }

    return ($quoted -join " ")
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = "",
        [switch]$AllowFailure
    )

    $resolvedPath = Resolve-NativeCommandPath -FilePath $FilePath
    $argumentString = Join-NativeArguments -Arguments $Arguments

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        $startArgs = @{
            FilePath = $resolvedPath
            ArgumentList = $argumentString
            Wait = $true
            PassThru = $true
            NoNewWindow = $true
            RedirectStandardOutput = $stdoutFile
            RedirectStandardError = $stderrFile
        }

        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            $startArgs["WorkingDirectory"] = $WorkingDirectory
        }

        $process = Start-Process @startArgs
        $exitCode = $process.ExitCode

        $stdout = @()
        $stderr = @()

        if (Test-Path -LiteralPath $stdoutFile) {
            $stdout = @(Get-Content -LiteralPath $stdoutFile -ErrorAction SilentlyContinue)
        }

        if (Test-Path -LiteralPath $stderrFile) {
            $stderr = @(Get-Content -LiteralPath $stderrFile -ErrorAction SilentlyContinue)
        }

        if ($null -eq $exitCode) {
            $exitCode = 0
        }

        return [pscustomobject]@{
            ExitCode = $exitCode
            StdOut = @($stdout)
            StdErr = @($stderr)
        }
    } finally {
        Remove-Item -LiteralPath $stdoutFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-External {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = "",
        [switch]$AllowFailure,
        [switch]$PassThruExitCode
    )

    Write-Info ("Running: {0} {1}" -f $FilePath, ($Arguments -join " "))

    $result = Invoke-NativeProcess -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory -AllowFailure:$AllowFailure

    foreach ($line in $result.StdOut) {
        if ($null -ne $line) {
            Write-Host ([string]$line)
        }
    }

    foreach ($line in $result.StdErr) {
        if ($null -ne $line) {
            Write-Host ([string]$line)
        }
    }

    if (($result.ExitCode -ne 0) -and (-not $AllowFailure)) {
        throw "Command failed with exit code $($result.ExitCode): $FilePath $($Arguments -join ' ')"
    }

    if ($PassThruExitCode) {
        return $result.ExitCode
    }

    return
}

function Get-CommandOutput {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = ""
    )

    $result = Invoke-NativeProcess -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory -AllowFailure

    $lines = New-Object System.Collections.Generic.List[string]

    foreach ($line in $result.StdOut) {
        if ($null -ne $line) {
            $lines.Add([string]$line) | Out-Null
        }
    }

    foreach ($line in $result.StdErr) {
        if ($null -ne $line) {
            $lines.Add([string]$line) | Out-Null
        }
    }

    return (($lines | Out-String).Trim())
}

function Test-WingetPackageInstalled {
    param([string]$PackageId)

    if (-not (Test-CommandExists "winget")) {
        return $false
    }

    $result = Invoke-NativeProcess -FilePath "winget" -Arguments @("list", "--id", $PackageId, "-e", "--accept-source-agreements") -AllowFailure
    $text = (($result.StdOut + $result.StdErr) | Out-String)
    return ($result.ExitCode -eq 0 -and $text -match [regex]::Escape($PackageId))
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory=$true)][string]$PackageId,
        [string]$DisplayName = "",
        [string[]]$ExtraArgs = @()
    )

    if (-not (Test-CommandExists "winget")) {
        throw "winget is missing. Install App Installer from Microsoft Store, then rerun this script."
    }

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = $PackageId
    }

    if (Test-WingetPackageInstalled -PackageId $PackageId) {
        Write-Ok "$DisplayName is already installed."
        return
    }

    Write-Info "Installing $DisplayName via winget..."
    $args = @(
        "install",
        "--id", $PackageId,
        "-e",
        "--source", "winget",
        "--accept-package-agreements",
        "--accept-source-agreements"
    ) + $ExtraArgs

    Invoke-External -FilePath "winget" -Arguments $args
    $Global:BootstrapActions.Add("Installed $DisplayName") | Out-Null
    Refresh-CurrentPath
}

function Ensure-Git {
    Write-Step "Checking Git"

    if (Test-CommandExists "git") {
        $version = Get-CommandOutput -FilePath "git" -Arguments @("--version")
        Write-Ok $version
        return
    }

    Install-WingetPackage -PackageId "Git.Git" -DisplayName "Git" -ExtraArgs @("--silent")
    Refresh-CurrentPath

    if (-not (Test-CommandExists "git")) {
        $gitCmd = "$env:ProgramFiles\Git\cmd"
        if (Test-Path -LiteralPath $gitCmd) {
            Add-UserPath -Directory $gitCmd
        }
    }

    if (-not (Test-CommandExists "git")) {
        throw "Git was installed, but git.exe is still not available in PATH. Open a new PowerShell window and rerun this script."
    }

    $version = Get-CommandOutput -FilePath "git" -Arguments @("--version")
    Write-Ok $version
}

function Ensure-Rust {
    Write-Step "Checking Rust toolchain"

    $cargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
    if (Test-Path -LiteralPath $cargoBin) {
        Add-UserPath -Directory $cargoBin
    }

    if (-not (Test-CommandExists "cargo")) {
        Install-WingetPackage -PackageId "Rustlang.Rustup" -DisplayName "Rustup" -ExtraArgs @("--silent")
        Refresh-CurrentPath
        if (Test-Path -LiteralPath $cargoBin) {
            Add-UserPath -Directory $cargoBin
        }
    }

    if (-not (Test-CommandExists "cargo")) {
        throw "Rust/Cargo was installed, but cargo.exe is still not available in PATH. Open a new PowerShell window and rerun this script."
    }

    if (Test-CommandExists "rustup") {
        Invoke-External -FilePath "rustup" -Arguments @("default", "stable")
        Invoke-External -FilePath "rustup" -Arguments @("update", "stable")
    } else {
        Write-Warn "rustup.exe was not found, but cargo.exe exists. Skipping rustup update."
    }

    $cargoVersion = Get-CommandOutput -FilePath "cargo" -Arguments @("--version")
    $rustcVersion = Get-CommandOutput -FilePath "rustc" -Arguments @("--version")
    Write-Ok $cargoVersion
    Write-Ok $rustcVersion
}

function Get-VsWherePath {
    $paths = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
        "$env:ProgramFiles\Microsoft Visual Studio\Installer\vswhere.exe"
    )

    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }

    return ""
}

function Test-VcToolsInstalled {
    $vswhere = Get-VsWherePath
    if ([string]::IsNullOrWhiteSpace($vswhere)) {
        return $false
    }

    $output = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    $path = ($output | Out-String).Trim()

    return (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path))
}

function Ensure-VsBuildTools {
    Write-Step "Checking Visual C++ build tools"

    if ($SkipVsBuildTools) {
        Write-Warn "Skipping Visual Studio Build Tools check because -SkipVsBuildTools was provided."
        return
    }

    if (Test-VcToolsInstalled) {
        Write-Ok "Visual C++ build tools are installed."
        return
    }

    if (-not (Test-IsAdmin)) {
        Write-Warn "Visual C++ build tools are missing. Rerun PowerShell as Administrator if the Rust build fails with linker errors."
        return
    }

    Write-Info "Installing Visual Studio 2022 Build Tools with VC tools workload. This can take a while."
    $override = '--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    Install-WingetPackage -PackageId "Microsoft.VisualStudio.2022.BuildTools" -DisplayName "Visual Studio 2022 Build Tools" -ExtraArgs @("--override", $override)

    if (-not (Test-VcToolsInstalled)) {
        Write-Warn "Visual C++ build tools were requested, but detection still failed. The Cargo build may still work; if not, rerun this script as Administrator."
    } else {
        Write-Ok "Visual C++ build tools are installed."
    }
}


function Get-LargestGpuVramGb {
    $maxBytes = 0

    try {
        $controllers = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop
    } catch {
        try {
            $controllers = Get-WmiObject -Class Win32_VideoController -ErrorAction Stop
        } catch {
            Write-Warn "Could not detect GPU VRAM automatically. Falling back to qwen2.5-coder:7b."
            return 0
        }
    }

    foreach ($controller in $controllers) {
        $name = [string]$controller.Name
        $ram = 0

        try {
            if ($null -ne $controller.AdapterRAM) {
                $ram = [int64]$controller.AdapterRAM
            }
        } catch {
            $ram = 0
        }

        if ($ram -lt 0) {
            $ram = 0
        }

        if ($ram -gt $maxBytes) {
            $maxBytes = $ram
        }

        if ($ram -gt 0) {
            $gb = [math]::Round(($ram / 1GB), 1)
            Write-Info ("Detected GPU: {0} / approx. {1} GB VRAM" -f $name, $gb)
        } else {
            Write-Info ("Detected GPU: {0} / VRAM unknown" -f $name)
        }
    }

    if ($maxBytes -le 0) {
        return 0
    }

    return [math]::Round(($maxBytes / 1GB), 1)
}

function Resolve-OllamaModel {
    param([string]$RequestedModel)

    if (-not [string]::IsNullOrWhiteSpace($RequestedModel) -and $RequestedModel -ine "auto") {
        Write-Ok "Using explicitly selected Ollama model: $RequestedModel"
        return $RequestedModel
    }

    $vramGb = Get-LargestGpuVramGb

    if ($vramGb -ge 20) {
        $selected = "qwen2.5-coder:32b"
        Write-Ok "Auto-selected model for approx. $vramGb GB VRAM: $selected"
        return $selected
    }

    if ($vramGb -ge 12) {
        $selected = "qwen2.5-coder:14b"
        Write-Ok "Auto-selected model for approx. $vramGb GB VRAM: $selected"
        return $selected
    }

    $selected = "qwen2.5-coder:7b"
    if ($vramGb -gt 0) {
        Write-Ok "Auto-selected model for approx. $vramGb GB VRAM: $selected"
    } else {
        Write-Ok "Auto-selected fallback model because VRAM could not be detected: $selected"
    }

    return $selected
}

function Ensure-Ollama {
    Write-Step "Checking Ollama"

    if ($NoOllama) {
        Write-Info "Ollama setup is disabled because -NoOllama was provided."
        return
    }

    $script:OllamaModel = Resolve-OllamaModel -RequestedModel $OllamaModel
    $OllamaModel = $script:OllamaModel


    if (-not (Test-CommandExists "ollama")) {
        Install-WingetPackage -PackageId "Ollama.Ollama" -DisplayName "Ollama" -ExtraArgs @("--silent")
        Refresh-CurrentPath
    }

    if (-not (Test-CommandExists "ollama")) {
        throw "Ollama was installed, but ollama.exe is still not available in PATH. Open a new PowerShell window and rerun this script."
    }

    $version = Get-CommandOutput -FilePath "ollama" -Arguments @("--version")
    Write-Ok $version

    $serverReady = $false
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get -TimeoutSec 3 | Out-Null
        $serverReady = $true
    } catch {
        $serverReady = $false
    }

    if (-not $serverReady) {
        Write-Info "Starting Ollama server..."
        Start-Process -FilePath "ollama" -ArgumentList @("serve") -WindowStyle Minimized | Out-Null
        Start-Sleep -Seconds 5
    }

    try {
        $tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get -TimeoutSec 10
        $modelExists = $false

        if ($null -ne $tags.models) {
            foreach ($model in $tags.models) {
                if ($model.name -ieq $OllamaModel -or $model.name -ieq "$OllamaModel`:latest") {
                    $modelExists = $true
                    break
                }
            }
        }

        if (-not $modelExists) {
            Write-Info "Pulling Ollama model: $OllamaModel"
            Invoke-External -FilePath "ollama" -Arguments @("pull", $OllamaModel)
            $Global:BootstrapActions.Add("Pulled Ollama model $OllamaModel") | Out-Null
        } else {
            Write-Ok "Ollama model is already present: $OllamaModel"
        }
    } catch {
        Write-Warn "Could not verify or pull Ollama model '$OllamaModel': $($_.Exception.Message)"
    }

    Set-UserEnvironmentVariable -Name "OPENAI_BASE_URL" -Value "http://127.0.0.1:11434/v1"
    Set-UserEnvironmentVariable -Name "OPENAI_API_KEY" -Value "local-dev-token"
}

function Set-UserEnvironmentVariable {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Value
    )

    $currentValue = [Environment]::GetEnvironmentVariable($Name, "User")
    if ($currentValue -ne $Value) {
        [Environment]::SetEnvironmentVariable($Name, $Value, "User")
        $Global:BootstrapActions.Add("Set user environment variable $Name") | Out-Null
        Write-Ok "Set user environment variable: $Name"
    } else {
        Write-Ok "User environment variable already set: $Name"
    }

    Set-Item -Path "Env:$Name" -Value $Value
}

function Ensure-Repository {
    Write-Step "Checking Claw Code repository"

    $parent = Split-Path -Parent $InstallRoot
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $InstallRoot) {
        $gitDir = Join-Path $InstallRoot ".git"

        if (-not (Test-Path -LiteralPath $gitDir)) {
            throw "InstallRoot exists but is not a Git repository: $InstallRoot"
        }

        $origin = Get-CommandOutput -FilePath "git" -Arguments @("remote", "get-url", "origin") -WorkingDirectory $InstallRoot
        Write-Ok "Repository exists: $InstallRoot"
        Write-Info "Origin: $origin"

        if (-not $NoUpdate) {
            Invoke-External -FilePath "git" -Arguments @("fetch", "--all", "--prune") -WorkingDirectory $InstallRoot
            Invoke-External -FilePath "git" -Arguments @("pull", "--ff-only") -WorkingDirectory $InstallRoot
            $Global:BootstrapActions.Add("Updated repository") | Out-Null
        } else {
            Write-Info "Skipping repository update because -NoUpdate was provided."
        }
    } else {
        Invoke-External -FilePath "git" -Arguments @("clone", $RepoUrl, $InstallRoot)
        $Global:BootstrapActions.Add("Cloned repository") | Out-Null
    }

    $rustDir = Join-Path $InstallRoot "rust"
    if (-not (Test-Path -LiteralPath $rustDir)) {
        throw "Rust workspace was not found: $rustDir"
    }

    return $rustDir
}

function Build-ClawCode {
    param([Parameter(Mandatory=$true)][string]$RustDir)

    Write-Step "Building Claw Code"

    $buildArgs = @("build", "--workspace")
    $targetKind = "debug"

    if ($Release) {
        $buildArgs += "--release"
        $targetKind = "release"
    }

    if ($ForceRebuild) {
        Invoke-External -FilePath "cargo" -Arguments @("clean") -WorkingDirectory $RustDir
        $Global:BootstrapActions.Add("Cleaned Cargo target directory") | Out-Null
    }

    Invoke-External -FilePath "cargo" -Arguments $buildArgs -WorkingDirectory $RustDir
    $Global:BootstrapActions.Add("Built Claw Code workspace") | Out-Null

    if ($RunTests) {
        Invoke-External -FilePath "cargo" -Arguments @("test", "--workspace") -WorkingDirectory $RustDir
        $Global:BootstrapActions.Add("Ran Cargo workspace tests") | Out-Null
    }

    $sourceBinary = Join-Path $RustDir "target\$targetKind\claw.exe"
    if (-not (Test-Path -LiteralPath $sourceBinary)) {
        throw "Build completed, but claw.exe was not found at expected path: $sourceBinary"
    }

    Write-Ok "Built binary: $sourceBinary"
    return $sourceBinary
}

function Install-ClawBinary {
    param([Parameter(Mandatory=$true)][string]$SourceBinary)

    Write-Step "Installing claw.exe into user PATH"

    $installDir = Join-Path $env:LOCALAPPDATA "Programs\ClawCode\bin"
    if (-not (Test-Path -LiteralPath $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    $targetBinary = Join-Path $installDir "claw.exe"

    $copyNeeded = $true
    if (Test-Path -LiteralPath $targetBinary) {
        $sourceHash = (Get-FileHash -LiteralPath $SourceBinary -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $targetBinary -Algorithm SHA256).Hash
        if ($sourceHash -eq $targetHash) {
            $copyNeeded = $false
        }
    }

    if ($copyNeeded) {
        Copy-Item -LiteralPath $SourceBinary -Destination $targetBinary -Force
        $Global:BootstrapActions.Add("Installed claw.exe to $targetBinary") | Out-Null
        Write-Ok "Installed: $targetBinary"
    } else {
        Write-Ok "Installed binary is already current: $targetBinary"
    }

    Add-UserPath -Directory $installDir
    return $targetBinary
}

function Configure-ApiKeys {
    Write-Step "Checking API/backend environment"

    if (-not [string]::IsNullOrWhiteSpace($AnthropicApiKey)) {
        Set-UserEnvironmentVariable -Name "ANTHROPIC_API_KEY" -Value $AnthropicApiKey
    } else {
        $existingAnthropic = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "User")
        $existingAnthropicProcess = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "Process")

        if ([string]::IsNullOrWhiteSpace($existingAnthropic) -and [string]::IsNullOrWhiteSpace($existingAnthropicProcess) -and $NoOllama) {
            Write-Warn "ANTHROPIC_API_KEY is not set. Pass -AnthropicApiKey 'sk-ant-...' or run without -NoOllama."
        } else {
            Write-Ok "Backend environment is configured."
        }
    }
}

function Verify-Claw {
    param([Parameter(Mandatory=$true)][string]$ClawBinary)

    Write-Step "Verifying Claw Code"

    Invoke-External -FilePath $ClawBinary -Arguments @("--version") -AllowFailure

    if ($SkipDoctor) {
        Write-Info "Skipping doctor check because -SkipDoctor was provided."
        return
    }

    $doctorExit = Invoke-External -FilePath $ClawBinary -Arguments @("doctor") -AllowFailure -PassThruExitCode
    if ($doctorExit -ne 0) {
        Write-Warn "claw doctor returned exit code $doctorExit. This is often caused by a missing API key or backend configuration."
    } else {
        Write-Ok "claw doctor completed successfully."
    }

    if (-not $NoOllama) {
        $promptExit = Invoke-External -FilePath $ClawBinary -Arguments @("--model", $OllamaModel, "prompt", "Say hello in one short sentence.") -AllowFailure -PassThruExitCode
        if ($promptExit -ne 0) {
            Write-Warn "Ollama prompt test returned exit code $promptExit. Check model name and local Ollama server."
        }
    }
}

function Show-Summary {
    Write-Step "Summary"

    if ($Global:BootstrapActions.Count -eq 0) {
        Write-Ok "No installation changes were needed."
    } else {
        Write-Host "Actions:"
        foreach ($action in $Global:BootstrapActions) {
            Write-Host " - $action"
        }
    }

    if ($Global:BootstrapWarnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Warnings:"
        foreach ($warning in $Global:BootstrapWarnings) {
            Write-Host " - $warning"
        }
    }

    Write-Host ""
    Write-Host "Useful commands:"
    Write-Host "  claw --version"
    Write-Host "  claw doctor"
    Write-Host "  ollama list"

    if (-not $NoOllama) {
        Write-Host ("  claw --model {0} prompt ""summarize this folder""" -f $OllamaModel)
    } else {
        Write-Host "  claw prompt ""summarize this folder"""
    }

    Write-Host ""
    Write-Host "If PATH changes are not visible in an old terminal, open a new PowerShell window."
}

try {
    Write-Host "Claw Code Local Ollama Bootstrap for Windows PowerShell 5.1 - fixed v8 sync-runner"
    Write-Host "InstallRoot: $InstallRoot"
    Write-Host "Release build: $Release"
    Write-Host "Use Ollama: $(-not $NoOllama)"
    Write-Host "Requested Ollama model: $OllamaModel"

    Refresh-CurrentPath

    if (-not (Test-IsAdmin)) {
        Write-Warn "PowerShell is not running as Administrator. Most steps can still work, but Visual Studio Build Tools installation may require elevation."
    }

    Ensure-Git
    Ensure-Rust
    Ensure-VsBuildTools
    Ensure-Ollama
    if ($script:OllamaModel) { $OllamaModel = $script:OllamaModel }
    Configure-ApiKeys

    $rustDir = @(Ensure-Repository | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })[-1]
    $builtBinary = @(Build-ClawCode -RustDir $rustDir | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })[-1]
    $installedBinary = @(Install-ClawBinary -SourceBinary $builtBinary | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })[-1]
    Verify-Claw -ClawBinary $installedBinary

    Show-Summary
    exit 0
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Rerun this script after fixing the reported problem. It is safe to run multiple times."
    exit 1
}
