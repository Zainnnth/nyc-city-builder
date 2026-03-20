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

var sim_timer := 0.0
const SIM_STEP_SECONDS := 1.0

var money := 8000
var population := 0
var jobs := 0
var connected_residential := 0
var connected_commercial := 0
var connected_industrial := 0

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
		draw_rect(rect.grow(-margin), BUILDING_COLOR, true)

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
	var road_tiles := 0

	connected_residential = 0
	connected_commercial = 0
	connected_industrial = 0

	for y in rows:
		for x in columns:
			var cell := Vector2i(x, y)
			var i := _to_index(cell)

			if road_by_index[i]:
				road_tiles += 1
				continue

			var zone := zone_by_index[i]
			if zone == Tool.BULLDOZE:
				building_level_by_index[i] = 0
				continue

			var connected := _is_adjacent_to_road(cell)
			if not connected:
				building_level_by_index[i] = max(building_level_by_index[i] - 1, 0)
				continue

			building_level_by_index[i] = min(building_level_by_index[i] + 1, 3)
			var level := building_level_by_index[i]
			if zone == Tool.RESIDENTIAL:
				connected_residential += 1
				pop_capacity += int(ZONE_CAPACITY[zone]) * level
			else:
				if zone == Tool.COMMERCIAL:
					connected_commercial += 1
				if zone == Tool.INDUSTRIAL:
					connected_industrial += 1
				job_capacity += int(ZONE_CAPACITY[zone]) * level

	var target_population: int = min(pop_capacity, int(round(job_capacity * 0.9)))
	population = int(lerp(float(population), float(target_population), 0.42))
	jobs = int(lerp(float(jobs), float(job_capacity), 0.35))

	var tax_income := int(round(population * 0.9 + jobs * 0.55))
	var upkeep := road_tiles * 2 + (connected_residential + connected_commercial + connected_industrial)
	money += tax_income - upkeep

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

	for i in columns * rows:
		zone_by_index.append(Tool.BULLDOZE)
		road_by_index.append(false)
		building_level_by_index.append(0)

func _is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < columns and cell.y < rows

func _to_index(cell: Vector2i) -> int:
	return cell.y * columns + cell.x

func apply_district_seed(seed_records: Array[Dictionary]) -> void:
	for record in seed_records:
		var cell: Vector2i = record.get("cell", Vector2i(-1, -1))
		if not _is_in_bounds(cell):
			continue

		var index := _to_index(cell)
		if road_by_index[index]:
			continue

		var zone := _zone_from_seed(record)
		zone_by_index[index] = zone
		building_level_by_index[index] = clampi(int(record.get("seed_level", 1)), 1, 3)
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
			building_level_by_index[idx] = 0
			return
