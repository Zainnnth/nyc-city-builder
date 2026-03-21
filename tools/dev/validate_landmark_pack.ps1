param(
	[string]$Manifest = "data/runtime/landmark_assets.json"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
if ([System.IO.Path]::IsPathRooted($Manifest)) {
	$manifestAbs = $Manifest
} else {
	$manifestAbs = Join-Path $repoRoot $Manifest
}

if (-not (Test-Path $manifestAbs)) {
	Write-Error "Landmark manifest not found: $manifestAbs"
	exit 2
}

$payload = Get-Content $manifestAbs -Raw | ConvertFrom-Json
$assets = $payload.assets
if ($null -eq $assets) {
	Write-Error "Manifest missing 'assets' map: $manifestAbs"
	exit 2
}

$total = 0
$ready = 0
$rows = @()
foreach ($prop in $assets.PSObject.Properties) {
	$total += 1
	$assetId = [string]$prop.Name
	$asset = $prop.Value
	$scenePath = [string]$asset.scene_path
	$fallbackPath = [string]$asset.fallback_scene_path

	$sceneRes = if ($scenePath -like "res://*") { Join-Path $repoRoot ($scenePath -replace "^res://", "" -replace "/", "\") } else { $scenePath }
	$fallbackRes = if ($fallbackPath -like "res://*") { Join-Path $repoRoot ($fallbackPath -replace "^res://", "" -replace "/", "\") } else { $fallbackPath }

	$sceneExists = $false
	if ($sceneRes -ne "") {
		$sceneExists = Test-Path $sceneRes
	}
	$fallbackExists = $false
	if ($fallbackRes -ne "") {
		$fallbackExists = Test-Path $fallbackRes
	}

	$status = "MISSING"
	if ($sceneExists) {
		$status = "READY"
		$ready += 1
	} elseif ($fallbackExists) {
		$status = "FALLBACK"
	}

	$rows += [pscustomobject]@{
		asset_id = $assetId
		status = $status
		scene_path = $scenePath
		fallback_scene_path = $fallbackPath
	}
}

$rows = $rows | Sort-Object asset_id
foreach ($row in $rows) {
	Write-Host ("[LANDMARK] {0,-24} {1,-8} scene={2}" -f $row.asset_id, $row.status, $row.scene_path)
}

$fallbackCount = ($rows | Where-Object { $_.status -eq "FALLBACK" }).Count
$missingCount = ($rows | Where-Object { $_.status -eq "MISSING" }).Count
$readyPct = if ($total -gt 0) { [math]::Round((100.0 * $ready / $total), 1) } else { 0.0 }

Write-Host ("[LANDMARK] Summary: ready={0}/{1} ({2}%), fallback={3}, missing={4}" -f $ready, $total, $readyPct, $fallbackCount, $missingCount)

if ($missingCount -gt 0) {
	Write-Warning "Some assets have neither mesh nor fallback scene configured."
	exit 1
}
exit 0
