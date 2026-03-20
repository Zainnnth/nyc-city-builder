extends CanvasLayer

signal district_focus_requested(target_pos: Vector2)

@export var district_generator_path: NodePath = ^"../DistrictGenerator"
@export var city_grid_path: NodePath = ^"../CityGrid"

@onready var input_seed: LineEdit = $Panel/VBox/SeedRow/SeedInput
@onready var apply_button: Button = $Panel/VBox/Controls/ApplySeedButton
@onready var random_button: Button = $Panel/VBox/Controls/RandomSeedButton
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var demand_rows: VBoxContainer = $DemandPanel/VBox/DemandRows
@onready var popup_panel: PanelContainer = $DistrictPopup
@onready var popup_title: Label = $DistrictPopup/VBox/PopupTitle
@onready var popup_body: Label = $DistrictPopup/VBox/PopupBody
@onready var close_popup_button: Button = $DistrictPopup/VBox/ClosePopupButton

var district_generator: Node2D
var city_grid: Node2D
var rng := RandomNumberGenerator.new()
var ui_timer := 0.0

const DISTRICT_NAMES := {
	"midtown_core": "Midtown",
	"financial_district": "Financial",
	"lower_east_side": "Lower East Side",
	"harlem": "Harlem",
	"queens_west": "Queens West",
	"outer_borough_mix": "Outer Mix"
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
	input_seed.text_submitted.connect(_on_text_submitted)
	close_popup_button.pressed.connect(_on_close_popup)
	popup_panel.visible = false

func _process(delta: float) -> void:
	ui_timer += delta
	if ui_timer >= 0.4:
		ui_timer = 0.0
		_refresh_demand_bars()

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
		sub.text = "R %d  C %d  I %d" % [res_d, com_d, ind_d]
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
	_show_popup(district_id, row_data)
	status_label.text = "Focused %s." % String(DISTRICT_NAMES.get(district_id, district_id))

func _show_popup(district_id: String, row_data: Dictionary) -> void:
	var district_name: String = String(DISTRICT_NAMES.get(district_id, district_id))
	var demand: int = int(round(float(row_data.get("demand_index", 0.0))))
	var res_d: int = int(round(float(row_data.get("res_demand", 0.0))))
	var com_d: int = int(round(float(row_data.get("com_demand", 0.0))))
	var ind_d: int = int(round(float(row_data.get("ind_demand", 0.0))))

	popup_title.text = "%s District" % district_name
	popup_body.text = "Demand %d\nResidential %d\nCommercial %d\nIndustrial %d" % [
		demand, res_d, com_d, ind_d
	]
	popup_panel.visible = true

func _on_close_popup() -> void:
	popup_panel.visible = false
