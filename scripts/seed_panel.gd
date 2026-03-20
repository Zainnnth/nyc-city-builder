extends CanvasLayer

signal district_focus_requested(target_pos: Vector2)

@export var district_generator_path: NodePath = ^"../DistrictGenerator"
@export var city_grid_path: NodePath = ^"../CityGrid"

@onready var input_seed: LineEdit = $Panel/VBox/SeedRow/SeedInput
@onready var apply_button: Button = $Panel/VBox/Controls/ApplySeedButton
@onready var random_button: Button = $Panel/VBox/Controls/RandomSeedButton
@onready var save_button: Button = $Panel/VBox/Persistence/SaveButton
@onready var load_button: Button = $Panel/VBox/Persistence/LoadButton
@onready var load_latest_button: Button = $Panel/VBox/Persistence/LoadLatestButton
@onready var slot_select: OptionButton = $Panel/VBox/Persistence/SlotSelect
@onready var autosave_toggle: CheckBox = $Panel/VBox/Persistence/AutosaveToggle
@onready var pause_button: Button = $Panel/VBox/TimeControls/PauseButton
@onready var speed_1x_button: Button = $Panel/VBox/TimeControls/Speed1xButton
@onready var speed_3x_button: Button = $Panel/VBox/TimeControls/Speed3xButton
@onready var preset_balanced_button: Button = $Panel/VBox/Presets/BalancedPresetButton
@onready var preset_midtown_button: Button = $Panel/VBox/Presets/MidtownPresetButton
@onready var preset_boroughs_button: Button = $Panel/VBox/Presets/BoroughPresetButton
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var demand_rows: VBoxContainer = $DemandPanel/VBox/DemandRows
@onready var econ_money: Label = $EconomyPanel/VBox/EconMoney
@onready var econ_population: Label = $EconomyPanel/VBox/EconPopulation
@onready var econ_jobs: Label = $EconomyPanel/VBox/EconJobs
@onready var econ_pressure: Label = $EconomyPanel/VBox/EconPressure
@onready var objective_summary: Label = $ObjectivesPanel/VBox/ObjectiveSummary
@onready var objective_rows: VBoxContainer = $ObjectivesPanel/VBox/ObjectiveRows
@onready var alert_rows: VBoxContainer = $AlertsPanel/VBox/AlertRows
@onready var milestone_banner: PanelContainer = $MilestoneBanner
@onready var milestone_banner_text: Label = $MilestoneBanner/VBox/BannerText
@onready var milestone_banner_sub: Label = $MilestoneBanner/VBox/BannerSub
@onready var popup_panel: PanelContainer = $DistrictPopup
@onready var popup_title: Label = $DistrictPopup/VBox/PopupTitle
@onready var popup_body: Label = $DistrictPopup/VBox/PopupBody
@onready var popup_policy: Label = $DistrictPopup/VBox/PopupPolicy
@onready var policy_balanced_button: Button = $DistrictPopup/VBox/PolicyButtons/BalancedButton
@onready var policy_growth_button: Button = $DistrictPopup/VBox/PolicyButtons/GrowthButton
@onready var policy_profit_button: Button = $DistrictPopup/VBox/PolicyButtons/ProfitButton
@onready var close_popup_button: Button = $DistrictPopup/VBox/ClosePopupButton

var district_generator: Node2D
var city_grid: Node2D
var rng := RandomNumberGenerator.new()
var ui_timer := 0.0
var focused_district_id := ""
var focused_row_data: Dictionary = {}
var autosave_timer := 0.0
var autosave_next_slot := 1
const AUTOSAVE_INTERVAL := 20.0
var banner_acknowledged := false

const DISTRICT_NAMES := {
	"midtown_core": "Midtown",
	"financial_district": "Financial",
	"lower_east_side": "Lower East Side",
	"harlem": "Harlem",
	"queens_west": "Queens West",
	"outer_borough_mix": "Outer Mix"
}

const POLICY_LABELS := {
	"balanced": "Balanced",
	"growth": "Growth",
	"profit": "Profit"
}

