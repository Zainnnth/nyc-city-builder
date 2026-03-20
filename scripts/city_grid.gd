extends Node2D

@export var columns := 24
@export var rows := 16
@export var cell_size := 64.0

enum Tool {
	ROAD,
	RESIDENTIAL,
	COMMERCIAL,
	INDUSTRIAL,
	BULLDOZE
}

const GRID_LINE_COLOR := Color(0.27, 0.31, 0.39, 0.85)
const BORDER_COLOR := Color(0.9, 0.52, 0.19, 0.9)
const BACKDROP_COLOR := Color(0.08, 0.09, 0.15, 0.98)
const ROAD_COLOR := Color(0.24, 0.26, 0.31, 1.0)
const EMPTY_LOT_COLOR := Color(0.11, 0.13, 0.2, 0.95)
const OUTLINE_COLOR := Color(0.08, 0.09, 0.13, 0.95)
const BUILDING_COLOR := Color(0.8, 0.84, 0.91, 0.9)

const ZONE_COLORS := {
	Tool.RESIDENTIAL: Color(0.26, 0.38, 0.7, 0.62),
	Tool.COMMERCIAL: Color(0.73, 0.57, 0.24, 0.62),
	Tool.INDUSTRIAL: Color(0.55, 0.35, 0.3, 0.62)
}

const TOOL_NAMES := {
	Tool.ROAD: "Road",
	Tool.RESIDENTIAL: "Residential",
	Tool.COMMERCIAL: "Commercial",
	Tool.INDUSTRIAL: "Industrial",
	Tool.BULLDOZE: "Bulldoze"
}

const ZONE_CAPACITY := {
	Tool.RESIDENTIAL: 14,
	Tool.COMMERCIAL: 9,
	Tool.INDUSTRIAL: 11
}

const TOOL_KEYS := {
	KEY_1: Tool.ROAD,
	KEY_2: Tool.RESIDENTIAL,
	KEY_3: Tool.COMMERCIAL,
	KEY_4: Tool.INDUSTRIAL,
	KEY_5: Tool.BULLDOZE
}

var selected_tool: Tool = Tool.ROAD
var is_drag_painting := false

var zone_by_index: Array[int] = []
var road_by_index: Array[bool] = []
var building_level_by_index: Array[int] = []
var district_id_by_index: Array[String] = []
var style_profile_by_index: Array[String] = []

var sim_timer := 0.0
const SIM_STEP_SECONDS := 1.0

var money := 8000
var population := 0
var jobs := 0
var connected_residential := 0
var connected_commercial := 0
var connected_industrial := 0
var district_demand_snapshot: Array[Dictionary] = []

const DISTRICT_TINTS := {
	"midtown_core": Color(0.98, 0.86, 0.54, 1.0),
	"financial_district": Color(0.96, 0.79, 0.60, 1.0),
	"lower_east_side": Color(0.70, 0.82, 0.98, 1.0),
	"harlem": Color(0.68, 0.90, 0.76, 1.0),
	"queens_west": Color(0.84, 0.76, 0.97, 1.0),
	"outer_borough_mix": Color(0.85, 0.87, 0.92, 1.0)
}

const DISTRICT_TAX_MULT := {
	"midtown_core": 1.18,
	"financial_district": 1.22,
	"lower_east_side": 1.03,
	"harlem": 0.98,
	"queens_west": 1.01,
	"outer_borough_mix": 1.0
}

const DISTRICT_UPKEEP_MULT := {
	"midtown_core": 1.12,
	"financial_district": 1.15,
	"lower_east_side": 1.0,
	"harlem": 0.95,
	"queens_west": 0.98,
	"outer_borough_mix": 1.0
}

func _draw() -> void:
	var map_size := Vector2(columns * cell_size, rows * cell_size)
	draw_rect(Rect2(Vector2.ZERO, map_size), BACKDROP_COLOR, true)

	for y in rows:
		for x in columns:
			var i := _to_index(Vector2i(x, y))
			var rect := Rect2(Vector2(x, y) * cell_size, Vector2.ONE * cell_size)
			_draw_tile(rect, i)
			draw_rect(rect, GRID_LINE_COLOR, false, 1.0)

	draw_rect(Rect2(Vector2.ZERO, map_size), BORDER_COLOR, false, 3.0)
	_draw_hud(map_size)
	_draw_tool_legend(map_size)

