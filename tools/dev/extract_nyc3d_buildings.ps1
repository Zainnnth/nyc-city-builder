param(
    [string]$ManifestPath = "data/raw/nyc3d/manifest.json",
    [string]$DistrictCode = "",
    [int]$MaxBuildingsPerDistrict = 0,
    [switch]$WriteGlb
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

$extractor = "tools/pipeline/node/extract_buildings_from_3dm.js"
if (-not (Test-Path $extractor)) {
    throw "Extractor not found: $extractor"
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
if (-not $manifest.entries) {
    throw "Manifest has no entries: $ManifestPath"
}

$districtMapPath = "tools/pipeline/config/nyc3d_community_district_map.json"
$districtProfilesPath = "tools/pipeline/config/district_profiles.json"
$districtMap = if (Test-Path $districtMapPath) { Get-Content $districtMapPath -Raw | ConvertFrom-Json } else { $null }
$districtProfiles = if (Test-Path $districtProfilesPath) { Get-Content $districtProfilesPath -Raw | ConvertFrom-Json } else { $null }

function Resolve-DistrictId([string]$code) {
    if ($null -eq $districtMap) { return "outer_borough_mix" }
    if ($districtMap.exact_map.PSObject.Properties.Name -contains $code) {
        return [string]$districtMap.exact_map.$code
    }
    $borough = if ($code.Length -ge 2) { $code.Substring(0,2) } else { "" }
    if ($districtMap.borough_fallback_map.PSObject.Properties.Name -contains $borough) {
        return [string]$districtMap.borough_fallback_map.$borough
    }
    return [string]$districtMap.default_district_id
}

function Resolve-StyleProfile([string]$districtId) {
    if ($null -eq $districtProfiles) { return "default_mixed" }
    foreach ($d in $districtProfiles.districts) {
        if ([string]$d.district_id -eq $districtId) {
            return [string]$d.style_profile
        }
    }
    return "default_mixed"
}

$processed = 0
$extracted = 0
$failed = 0
$skipped = 0

foreach ($entry in $manifest.entries) {
    $code = [string]$entry.community_district
    if (-not [string]::IsNullOrWhiteSpace($DistrictCode) -and $code -ne $DistrictCode.ToUpper()) {
        continue
    }
    $sourcePath = [string]$entry.source_path
    if (-not (Test-Path $sourcePath)) {
        Write-Warning "[NYC3D-BLDG] SKIP $code missing source: $sourcePath"
        $skipped += 1
        continue
    }

    $districtId = Resolve-DistrictId $code
    $styleProfile = Resolve-StyleProfile $districtId
    $outCatalog = "data/processed/nyc3d_buildings/$code/catalog.json"
    $outGlbDir = "assets/buildings/nyc3d/buildings/$code"

    $args = @(
        $extractor,
        "--input", $sourcePath,
        "--district-code", $code,
        "--district-id", $districtId,
        "--style-profile", $styleProfile,
        "--out-catalog", $outCatalog
    )
    if ($MaxBuildingsPerDistrict -gt 0) {
        $args += @("--max-buildings", "$MaxBuildingsPerDistrict")
    }
    if ($WriteGlb) {
        $args += @("--write-glb", "--out-glb-dir", $outGlbDir)
    }

    Write-Host "[NYC3D-BLDG] EXTRACT $code -> $outCatalog"
    $processed += 1
    try {
        node @args
        if ($LASTEXITCODE -ne 0) {
            throw "Extractor exited with code $LASTEXITCODE"
        }
        $extracted += 1
    } catch {
        Write-Warning "[NYC3D-BLDG] FAIL $code : $_"
        $failed += 1
    }
}

Write-Host "[NYC3D-BLDG] Summary processed=$processed extracted=$extracted skipped=$skipped failed=$failed"
if ($failed -gt 0) {
    exit 1
}