const SCENARIOS := {
	"balanced": {
		"name": "Balanced Start",
		"seed": 1998,
		"policies": {
			"midtown_core": "balanced",
			"financial_district": "balanced",
			"lower_east_side": "balanced",
			"harlem": "balanced",
			"queens_west": "balanced"
		}
	},
	"midtown_boom": {
		"name": "Midtown Boom",
		"seed": 2001,
		"policies": {
			"midtown_core": "profit",
			"financial_district": "profit",
			"lower_east_side": "growth",
			"harlem": "balanced",
			"queens_west": "balanced"
		}
	},
	"borough_buildout": {
		"name": "Borough Buildout",
		"seed": 1995,
		"policies": {
			"midtown_core": "balanced",
			"financial_district": "balanced",
			"lower_east_side": "growth",
			"harlem": "growth",
			"queens_west": "growth"
		}
	}
}

func _ready() -> void:
	rng.randomize()
	district_generator = get_node_or_null(district_generator_path)
	city_grid = get_node_or_null(city_grid_path)
	if district_generator == null:
		status_label.text = "DistrictGenerator not found."
		apply_button.disabled = true
		random_button.disabled = true
		return

	input_seed.text = str(district_generator.call("get_world_seed"))
	status_label.text = "Ready."
	apply_button.pressed.connect(_on_apply_seed)
	random_button.pressed.connect(_on_random_seed)
	save_button.pressed.connect(_on_save_city)
	load_button.pressed.connect(_on_load_city)
	load_latest_button.pressed.connect(_on_load_latest_city)
	slot_select.item_selected.connect(_on_slot_changed)
	autosave_toggle.toggled.connect(_on_autosave_toggled)
	pause_button.pressed.connect(_on_pause_toggled)
	speed_1x_button.pressed.connect(_on_set_speed.bind(1.0))
	speed_3x_button.pressed.connect(_on_set_speed.bind(3.0))
	preset_balanced_button.pressed.connect(_on_apply_preset.bind("balanced"))
	preset_midtown_button.pressed.connect(_on_apply_preset.bind("midtown_boom"))
	preset_boroughs_button.pressed.connect(_on_apply_preset.bind("borough_buildout"))
	input_seed.text_submitted.connect(_on_text_submitted)
	close_popup_button.pressed.connect(_on_close_popup)
	policy_balanced_button.pressed.connect(_on_set_policy.bind("balanced"))
	policy_growth_button.pressed.connect(_on_set_policy.bind("growth"))
	policy_profit_button.pressed.connect(_on_set_policy.bind("profit"))
	popup_panel.visible = false
	milestone_banner.visible = false
	_init_slot_ui()
	_refresh_economy()
	_refresh_objectives()

func _process(delta: float) -> void:
	ui_timer += delta
	if ui_timer >= 0.4:
		ui_timer = 0.0
		_refresh_demand_bars()
		_refresh_economy()
		_refresh_objectives()
		_refresh_alerts()
		_update_time_buttons()
	if autosave_toggle.button_pressed:
		autosave_timer += delta
		if autosave_timer >= AUTOSAVE_INTERVAL:
			autosave_timer = 0.0
			_run_rolling_autosave()

func _on_text_submitted(_value: String) -> void:
	_on_apply_seed()

func _on_apply_seed() -> void:
	var text: String = input_seed.text.strip_edges()
	if text == "":
		status_label.text = "Enter a seed."
		return

	if not text.is_valid_int():
		status_label.text = "Seed must be an integer."
		return

	var seed_value: int = int(text)
	district_generator.call("regenerate", seed_value, false)
	status_label.text = "Regenerated with seed %d." % seed_value

func _on_random_seed() -> void:
	var seed_value: int = rng.randi_range(1000, 9999999)
	input_seed.text = str(seed_value)
	district_generator.call("regenerate", seed_value, false)
	status_label.text = "Random seed %d applied." % seed_value

func _on_save_city() -> void:
	if district_generator == null:
		return
	var slot := _current_slot()
	var ok: bool = district_generator.call("save_to_slot", slot)
	if ok:
		status_label.text = "City saved to slot %d." % slot
	else:
		status_label.text = "Save failed."

func _on_load_city() -> void:
	if district_generator == null:
		return
	var slot := _current_slot()
	var ok: bool = district_generator.call("load_from_slot", slot)
	if ok:
		input_seed.text = str(district_generator.call("get_world_seed"))
		status_label.text = "City loaded from slot %d." % slot
	else:
		status_label.text = "Load failed for slot %d." % slot