func _ready() -> void:
	_init_tiles()
	queue_redraw()

func _process(delta: float) -> void:
	sim_timer += delta
	while sim_timer >= SIM_STEP_SECONDS:
		sim_timer -= SIM_STEP_SECONDS
		_run_sim_step()
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if TOOL_KEYS.has(event.keycode):
			selected_tool = TOOL_KEYS[event.keycode]
			queue_redraw()
			return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_drag_painting = event.pressed
			if event.pressed:
				_paint_at_mouse_position()

	if event is InputEventMouseMotion and is_drag_painting:
		_paint_at_mouse_position()

func _draw_tile(rect: Rect2, index: int) -> void:
	if road_by_index[index]:
		draw_rect(rect, ROAD_COLOR, true)
		return

	var zone := zone_by_index[index]
	if zone == Tool.BULLDOZE:
		draw_rect(rect, EMPTY_LOT_COLOR, true)
		return

	draw_rect(rect, ZONE_COLORS[zone], true)
	draw_rect(rect.grow(-5.0), OUTLINE_COLOR, false, 1.0)

	var building_level := building_level_by_index[index]
	if building_level > 0:
		var margin := 18.0 - float(building_level * 3)
		margin = clamp(margin, 6.0, 16.0)
		draw_rect(rect.grow(-margin), _building_color_for(index), true)

func _building_color_for(index: int) -> Color:
	var district_id: String = district_id_by_index[index]
	var district_tint: Color = DISTRICT_TINTS.get(district_id, DISTRICT_TINTS["outer_borough_mix"])
	var style_profile: String = style_profile_by_index[index]

	if style_profile.find("industrial") != -1:
		return district_tint.darkened(0.2)
	if style_profile.find("brownstone") != -1:
		return district_tint.darkened(0.1)
	return district_tint

func _draw_hud(map_size: Vector2) -> void:
	var text := "Tool: %s   |   Money: $%d   |   Pop: %d   |   Jobs: %d" % [
		TOOL_NAMES[selected_tool], money, population, jobs
	]
	draw_string(
		ThemeDB.fallback_font,
		Vector2(16, map_size.y + 36),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		map_size.x - 32,
		22,
		Color(0.83, 0.86, 0.93, 0.92)
	)

	var sim_text := "Connected Zones - Res: %d  Com: %d  Ind: %d" % [
		connected_residential, connected_commercial, connected_industrial
	]
	draw_string(
		ThemeDB.fallback_font,
		Vector2(16, map_size.y + 64),
		sim_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		map_size.x - 32,
		20,
		Color(0.73, 0.78, 0.9, 0.92)
	)

func _draw_tool_legend(map_size: Vector2) -> void:
	var text := "1 Road  2 Res  3 Com  4 Ind  5 Bulldoze   |   LMB drag: paint   |   Arrows: pan   |   Wheel: zoom"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(16, map_size.y + 92),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		map_size.x - 32,
		20,
		Color(0.63, 0.69, 0.81, 0.95)
	)

func _paint_at_mouse_position() -> void:
	var local_mouse := to_local(get_global_mouse_position())
	var cell := Vector2i(floor(local_mouse.x / cell_size), floor(local_mouse.y / cell_size))
	if not _is_in_bounds(cell):
		return

	var index := _to_index(cell)
	match selected_tool:
		Tool.ROAD:
			if not road_by_index[index]:
				road_by_index[index] = true
				zone_by_index[index] = Tool.BULLDOZE
				building_level_by_index[index] = 0
				money -= 8
		Tool.BULLDOZE:
			if road_by_index[index] or zone_by_index[index] != Tool.BULLDOZE or building_level_by_index[index] > 0:
				road_by_index[index] = false
				zone_by_index[index] = Tool.BULLDOZE
				building_level_by_index[index] = 0
				money -= 3
		_:
			if zone_by_index[index] != selected_tool or road_by_index[index]:
				road_by_index[index] = false
				zone_by_index[index] = selected_tool
				building_level_by_index[index] = 0
				money -= 5

	queue_redraw()

