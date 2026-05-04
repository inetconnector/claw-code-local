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
    [switch]$SkipDoctor,
    [switch]$RunPromptTest
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
        [switch]$AllowFailure,
        [int]$TimeoutSeconds = 0
    )

    $resolvedPath = Resolve-NativeCommandPath -FilePath $FilePath
    $argumentString = Join-NativeArguments -Arguments $Arguments

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        $startArgs = @{
            FilePath = $resolvedPath
            ArgumentList = $argumentString
            PassThru = $true
            NoNewWindow = $true
            RedirectStandardOutput = $stdoutFile
            RedirectStandardError = $stderrFile
        }

        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            $startArgs["WorkingDirectory"] = $WorkingDirectory
        }

        $process = Start-Process @startArgs
        if ($TimeoutSeconds -gt 0) {
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                try { $process.Kill() } catch { }
                throw "Command timed out after $TimeoutSeconds seconds: $FilePath $($Arguments -join ' ')"
            }
        } else {
            $process.WaitForExit()
        }
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

function Invoke-LiveNativeProcess {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = ""
    )

    # Use PowerShell's native call operator for live-output commands.
    # Start-Process -Wait can remain attached to child handles on some Windows/cargo
    # combinations after cargo prints "Finished ...", which makes setup.bat look hung.
    # The call operator streams output live and returns as soon as the command exits.
    $resolvedPath = Resolve-NativeCommandPath -FilePath $FilePath
    $previousLocation = (Get-Location).Path

    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Set-Location -LiteralPath $WorkingDirectory
        }

        & $resolvedPath @Arguments
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) {
            return 0
        }

        return [int]$exitCode
    } finally {
        Set-Location -LiteralPath $previousLocation
    }
}