func _on_load_latest_city() -> void:
	if district_generator == null:
		return
	var slot: int = district_generator.call("load_latest_slot")
	if slot > 0:
		input_seed.text = str(district_generator.call("get_world_seed"))
		slot_select.select(slot - 1)
		autosave_next_slot = slot
		status_label.text = "Loaded latest autosave (slot %d)." % slot
		_update_slot_labels()
	else:
		status_label.text = "No autosave slot found."

func _refresh_demand_bars() -> void:
	if city_grid == null:
		return
	if not city_grid.has_method("get_district_demand_snapshot"):
		return

	var snapshot_variant: Variant = city_grid.call("get_district_demand_snapshot")
	if typeof(snapshot_variant) != TYPE_ARRAY:
		return
	var snapshot: Array = snapshot_variant

	for child in demand_rows.get_children():
		child.queue_free()

	var count: int = min(snapshot.size(), 6)
	if count == 0:
		var empty := Label.new()
		empty.text = "No district demand data yet."
		demand_rows.add_child(empty)
		return

	for i in range(count):
		var row_data_variant: Variant = snapshot[i]
		if typeof(row_data_variant) != TYPE_DICTIONARY:
			continue
		var row_data: Dictionary = row_data_variant
		var district_id: String = String(row_data.get("district_id", "outer_borough_mix"))
		var display_name: String = String(DISTRICT_NAMES.get(district_id, district_id))
		var demand: float = float(row_data.get("demand_index", 0.0))
		var policy_id: String = String(row_data.get("policy_id", "balanced"))
		var res_d: int = int(round(float(row_data.get("res_demand", 0.0))))
		var com_d: int = int(round(float(row_data.get("com_demand", 0.0))))
		var ind_d: int = int(round(float(row_data.get("ind_demand", 0.0))))

		var row: VBoxContainer = VBoxContainer.new()
		var title: Label = Label.new()
		title.text = "%s  %d" % [display_name, int(round(demand))]
		row.add_child(title)

		var bar: ProgressBar = ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = demand
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)

		var sub: Label = Label.new()
		sub.modulate = Color(0.72, 0.78, 0.9, 0.95)
		sub.text = "R %d  C %d  I %d  |  %s" % [
			res_d, com_d, ind_d, String(POLICY_LABELS.get(policy_id, "Balanced"))
		]
		row.add_child(sub)

		var focus_button: Button = Button.new()
		focus_button.text = "Focus District"
		focus_button.pressed.connect(_on_focus_district.bind(district_id, row_data))
		row.add_child(focus_button)
		demand_rows.add_child(row)

func _on_focus_district(district_id: String, row_data: Dictionary) -> void:
	if district_generator == null:
		return
	if not district_generator.call("has_district_focus_point", district_id):
		status_label.text = "No focus point for %s." % district_id
		return

	var target: Vector2 = district_generator.call("get_district_focus_point", district_id)
	district_focus_requested.emit(target)
	focused_district_id = district_id
	focused_row_data = row_data.duplicate(true)
	_show_popup(district_id, row_data)
	status_label.text = "Focused %s." % String(DISTRICT_NAMES.get(district_id, district_id))

func _show_popup(district_id: String, row_data: Dictionary) -> void:
	var district_name: String = String(DISTRICT_NAMES.get(district_id, district_id))
	var demand: int = int(round(float(row_data.get("demand_index", 0.0))))
	var res_d: int = int(round(float(row_data.get("res_demand", 0.0))))
	var com_d: int = int(round(float(row_data.get("com_demand", 0.0))))
	var ind_d: int = int(round(float(row_data.get("ind_demand", 0.0))))
	var policy_id: String = String(row_data.get("policy_id", "balanced"))

	popup_title.text = "%s District" % district_name
	popup_body.text = "Demand %d\nResidential %d\nCommercial %d\nIndustrial %d" % [
		demand, res_d, com_d, ind_d
	]
	popup_policy.text = "Policy: %s" % String(POLICY_LABELS.get(policy_id, "Balanced"))
	popup_panel.visible = true

func _on_close_popup() -> void:
	popup_panel.visible = false

func _on_set_policy(policy_id: String) -> void:
	if focused_district_id == "":
		return
	if city_grid == null:
		return
	if not city_grid.has_method("set_district_policy"):
		return
	city_grid.call("set_district_policy", focused_district_id, policy_id)
	var row_data := focused_row_data.duplicate(true)
	row_data["policy_id"] = policy_id
	_show_popup(focused_district_id, row_data)
	status_label.text = "Policy set: %s" % String(POLICY_LABELS.get(policy_id, policy_id))