func _run_sim_step() -> void:
	var pop_capacity := 0
	var job_capacity := 0
	var road_upkeep_cost := 0.0
	var zone_upkeep_cost := 0.0
	var tax_income_raw := 0.0
	var district_stats := {}

	connected_residential = 0
	connected_commercial = 0
	connected_industrial = 0

	for y in rows:
		for x in columns:
			var cell := Vector2i(x, y)
			var i := _to_index(cell)

			if road_by_index[i]:
				road_upkeep_cost += 2.0 * _district_upkeep_multiplier(district_id_by_index[i])
				continue

			var zone := zone_by_index[i]
			if zone == Tool.BULLDOZE:
				building_level_by_index[i] = 0
				continue

			var connected := _is_adjacent_to_road(cell)
			var district_id: String = district_id_by_index[i]
			_ensure_district_stat(district_stats, district_id)
			var stat: Dictionary = district_stats[district_id]
			stat["zone_total"] = int(stat["zone_total"]) + 1
			if connected:
				stat["connected"] = int(stat["connected"]) + 1

			if not connected:
				building_level_by_index[i] = max(building_level_by_index[i] - 1, 0)
				district_stats[district_id] = stat
				continue

			building_level_by_index[i] = min(building_level_by_index[i] + 1, 3)
			var level := building_level_by_index[i]
			var style_profile: String = style_profile_by_index[i]
			var growth_mult := _growth_multiplier(style_profile)
			if zone == Tool.RESIDENTIAL:
				connected_residential += 1
				var res_cap := int(round(float(ZONE_CAPACITY[zone]) * level * growth_mult))
				pop_capacity += max(1, res_cap)
				stat["res_zones"] = int(stat["res_zones"]) + 1
			else:
				if zone == Tool.COMMERCIAL:
					connected_commercial += 1
					stat["com_zones"] = int(stat["com_zones"]) + 1
				if zone == Tool.INDUSTRIAL:
					connected_industrial += 1
					stat["ind_zones"] = int(stat["ind_zones"]) + 1
				var job_cap := int(round(float(ZONE_CAPACITY[zone]) * level * growth_mult))
				job_capacity += max(1, job_cap)

			var tile_output := (float(level) * 4.0) + 3.0
			tax_income_raw += tile_output * _district_tax_multiplier(district_id)
			zone_upkeep_cost += 1.0 * _district_upkeep_multiplier(district_id)
			stat["level_sum"] = int(stat["level_sum"]) + level
			district_stats[district_id] = stat

	var target_population: int = min(pop_capacity, int(round(job_capacity * 0.9)))
	population = int(lerp(float(population), float(target_population), 0.42))
	jobs = int(lerp(float(jobs), float(job_capacity), 0.35))

	var tax_income := int(round(population * 0.7 + jobs * 0.45 + tax_income_raw))
	var upkeep := int(round(road_upkeep_cost + zone_upkeep_cost))
	money += tax_income - upkeep
	_update_district_demand_snapshot(district_stats)

func _is_adjacent_to_road(cell: Vector2i) -> bool:
	var neighbors := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	for dir in neighbors:
		var n: Vector2i = cell + dir
		if _is_in_bounds(n) and road_by_index[_to_index(n)]:
			return true
	return false

func _init_tiles() -> void:
	zone_by_index.clear()
	road_by_index.clear()
	building_level_by_index.clear()
	district_id_by_index.clear()
	style_profile_by_index.clear()

	for i in columns * rows:
		zone_by_index.append(Tool.BULLDOZE)
		road_by_index.append(false)
		building_level_by_index.append(0)
		district_id_by_index.append("outer_borough_mix")
		style_profile_by_index.append("default_mixed")

func _is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < columns and cell.y < rows

func _to_index(cell: Vector2i) -> int:
	return cell.y * columns + cell.x

func reset_grid() -> void:
	_init_tiles()
	money = 8000
	population = 0
	jobs = 0
	connected_residential = 0
	connected_commercial = 0
	connected_industrial = 0
	district_demand_snapshot.clear()
	sim_timer = 0.0
	queue_redraw()

func apply_district_seed(seed_records: Array[Dictionary]) -> void:
	for record in seed_records:
		var cell: Vector2i = record.get("cell", Vector2i(-1, -1))
		if not _is_in_bounds(cell):
			continue

		var index := _to_index(cell)
		if road_by_index[index]:
			continue

		var zone := _zone_from_seed(record)
		var district_id: String = String(record.get("district_id", "outer_borough_mix"))
		var style_profile: String = String(record.get("style_profile", "default_mixed"))
		zone_by_index[index] = zone
		building_level_by_index[index] = clampi(int(record.get("seed_level", 1)), 1, 3)
		district_id_by_index[index] = district_id
		style_profile_by_index[index] = style_profile
		_ensure_adjacent_road(cell)

	queue_redraw()

