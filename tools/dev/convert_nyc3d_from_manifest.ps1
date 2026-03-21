param(
    [string]$ManifestPath = "data/raw/nyc3d/manifest.json",
    [switch]$Force,
    [int]$Limit = 0
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

$converter = "tools/pipeline/node/convert_3dm_to_glb.js"
if (-not (Test-Path $converter)) {
    throw "Converter script not found: $converter"
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
if (-not $manifest.entries) {
    throw "Manifest has no entries: $ManifestPath"
}

$processed = 0
$converted = 0
$skipped = 0
$failed = 0

foreach ($entry in $manifest.entries) {
    if ($Limit -gt 0 -and $processed -ge $Limit) {
        break
    }
    $processed += 1

    $sourcePath = [string]$entry.source_path
    $targetPath = [string]$entry.glb_path
    $code = [string]$entry.community_district
    if ([string]::IsNullOrWhiteSpace($sourcePath) -or [string]::IsNullOrWhiteSpace($targetPath)) {
        Write-Warning "[NYC3D] SKIP $code missing source_path/glb_path"
        $skipped += 1
        continue
    }

    if (-not (Test-Path $sourcePath)) {
        Write-Warning "[NYC3D] SKIP $code source not found: $sourcePath"
        $skipped += 1
        continue
    }

    if ((Test-Path $targetPath) -and (-not $Force)) {
        Write-Host "[NYC3D] SKIP $code target exists: $targetPath"
        $skipped += 1
        continue
    }

    Write-Host "[NYC3D] CONVERT $code $sourcePath -> $targetPath"
    try {
        node $converter $sourcePath $targetPath
        if ($LASTEXITCODE -ne 0) {
            throw "Converter exited with code $LASTEXITCODE"
        }
        $converted += 1
    } catch {
        Write-Warning "[NYC3D] FAIL $code : $_"
        $failed += 1
    }
}

Write-Host "[NYC3D] Summary processed=$processed converted=$converted skipped=$skipped failed=$failed"
if ($failed -gt 0) {
    exit 1
}
