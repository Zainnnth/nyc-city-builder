param(
	[string]$GodotExe = "C:\Users\ps450\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.1-stable_win64.exe",
	[int]$Steps = 320,
	[int]$Warmup = 48,
	[int]$Seed = 1998,
	[string]$Scene = "res://scenes/benchmark.tscn",
	[string]$Profile = "default",
	[string]$OutputJson = "tools/dev/benchmarks/benchmark_last.json",
	[string]$HistoryCsv = "tools/dev/benchmarks/benchmark_history.csv",
	[switch]$EnforceBudget,
	[string]$BudgetConfig = "tools/dev/benchmarks/budget_thresholds.json",
	[double]$TickMeanBudgetMs = -1.0,
	[double]$TickP95BudgetMs = -1.0,
	[double]$TickMaxBudgetMs = -1.0
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$runBenchmarkScript = Join-Path $repoRoot "tools\dev\run_benchmark.ps1"
if ([System.IO.Path]::IsPathRooted($OutputJson)) {
	$outputJsonAbs = $OutputJson
} else {
	$outputJsonAbs = Join-Path $repoRoot $OutputJson
}
if ([System.IO.Path]::IsPathRooted($HistoryCsv)) {
	$historyCsvAbs = $HistoryCsv
} else {
	$historyCsvAbs = Join-Path $repoRoot $HistoryCsv
}
if ([System.IO.Path]::IsPathRooted($BudgetConfig)) {
	$budgetConfigAbs = $BudgetConfig
} else {
	$budgetConfigAbs = Join-Path $repoRoot $BudgetConfig
}

$benchDir = Split-Path -Path $outputJsonAbs -Parent
if ($benchDir -ne "" -and -not (Test-Path $benchDir)) {
	New-Item -ItemType Directory -Path $benchDir | Out-Null
}
$historyDir = Split-Path -Path $historyCsvAbs -Parent
if ($historyDir -ne "" -and -not (Test-Path $historyDir)) {
	New-Item -ItemType Directory -Path $historyDir | Out-Null
}

function _resolve_budget {
	param(
		[string]$budgetConfigPath,
		[string]$profile,
		[double]$tickMeanBudgetMs,
		[double]$tickP95BudgetMs,
		[double]$tickMaxBudgetMs
	)
	$defaultBudget = [pscustomobject]@{
		tick_mean_ms_max = 8.0
		tick_p95_ms_max = 12.0
		tick_max_ms_max = 20.0
	}
	if (Test-Path $budgetConfigPath) {
		$cfg = Get-Content $budgetConfigPath -Raw | ConvertFrom-Json
		if ($null -ne $cfg.default) {
			$defaultBudget.tick_mean_ms_max = [double]$cfg.default.tick_mean_ms_max
			$defaultBudget.tick_p95_ms_max = [double]$cfg.default.tick_p95_ms_max
			$defaultBudget.tick_max_ms_max = [double]$cfg.default.tick_max_ms_max
		}
		if ($null -ne $cfg.profiles -and $null -ne $cfg.profiles.$profile) {
			$profileBudget = $cfg.profiles.$profile
			$defaultBudget.tick_mean_ms_max = [double]$profileBudget.tick_mean_ms_max
			$defaultBudget.tick_p95_ms_max = [double]$profileBudget.tick_p95_ms_max
			$defaultBudget.tick_max_ms_max = [double]$profileBudget.tick_max_ms_max
		}
	}
	if ($tickMeanBudgetMs -gt 0) {
		$defaultBudget.tick_mean_ms_max = $tickMeanBudgetMs
	}
	if ($tickP95BudgetMs -gt 0) {
		$defaultBudget.tick_p95_ms_max = $tickP95BudgetMs
	}
	if ($tickMaxBudgetMs -gt 0) {
		$defaultBudget.tick_max_ms_max = $tickMaxBudgetMs
	}
	return $defaultBudget
}

$runOutput = powershell -ExecutionPolicy Bypass -File $runBenchmarkScript -GodotExe $GodotExe -Steps $Steps -Warmup $Warmup -Seed $Seed -Scene $Scene -Out $outputJsonAbs 2>&1
$runCode = $LASTEXITCODE
foreach ($line in $runOutput) {
	Write-Host $line
}
if ($LASTEXITCODE -ne 0) {
	Write-Error "Benchmark run failed with exit code $runCode"
	exit $runCode
}

$report = $null
$jsonLine = $runOutput | Where-Object { $_ -match '^\[BENCH\]\s+\{' } | Select-Object -Last 1
if ($null -ne $jsonLine) {
	$jsonText = ($jsonLine -replace '^\[BENCH\]\s+', '')
	$report = $jsonText | ConvertFrom-Json
} elseif (Test-Path $outputJsonAbs) {
	$report = Get-Content $outputJsonAbs -Raw | ConvertFrom-Json
} else {
	Write-Error "Benchmark output missing in both stdout and file: $outputJsonAbs"
	exit 3
}

$entry = [pscustomobject]@{
	timestamp_unix = [int]$report.timestamp_unix
	profile = $Profile
	seed = [int]$report.seed
	scene = [string]$report.scene
	steps = [int]$report.steps
	warmup_steps = [int]$report.warmup_steps
	grid_columns = [int]$report.grid_columns
	grid_rows = [int]$report.grid_rows
	tick_mean_ms = [double]$report.tick_ms.mean
	tick_p95_ms = [double]$report.tick_ms.p95
	tick_max_ms = [double]$report.tick_ms.max
	population = [int]$report.economy.population
	jobs = [int]$report.economy.jobs
	money = [int]$report.economy.money
	drawn_instances = [int]$report.render_stats.drawn_instances
	total_instances = [int]$report.render_stats.total_instances
}

if (-not (Test-Path $historyCsvAbs)) {
	$entry | Export-Csv -Path $historyCsvAbs -NoTypeInformation
} else {
	$entry | Export-Csv -Path $historyCsvAbs -NoTypeInformation -Append
}

$rows = @(Import-Csv -Path $historyCsvAbs | Where-Object { $_.profile -eq $Profile })
$count = $rows.Count
$current = $rows[$count - 1]
$previous = $null
if ($count -ge 2) {
	$previous = $rows[$count - 2]
}
$baseline = $rows[0]

Write-Host ("[BENCH] Recorded profile '{0}' run #{1}" -f $Profile, $count)
Write-Host ("[BENCH] tick mean={0}ms p95={1}ms max={2}ms" -f $current.tick_mean_ms, $current.tick_p95_ms, $current.tick_max_ms)

if ($null -ne $previous) {
	$deltaPrev = [double]$current.tick_mean_ms - [double]$previous.tick_mean_ms
	Write-Host ("[BENCH] vs previous mean delta: {0}ms" -f ([math]::Round($deltaPrev, 4)))
}
$deltaBase = [double]$current.tick_mean_ms - [double]$baseline.tick_mean_ms
Write-Host ("[BENCH] vs baseline mean delta: {0}ms" -f ([math]::Round($deltaBase, 4)))
Write-Host ("[BENCH] History file: {0}" -f $historyCsvAbs)

$budget = _resolve_budget -budgetConfigPath $budgetConfigAbs -profile $Profile -tickMeanBudgetMs $TickMeanBudgetMs -tickP95BudgetMs $TickP95BudgetMs -tickMaxBudgetMs $TickMaxBudgetMs
if ($EnforceBudget) {
	Write-Host ("[BENCH] Budget thresholds mean<= {0}ms p95<= {1}ms max<= {2}ms" -f $budget.tick_mean_ms_max, $budget.tick_p95_ms_max, $budget.tick_max_ms_max)
	$budgetFailures = @()
	if ([double]$current.tick_mean_ms -gt [double]$budget.tick_mean_ms_max) {
		$budgetFailures += ("mean {0}ms > budget {1}ms" -f $current.tick_mean_ms, $budget.tick_mean_ms_max)
	}
	if ([double]$current.tick_p95_ms -gt [double]$budget.tick_p95_ms_max) {
		$budgetFailures += ("p95 {0}ms > budget {1}ms" -f $current.tick_p95_ms, $budget.tick_p95_ms_max)
	}
	if ([double]$current.tick_max_ms -gt [double]$budget.tick_max_ms_max) {
		$budgetFailures += ("max {0}ms > budget {1}ms" -f $current.tick_max_ms, $budget.tick_max_ms_max)
	}
	if ($budgetFailures.Count -gt 0) {
		foreach ($failure in $budgetFailures) {
			Write-Error ("[BENCH] Budget violation: {0}" -f $failure)
		}
		exit 4
	}
	Write-Host "[BENCH] Budget gate: PASS"
}

exit 0
