# ==================================================
# Install ComfyUI Nodes from nodes.json
# ==================================================

$InstallRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
$AIRoot = Split-Path $InstallRoot -Parent
$ComfyUIPath = Join-Path $AIRoot "ComfyUI"

$Python = Join-Path $ComfyUIPath "venv\Scripts\python.exe"
$NodeFile = Join-Path $InstallRoot "nodes.json"

if (-not (Test-Path $NodeFile)) {
    throw "nodes.json not found."
}

$Config = Get-Content $NodeFile -Raw | ConvertFrom-Json

$Repositories = $Config.repositories

if ($null -eq $Repositories) {
    throw "nodes.json does not contain a repositories collection."
}

$NodeRepos = @{}

foreach ($repo in $Repositories) {
    if ($null -eq $repo) {
        continue
    }

    $name = $repo.name
    $url = $repo.url

    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "A repository entry in nodes.json is missing a name."
    }

    if ([string]::IsNullOrWhiteSpace($url)) {
        throw "Repository '$name' is missing a URL in nodes.json."
    }

    $NodeRepos[$name] = $url
}

function Install-Requirements {
    param(
        [string]$NodePath
    )

    $Requirements = Join-Path $NodePath "requirements.txt"

    if (Test-Path $Requirements) {
        Write-Host ""
        Write-Host "Installing requirements for:"
        Write-Host $NodePath

        & $Python -m pip install -r $Requirements
    }
}

foreach ($Node in $NodeRepos.Keys) {
    $Repo = $NodeRepos[$Node]
    $Target = Join-Path "$ComfyUIPath\custom_nodes" $Node

    if (-not (Test-Path $Target)) {
        Write-Host ""
        Write-Host "Installing $Node"

        git clone $Repo $Target
    }
    else {
        Write-Host ""
        Write-Host "$Node already installed"

        Push-Location $Target
        git pull --ff-only
        Pop-Location
    }

    Install-Requirements $Target
}

Write-Host ""
Write-Host "Node installation complete."
