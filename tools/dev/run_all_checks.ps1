param(
	[string]$GodotExe = "C:\Users\ps450\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.1-stable_win64.exe"
)

$ErrorActionPreference = "Stop"

Write-Host "[CHECKS] Starting full local checks..."

if (-not (Test-Path $GodotExe)) {
	Write-Error "Godot executable not found at: $GodotExe"
	exit 2
}

Write-Host "[CHECKS] Smoke harness..."
powershell -ExecutionPolicy Bypass -File tools/smoke/run_smoke.ps1 -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) {
	Write-Error "Smoke checks failed with exit code $LASTEXITCODE"
	exit $LASTEXITCODE
}

Write-Host "[CHECKS] PASS"
exit 0
