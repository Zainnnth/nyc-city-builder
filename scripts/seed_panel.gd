extends CanvasLayer

signal district_focus_requested(target_pos: Vector2)

@export var district_generator_path: NodePath = ^"../DistrictGenerator"
@export var city_grid_path: NodePath = ^"../CityGrid"
@export var scenario_cards_path := "res://data/runtime/scenario_cards.json"

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
@onready var balance_profile_select: OptionButton = $Panel/VBox/BalanceRow/BalanceProfileSelect
@onready var scenario_card_select: OptionButton = $ScenarioCardsPanel/VBox/ScenarioRow/ScenarioSelect
@onready var scenario_summary: Label = $ScenarioCardsPanel/VBox/ScenarioSummary
@onready var scenario_goals: Label = $ScenarioCardsPanel/VBox/ScenarioGoals
@onready var apply_scenario_card_button: Button = $ScenarioCardsPanel/VBox/ApplyScenarioCardButton
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var demand_rows: VBoxContainer = $DemandPanel/VBox/DemandRows
@onready var police_slider: HSlider = $ServicesPanel/VBox/PoliceRow/PoliceSlider
@onready var police_value: Label = $ServicesPanel/VBox/PoliceRow/PoliceValue
@onready var fire_slider: HSlider = $ServicesPanel/VBox/FireRow/FireSlider
@onready var fire_value: Label = $ServicesPanel/VBox/FireRow/FireValue
@onready var sanitation_slider: HSlider = $ServicesPanel/VBox/SanitationRow/SanitationSlider
@onready var sanitation_value: Label = $ServicesPanel/VBox/SanitationRow/SanitationValue
@onready var transit_slider: HSlider = $ServicesPanel/VBox/TransitRow/TransitSlider
@onready var transit_value: Label = $ServicesPanel/VBox/TransitRow/TransitValue
@onready var overlay_select: OptionButton = $OverlayPanel/VBox/OverlayRow/OverlaySelect
@onready var overlay_stats: Label = $OverlayPanel/VBox/OverlayStats
@onready var trigger_event_button: Button = $EventPanel/VBox/EventControls/TriggerEventButton
@onready var event_status: Label = $EventPanel/VBox/EventStatus
@onready var event_history: Label = $EventPanel/VBox/EventHistory
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
@onready var tutorial_panel: PanelContainer = $TutorialPanel
@onready var tutorial_title: Label = $TutorialPanel/VBox/TutorialTitle
@onready var tutorial_body: Label = $TutorialPanel/VBox/TutorialBody
@onready var tutorial_progress: Label = $TutorialPanel/VBox/TutorialProgress
@onready var tutorial_next_button: Button = $TutorialPanel/VBox/TutorialButtons/TutorialNextButton
@onready var tutorial_skip_button: Button = $TutorialPanel/VBox/TutorialButtons/TutorialSkipButton
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
var is_syncing_services := false
var is_syncing_balance := false
var last_viewport_size: Vector2 = Vector2.ZERO
var scenario_cards: Dictionary = {}
var scenario_card_order: Array[String] = []
var tutorial_step_index := 0
var tutorial_active := false
var compact_mode := false
var hud_mode_button: Button
const COMPACT_TOGGLE_KEY := KEY_TAB
const COMPACT_HIDE_PANELS := [
	"OverlayPanel",
	"EventPanel",
	"AlertsPanel",
	"TutorialPanel",
	"MilestoneBanner"
]
const TUTORIAL_STATE_PATH := "user://tutorial_state.json"
const TUTORIAL_STEPS := [
	{
		"title": "Welcome to Neon Boroughs",
		"body": "Paint roads and zones with number keys 1-5, then drag with left mouse to build quickly."
	},
	{
		"title": "Seed and Scenario",
		"body": "Use seed + presets to generate district layouts, then pick a balance profile to tune growth pressure."
	},
	{
		"title": "Services and Overlays",
		"body": "Adjust police/fire/sanitation/transit, then inspect Land/Noise/Crime overlays to spot weak neighborhoods."
	},
	{
		"title": "District Management",
		"body": "Focus districts from demand rows, set policies in the popup, and react to events before they compound."
	},
	{
		"title": "Progress and Persistence",
		"body": "Track objectives + alerts, use save slots/autosave, and keep a positive treasury for long-term expansion."
	}
]

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
	balance_profile_select.item_selected.connect(_on_balance_profile_selected)
	scenario_card_select.item_selected.connect(_on_scenario_card_selected)
	apply_scenario_card_button.pressed.connect(_on_apply_scenario_card)
	police_slider.value_changed.connect(_on_service_changed.bind("police"))
	fire_slider.value_changed.connect(_on_service_changed.bind("fire"))
	sanitation_slider.value_changed.connect(_on_service_changed.bind("sanitation"))
	transit_slider.value_changed.connect(_on_service_changed.bind("transit"))
	overlay_select.item_selected.connect(_on_overlay_selected)
	trigger_event_button.pressed.connect(_on_trigger_event)
	input_seed.text_submitted.connect(_on_text_submitted)
	close_popup_button.pressed.connect(_on_close_popup)
	policy_balanced_button.pressed.connect(_on_set_policy.bind("balanced"))
	policy_growth_button.pressed.connect(_on_set_policy.bind("growth"))
	policy_profit_button.pressed.connect(_on_set_policy.bind("profit"))
	tutorial_next_button.pressed.connect(_on_tutorial_next)
	tutorial_skip_button.pressed.connect(_on_tutorial_skip)
	popup_panel.visible = false
	milestone_banner.visible = false
	tutorial_panel.visible = false
	_setup_hud_mode_button()
	_apply_retro_ui_theme()
	_apply_layout_pass_v1()
	last_viewport_size = get_viewport().get_visible_rect().size
	_apply_tooltips()
	_init_slot_ui()
	_init_balance_profiles()
	_init_scenario_cards()
	_init_overlay_ui()
	_init_tutorial()
	_refresh_service_controls()
	_refresh_economy()
	_refresh_event_panel()
	_refresh_objectives()
	_set_compact_mode(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == COMPACT_TOGGLE_KEY:
		if input_seed.has_focus():
			return
		_set_compact_mode(not compact_mode)

func _apply_layout_pass_v1() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var margin: float = 14.0
	var gap: float = 10.0
	var left_w: float = float(clamp(viewport_size.x * 0.26, 352.0, 420.0))
	var mid_w: float = float(clamp(viewport_size.x * 0.2, 270.0, 320.0))
	var right_x: float = margin + left_w + gap + mid_w + gap
	var right_w: float = max(300.0, viewport_size.x - right_x - margin)
	var top_h: float = 190.0
	var demand_h: float = float(clamp(viewport_size.y * 0.39, 256.0, 340.0))
	var services_h: float = max(178.0, viewport_size.y - margin * 2.0 - top_h - demand_h - gap * 2.0)

	_set_panel_rect(get_node_or_null("Panel"), margin, margin, left_w, top_h)
	_set_panel_rect(get_node_or_null("DemandPanel"), margin, margin + top_h + gap, left_w, demand_h)
	_set_panel_rect(get_node_or_null("ServicesPanel"), margin, margin + top_h + gap + demand_h + gap, left_w, services_h)

	var mid_x: float = margin + left_w + gap
	_set_panel_rect(get_node_or_null("EconomyPanel"), mid_x, margin, mid_w, 154.0)
	_set_panel_rect(get_node_or_null("ObjectivesPanel"), mid_x, margin + 154.0 + gap, mid_w, 120.0)
	_set_panel_rect(get_node_or_null("AlertsPanel"), mid_x, margin + 154.0 + gap + 120.0 + gap, mid_w, viewport_size.y - (margin + 154.0 + gap + 120.0 + gap) - margin)
	_set_panel_rect(get_node_or_null("DistrictPopup"), mid_x, margin, mid_w, 230.0)

	_set_panel_rect(get_node_or_null("MilestoneBanner"), right_x, margin, right_w, 112.0)
	_set_panel_rect(get_node_or_null("OverlayPanel"), right_x, margin + 112.0 + gap, right_w, 104.0)
	_set_panel_rect(get_node_or_null("EventPanel"), right_x, margin + 112.0 + gap + 104.0 + gap, right_w, 134.0)
	_set_panel_rect(get_node_or_null("TutorialPanel"), right_x, margin + 112.0 + gap + 104.0 + gap + 134.0 + gap, right_w, 152.0)
	_set_panel_rect(get_node_or_null("ScenarioCardsPanel"), right_x, margin + 112.0 + gap + 104.0 + gap + 134.0 + gap + 152.0 + gap, right_w, viewport_size.y - (margin + 112.0 + gap + 104.0 + gap + 134.0 + gap + 152.0 + gap) - margin)

	if hud_mode_button != null:
		hud_mode_button.position = Vector2(right_x + right_w - 132.0, margin + 4.0)
		hud_mode_button.size = Vector2(128.0, 26.0)

func _set_panel_rect(node: Node, left: float, top: float, width: float, height: float) -> void:
	if not (node is Control):
		return
	var ctl: Control = node
	ctl.offset_left = left
	ctl.offset_top = top
	ctl.offset_right = left + max(80.0, width)
	ctl.offset_bottom = top + max(40.0, height)

func _setup_hud_mode_button() -> void:
	hud_mode_button = Button.new()
	hud_mode_button.text = "HUD: Full"
	hud_mode_button.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_mode_button.pressed.connect(_on_toggle_compact_mode)
	add_child(hud_mode_button)

func _on_toggle_compact_mode() -> void:
	_set_compact_mode(not compact_mode)

func _set_compact_mode(enabled: bool) -> void:
	compact_mode = enabled
	for panel_name in COMPACT_HIDE_PANELS:
		var panel_node: Node = get_node_or_null(panel_name)
		if panel_node == null:
			continue
		if panel_name == "TutorialPanel" and tutorial_active:
			panel_node.set("visible", true)
			continue
		panel_node.set("visible", not compact_mode)
	if hud_mode_button != null:
		hud_mode_button.text = "HUD: Compact" if compact_mode else "HUD: Full"
		hud_mode_button.tooltip_text = "Toggle HUD clutter reduction (Tab)."

func _process(delta: float) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size != last_viewport_size:
		last_viewport_size = viewport_size
		_apply_layout_pass_v1()

	ui_timer += delta
	if ui_timer >= 0.4:
		ui_timer = 0.0
		_refresh_demand_bars()
		_refresh_service_controls()
		_refresh_overlay_controls()
		_refresh_economy()
		_refresh_balance_profile()
		_refresh_event_panel()
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
		var traffic_stress: float = float(row_data.get("traffic_stress", 0.0))
		var service_stress: float = float(row_data.get("service_stress", 0.0))
		var upkeep_hook: float = float(row_data.get("upkeep_hook", 1.0))
		var active_event: String = String(row_data.get("active_event", "None"))
		var identity_tag: String = String(row_data.get("primary_archetype", _district_identity_tag(district_id))).replace("_", " ")
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
		sub.text = "R %d  C %d  I %d  |  T %.2f  S %.2f  U %.2f  |  %s  |  %s  |  %s" % [
			res_d, com_d, ind_d, traffic_stress, service_stress, upkeep_hook, String(POLICY_LABELS.get(policy_id, "Balanced")), active_event, identity_tag
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
	var traffic_stress: float = float(row_data.get("traffic_stress", 0.0))
	var service_stress: float = float(row_data.get("service_stress", 0.0))
	var upkeep_hook: float = float(row_data.get("upkeep_hook", 1.0))
	var active_event: String = String(row_data.get("active_event", "None"))
	var identity_tag: String = String(row_data.get("primary_archetype", _district_identity_tag(district_id))).replace("_", " ")
	var policy_id: String = String(row_data.get("policy_id", "balanced"))

	popup_title.text = "%s District" % district_name
	popup_body.text = "Demand %d\nResidential %d\nCommercial %d\nIndustrial %d\nTraffic Stress %.2f\nService Stress %.2f\nUpkeep Hook %.2f\nActive Event %s\nIdentity %s" % [
		demand, res_d, com_d, ind_d, traffic_stress, service_stress, upkeep_hook, active_event, identity_tag
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

func _init_balance_profiles() -> void:
	balance_profile_select.clear()
	if city_grid == null:
		return
	if not city_grid.has_method("get_balance_profiles"):
		return

	var profiles_v: Variant = city_grid.call("get_balance_profiles")
	if typeof(profiles_v) != TYPE_DICTIONARY:
		return
	var profiles: Dictionary = profiles_v
	var keys: Array[String] = []
	for key in profiles.keys():
		keys.append(String(key))
	keys.sort()
	for profile_id in keys:
		var profile_v: Variant = profiles.get(profile_id, {})
		var profile: Dictionary = profile_v if typeof(profile_v) == TYPE_DICTIONARY else {}
		var name: String = String(profile.get("display_name", profile_id.capitalize()))
		balance_profile_select.add_item(name, balance_profile_select.get_item_count())
		var idx: int = balance_profile_select.get_item_count() - 1
		balance_profile_select.set_item_metadata(idx, profile_id)
	_refresh_balance_profile()

func _on_balance_profile_selected(index: int) -> void:
	if is_syncing_balance:
		return
	if city_grid == null:
		return
	if not city_grid.has_method("set_balance_profile"):
		return
	if index < 0 or index >= balance_profile_select.get_item_count():
		return
	var profile_id: String = String(balance_profile_select.get_item_metadata(index))
	var ok: bool = city_grid.call("set_balance_profile", profile_id)
	if ok:
		status_label.text = "Balance profile set: %s" % balance_profile_select.get_item_text(index)
	else:
		status_label.text = "Invalid balance profile."
	_refresh_balance_profile()

func _refresh_balance_profile() -> void:
	if city_grid == null:
		return
	if not city_grid.has_method("get_balance_profile_id"):
		return
	var active_id: String = String(city_grid.call("get_balance_profile_id"))
	is_syncing_balance = true
	for i in range(balance_profile_select.get_item_count()):
		var profile_id: String = String(balance_profile_select.get_item_metadata(i))
		if profile_id == active_id:
			if balance_profile_select.selected != i:
				balance_profile_select.select(i)
			break
	is_syncing_balance = false

func _init_scenario_cards() -> void:
	scenario_cards = _load_scenario_cards()
	if scenario_cards.is_empty():
		scenario_cards = SCENARIOS.duplicate(true)

	scenario_card_order.clear()
	for card_key in scenario_cards.keys():
		scenario_card_order.append(String(card_key))
	scenario_card_order.sort()

	scenario_card_select.clear()
	for card_id in scenario_card_order:
		var card_v: Variant = scenario_cards.get(card_id, {})
		var card: Dictionary = card_v if typeof(card_v) == TYPE_DICTIONARY else {}
		var card_name: String = String(card.get("name", card_id.capitalize()))
		scenario_card_select.add_item(card_name, scenario_card_select.get_item_count())
		var idx: int = scenario_card_select.get_item_count() - 1
		scenario_card_select.set_item_metadata(idx, card_id)

	if scenario_card_select.get_item_count() > 0:
		scenario_card_select.select(0)
	_refresh_scenario_card_preview()

func _load_scenario_cards() -> Dictionary:
	if not FileAccess.file_exists(scenario_cards_path):
		return {}
	var fp := FileAccess.open(scenario_cards_path, FileAccess.READ)
	if fp == null:
		return {}
	var parsed: Variant = JSON.parse_string(fp.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var payload: Dictionary = parsed
	var cards_v: Variant = payload.get("cards", payload)
	if typeof(cards_v) != TYPE_DICTIONARY:
		return {}
	var cards_dict: Dictionary = cards_v
	var cards: Dictionary = {}
	for key in cards_dict.keys():
		var card_v: Variant = cards_dict.get(key, {})
		if typeof(card_v) == TYPE_DICTIONARY:
			cards[String(key)] = (card_v as Dictionary).duplicate(true)
	return cards

func _on_scenario_card_selected(_index: int) -> void:
	_refresh_scenario_card_preview()

func _refresh_scenario_card_preview() -> void:
	if scenario_card_select.get_item_count() == 0:
		scenario_summary.text = "No authored cards loaded."
		scenario_goals.text = "Goals: Add data/runtime/scenario_cards.json."
		return
	var idx: int = scenario_card_select.selected
	if idx < 0 or idx >= scenario_card_select.get_item_count():
		idx = 0
		scenario_card_select.select(0)
	var card_id: String = String(scenario_card_select.get_item_metadata(idx))
	var card_v: Variant = scenario_cards.get(card_id, {})
	var card: Dictionary = card_v if typeof(card_v) == TYPE_DICTIONARY else {}
	var summary: String = String(card.get("summary", "No summary provided."))
	var goals_v: Variant = card.get("goal_cards", [])
	var goals: Array[String] = []
	if typeof(goals_v) == TYPE_ARRAY:
		for goal_v in goals_v:
			goals.append(String(goal_v))
	scenario_summary.text = summary
	if goals.is_empty():
		scenario_goals.text = "Goals: Sandbox freeplay."
	else:
		scenario_goals.text = "Goals:\n- %s" % "\n- ".join(goals)

func _on_apply_scenario_card() -> void:
	var idx: int = scenario_card_select.selected
	if idx < 0 or idx >= scenario_card_select.get_item_count():
		status_label.text = "Select a scenario card first."
		return
	var card_id: String = String(scenario_card_select.get_item_metadata(idx))
	var card_v: Variant = scenario_cards.get(card_id, {})
	if typeof(card_v) != TYPE_DICTIONARY:
		status_label.text = "Scenario card data missing."
		return
	_apply_scenario_payload(card_v, card_id)

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

func _init_tutorial() -> void:
	var seen: bool = _load_tutorial_seen()
	if seen:
		tutorial_active = false
		tutorial_panel.visible = false
		return
	tutorial_active = true
	tutorial_step_index = 0
	_refresh_tutorial_panel()

func _refresh_tutorial_panel() -> void:
	if not tutorial_active:
		tutorial_panel.visible = false
		return
	if tutorial_step_index < 0 or tutorial_step_index >= TUTORIAL_STEPS.size():
		tutorial_active = false
		tutorial_panel.visible = false
		_save_tutorial_seen(true)
		return
	tutorial_panel.visible = true
	var step: Dictionary = TUTORIAL_STEPS[tutorial_step_index]
	tutorial_title.text = String(step.get("title", "Onboarding"))
	tutorial_body.text = String(step.get("body", ""))
	tutorial_progress.text = "Step %d/%d" % [tutorial_step_index + 1, TUTORIAL_STEPS.size()]
	tutorial_next_button.text = "Finish" if tutorial_step_index == TUTORIAL_STEPS.size() - 1 else "Next"

func _on_tutorial_next() -> void:
	if not tutorial_active:
		return
	tutorial_step_index += 1
	if tutorial_step_index >= TUTORIAL_STEPS.size():
		tutorial_active = false
		tutorial_panel.visible = false
		_save_tutorial_seen(true)
		status_label.text = "Tutorial complete."
		return
	_refresh_tutorial_panel()

func _on_tutorial_skip() -> void:
	tutorial_active = false
	tutorial_panel.visible = false
	_save_tutorial_seen(true)
	status_label.text = "Tutorial skipped."

func _load_tutorial_seen() -> bool:
	if not FileAccess.file_exists(TUTORIAL_STATE_PATH):
		return false
	var fp := FileAccess.open(TUTORIAL_STATE_PATH, FileAccess.READ)
	if fp == null:
		return false
	var parsed: Variant = JSON.parse_string(fp.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var payload: Dictionary = parsed
	return bool(payload.get("tutorial_seen", false))

func _save_tutorial_seen(seen: bool) -> void:
	var payload := {"tutorial_seen": seen}
	var fp := FileAccess.open(TUTORIAL_STATE_PATH, FileAccess.WRITE)
	if fp == null:
		return
	fp.store_string(JSON.stringify(payload))

func _apply_tooltips() -> void:
	input_seed.tooltip_text = "Deterministic city seed. Use same seed for same base layout."
	apply_button.tooltip_text = "Regenerate districts with the current seed."
	random_button.tooltip_text = "Roll a random seed and regenerate."
	save_button.tooltip_text = "Save current city state to selected slot."
	load_button.tooltip_text = "Load selected save slot."
	load_latest_button.tooltip_text = "Load most recently modified save slot."
	autosave_toggle.tooltip_text = "Enable rolling autosaves every ~20 seconds."
	balance_profile_select.tooltip_text = "Scenario tuning profile affecting growth/tax/upkeep/event pressure."
	scenario_card_select.tooltip_text = "Authorable scenario cards from JSON with goals and setup parameters."
	apply_scenario_card_button.tooltip_text = "Apply selected card seed, district policies, balance profile, and service levels."
	pause_button.tooltip_text = "Pause or resume simulation."
	speed_1x_button.tooltip_text = "Set simulation speed to real-time."
	speed_3x_button.tooltip_text = "Set simulation speed to 3x."
	police_slider.tooltip_text = "Higher police lowers crime stress."
	fire_slider.tooltip_text = "Higher fire lowers disaster risk impact."
	sanitation_slider.tooltip_text = "Higher sanitation improves land value and reduces noise pressure."
	transit_slider.tooltip_text = "Higher transit improves growth and commute outcomes."
	overlay_select.tooltip_text = "Select an overlay to visualize hidden simulation pressures."
	trigger_event_button.tooltip_text = "Force a random district event for stress testing."
	if hud_mode_button != null:
		hud_mode_button.tooltip_text = "Toggle compact HUD mode to reduce panel clutter (Tab)."

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
	var avg_upkeep_hook: float = float(snap.get("avg_upkeep_hook", 1.0))
	var balance_profile_id: String = String(snap.get("balance_profile_id", "standard"))
	var era_stage_label: String = String(snap.get("era_stage_label", "Late 90s Stability"))
	var theme_pressure: float = float(snap.get("theme_pressure", 0.0))
	var difficulty_upkeep_mult: float = float(snap.get("difficulty_upkeep_mult", 1.0))
	var event_title: String = String(snap.get("active_event_title", "None"))
	var event_district: String = String(snap.get("active_event_district", ""))
	var event_ticks_left: int = int(snap.get("event_ticks_left", 0))

	econ_money.text = "Money: $%d (%s%d)" % [money, "+" if d_money >= 0 else "", d_money]
	econ_population.text = "Population: %d (%s%d)" % [pop, "+" if d_pop >= 0 else "", d_pop]
	econ_jobs.text = "Jobs: %d (%s%d)" % [jobs, "+" if d_jobs >= 0 else "", d_jobs]
	econ_pressure.text = "Housing P: %.2f  |  Job P: %.2f  |  Upkeep x%.2f  |  Era %s  |  Theme %.0f%%  |  Diff Upkeep x%.2f  |  Balance %s" % [
		housing_p,
		job_p,
		avg_upkeep_hook,
		era_stage_label,
		theme_pressure * 100.0,
		difficulty_upkeep_mult,
		balance_profile_id
	]
	if event_title != "None":
		econ_pressure.text += "  |  %s (%s, %dt)" % [event_title, event_district, event_ticks_left]

func _on_service_changed(value: float, service_id: String) -> void:
	if is_syncing_services:
		return
	if city_grid == null:
		return
	if not city_grid.has_method("set_service_level"):
		return
	city_grid.call("set_service_level", service_id, value)
	_update_service_labels()

func _refresh_service_controls() -> void:
	if city_grid == null:
		return
	if not city_grid.has_method("get_service_levels"):
		return

	var levels_v: Variant = city_grid.call("get_service_levels")
	if typeof(levels_v) != TYPE_DICTIONARY:
		return
	var levels: Dictionary = levels_v

	is_syncing_services = true
	police_slider.value = float(levels.get("police", police_slider.value))
	fire_slider.value = float(levels.get("fire", fire_slider.value))
	sanitation_slider.value = float(levels.get("sanitation", sanitation_slider.value))
	transit_slider.value = float(levels.get("transit", transit_slider.value))
	is_syncing_services = false
	_update_service_labels()

func _update_service_labels() -> void:
	police_value.text = str(int(round(police_slider.value)))
	fire_value.text = str(int(round(fire_slider.value)))
	sanitation_value.text = str(int(round(sanitation_slider.value)))
	transit_value.text = str(int(round(transit_slider.value)))

func _init_overlay_ui() -> void:
	overlay_select.clear()
	overlay_select.add_item("Overlay: None", 0)
	overlay_select.add_item("Overlay: Land Value", 1)
	overlay_select.add_item("Overlay: Noise", 2)
	overlay_select.add_item("Overlay: Crime", 3)
	overlay_select.select(0)
	overlay_stats.text = "Land 0.0  Noise 0.0  Crime 0.0  Commute 0.0"

func _on_overlay_selected(index: int) -> void:
	if city_grid == null:
		return
	if not city_grid.has_method("set_overlay_mode"):
		return
	var mode := "none"
	if index == 1:
		mode = "land_value"
	elif index == 2:
		mode = "noise"
	elif index == 3:
		mode = "crime"
	city_grid.call("set_overlay_mode", mode)

func _refresh_overlay_controls() -> void:
	if city_grid == null:
		return
	if not city_grid.has_method("get_overlay_mode"):
		return
	if not city_grid.has_method("get_overlay_metrics"):
		return

	var mode: String = String(city_grid.call("get_overlay_mode"))
	var target_idx := 0
	if mode == "land_value":
		target_idx = 1
	elif mode == "noise":
		target_idx = 2
	elif mode == "crime":
		target_idx = 3
	if overlay_select.selected != target_idx:
		overlay_select.select(target_idx)

	var metrics_v: Variant = city_grid.call("get_overlay_metrics")
	if typeof(metrics_v) != TYPE_DICTIONARY:
		return
	var metrics: Dictionary = metrics_v
	var land: float = float(metrics.get("avg_land_value", 0.0))
	var noise: float = float(metrics.get("avg_noise", 0.0))
	var crime: float = float(metrics.get("avg_crime", 0.0))
	var commute: float = float(metrics.get("avg_commute_penalty", 0.0))
	overlay_stats.text = "Land %.1f  Noise %.1f  Crime %.1f  Commute %.2f" % [land, noise, crime, commute]

func _on_trigger_event() -> void:
	if city_grid == null:
		return
	if not city_grid.has_method("trigger_random_event"):
		return
	var ok: bool = city_grid.call("trigger_random_event")
	if ok:
		status_label.text = "Manual event triggered."
	else:
		status_label.text = "Unable to trigger event right now."
	_refresh_event_panel()

func _refresh_event_panel() -> void:
	if city_grid == null:
		return
	if not city_grid.has_method("get_event_snapshot"):
		return
	var snap_v: Variant = city_grid.call("get_event_snapshot")
	if typeof(snap_v) != TYPE_DICTIONARY:
		return
	var snap: Dictionary = snap_v
	var title: String = String(snap.get("active_event_title", "None"))
	var district_id: String = String(snap.get("active_event_district", ""))
	var ticks_left: int = int(snap.get("ticks_left", 0))
	var cooldown: int = int(snap.get("cooldown_ticks", 0))
	if title == "None":
		event_status.text = "Active: None (cooldown %dt)" % cooldown
	else:
		event_status.text = "Active: %s in %s (%dt)" % [title, String(DISTRICT_NAMES.get(district_id, district_id)), ticks_left]

	var recent_v: Variant = snap.get("recent_events", [])
	if typeof(recent_v) != TYPE_ARRAY:
		event_history.text = "History: none"
		return
	var recent: Array = recent_v
	if recent.is_empty():
		event_history.text = "History: none"
		return
	var latest: Dictionary = recent[recent.size() - 1]
	var latest_title: String = String(latest.get("event_title", "Event"))
	var latest_district: String = String(latest.get("district_id", ""))
	var latest_state: String = String(latest.get("state", ""))
	var latest_tick: int = int(latest.get("tick", 0))
	event_history.text = "Last: t%d %s %s (%s)" % [
		latest_tick,
		latest_title,
		String(DISTRICT_NAMES.get(latest_district, latest_district)),
		latest_state
	]

func _district_identity_tag(district_id: String) -> String:
	if city_grid == null:
		return "Identity n/a"
	if not city_grid.has_method("get_district_identity"):
		return "Identity n/a"
	var id_v: Variant = city_grid.call("get_district_identity", district_id)
	if typeof(id_v) != TYPE_DICTIONARY:
		return "Identity n/a"
	var identity: Dictionary = id_v
	var archetypes_v: Variant = identity.get("archetypes", [])
	if typeof(archetypes_v) != TYPE_ARRAY:
		return "Identity n/a"
	var archetypes: Array = archetypes_v
	if archetypes.is_empty():
		return "Identity n/a"
	return String(archetypes[0]).replace("_", " ")

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
	if not SCENARIOS.has(preset_id):
		status_label.text = "Preset not found."
		return
	var preset_v: Variant = SCENARIOS[preset_id]
	if typeof(preset_v) != TYPE_DICTIONARY:
		status_label.text = "Preset data invalid."
		return
	_apply_scenario_payload(preset_v, preset_id)

func _apply_scenario_payload(payload_v: Variant, fallback_id: String) -> void:
	if district_generator == null:
		return
	if city_grid == null:
		return
	if typeof(payload_v) != TYPE_DICTIONARY:
		return
	var payload: Dictionary = payload_v
	var seed: int = int(payload.get("seed", district_generator.call("get_world_seed")))
	var scenario_name: String = String(payload.get("name", fallback_id))
	input_seed.text = str(seed)
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

	status_label.text = "Scenario loaded: %s" % scenario_name
	_refresh_demand_bars()
	_refresh_service_controls()
	_refresh_balance_profile()
	_refresh_economy()
	_refresh_objectives()
	_refresh_alerts()
	_refresh_scenario_card_preview()
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

func _apply_retro_ui_theme() -> void:
	var panel_bg := Color(0.09, 0.1, 0.16, 0.9)
	var panel_border := Color(0.87, 0.55, 0.24, 0.86)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = panel_bg
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = panel_border
	panel_style.corner_radius_top_left = 2
	panel_style.corner_radius_top_right = 2
	panel_style.corner_radius_bottom_left = 2
	panel_style.corner_radius_bottom_right = 2

	var panel_paths: Array[String] = [
		"Panel",
		"DemandPanel",
		"ServicesPanel",
		"EconomyPanel",
		"AlertsPanel",
		"OverlayPanel",
		"EventPanel",
		"ObjectivesPanel",
		"ScenarioCardsPanel",
		"DistrictPopup",
		"MilestoneBanner",
		"TutorialPanel"
	]
	for panel_path in panel_paths:
		var node: Node = get_node_or_null(panel_path)
		if node is PanelContainer:
			var panel_node: PanelContainer = node
			panel_node.add_theme_stylebox_override("panel", panel_style.duplicate())

	var button_normal := StyleBoxFlat.new()
	button_normal.bg_color = Color(0.14, 0.17, 0.25, 0.96)
	button_normal.border_width_left = 1
	button_normal.border_width_top = 1
	button_normal.border_width_right = 1
	button_normal.border_width_bottom = 1
	button_normal.border_color = Color(0.25, 0.72, 0.69, 0.85)
	button_normal.corner_radius_top_left = 2
	button_normal.corner_radius_top_right = 2
	button_normal.corner_radius_bottom_left = 2
	button_normal.corner_radius_bottom_right = 2

	var button_hover: StyleBoxFlat = button_normal.duplicate()
	button_hover.bg_color = Color(0.18, 0.22, 0.31, 0.98)
	button_hover.border_color = Color(0.91, 0.62, 0.28, 0.9)

	var button_pressed: StyleBoxFlat = button_normal.duplicate()
	button_pressed.bg_color = Color(0.21, 0.14, 0.12, 0.98)
	button_pressed.border_color = Color(0.91, 0.62, 0.28, 1.0)

	for btn in _all_buttons():
		btn.custom_minimum_size = Vector2(0.0, 28.0)
		btn.add_theme_stylebox_override("normal", button_normal.duplicate())
		btn.add_theme_stylebox_override("hover", button_hover.duplicate())
		btn.add_theme_stylebox_override("pressed", button_pressed.duplicate())
		btn.add_theme_color_override("font_color", Color(0.83, 0.87, 0.95, 0.98))
		btn.add_theme_color_override("font_hover_color", Color(0.94, 0.67, 0.3, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.98, 0.84, 0.62, 1.0))

	for picker in [slot_select, balance_profile_select, scenario_card_select, overlay_select]:
		picker.custom_minimum_size = Vector2(0.0, 28.0)

	for slider in [police_slider, fire_slider, sanitation_slider, transit_slider]:
		slider.custom_minimum_size = Vector2(0.0, 24.0)

	_apply_label_palette(self)

func _all_buttons() -> Array[Button]:
	var buttons: Array[Button] = [
		apply_button,
		random_button,
		save_button,
		load_button,
		load_latest_button,
		pause_button,
		speed_1x_button,
		speed_3x_button,
		preset_balanced_button,
		preset_midtown_button,
		preset_boroughs_button,
		apply_scenario_card_button,
		policy_balanced_button,
		policy_growth_button,
		policy_profit_button,
		close_popup_button,
		trigger_event_button,
		tutorial_next_button,
		tutorial_skip_button
	]
	if hud_mode_button != null:
		buttons.append(hud_mode_button)
	return buttons

func _apply_label_palette(root: Node) -> void:
	for child in root.get_children():
		if child is Label:
			var label: Label = child
			label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.93, 0.98))
			if label.name == "Title" or label.name.find("Title") != -1:
				label.add_theme_color_override("font_color", Color(0.95, 0.66, 0.32, 0.98))
		_apply_label_palette(child)
