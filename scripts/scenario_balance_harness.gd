extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const SCENARIO_CARDS_PATH := "res://data/runtime/scenario_cards.json"
const DEFAULT_STEPS := 180
const DEFAULT_OUT_PATH := "scenario_balance_report.json"

func _initialize() -> void:
	var cfg: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var failures: Array[String] = []

	var packed: PackedScene = load(MAIN_SCENE_PATH)
	if packed == null:
		_fail_and_quit(["Failed to load %s" % MAIN_SCENE_PATH])
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	for _i in range(16):
		await process_frame

	var city_grid: Node = main.get_node_or_null("CityGrid")
	var district_generator: Node = main.get_node_or_null("DistrictGenerator")
	if city_grid == null:
		failures.append("Missing node: CityGrid")
	if district_generator == null:
		failures.append("Missing node: DistrictGenerator")
	if not failures.is_empty():
		_fail_and_quit(failures)
		return

	var cards: Dictionary = _load_cards()
	if cards.is_empty():
		_fail_and_quit(["No scenario cards loaded from %s" % SCENARIO_CARDS_PATH])
		return

	var card_ids: Array[String] = []
	for card_key in cards.keys():
		card_ids.append(String(card_key))
	card_ids.sort()

	var steps: int = max(int(cfg.get("steps", DEFAULT_STEPS)), 1)
	var seeds: Array[int] = cfg.get("seeds", [])
	var results: Array[Dictionary] = []
	var summary_by_card: Dictionary = {}
	for card_id in card_ids:
		var card_v: Variant = cards.get(card_id, {})
		if typeof(card_v) != TYPE_DICTIONARY:
			continue
		var payload: Dictionary = Dictionary(card_v)
		var trial_seeds: Array[int] = []
		if seeds.is_empty():
			trial_seeds.append(int(payload.get("seed", district_generator.call("get_world_seed"))))
		else:
			for seed in seeds:
				trial_seeds.append(seed)
		for trial_seed in trial_seeds:
			_apply_payload(city_grid, district_generator, payload, card_id, trial_seed)
			for _i in range(steps):
				city_grid.call("_run_sim_step")
			var result: Dictionary = _scenario_result(city_grid, payload, card_id, steps, trial_seed)
			results.append(result)
			_accumulate_card_summary(summary_by_card, result)

	var report := {
		"kind": "scenario_balance_report",
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"steps": steps,
		"scenario_count": card_ids.size(),
		"trial_count": results.size(),
		"seeds": seeds,
		"summary_by_card": _summary_rows(summary_by_card),
		"results": results
	}

	var out_path: String = String(cfg.get("out", DEFAULT_OUT_PATH))
	if out_path != "":
		var fp: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		if fp == null:
			_fail_and_quit(["Failed to write report to %s" % out_path])
			return
		fp.store_string(JSON.stringify(report, "  "))
	print("[BALANCE] %s" % JSON.stringify(report))
	quit(0)

func _parse_args(args: PackedStringArray) -> Dictionary:
	var cfg: Dictionary = {
		"steps": DEFAULT_STEPS,
		"out": DEFAULT_OUT_PATH,
		"seeds": []
	}
	for arg in args:
		var token: String = String(arg)
		if token.begins_with("--steps="):
			cfg["steps"] = max(int(token.trim_prefix("--steps=")), 1)
		elif token.begins_with("--seeds="):
			cfg["seeds"] = _parse_seeds(token.trim_prefix("--seeds="))
		elif token.begins_with("--out="):
			cfg["out"] = token.trim_prefix("--out=")
		elif token == "--no-out":
			cfg["out"] = ""
	return cfg

func _parse_seeds(raw: String) -> Array[int]:
	var out: Array[int] = []
	var parts: PackedStringArray = raw.split(",", false)
	for part in parts:
		var token: String = part.strip_edges()
		if token == "":
			continue
		out.append(int(token))
	return out