func _init_slot_ui() -> void:
	slot_select.clear()
	slot_select.add_item("Slot 1", 1)
	slot_select.add_item("Slot 2", 2)
	slot_select.add_item("Slot 3", 3)
	slot_select.select(0)
	autosave_toggle.button_pressed = false
	autosave_timer = 0.0
	autosave_next_slot = 1
	_update_slot_labels()
	_update_time_buttons()

func _on_slot_changed(_idx: int) -> void:
	autosave_next_slot = _current_slot()
	_update_slot_labels()

func _on_autosave_toggled(enabled: bool) -> void:
	autosave_timer = 0.0
	if enabled:
		autosave_next_slot = _current_slot()
		status_label.text = "Autosave enabled."
	else:
		status_label.text = "Autosave disabled."

func _run_rolling_autosave() -> void:
	if district_generator == null:
		return
	var slot: int = autosave_next_slot
	var ok: bool = district_generator.call("save_to_slot", slot)
	if ok:
		status_label.text = "Autosaved slot %d." % slot
		autosave_next_slot += 1
		if autosave_next_slot > 3:
			autosave_next_slot = 1
	else:
		status_label.text = "Autosave failed."
	_update_slot_labels()

func _current_slot() -> int:
	var idx := slot_select.selected
	if idx < 0:
		return 1
	var id := slot_select.get_item_id(idx)
	if id < 1 or id > 3:
		return 1
	return id

func _update_slot_labels() -> void:
	if district_generator == null:
		return
	for slot in [1, 2, 3]:
		var exists: bool = district_generator.call("has_slot", slot)
		var item_idx: int = slot - 1
		var text: String = "Slot %d%s" % [slot, " *" if exists else ""]
		slot_select.set_item_text(item_idx, text)

func _refresh_economy() -> void:
	if city_grid == null:
		return
	if not city_grid.has_method("get_economy_snapshot"):
		return

	var snap_v: Variant = city_grid.call("get_economy_snapshot")
	if typeof(snap_v) != TYPE_DICTIONARY:
		return
	var snap: Dictionary = snap_v

	var money: int = int(snap.get("money", 0))
	var pop: int = int(snap.get("population", 0))
	var jobs: int = int(snap.get("jobs", 0))
	var d_money: int = int(snap.get("delta_money", 0))
	var d_pop: int = int(snap.get("delta_population", 0))
	var d_jobs: int = int(snap.get("delta_jobs", 0))
	var housing_p: float = float(snap.get("housing_pressure", 1.0))
	var job_p: float = float(snap.get("job_pressure", 1.0))

	econ_money.text = "Money: $%d (%s%d)" % [money, "+" if d_money >= 0 else "", d_money]
	econ_population.text = "Population: %d (%s%d)" % [pop, "+" if d_pop >= 0 else "", d_pop]
	econ_jobs.text = "Jobs: %d (%s%d)" % [jobs, "+" if d_jobs >= 0 else "", d_jobs]
	econ_pressure.text = "Housing P: %.2f  |  Job P: %.2f" % [housing_p, job_p]

func _refresh_objectives() -> void:
	if city_grid == null:
		return
	if not city_grid.has_method("get_objective_snapshot"):
		return

	var objectives_v: Variant = city_grid.call("get_objective_snapshot")
	if typeof(objectives_v) != TYPE_ARRAY:
		return
	var objectives: Array = objectives_v

	for child in objective_rows.get_children():
		child.queue_free()

	for objective_v in objectives:
		if typeof(objective_v) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_v
		var id: String = String(objective.get("id", ""))
		if id == "__meta__":
			_update_objective_meta(objective)
			continue
		var title: String = String(objective.get("title", "Objective"))
		var progress: String = String(objective.get("progress", ""))
		var complete: bool = bool(objective.get("complete", false))

		var label: Label = Label.new()
		label.text = "%s %s (%s)" % ["[x]" if complete else "[ ]", title, progress]
		label.modulate = Color(0.60, 0.89, 0.65, 0.98) if complete else Color(0.76, 0.82, 0.93, 0.98)
		objective_rows.add_child(label)

