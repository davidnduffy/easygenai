# =================================
# AI Workstation Setup
# Tested with RTX 5070 / ComfyUI
# =================================

$Root = Split-Path $PSScriptRoot -Parent

# ------------------------------------------------
# Required Versions
# ------------------------------------------------

$MinPythonVersion = [Version]"3.12.0"
$MinGitVersion = [Version]"2.45.0"

# ------------------------------------------------
# Helpers
# ------------------------------------------------

function Confirm-Upgrade {
    param(
        [string]$Software,
        [Version]$CurrentVersion,
        [Version]$RequiredVersion
    )

    Write-Host ""
    Write-Host "$Software version $CurrentVersion detected."
    Write-Host "$RequiredVersion or newer is recommended."
    Write-Host ""

    $response = Read-Host "Upgrade $Software? (Y/N)"
    return $response -match "^[Yy]"
}

function Get-PythonVersion {
    try {
        $ver = python --version 2>&1

        if ($ver -match "(\d+\.\d+\.\d+)") {
            return [Version]$matches[1]
        }
    }
    catch {
    }

    return $null
}

function Get-GitVersion {
    try {
        $ver = git --version

        if ($ver -match "(\d+\.\d+\.\d+)") {
            return [Version]$matches[1]
        }
    }
    catch {
    }

    return $null
}

function Install-WithWinget {
    param(
        [string]$PackageId
    )

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "Winget not installed."
    }

    winget install `
        --id $PackageId `
        --exact `
        --accept-package-agreements `
        --accept-source-agreements

    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User') + ';' + $env:Path
}

function Resolve-PythonExecutable {
    $candidates = @(
        (Get-Command py -ErrorAction SilentlyContinue).Source,
        (Get-Command python -ErrorAction SilentlyContinue).Source,
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:ProgramFiles 'Python312\python.exe'),
        'python'
    )

    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        if (Test-Path $candidate -PathType Leaf -ErrorAction SilentlyContinue) {
            return $candidate
        }
    }

    return $null
}

function Resolve-VenvTool {
    param(
        [string]$ToolName,
        [string]$VenvRoot
    )

    $VenvBin = Join-Path $VenvRoot 'Scripts'
    $Candidates = @(
        (Join-Path $VenvBin "$ToolName.exe"),
        (Join-Path $VenvBin $ToolName),
        (Join-Path $VenvBin "$ToolName.cmd")
    )

    foreach ($Candidate in $Candidates) {
        if (Test-Path $Candidate -PathType Leaf -ErrorAction SilentlyContinue) {
            return $Candidate
        }
    }

    return $null
}

# ------------------------------------------------
# Python Check
# ------------------------------------------------

$PythonVersion = Get-PythonVersion

if (-not $PythonVersion) {
    Write-Host ""
    Write-Host "Python not found."
    Write-Host "Installing Python 3.12..."
    Install-WithWinget "Python.Python.3.12"
}
elseif ($PythonVersion -lt $MinPythonVersion) {
    if (Confirm-Upgrade "Python" $PythonVersion $MinPythonVersion) {
        Install-WithWinget "Python.Python.3.12"
    }
    else {
        Write-Warning "Continuing with older Python."
    }
}
else {
    Write-Host "Python $PythonVersion OK"
}

# ------------------------------------------------
# Git Check
# ------------------------------------------------

$GitVersion = Get-GitVersion

if (-not $GitVersion) {
    Write-Host ""
    Write-Host "Git not found."
    Write-Host "Installing Git..."
    Install-WithWinget "Git.Git"
}
elseif ($GitVersion -lt $MinGitVersion) {
    if (Confirm-Upgrade "Git" $GitVersion $MinGitVersion) {
        Install-WithWinget "Git.Git"
    }
    else {
        Write-Warning "Continuing with older Git."
    }
}
else {
    Write-Host "Git $GitVersion OK"
}

# Refresh PATH for current session
$env:Path += ";C:\Program Files\Git\bin"
$env:Path += ";$env:LOCALAPPDATA\Programs\Python\Python312"
$env:Path += ";$env:LOCALAPPDATA\Programs\Python\Python312\Scripts"

$PythonExe = Resolve-PythonExecutable
if (-not $PythonExe) {
    throw "Python 3.12 was not found after installation."
}

# ------------------------------------------------
# AI Setup
# ------------------------------------------------

$ComfyUIPath = Join-Path $Root "ComfyUI"
$ModelsPath = Join-Path $Root "Models"
$LaunchPath = Join-Path $Root "Launch"

Write-Host ""
Write-Host "Creating folders..."

$folders = @(
    $ComfyUIPath,
    $ModelsPath,
    $LaunchPath,
    (Join-Path $ModelsPath 'Checkpoints'),
    (Join-Path $ModelsPath 'Flux'),
    (Join-Path $ModelsPath 'Loras'),
    (Join-Path $ModelsPath 'ControlNet'),
    (Join-Path $ModelsPath '3D'),
    (Join-Path $ModelsPath 'VAE')
)