func _load_cards() -> Dictionary:
	if not FileAccess.file_exists(SCENARIO_CARDS_PATH):
		return {}
	var fp: FileAccess = FileAccess.open(SCENARIO_CARDS_PATH, FileAccess.READ)
	if fp == null:
		return {}
	var parsed: Variant = JSON.parse_string(fp.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var payload: Dictionary = parsed
	var cards_v: Variant = payload.get("cards", payload)
	if typeof(cards_v) != TYPE_DICTIONARY:
		return {}
	return Dictionary(cards_v).duplicate(true)

func _apply_payload(city_grid: Node, district_generator: Node, payload: Dictionary, fallback_id: String, seed: int) -> void:
	district_generator.call("regenerate", seed, false)

	var policies_v: Variant = payload.get("policies", {})
	if typeof(policies_v) == TYPE_DICTIONARY and city_grid.has_method("set_district_policy"):
		var policies: Dictionary = policies_v
		for district_key in policies.keys():
			var district_id: String = String(district_key)
			var policy_id: String = String(policies[district_key])
			city_grid.call("set_district_policy", district_id, policy_id)

	var balance_profile_id: String = String(payload.get("balance_profile_id", ""))
	if balance_profile_id != "" and city_grid.has_method("set_balance_profile"):
		city_grid.call("set_balance_profile", balance_profile_id)

	if city_grid.has_method("set_objective_mode"):
		var objective_mode: String = String(payload.get("objective_mode", "full"))
		city_grid.call("set_objective_mode", objective_mode)

	if city_grid.has_method("set_difficulty_profile"):
		var difficulty_profile_v: Variant = payload.get("difficulty_profile", {})
		if typeof(difficulty_profile_v) == TYPE_DICTIONARY:
			city_grid.call("set_difficulty_profile", difficulty_profile_v)
		else:
			city_grid.call("set_difficulty_profile", {})

	var services_v: Variant = payload.get("service_levels", {})
	if typeof(services_v) == TYPE_DICTIONARY and city_grid.has_method("set_service_level"):
		var services: Dictionary = services_v
		for service_key in services.keys():
			var service_id: String = String(service_key)
			city_grid.call("set_service_level", service_id, float(services[service_key]))

	if city_grid.has_method("set_scenario_goal_rules"):
		var goal_rules_v: Variant = payload.get("goal_rules", [])
		if typeof(goal_rules_v) == TYPE_ARRAY:
			city_grid.call("set_scenario_goal_rules", goal_rules_v)
		else:
			city_grid.call("set_scenario_goal_rules", [])

	if city_grid.has_method("set_sim_paused"):
		city_grid.call("set_sim_paused", false)
	if city_grid.has_method("set_sim_speed"):
		city_grid.call("set_sim_speed", 1.0)

func _scenario_result(city_grid: Node, payload: Dictionary, card_id: String, steps: int, seed: int) -> Dictionary:
	var objectives_v: Variant = city_grid.call("get_objective_snapshot")
	var economy_v: Variant = city_grid.call("get_economy_snapshot")
	var scenario_state_v: Variant = city_grid.call("get_scenario_state")
	var objective_meta: Dictionary = {}
	if typeof(objectives_v) == TYPE_ARRAY:
		var objectives: Array = objectives_v
		for obj_v in objectives:
			if typeof(obj_v) != TYPE_DICTIONARY:
				continue
			var obj: Dictionary = obj_v
			if String(obj.get("id", "")) == "__meta__":
				objective_meta = obj
				break

	var economy: Dictionary = economy_v if typeof(economy_v) == TYPE_DICTIONARY else {}
	var scenario_state: Dictionary = scenario_state_v if typeof(scenario_state_v) == TYPE_DICTIONARY else {}

	return {
		"card_id": card_id,
		"name": String(payload.get("name", card_id)),
		"seed": seed,
		"steps": steps,
		"objective_progress": String(objective_meta.get("progress", "0/0")),
		"objectives_complete": bool(objective_meta.get("complete", false)),
		"failed_count": int(objective_meta.get("failed_count", 0)),
		"scenario_failed": bool(scenario_state.get("failed", false)),
		"scenario_fail_reason": String(scenario_state.get("fail_reason", "")),
		"money": int(economy.get("money", 0)),
		"population": int(economy.get("population", 0)),
		"jobs": int(economy.get("jobs", 0)),
		"sim_tick": int(economy.get("sim_tick", 0))
	}

func _accumulate_card_summary(summary: Dictionary, result: Dictionary) -> void:
	var card_id: String = String(result.get("card_id", ""))
	if card_id == "":
		return
	if not summary.has(card_id):
		summary[card_id] = {
			"card_id": card_id,
			"name": String(result.get("name", card_id)),
			"trials": 0,
			"wins": 0,
			"losses": 0,
			"sum_money": 0.0,
			"sum_population": 0.0,
			"sum_jobs": 0.0
		}
	var row: Dictionary = summary[card_id]
	row["trials"] = int(row.get("trials", 0)) + 1
	var won: bool = bool(result.get("objectives_complete", false)) and not bool(result.get("scenario_failed", false))
	if won:
		row["wins"] = int(row.get("wins", 0)) + 1
	else:
		row["losses"] = int(row.get("losses", 0)) + 1
	row["sum_money"] = float(row.get("sum_money", 0.0)) + float(result.get("money", 0))
	row["sum_population"] = float(row.get("sum_population", 0.0)) + float(result.get("population", 0))
	row["sum_jobs"] = float(row.get("sum_jobs", 0.0)) + float(result.get("jobs", 0))
	summary[card_id] = row

func _summary_rows(summary: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var keys: Array[String] = []
	for key in summary.keys():
		keys.append(String(key))
	keys.sort()
	for card_id in keys:
		var row: Dictionary = summary[card_id]
		var trials: int = max(int(row.get("trials", 0)), 1)
		var wins: int = int(row.get("wins", 0))
		rows.append(
			{
				"card_id": card_id,
				"name": String(row.get("name", card_id)),
				"trials": trials,
				"wins": wins,
				"losses": int(row.get("losses", 0)),
				"win_rate": float(wins) / float(trials),
				"avg_money": float(row.get("sum_money", 0.0)) / float(trials),
				"avg_population": float(row.get("sum_population", 0.0)) / float(trials),
				"avg_jobs": float(row.get("sum_jobs", 0.0)) / float(trials)
			}
		)
	return rows

func _fail_and_quit(failures: Array[String]) -> void:
	for failure in failures:
		push_error("[BALANCE] %s" % failure)
	quit(1)