func _zone_from_seed(record: Dictionary) -> int:
	var district_id := String(record.get("district_id", ""))
	var style_profile := String(record.get("style_profile", "")).to_lower()

	if district_id in ["midtown_core", "financial_district"]:
		return Tool.COMMERCIAL
	if "industrial" in style_profile:
		return Tool.INDUSTRIAL
	if "tower" in style_profile:
		return Tool.COMMERCIAL
	return Tool.RESIDENTIAL

func _ensure_adjacent_road(cell: Vector2i) -> void:
	var neighbors := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	for dir in neighbors:
		var n: Vector2i = cell + dir
		if not _is_in_bounds(n):
			continue
		var idx := _to_index(n)
		if zone_by_index[idx] == Tool.BULLDOZE and not road_by_index[idx]:
			road_by_index[idx] = true
			district_id_by_index[idx] = district_id_by_index[_to_index(cell)]
			style_profile_by_index[idx] = style_profile_by_index[_to_index(cell)]
			building_level_by_index[idx] = 0
			return

func _growth_multiplier(style_profile: String) -> float:
	if style_profile.find("tower") != -1:
		return 1.18
	if style_profile.find("industrial") != -1:
		return 1.1
	if style_profile.find("brownstone") != -1:
		return 0.92
	return 1.0

func _district_tax_multiplier(district_id: String) -> float:
	return float(DISTRICT_TAX_MULT.get(district_id, 1.0))

func _district_upkeep_multiplier(district_id: String) -> float:
	return float(DISTRICT_UPKEEP_MULT.get(district_id, 1.0))

func _ensure_district_stat(stats: Dictionary, district_id: String) -> void:
	if stats.has(district_id):
		return
	stats[district_id] = {
		"district_id": district_id,
		"zone_total": 0,
		"connected": 0,
		"res_zones": 0,
		"com_zones": 0,
		"ind_zones": 0,
		"level_sum": 0
	}

func _update_district_demand_snapshot(stats: Dictionary) -> void:
	district_demand_snapshot.clear()

	var housing_pressure: float = clamp((float(jobs) + 1.0) / (float(population) + 1.0), 0.55, 1.9)
	var job_pressure: float = clamp((float(population) + 1.0) / (float(jobs) + 1.0), 0.55, 1.9)

	for district_key in stats.keys():
		var district_id: String = String(district_key)
		var stat: Dictionary = stats[district_id]
		var total: int = int(stat["zone_total"])
		if total <= 0:
			continue

		var connected: int = int(stat["connected"])
		var connected_ratio: float = float(connected) / float(total)
		var res_share: float = float(stat["res_zones"]) / float(total)
		var com_share: float = float(stat["com_zones"]) / float(total)
		var ind_share: float = float(stat["ind_zones"]) / float(total)
		var avg_level: float = float(stat["level_sum"]) / float(max(connected, 1))
		var maturity_factor: float = clamp(avg_level / 3.0, 0.0, 1.0)

		var res_demand: float = clamp(50.0 + (housing_pressure - 1.0) * 38.0 + (1.0 - res_share) * 10.0 + (connected_ratio - 0.5) * 14.0, 0.0, 100.0)
		var com_demand: float = clamp(50.0 + (job_pressure - 1.0) * 32.0 + (1.0 - com_share) * 8.0 + (connected_ratio - 0.5) * 10.0, 0.0, 100.0)
		var ind_demand: float = clamp(42.0 + (job_pressure - 1.0) * 24.0 + (1.0 - ind_share) * 12.0 - maturity_factor * 12.0, 0.0, 100.0)
		var composite: float = clamp((res_demand * 0.4) + (com_demand * 0.35) + (ind_demand * 0.25), 0.0, 100.0)

		district_demand_snapshot.append(
			{
				"district_id": district_id,
				"demand_index": composite,
				"res_demand": res_demand,
				"com_demand": com_demand,
				"ind_demand": ind_demand
			}
		)

	district_demand_snapshot.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("demand_index", 0.0)) > float(b.get("demand_index", 0.0))
	)

func get_district_demand_snapshot() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for item in district_demand_snapshot:
		output.append(item.duplicate(true))
	return output
