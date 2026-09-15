foreach($Model in $Config.models)
{
    $TargetPath =
        Join-Path `
        $ModelsRoot `
        $Model.targetFolder

    New-Item `
        -ItemType Directory `
        -Path $TargetPath `
        -Force | Out-Null

    Write-Host ""
    Write-Host "Downloading $($Model.name)"

    huggingface-cli download `
        $Model.repo `
        --local-dir $TargetPath
}