func _update_objective_meta(meta: Dictionary) -> void:
	var completed: int = int(meta.get("completed_count", 0))
	var total: int = int(meta.get("total_count", 0))
	var is_complete: bool = bool(meta.get("complete", false))
	var just_completed: bool = bool(meta.get("just_completed", false))
	var complete_tick: int = int(meta.get("complete_tick", -1))

	objective_summary.text = "Progress: %d / %d complete" % [completed, total]
	objective_summary.modulate = Color(0.60, 0.89, 0.65, 0.98) if is_complete else Color(0.76, 0.82, 0.93, 0.98)

	if just_completed:
		banner_acknowledged = false
	if is_complete and not banner_acknowledged:
		milestone_banner_text.text = "City Milestone Complete"
		milestone_banner_sub.text = "All objectives achieved at tick %d." % complete_tick
		milestone_banner.visible = true
		banner_acknowledged = true
	elif not is_complete:
		milestone_banner.visible = false
		banner_acknowledged = false

func _refresh_alerts() -> void:
	if city_grid == null:
		return
	if not city_grid.has_method("get_active_alerts"):
		return

	var alerts_v: Variant = city_grid.call("get_active_alerts")
	if typeof(alerts_v) != TYPE_ARRAY:
		return
	var alerts: Array = alerts_v

	for child in alert_rows.get_children():
		child.queue_free()

	for alert_v in alerts:
		if typeof(alert_v) != TYPE_DICTIONARY:
			continue
		var alert: Dictionary = alert_v
		var level: String = String(alert.get("level", "info"))
		var title: String = String(alert.get("title", "Alert"))
		var detail: String = String(alert.get("detail", ""))

		var label: Label = Label.new()
		label.text = "%s: %s" % [title, detail]
		label.modulate = _alert_color(level)
		alert_rows.add_child(label)

func _alert_color(level: String) -> Color:
	if level == "critical":
		return Color(0.96, 0.42, 0.37, 0.98)
	if level == "warning":
		return Color(0.95, 0.76, 0.31, 0.98)
	if level == "ok":
		return Color(0.55, 0.86, 0.62, 0.98)
	return Color(0.74, 0.81, 0.92, 0.98)

func _on_pause_toggled() -> void:
	if city_grid == null:
		return
	if not city_grid.has_method("set_sim_paused"):
		return
	var current_paused: bool = false
	if city_grid.has_method("is_sim_paused"):
		current_paused = city_grid.call("is_sim_paused")
	city_grid.call("set_sim_paused", not current_paused)
	_update_time_buttons()

func _on_set_speed(speed: float) -> void:
	if city_grid == null:
		return
	if not city_grid.has_method("set_sim_speed"):
		return
	city_grid.call("set_sim_speed", speed)
	_update_time_buttons()

func _on_apply_preset(preset_id: String) -> void:
	if district_generator == null:
		return
	if city_grid == null:
		return
	if not SCENARIOS.has(preset_id):
		status_label.text = "Preset not found."
		return

	var preset: Dictionary = SCENARIOS[preset_id]
	var seed: int = int(preset.get("seed", 1998))
	var scenario_name: String = String(preset.get("name", preset_id))
	input_seed.text = str(seed)
	district_generator.call("regenerate", seed, false)

	var policies_v: Variant = preset.get("policies", {})
	if typeof(policies_v) == TYPE_DICTIONARY and city_grid.has_method("set_district_policy"):
		var policies: Dictionary = policies_v
		for district_key in policies.keys():
			var district_id: String = String(district_key)
			var policy_id: String = String(policies[district_id])
			city_grid.call("set_district_policy", district_id, policy_id)

	if city_grid.has_method("set_sim_paused"):
		city_grid.call("set_sim_paused", false)
	if city_grid.has_method("set_sim_speed"):
		city_grid.call("set_sim_speed", 1.0)

	status_label.text = "Scenario loaded: %s" % scenario_name
	_refresh_demand_bars()
	_refresh_economy()
	_refresh_objectives()
	_refresh_alerts()
	_update_time_buttons()

func _update_time_buttons() -> void:
	if city_grid == null:
		return
	var paused := false
	var speed := 1.0
	if city_grid.has_method("is_sim_paused"):
		paused = city_grid.call("is_sim_paused")
	if city_grid.has_method("get_sim_speed"):
		speed = float(city_grid.call("get_sim_speed"))

	pause_button.text = "Resume" if paused else "Pause"
	speed_1x_button.disabled = paused or is_equal_approx(speed, 1.0)
	speed_3x_button.disabled = paused or is_equal_approx(speed, 3.0)