foreach ($folder in $folders) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}

# ------------------------------------------------
# Validate Tools
# ------------------------------------------------

function Test-Command {
    param(
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name not installed."
    }
}

Write-Host "Checking prerequisites..."
Test-Command git

# ------------------------------------------------
# Clone ComfyUI
# ------------------------------------------------

if (-not (Test-Path "$ComfyUIPath\.git")) {
    Write-Host "Cloning ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git $ComfyUIPath
}
else {
    Write-Host "ComfyUI already exists."
}

# ------------------------------------------------
# Python VENV
# ------------------------------------------------

if (-not (Test-Path "$ComfyUIPath\venv")) {
    Write-Host "Creating Python environment..."
    & $PythonExe -m venv "$ComfyUIPath\venv"
}

$Python = "$ComfyUIPath\venv\Scripts\python.exe"

# ------------------------------------------------
# Upgrade Pip
# ------------------------------------------------

& $Python -m pip install --upgrade pip

# ------------------------------------------------
# Install ComfyUI Requirements
# ------------------------------------------------

Write-Host "Installing ComfyUI requirements..."
& $Python -m pip install -r (Join-Path $ComfyUIPath 'requirements.txt')

# ------------------------------------------------
# Install PyTorch CUDA
# ------------------------------------------------

Write-Host "Installing CUDA PyTorch..."

& $Python -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# ------------------------------------------------
# Install ComfyUI-Manager
# ------------------------------------------------

Write-Host ""
Write-Host "Installing ComfyUI-Manager..."

$ManagerPath = Join-Path $ComfyUIPath 'custom_nodes\ComfyUI-Manager'

if (-not (Test-Path $ManagerPath)) {
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git $ManagerPath
}
else {
    Write-Host "ComfyUI-Manager already installed."
}

if (Test-Path $ManagerPath) {
    Write-Host ""
    Write-Host "ComfyUI-Manager installed"
}
else {
    throw "ComfyUI-Manager installation failed."
}

# ------------------------------------------------
# Install ComfyUI-Manager Requirements
# ------------------------------------------------

$ManagerRequirements = Join-Path $ManagerPath 'requirements.txt'

if (Test-Path $ManagerRequirements) {
    Write-Host ""
    Write-Host "Installing ComfyUI-Manager dependencies..."
    & $Python -m pip install -r $ManagerRequirements
}

# ------------------------------------------------
# Install configured nodes
# ------------------------------------------------

Write-Host ""
Write-Host "Installing configured custom nodes..."

$NodeInstaller = Join-Path $PSScriptRoot 'install_nodes.ps1'

if (Test-Path $NodeInstaller) {
    & $NodeInstaller
}
else {
    Write-Warning "install_nodes.ps1 not found."
}

# ------------------------------------------------
# extra_model_paths.yaml
# ------------------------------------------------

$YamlLines = @(
    'easygenai:',
    '  base_path: ../Models',
    '  checkpoints: Checkpoints',
    '  loras: Loras',
    '  controlnet: ControlNet',
    '  diffusion_models: Flux',
    '  vae: VAE'
)

$YamlPath = Join-Path $ComfyUIPath 'extra_model_paths.yaml'
$YamlLines | Set-Content -Path $YamlPath -Encoding UTF8

# ------------------------------------------------
# HuggingFace CLI
# ------------------------------------------------

Write-Host "Installing HuggingFace CLI..."
& $Python -m pip install --upgrade "huggingface_hub[cli]>=1.5.0,<2.0"

Write-Host ""
Write-Host "If this is your first install,"
Write-Host "login to Hugging Face."

$HfCli = Resolve-VenvTool -ToolName 'hf' -VenvRoot (Join-Path $ComfyUIPath 'venv')

if ($HfCli) {
    & $HfCli auth login
}
else {
    Write-Warning "hf CLI not found in venv. Trying module fallback..."
    & $Python -m huggingface_hub.commands.hf auth login
}

# ------------------------------------------------
# Install Models
# ------------------------------------------------

Write-Host ""
Write-Host "Installing models..."

$ModelInstaller = Join-Path $PSScriptRoot 'install_models.ps1'
& $ModelInstaller

# ------------------------------------------------
# Launcher
# ------------------------------------------------

$LauncherPath = Join-Path $LaunchPath 'Launch_ComfyUI.bat'
$LauncherLines = @(
    '@echo off',
    'cd /d "%~dp0..\ComfyUI" || exit /b 1',
    '"venv\Scripts\python.exe" main.py'
)

[System.IO.File]::WriteAllLines($LauncherPath, $LauncherLines, [System.Text.Encoding]::ASCII)

Write-Host ""
Write-Host "Setup Complete"
Write-Host ""
Write-Host "Launch:"
Write-Host $LauncherPath