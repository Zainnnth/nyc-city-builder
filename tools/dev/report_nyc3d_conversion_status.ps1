param(
    [string]$ManifestPath = "data/raw/nyc3d/manifest.json",
    [string]$OutPath = "tools/dev/benchmarks/nyc3d_conversion_status.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
if (-not $manifest.entries) {
    throw "Manifest has no entries: $ManifestPath"
}

$results = @()
$converted = 0
$pending = 0
$missingSource = 0

foreach ($entry in $manifest.entries) {
    $cd = [string]$entry.community_district
    $sourcePath = [string]$entry.source_path
    $glbPath = [string]$entry.glb_path

    $sourceExists = Test-Path $sourcePath
    $glbExists = Test-Path $glbPath
    $status = "pending"
    if (-not $sourceExists) {
        $status = "missing_source"
        $missingSource += 1
    } elseif ($glbExists) {
        $status = "converted"
        $converted += 1
    } else {
        $pending += 1
    }

    $glbBytes = 0
    if ($glbExists) {
        $glbBytes = (Get-Item $glbPath).Length
    }

    $results += [PSCustomObject]@{
        community_district = $cd
        status = $status
        source_path = $sourcePath
        source_exists = $sourceExists
        glb_path = $glbPath
        glb_exists = $glbExists
        glb_size_bytes = $glbBytes
    }
}

$summary = [PSCustomObject]@{
    total = $manifest.entries.Count
    converted = $converted
    pending = $pending
    missing_source = $missingSource
    converted_pct = if ($manifest.entries.Count -gt 0) { [Math]::Round(($converted * 100.0) / $manifest.entries.Count, 1) } else { 0.0 }
}

$payload = [PSCustomObject]@{
    generated_utc = [DateTime]::UtcNow.ToString("o")
    manifest_path = $ManifestPath
    summary = $summary
    entries = $results
}

$outDir = Split-Path -Parent $OutPath
if (-not [string]::IsNullOrWhiteSpace($outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}
$payload | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $OutPath

Write-Host ("[NYC3D] total={0} converted={1} pending={2} missing_source={3} ({4}%)" -f `
    $summary.total, $summary.converted, $summary.pending, $summary.missing_source, $summary.converted_pct)
Write-Host "[NYC3D] Report -> $OutPath"
