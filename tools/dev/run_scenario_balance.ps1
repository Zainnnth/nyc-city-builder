param(
	[string]$GodotExe = "C:\Users\ps450\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.1-stable_win64.exe",
	[int]$Steps = 180,
	[string]$Seeds = "",
	[string]$Out = "tools/dev/benchmarks/scenario_balance_report.json",
	[switch]$EnforceTargets,
	[string]$TargetsConfig = "tools/dev/benchmarks/scenario_winrate_targets.json"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
if (Test-Path $GodotExe) {
	$godotExeResolved = (Resolve-Path $GodotExe).Path
} else {
	$godotCmd = Get-Command $GodotExe -ErrorAction SilentlyContinue
	if ($null -eq $godotCmd) {
		Write-Error "Godot executable not found as path or command: $GodotExe"
		exit 2
	}
	$godotExeResolved = $godotCmd.Source
}
if ([System.IO.Path]::IsPathRooted($Out)) {
	$outAbs = $Out
} else {
	$outAbs = Join-Path $repoRoot $Out
}
if ([System.IO.Path]::IsPathRooted($TargetsConfig)) {
	$targetsConfigAbs = $TargetsConfig
} else {
	$targetsConfigAbs = Join-Path $repoRoot $TargetsConfig
}

$outDir = Split-Path -Path $outAbs -Parent
if ($outDir -ne "" -and -not (Test-Path $outDir)) {
	New-Item -ItemType Directory -Path $outDir | Out-Null
}

Write-Host "[BALANCE] Running scenario balance harness..."
if ($Seeds -ne "") {
	& $godotExeResolved --headless --path . --script res://scripts/scenario_balance_harness.gd -- "--steps=$Steps" "--seeds=$Seeds" "--out=$outAbs"
} else {
	& $godotExeResolved --headless --path . --script res://scripts/scenario_balance_harness.gd -- "--steps=$Steps" "--out=$outAbs"
}
$code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
if ($code -ne 0) {
	Write-Error "Scenario balance harness failed with exit code $code"
	exit $code
}

if ($EnforceTargets) {
	if (-not (Test-Path $outAbs)) {
		Write-Error "Scenario report missing for target enforcement: $outAbs"
		exit 3
	}
	if (-not (Test-Path $targetsConfigAbs)) {
		Write-Error "Scenario target config missing: $targetsConfigAbs"
		exit 3
	}
	$report = Get-Content $outAbs -Raw | ConvertFrom-Json
	$targets = Get-Content $targetsConfigAbs -Raw | ConvertFrom-Json
	$defaultMin = [double]$targets.default.min_win_rate
	$defaultMax = [double]$targets.default.max_win_rate
	$failures = @()
	foreach ($row in $report.summary_by_card) {
		$cardId = [string]$row.card_id
		$winRate = [double]$row.win_rate
		$minRate = $defaultMin
		$maxRate = $defaultMax
		if ($null -ne $targets.cards.$cardId) {
			$minRate = [double]$targets.cards.$cardId.min_win_rate
			$maxRate = [double]$targets.cards.$cardId.max_win_rate
		}
		Write-Host ("[BALANCE] {0} win_rate={1} target=[{2}, {3}]" -f $cardId, [math]::Round($winRate, 4), $minRate, $maxRate)
		if ($winRate -lt $minRate -or $winRate -gt $maxRate) {
			$failures += ("{0} win_rate {1} outside [{2}, {3}]" -f $cardId, [math]::Round($winRate, 4), $minRate, $maxRate)
		}
	}
	if ($failures.Count -gt 0) {
		foreach ($failure in $failures) {
			Write-Error ("[BALANCE] Target violation: {0}" -f $failure)
		}
		exit 4
	}
	Write-Host "[BALANCE] Target gate: PASS"
}

Write-Host "[BALANCE] PASS"
exit 0