function Invoke-External {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = "",
        [switch]$AllowFailure,
        [switch]$PassThruExitCode,
        [switch]$LiveOutput,
        [int]$TimeoutSeconds = 0
    )

    Write-Info ("Running: {0} {1}" -f $FilePath, ($Arguments -join " "))

    if ($LiveOutput) {
        $exitCode = Invoke-LiveNativeProcess -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory

        if (($exitCode -ne 0) -and (-not $AllowFailure)) {
            throw "Command failed with exit code $($exitCode): $FilePath $($Arguments -join ' ')"
        }

        if ($PassThruExitCode) {
            return $exitCode
        }

        return
    }

    try {
        $result = Invoke-NativeProcess -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory -AllowFailure:$AllowFailure -TimeoutSeconds $TimeoutSeconds
    } catch {
        if ($AllowFailure) {
            Write-Warn $_.Exception.Message
            if ($PassThruExitCode) { return 124 }
            return
        }
        throw
    }

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
    $maxGb = 0

    if (Test-CommandExists "nvidia-smi") {
        try {
            $gpuInfo = Get-CommandOutput -FilePath "nvidia-smi" -Arguments @("--query-gpu=name,memory.total", "--format=csv,noheader,nounits")
            $lines = @($gpuInfo -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

            foreach ($line in $lines) {
                $parts = $line.Split(",")
                if ($parts.Count -ge 2) {
                    $name = $parts[0].Trim()
                    $memoryMbText = $parts[1].Trim()
                    $memoryMb = 0

                    if ([int]::TryParse($memoryMbText, [ref]$memoryMb)) {
                        $gb = [math]::Round(($memoryMb / 1024), 1)
                        Write-Info ("Detected NVIDIA GPU via nvidia-smi: {0} / approx. {1} GB VRAM" -f $name, $gb)

                        if ($gb -gt $maxGb) {
                            $maxGb = $gb
                        }
                    }
                }
            }

            if ($maxGb -gt 0) {
                return $maxGb
            }
        } catch {
            Write-Warn "nvidia-smi VRAM detection failed. Falling back to Windows video controller detection."
        }
    }

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
            Write-Info ("Detected GPU via Windows video controller: {0} / approx. {1} GB VRAM" -f $name, $gb)
        } else {
            Write-Info ("Detected GPU via Windows video controller: {0} / VRAM unknown" -f $name)
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
            Invoke-External -FilePath "ollama" -Arguments @("pull", $OllamaModel) -LiveOutput
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
        Invoke-External -FilePath "cargo" -Arguments @("clean") -WorkingDirectory $RustDir -LiveOutput
        $Global:BootstrapActions.Add("Cleaned Cargo target directory") | Out-Null
    }

    Invoke-External -FilePath "cargo" -Arguments $buildArgs -WorkingDirectory $RustDir -LiveOutput
    Write-Ok "Cargo build completed. Continuing with post-build setup."
    $Global:BootstrapActions.Add("Built Claw Code workspace") | Out-Null

    if ($RunTests) {
        Invoke-External -FilePath "cargo" -Arguments @("test", "--workspace") -WorkingDirectory $RustDir -LiveOutput
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

function Install-ClawStudio {
    Write-Step "Installing Claw Studio"

    $sourceStudioScript = Join-Path $PSScriptRoot "ClawStudio.ps1"
    $sourceLauncher = Join-Path $PSScriptRoot "launch-claw-studio.bat"
    $sourceLauncherVbs = Join-Path $PSScriptRoot "launch-claw-studio.vbs"
    $sourceNativeProject = Join-Path $PSScriptRoot "ClawStudioApp"
    $sourceNativeSolution = Join-Path $PSScriptRoot "ClawStudioApp.sln"
    $sourceNativeLauncher = Join-Path $PSScriptRoot "build-run-claw-studio.bat"
    $sourceIcon = Join-Path $PSScriptRoot "assets\ClawStudio.ico"

    if (-not (Test-Path -LiteralPath $sourceStudioScript)) {
        Write-Warn "Claw Studio script was not found next to the installer. Skipping GUI installation."
        return
    }

    if (-not (Test-Path -LiteralPath $sourceLauncher)) {
        Write-Warn "Claw Studio launcher was not found next to the installer. Skipping GUI installation."
        return
    }

    if (-not (Test-Path -LiteralPath $sourceLauncherVbs)) {
        Write-Warn "Claw Studio VBS launcher was not found next to the installer. Skipping GUI installation."
        return
    }

    if (-not (Test-Path -LiteralPath $sourceIcon)) {
        Write-Warn "Claw Studio icon was not found next to the installer. Shortcuts will use the default launcher icon."
    }

    $studioDir = Join-Path $env:LOCALAPPDATA "Programs\ClawCode\studio"
    $binDir = Join-Path $env:LOCALAPPDATA "Programs\ClawCode\bin"
    $targetStudioScript = Join-Path $studioDir "ClawStudio.ps1"
    $targetLauncherVbs = Join-Path $studioDir "launch-claw-studio.vbs"
    $targetNativeProject = Join-Path $studioDir "ClawStudioApp"
    $targetNativeSolution = Join-Path $studioDir "ClawStudioApp.sln"
    $targetNativeLauncher = Join-Path $studioDir "build-run-claw-studio.bat"
    $targetIcon = Join-Path $studioDir "ClawStudio.ico"
    $targetLauncher = Join-Path $binDir "claw-studio.bat"
    $desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Claw Studio.lnk"
    $programsDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    $startMenuShortcut = Join-Path $programsDir "Claw Studio.lnk"

    if (-not (Test-Path -LiteralPath $studioDir)) {
        New-Item -ItemType Directory -Path $studioDir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $programsDir)) {
        New-Item -ItemType Directory -Path $programsDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $sourceStudioScript -Destination $targetStudioScript -Force
    Copy-Item -LiteralPath $sourceLauncher -Destination $targetLauncher -Force
    Copy-Item -LiteralPath $sourceLauncherVbs -Destination $targetLauncherVbs -Force
    if (Test-Path -LiteralPath $sourceNativeProject) {
        if (Test-Path -LiteralPath $targetNativeProject) { Remove-Item -LiteralPath $targetNativeProject -Recurse -Force }
        Copy-Item -LiteralPath $sourceNativeProject -Destination $targetNativeProject -Recurse -Force
    }
    if (Test-Path -LiteralPath $sourceNativeSolution) {
        Copy-Item -LiteralPath $sourceNativeSolution -Destination $targetNativeSolution -Force
    }
    if (Test-Path -LiteralPath $sourceNativeLauncher) {
        Copy-Item -LiteralPath $sourceNativeLauncher -Destination $targetNativeLauncher -Force
    }
    if (Test-Path -LiteralPath $sourceIcon) {
        Copy-Item -LiteralPath $sourceIcon -Destination $targetIcon -Force
    }

    # Keep the native Visual Studio GUI in sync with the model that setup actually installed.
    # This prevents an old saved 14b selection from being reused on machines where setup
    # auto-selected/pulled 7b, which would otherwise produce: model 'qwen2.5-coder:14b' not found.
    try {
        $targetSettings = Join-Path $studioDir "settings.json"
        $studioModel = Get-ClawModelName -OllamaModelName $OllamaModel
        $settings = $null
        if (Test-Path -LiteralPath $targetSettings) {
            try { $settings = Get-Content -LiteralPath $targetSettings -Raw | ConvertFrom-Json } catch { $settings = $null }
        }
        if ($null -eq $settings) { $settings = [pscustomobject]@{} }

        function Set-StudioSettingValue {
            param([object]$Object, [string]$Name, [object]$Value)
            if ($Object.PSObject.Properties.Name -contains $Name) {
                $Object.$Name = $Value
            } else {
                Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value
            }
        }

        Set-StudioSettingValue -Object $settings -Name "ClawPath" -Value (Join-Path $binDir "claw.exe")
        if (-not ($settings.PSObject.Properties.Name -contains "ProjectPath") -or [string]::IsNullOrWhiteSpace([string]$settings.ProjectPath)) {
            Set-StudioSettingValue -Object $settings -Name "ProjectPath" -Value ([Environment]::GetFolderPath("UserProfile"))
        }
        Set-StudioSettingValue -Object $settings -Name "Model" -Value $studioModel
        if (-not ($settings.PSObject.Properties.Name -contains "PermissionMode") -or [string]::IsNullOrWhiteSpace([string]$settings.PermissionMode)) {
            Set-StudioSettingValue -Object $settings -Name "PermissionMode" -Value "workspace-write"
        }
        if (-not ($settings.PSObject.Properties.Name -contains "GitRemote")) {
            Set-StudioSettingValue -Object $settings -Name "GitRemote" -Value ""
        }

        $settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $targetSettings -Encoding UTF8
        Write-Ok "Configured Claw Studio model: $studioModel"
    } catch {
        Write-Warn "Could not write Claw Studio settings.json: $($_.Exception.Message)"
    }

    try {
        $wsh = New-Object -ComObject WScript.Shell

        foreach ($shortcutPath in @($desktopShortcut, $startMenuShortcut)) {
            $shortcut = $wsh.CreateShortcut($shortcutPath)
            # Use the visible batch launcher directly. The old wscript-based hidden launcher
            # made double-click failures look like "nothing happened" because build/runtime
            # errors were hidden together with the console window.
            $shortcut.TargetPath = $targetLauncher
            $shortcut.Arguments = ""
            $shortcut.WorkingDirectory = $binDir
            $shortcut.Description = "Launch Claw Studio"
            if (Test-Path -LiteralPath $targetIcon) {
                $shortcut.IconLocation = $targetIcon
            } else {
                $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,220"
            }
            $shortcut.Save()
        }

        $Global:BootstrapActions.Add("Created Claw Studio shortcuts") | Out-Null
        Write-Ok "Created desktop shortcut: $desktopShortcut"
        Write-Ok "Created Start menu shortcut: $startMenuShortcut"
    } catch {
        Write-Warn "Claw Studio was installed, but shortcut creation failed: $($_.Exception.Message)"
    }

    $Global:BootstrapActions.Add("Installed Claw Studio to $studioDir") | Out-Null
    Write-Ok "Installed Claw Studio legacy script: $targetStudioScript"
    Write-Ok "Installed Claw Studio native project: $targetNativeProject"
    Write-Ok "Installed launcher: $targetLauncher"
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


function Get-ClawModelName {
    param([string]$OllamaModelName)

    if ([string]::IsNullOrWhiteSpace($OllamaModelName)) {
        return ""
    }

    if ($OllamaModelName -match "^[^/]+/.+") {
        return $OllamaModelName
    }

    return "openai/$OllamaModelName"
}

function Verify-Claw {
    param([Parameter(Mandatory=$true)][string]$ClawBinary)

    Write-Step "Verifying Claw Code"

    Invoke-External -FilePath $ClawBinary -Arguments @("--version") -AllowFailure -TimeoutSeconds 20

    if ($SkipDoctor) {
        Write-Info "Skipping doctor check because -SkipDoctor was provided."
        return
    }

    $doctorExit = Invoke-External -FilePath $ClawBinary -Arguments @("doctor") -AllowFailure -PassThruExitCode -TimeoutSeconds 45
    if ($doctorExit -ne 0) {
        Write-Warn "claw doctor returned exit code $doctorExit. This is often caused by a missing API key or backend configuration."
    } else {
        Write-Ok "claw doctor completed successfully."
    }

    if ($RunPromptTest -and -not $NoOllama) {
        $clawModel = Get-ClawModelName -OllamaModelName $OllamaModel
        $promptExit = Invoke-External -FilePath $ClawBinary -Arguments @("--model", $clawModel, "prompt", "Say hello in one short sentence.") -AllowFailure -PassThruExitCode -TimeoutSeconds 60
        if ($promptExit -ne 0) {
            Write-Warn "Ollama prompt test returned exit code $promptExit. Check model name and local Ollama server."
        }
    } elseif (-not $NoOllama) {
        Write-Info "Skipping the automatic Ollama prompt test. Use Claw Studio or a manual claw --model ... prompt command when you are ready."
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
    Write-Host "  claw-studio.bat"
    Write-Host "  ollama list"

    if (-not $NoOllama) {
        $clawModel = Get-ClawModelName -OllamaModelName $OllamaModel
        Write-Host ("  claw --model {0} prompt ""summarize this folder""" -f $clawModel)
    } else {
        Write-Host "  claw prompt ""summarize this folder"""
    }

    Write-Host ""
    Write-Host "If PATH changes are not visible in an old terminal, open a new PowerShell window or use the full path:"
    Write-Host ("  ""{0}"" --version" -f (Join-Path $env:LOCALAPPDATA "Programs\ClawCode\bin\claw.exe"))
}

try {
    Write-Host "Claw Code Local Ollama Bootstrap for Windows PowerShell 5.1 - v12 studio"
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
    Install-ClawStudio
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
