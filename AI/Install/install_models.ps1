# ============================================================
# install_models.ps1
# ============================================================

$InstallRoot =
    Split-Path $MyInvocation.MyCommand.Path -Parent

$AIRoot =
    Split-Path $InstallRoot -Parent

$ModelsRoot =
    Join-Path $AIRoot "Models"

$ComfyUIRoot =
    Join-Path $AIRoot "ComfyUI"

$ModelsJson =
    Join-Path $InstallRoot "models.json"

if(-not (Test-Path $ModelsJson))
{
    throw "models.json not found."
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

function Get-RepoRevision {
    param(
        [string]$RepoId,
        [string]$PythonExe
    )

    try {
        $SafeRepoId = $RepoId.Replace('"', '\"')
        $Script = @"
import json
from huggingface_hub import HfApi
repo = "$SafeRepoId"
info = HfApi().model_info(repo)
print(info.sha or '')
"@

        $Output = & $PythonExe -c $Script 2>$null
        if ($LASTEXITCODE -eq 0 -and $Output) {
            return ($Output | Select-Object -First 1).Trim()
        }
    }
    catch {
    }

    return $null
}

function Get-ModelMetadataPath {
    param(
        [string]$TargetFolder
    )

    return Join-Path $TargetFolder '.easygenai-model.json'
}

function Save-ModelMetadata {
    param(
        [string]$TargetFolder,
        [string]$RepoId,
        [string]$Revision
    )

    $MetadataPath = Get-ModelMetadataPath -TargetFolder $TargetFolder
    $Payload = [ordered]@{
        repo = $RepoId
        revision = $Revision
    }

    $Payload | ConvertTo-Json | Set-Content -Path $MetadataPath -Encoding UTF8
}

$Config =
    Get-Content $ModelsJson -Raw |
    ConvertFrom-Json

function Download-HuggingFaceModel
{
    param(
        $Model
    )

    $TargetFolder =
        Join-Path `
        $ModelsRoot `
        $Model.targetFolder

    New-Item `
        -ItemType Directory `
        -Path $TargetFolder `
        -Force | Out-Null

    Write-Host ""
    Write-Host "====================================="
    Write-Host "Model: $($Model.name)"
    Write-Host "Repo : $($Model.repo)"
    Write-Host "Target: $TargetFolder"
    Write-Host "====================================="

    if($Model.requiresLicenseAcceptance)
    {
        Write-Host ""
        Write-Host "NOTE:"
        Write-Host "This model requires HuggingFace"
        Write-Host "license acceptance."
        Write-Host ""
    }

    $VenvPython = Join-Path $ComfyUIRoot 'venv\Scripts\python.exe'
    $HfCli = Resolve-VenvTool -ToolName 'hf' -VenvRoot (Join-Path $ComfyUIRoot 'venv')
    $MetadataPath = Get-ModelMetadataPath -TargetFolder $TargetFolder

    if (Test-Path $MetadataPath) {
        try {
            $Metadata = Get-Content $MetadataPath -Raw | ConvertFrom-Json
            $CurrentRevision = Get-RepoRevision -RepoId $Model.repo -PythonExe $VenvPython

            if ($Metadata.repo -eq $Model.repo -and $CurrentRevision -and $Metadata.revision -eq $CurrentRevision) {
                Write-Host "Skipping $($Model.name): model revision is already installed."
                return
            }
        }
        catch {
        }
    }

    $FilesInTarget = Get-ChildItem -Path $TargetFolder -Force -ErrorAction SilentlyContinue
    if ($FilesInTarget -and $FilesInTarget.Count -gt 0) {
        $CurrentRevision = Get-RepoRevision -RepoId $Model.repo -PythonExe $VenvPython
        if ($CurrentRevision) {
            $Metadata = Get-Content $MetadataPath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($Metadata -and $Metadata.repo -eq $Model.repo -and $Metadata.revision -eq $CurrentRevision) {
                Write-Host "Skipping $($Model.name): target folder already matches current revision."
                return
            }
        }
    }

    $LastError = $null
    for ($Attempt = 1; $Attempt -le 3; $Attempt++) {
        try {
            if ($HfCli) {
                & $HfCli download $Model.repo --repo-type model --local-dir $TargetFolder
            }
            else {
                & $VenvPython -m huggingface_hub.commands.hf download $Model.repo --repo-type model --local-dir $TargetFolder
            }

            $FinalRevision = Get-RepoRevision -RepoId $Model.repo -PythonExe $VenvPython
            if ($FinalRevision) {
                Save-ModelMetadata -TargetFolder $TargetFolder -RepoId $Model.repo -Revision $FinalRevision
            }

            return
        }
        catch {
            $LastError = $_
            if ($Attempt -lt 3) {
                Write-Warning "Download attempt $Attempt failed for $($Model.name). Retrying..."
                Start-Sleep -Seconds 5
            }
        }
    }

    throw $LastError
}

# ----------------------------------------------------
# Verify HuggingFace CLI
# ----------------------------------------------------

$VenvPython = Join-Path $ComfyUIRoot 'venv\Scripts\python.exe'
$HfCli = Resolve-VenvTool -ToolName 'hf' -VenvRoot (Join-Path $ComfyUIRoot 'venv')

if (-not $HfCli -and -not (Test-Path $VenvPython)) {
    throw @"

hf CLI not installed.

Run:

pip install huggingface_hub[cli]

and then:

hf auth login

"@
}

try
{
    if ($HfCli) {
        & $HfCli --version | Out-Null
    }
    else {
        & $VenvPython -m huggingface_hub.commands.hf --version | Out-Null
    }
}
catch
{
    throw @"

hf CLI not installed or not available in the current environment.

Run:

pip install huggingface_hub[cli]

and then:

hf auth login

"@
}

# ----------------------------------------------------
# Sort by installPriority
# ----------------------------------------------------

$ModelList =
    $Config.models |
    Sort-Object installPriority

foreach($Model in $ModelList)
{
    try
    {
        Download-HuggingFaceModel $Model
    }
    catch
    {
        Write-Warning ""
        Write-Warning "Failed:"
        Write-Warning $Model.name
        Write-Warning $_
    }
}

Write-Host ""
Write-Host "====================================="
Write-Host "Model Installation Complete"
Write-Host "====================================="
