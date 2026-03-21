param(
    [string]$InputManifest = "data/raw/nyc3d/manifest.json",
    [string]$DatasetName = "",
    [string]$LicenseId = "NYC_OPEN_DATA"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($DatasetName)) {
    $DatasetName = "nyc3d_partial_" + (Get-Date -Format "yyyyMMdd")
}

python tools/pipeline/scripts/prepare_nyc3d_mesh_manifest.py `
    --input-manifest $InputManifest `
    --dataset-name $DatasetName `
    --license-id $LicenseId `
    --skip-missing-glb `
    --skip-provenance

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "[NYC3D] Partial manifests refreshed from currently converted .glb files."
