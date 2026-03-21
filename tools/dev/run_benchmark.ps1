param(
	[string]$GodotExe = "C:\Users\ps450\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.1-stable_win64.exe",
	[int]$Steps = 320,
	[int]$Warmup = 48,
	[int]$Seed = 1998,
	[string]$Scene = "res://scenes/benchmark.tscn",
	[string]$Out = "benchmark_last.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $GodotExe)) {
	Write-Error "Godot executable not found at: $GodotExe"
	exit 2
}

Write-Host "[BENCH] Running benchmark harness..."
& $GodotExe --headless --path . --script res://scripts/benchmark_harness.gd -- "--bench-scene=$Scene" "--bench-steps=$Steps" "--bench-warmup=$Warmup" "--bench-seed=$Seed" "--bench-out=$Out"
$code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
if ($code -ne 0) {
	Write-Error "Benchmark harness failed with exit code $code"
	exit $code
}

Write-Host "[BENCH] PASS"
exit 0
