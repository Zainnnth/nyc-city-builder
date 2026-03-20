param(
	[string]$GodotExe = "C:\Users\ps450\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.1-stable_win64.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $GodotExe)) {
	Write-Error "Godot executable not found at: $GodotExe"
	exit 2
}

Write-Host "[SMOKE] Running project load check..."
& $GodotExe --headless --path . --quit
$loadCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
if ($loadCode -ne 0) {
	Write-Error "Project load check failed with exit code $loadCode"
	exit $loadCode
}

Write-Host "[SMOKE] Running smoke harness..."
& $GodotExe --headless --path . --script res://scripts/smoke_harness.gd
$smokeCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
if ($smokeCode -ne 0) {
	Write-Error "Smoke harness failed with exit code $smokeCode"
	exit $smokeCode
}

Write-Host "[SMOKE] PASS"
exit 0
