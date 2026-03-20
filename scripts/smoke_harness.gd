extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main.tscn"

func _initialize() -> void:
	var failures: Array[String] = []
	var packed: PackedScene = load(MAIN_SCENE_PATH)
	if packed == null:
		_fail_and_quit(["Failed to load %s" % MAIN_SCENE_PATH])
		return

	var main: Node = packed.instantiate()
	root.add_child(main)

	for _i in range(14):
		await process_frame

	var city_grid: Node = main.get_node_or_null("CityGrid")
	var district_generator: Node = main.get_node_or_null("DistrictGenerator")
	var seed_panel: Node = main.get_node_or_null("SeedPanel")
	var audio_bed: Node = main.get_node_or_null("AudioBed")

	if city_grid == null:
		failures.append("Missing node: CityGrid")
	if district_generator == null:
		failures.append("Missing node: DistrictGenerator")
	if seed_panel == null:
		failures.append("Missing node: SeedPanel")
	if audio_bed == null:
		failures.append("Missing node: AudioBed")

	if failures.is_empty() and city_grid != null:
		_check_city_grid_api(city_grid, failures)
		_check_city_grid_snapshots(city_grid, failures)
		_check_city_grid_save_roundtrip(city_grid, failures)

	if failures.is_empty() and district_generator != null:
		_check_generator_api(district_generator, failures)

	if failures.is_empty():
		print("[SMOKE] PASS: core systems booted and API checks passed.")
		quit(0)
		return

	_fail_and_quit(failures)

func _check_city_grid_api(city_grid: Node, failures: Array[String]) -> void:
	var required_methods := [
		"get_district_demand_snapshot",
		"get_economy_snapshot",
		"get_active_alerts",
		"get_objective_snapshot",
		"get_event_snapshot",
		"set_balance_profile",
		"get_balance_profiles",
		"set_overlay_mode",
		"export_state",
		"import_state"
	]
	for method_name in required_methods:
		if not city_grid.has_method(method_name):
			failures.append("CityGrid missing method: %s" % method_name)

func _check_city_grid_snapshots(city_grid: Node, failures: Array[String]) -> void:
	city_grid.call("set_balance_profile", "standard")
	city_grid.call("set_overlay_mode", "land_value")
	city_grid.call("set_service_level", "police", 60.0)
	city_grid.call("set_service_level", "fire", 60.0)
	city_grid.call("set_service_level", "sanitation", 60.0)
	city_grid.call("set_service_level", "transit", 60.0)
	city_grid.call("_run_sim_step")

	var demand_v: Variant = city_grid.call("get_district_demand_snapshot")
	var econ_v: Variant = city_grid.call("get_economy_snapshot")
	var alerts_v: Variant = city_grid.call("get_active_alerts")
	var objectives_v: Variant = city_grid.call("get_objective_snapshot")
	var events_v: Variant = city_grid.call("get_event_snapshot")
	var profiles_v: Variant = city_grid.call("get_balance_profiles")

	if typeof(demand_v) != TYPE_ARRAY:
		failures.append("get_district_demand_snapshot did not return Array")
	if typeof(econ_v) != TYPE_DICTIONARY:
		failures.append("get_economy_snapshot did not return Dictionary")
	if typeof(alerts_v) != TYPE_ARRAY:
		failures.append("get_active_alerts did not return Array")
	if typeof(objectives_v) != TYPE_ARRAY:
		failures.append("get_objective_snapshot did not return Array")
	if typeof(events_v) != TYPE_DICTIONARY:
		failures.append("get_event_snapshot did not return Dictionary")
	if typeof(profiles_v) != TYPE_DICTIONARY:
		failures.append("get_balance_profiles did not return Dictionary")

func _check_city_grid_save_roundtrip(city_grid: Node, failures: Array[String]) -> void:
	var state_v: Variant = city_grid.call("export_state")
	if typeof(state_v) != TYPE_DICTIONARY:
		failures.append("export_state did not return Dictionary")
		return
	var state: Dictionary = state_v
	var ok: bool = bool(city_grid.call("import_state", state))
	if not ok:
		failures.append("import_state returned false on exported state")

func _check_generator_api(district_generator: Node, failures: Array[String]) -> void:
	if not district_generator.has_method("regenerate"):
		failures.append("DistrictGenerator missing method: regenerate")
		return
	district_generator.call("regenerate", 1998, false)

func _fail_and_quit(failures: Array[String]) -> void:
	for failure in failures:
		push_error("[SMOKE] %s" % failure)
	quit(1)
