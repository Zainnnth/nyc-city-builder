extends SceneTree

const DEFAULT_SCENE_PATH := "res://scenes/benchmark.tscn"
const DEFAULT_STEPS := 320
const DEFAULT_WARMUP_STEPS := 48
const DEFAULT_SEED := 1998
const DEFAULT_OUT_PATH := "user://benchmark_last.json"

func _initialize() -> void:
	var cfg: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var failures: Array[String] = []

	var scene_path: String = String(cfg.get("scene", DEFAULT_SCENE_PATH))
	var packed: PackedScene = load(scene_path)
	if packed == null:
		_fail_and_quit(["Failed to load benchmark scene: %s" % scene_path])
		return

	var main: Node = packed.instantiate()
	root.add_child(main)
	for _i in range(16):
		await process_frame

	var city_grid: Node = main.get_node_or_null("CityGrid")
	var district_generator: Node = main.get_node_or_null("DistrictGenerator")
	var massing_layer: Node = main.get_node_or_null("MassingLayer")
	if city_grid == null:
		failures.append("Missing node: CityGrid")
	if district_generator == null:
		failures.append("Missing node: DistrictGenerator")
	if massing_layer == null:
		failures.append("Missing node: MassingLayer")
	if not failures.is_empty():
		_fail_and_quit(failures)
		return

	var seed_value: int = int(cfg.get("seed", DEFAULT_SEED))
	if district_generator.has_method("regenerate"):
		district_generator.call("regenerate", seed_value, false)
	for _i in range(6):
		await process_frame

	if city_grid.has_method("set_sim_paused"):
		city_grid.call("set_sim_paused", true)
	if city_grid.has_method("set_balance_profile"):
		city_grid.call("set_balance_profile", "standard")

	var warmup_steps: int = int(cfg.get("warmup_steps", DEFAULT_WARMUP_STEPS))
	for _i in range(max(warmup_steps, 0)):
		city_grid.call("_run_sim_step")

	var samples_ms: Array[float] = []
	var steps: int = max(int(cfg.get("steps", DEFAULT_STEPS)), 1)
	for _i in range(steps):
		var start_us: int = Time.get_ticks_usec()
		city_grid.call("_run_sim_step")
		var elapsed_ms: float = float(Time.get_ticks_usec() - start_us) / 1000.0
		samples_ms.append(elapsed_ms)

	var tick_stats: Dictionary = _summarize_samples(samples_ms)
	var econ: Dictionary = _dict_or_empty(city_grid.call("get_economy_snapshot"))
	var overlay: Dictionary = _dict_or_empty(city_grid.call("get_overlay_metrics"))
	var roads: Dictionary = _dict_or_empty(city_grid.call("get_road_metrics"))
	var render_stats: Dictionary = {}
	if massing_layer.has_method("get_render_stats"):
		render_stats = _dict_or_empty(massing_layer.call("get_render_stats"))

	var report: Dictionary = {
		"kind": "benchmark_report",
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"scene": scene_path,
		"seed": seed_value,
		"steps": steps,
		"warmup_steps": warmup_steps,
		"grid_columns": int(city_grid.get("columns")),
		"grid_rows": int(city_grid.get("rows")),
		"tick_ms": tick_stats,
		"economy": {
			"money": int(econ.get("money", 0)),
			"population": int(econ.get("population", 0)),
			"jobs": int(econ.get("jobs", 0)),
			"sim_tick": int(econ.get("sim_tick", 0))
		},
		"overlay": {
			"avg_land_value": float(overlay.get("avg_land_value", 0.0)),
			"avg_noise": float(overlay.get("avg_noise", 0.0)),
			"avg_crime": float(overlay.get("avg_crime", 0.0)),
			"avg_commute_penalty": float(overlay.get("avg_commute_penalty", 0.0))
		},
		"roads": roads,
		"render_stats": render_stats
	}

	var out_path: String = String(cfg.get("out", DEFAULT_OUT_PATH))
	if out_path != "":
		var fp: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		if fp == null:
			failures.append("Failed to open output path: %s" % out_path)
		else:
			fp.store_string(JSON.stringify(report, "  "))

	print("[BENCH] %s" % JSON.stringify(report))
	if failures.is_empty():
		quit(0)
		return
	_fail_and_quit(failures)

func _parse_args(args: PackedStringArray) -> Dictionary:
	var cfg: Dictionary = {
		"scene": DEFAULT_SCENE_PATH,
		"steps": DEFAULT_STEPS,
		"warmup_steps": DEFAULT_WARMUP_STEPS,
		"seed": DEFAULT_SEED,
		"out": DEFAULT_OUT_PATH
	}
	for arg in args:
		var token: String = String(arg)
		if token.begins_with("--bench-scene="):
			cfg["scene"] = token.trim_prefix("--bench-scene=")
		elif token.begins_with("--bench-steps="):
			cfg["steps"] = max(int(token.trim_prefix("--bench-steps=")), 1)
		elif token.begins_with("--bench-warmup="):
			cfg["warmup_steps"] = max(int(token.trim_prefix("--bench-warmup=")), 0)
		elif token.begins_with("--bench-seed="):
			cfg["seed"] = int(token.trim_prefix("--bench-seed="))
		elif token.begins_with("--bench-out="):
			cfg["out"] = token.trim_prefix("--bench-out=")
		elif token == "--bench-no-out":
			cfg["out"] = ""
	return cfg

func _summarize_samples(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {
			"count": 0,
			"mean": 0.0,
			"min": 0.0,
			"p95": 0.0,
			"max": 0.0
		}
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var sum: float = 0.0
	for val in samples:
		sum += val
	return {
		"count": sorted.size(),
		"mean": sum / float(sorted.size()),
		"min": sorted[0],
		"p95": _percentile(sorted, 0.95),
		"max": sorted[sorted.size() - 1]
	}

func _percentile(sorted_samples: Array[float], p: float) -> float:
	if sorted_samples.is_empty():
		return 0.0
	var idx: int = int(round((float(sorted_samples.size() - 1)) * clamp(p, 0.0, 1.0)))
	idx = clampi(idx, 0, sorted_samples.size() - 1)
	return sorted_samples[idx]

func _dict_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return Dictionary(value)
	return {}

func _fail_and_quit(failures: Array[String]) -> void:
	for failure in failures:
		push_error("[BENCH] %s" % failure)
	quit(1)
