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
    [string]$OllamaModel = "qwen2.5-coder:14b",
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

function Invoke-External {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = "",
        [switch]$AllowFailure
    )

    $oldLocation = Get-Location
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Set-Location -LiteralPath $WorkingDirectory
        }

        Write-Info ("Running: {0} {1}" -f $FilePath, ($Arguments -join " "))
        & $FilePath @Arguments
        $exitCode = $LASTEXITCODE

        if ($null -eq $exitCode) {
            $exitCode = 0
        }

        if (($exitCode -ne 0) -and (-not $AllowFailure)) {
            throw "Command failed with exit code $exitCode`: $FilePath $($Arguments -join ' ')"
        }

        return $exitCode
    } finally {
        Set-Location $oldLocation
    }
}

function Get-CommandOutput {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = ""
    )

    $oldLocation = Get-Location
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Set-Location -LiteralPath $WorkingDirectory
        }

        $output = & $FilePath @Arguments 2>&1
        return ($output | Out-String).Trim()
    } finally {
        Set-Location $oldLocation
    }
}

function Test-WingetPackageInstalled {
    param([string]$PackageId)

    if (-not (Test-CommandExists "winget")) {
        return $false
    }

    $output = & winget list --id $PackageId -e --accept-source-agreements 2>&1
    $text = ($output | Out-String)
    return ($LASTEXITCODE -eq 0 -and $text -match [regex]::Escape($PackageId))
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

function Ensure-Ollama {
    Write-Step "Checking Ollama"

    if ($NoOllama) {
        Write-Info "Ollama setup is disabled because -NoOllama was provided."
        return
    }

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

    $doctorExit = Invoke-External -FilePath $ClawBinary -Arguments @("doctor") -AllowFailure
    if ($doctorExit -ne 0) {
        Write-Warn "claw doctor returned exit code $doctorExit. This is often caused by a missing API key or backend configuration."
    } else {
        Write-Ok "claw doctor completed successfully."
    }

    if (-not $NoOllama) {
        $promptExit = Invoke-External -FilePath $ClawBinary -Arguments @("--model", $OllamaModel, "prompt", "Say hello in one short sentence.") -AllowFailure
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
    Write-Host "Claw Code Local Ollama Bootstrap for Windows PowerShell 5.1"
    Write-Host "InstallRoot: $InstallRoot"
    Write-Host "Release build: $Release"
    Write-Host "Use Ollama: $(-not $NoOllama)"

    Refresh-CurrentPath

    if (-not (Test-IsAdmin)) {
        Write-Warn "PowerShell is not running as Administrator. Most steps can still work, but Visual Studio Build Tools installation may require elevation."
    }

    Ensure-Git
    Ensure-Rust
    Ensure-VsBuildTools
    Ensure-Ollama
    Configure-ApiKeys

    $rustDir = Ensure-Repository
    $builtBinary = Build-ClawCode -RustDir $rustDir
    $installedBinary = Install-ClawBinary -SourceBinary $builtBinary
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
