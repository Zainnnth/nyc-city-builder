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
const HAZE_SKY_COLOR := Color(0.11, 0.12, 0.2, 1.0)
const HAZE_HORIZON_COLOR := Color(0.30, 0.23, 0.27, 0.95)
const SODIUM_LIGHT_COLOR := Color(0.92, 0.61, 0.24, 0.17)
const RETRO_TEAL_COLOR := Color(0.24, 0.71, 0.68, 0.45)
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
var stroke_capture_active := false
var stroke_dirty := false

var zone_by_index: Array[int] = []
var road_by_index: Array[bool] = []
var building_level_by_index: Array[int] = []
var district_id_by_index: Array[String] = []
var style_profile_by_index: Array[String] = []
var archetype_by_index: Array[String] = []
var land_value_by_index: Array[float] = []
var noise_by_index: Array[float] = []
var crime_by_index: Array[float] = []
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
const MAX_EDIT_HISTORY := 60

var sim_timer := 0.0
const SIM_STEP_SECONDS := 1.0
var sim_speed := 1.0
var sim_paused := false

var money := 8000
var population := 0
var jobs := 0
var connected_residential := 0
var connected_commercial := 0
var connected_industrial := 0
var district_demand_snapshot: Array[Dictionary] = []
var district_policy_map: Dictionary = {}
var economy_history: Array[Dictionary] = []
var sim_tick := 0
const MAX_HISTORY := 90
var active_alerts: Array[Dictionary] = []
var positive_cashflow_streak := 0
var objectives_complete := false
var objectives_complete_tick := -1
var road_cluster_count := 0
var largest_road_cluster := 0
var road_efficiency := 1.0
var avg_commute_penalty := 0.0
var avg_land_value := 0.0
var avg_noise := 0.0
var avg_crime := 0.0
var district_upkeep_hook_map: Dictionary = {}
var district_identity_profiles: Dictionary = {}
var service_levels := {
	"police": 55.0,
	"fire": 55.0,
	"sanitation": 55.0,
	"transit": 55.0
}
var sim_rng := RandomNumberGenerator.new()
var active_event_id := ""
var active_event_district := ""
var active_event_ticks_left := 0
var event_cooldown_ticks := 0
var recent_events: Array[Dictionary] = []
const MAX_EVENT_HISTORY := 8

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

const POLICY_BALANCED := "balanced"
const POLICY_GROWTH := "growth"
const POLICY_PROFIT := "profit"

const POLICY_GROWTH_MULT := {
	POLICY_BALANCED: 1.0,
	POLICY_GROWTH: 1.15,
	POLICY_PROFIT: 0.9
}

const POLICY_TAX_MULT := {
	POLICY_BALANCED: 1.0,
	POLICY_GROWTH: 0.92,
	POLICY_PROFIT: 1.12
}

const POLICY_UPKEEP_MULT := {
	POLICY_BALANCED: 1.0,
	POLICY_GROWTH: 1.06,
	POLICY_PROFIT: 0.98
}

const OBJECTIVES := [
	{"id": "pop_500", "title": "Reach population 500"},
	{"id": "jobs_350", "title": "Reach jobs 350"},
	{"id": "cash_12000", "title": "Reach treasury $12,000"},
	{"id": "cashflow_20", "title": "Maintain positive cashflow for 20 ticks"}
]

const OVERLAY_NONE := "none"
const OVERLAY_LAND_VALUE := "land_value"
const OVERLAY_NOISE := "noise"
const OVERLAY_CRIME := "crime"
const EVENT_BLACKOUT := "blackout"
const EVENT_STRIKE := "strike"
const EVENT_HEATWAVE := "heatwave"

const EVENT_TITLES := {
	EVENT_BLACKOUT: "Blackout",
	EVENT_STRIKE: "Transit Strike",
	EVENT_HEATWAVE: "Heatwave"
}

const EVENT_BASE_DURATION := {
	EVENT_BLACKOUT: 8,
	EVENT_STRIKE: 10,
	EVENT_HEATWAVE: 12
}

var overlay_mode := OVERLAY_NONE
var overlay_alpha := 0.42
var atmosphere_time := 0.0
var atmosphere_redraw_accum := 0.0
const ATMOSPHERE_REDRAW_STEP := 0.16

func _draw() -> void:
	var map_size := Vector2(columns * cell_size, rows * cell_size)
	_draw_atmosphere_background(map_size)

	for y in rows:
		for x in columns:
			var i := _to_index(Vector2i(x, y))
			var rect := Rect2(Vector2(x, y) * cell_size, Vector2.ONE * cell_size)
			_draw_tile(rect, i)
			draw_rect(rect, GRID_LINE_COLOR, false, 1.0)

	draw_rect(Rect2(Vector2.ZERO, map_size), BORDER_COLOR, false, 3.0)
	_draw_atmosphere_foreground(map_size)
	_draw_hud(map_size)
	_draw_tool_legend(map_size)

func _ready() -> void:
	sim_rng.randomize()
	_init_tiles()
	queue_redraw()

func _process(delta: float) -> void:
	atmosphere_time += delta
	atmosphere_redraw_accum += delta
	var needs_redraw := false
	if atmosphere_redraw_accum >= ATMOSPHERE_REDRAW_STEP:
		atmosphere_redraw_accum = 0.0
		needs_redraw = true
	if sim_paused:
		if needs_redraw:
			queue_redraw()
		return
	sim_timer += delta
	var step_size: float = SIM_STEP_SECONDS / max(sim_speed, 0.001)
	while sim_timer >= step_size:
		sim_timer -= step_size
		_run_sim_step()
		needs_redraw = true
	if needs_redraw:
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			undo_edit()
			return
		if event.ctrl_pressed and event.keycode == KEY_Y:
			redo_edit()
			return
		if TOOL_KEYS.has(event.keycode):
			selected_tool = TOOL_KEYS[event.keycode]
			queue_redraw()
			return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_edit_stroke()
			elif is_drag_painting:
				_end_edit_stroke()
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
		var building_rect := rect.grow(-margin)
		draw_rect(building_rect, _building_color_for(index), true)
		_draw_signage_lights(building_rect, index, building_level)

	_draw_overlay(rect, index)

func _draw_overlay(rect: Rect2, index: int) -> void:
	if overlay_mode == OVERLAY_NONE:
		return
	if road_by_index[index]:
		return

	var value := 0.0
	var color := Color(1, 1, 1, overlay_alpha)
	if overlay_mode == OVERLAY_LAND_VALUE:
		value = clamp(land_value_by_index[index] / 100.0, 0.0, 1.0)
		color = Color(0.15, 0.85, 0.34, overlay_alpha * value)
	elif overlay_mode == OVERLAY_NOISE:
		value = clamp(noise_by_index[index] / 100.0, 0.0, 1.0)
		color = Color(0.96, 0.73, 0.24, overlay_alpha * value)
	elif overlay_mode == OVERLAY_CRIME:
		value = clamp(crime_by_index[index] / 100.0, 0.0, 1.0)
		color = Color(0.9, 0.24, 0.24, overlay_alpha * value)
	if value > 0.01:
		draw_rect(rect.grow(-2.0), color, true)

func _building_color_for(index: int) -> Color:
	var district_id: String = district_id_by_index[index]
	var district_tint: Color = DISTRICT_TINTS.get(district_id, DISTRICT_TINTS["outer_borough_mix"])
	var style_profile: String = style_profile_by_index[index]
	var identity_profile: Dictionary = _identity_profile_for(district_id)
	var accent: Color = _identity_color(identity_profile, "accent_color", district_tint)
	var tint_mix: float = clamp(_identity_signage_density(identity_profile) * 0.28, 0.05, 0.3)
	var base: Color = district_tint.lerp(accent, tint_mix)

	if style_profile.find("industrial") != -1:
		return base.darkened(0.2)
	if style_profile.find("brownstone") != -1:
		return base.darkened(0.1)
	return base

func _draw_signage_lights(building_rect: Rect2, index: int, building_level: int) -> void:
	var district_id: String = district_id_by_index[index]
	var identity_profile: Dictionary = _identity_profile_for(district_id)
	var density: float = _identity_signage_density(identity_profile)
	var archetype: String = archetype_by_index[index]
	var archetype_mod: Dictionary = _archetype_signage_mod(archetype)
	density *= float(archetype_mod.get("density_mult", 1.0))
	if density <= 0.01:
		return
	if building_level < 2:
		return

	var light_color: Color = _identity_color(identity_profile, "night_accent_color", Color(0.78, 0.83, 0.92, 0.9))
	var color_shift: float = float(archetype_mod.get("color_shift", 0.0))
	light_color = light_color.lightened(max(color_shift, 0.0)).darkened(max(-color_shift, 0.0))
	var stripe_count: int = clampi(building_level + int(archetype_mod.get("stripe_bonus", 0)), 2, 5)
	for stripe in range(stripe_count):
		var roll: float = _tile_noise01(index, stripe + 17)
		if roll > density:
			continue
		var y_t: float = 0.2 + 0.22 * float(stripe)
		var stripe_h: float = clamp(building_rect.size.y * 0.08, 2.0, 4.5)
		var inset: float = clamp(building_rect.size.x * 0.14, 2.0, 7.0)
		var stripe_rect: Rect2 = Rect2(
			Vector2(building_rect.position.x + inset, building_rect.position.y + building_rect.size.y * y_t),
			Vector2(max(3.0, building_rect.size.x - inset * 2.0), stripe_h)
		)
		draw_rect(stripe_rect, light_color, true)

func _tile_noise01(index: int, salt: int) -> float:
	var h: int = int(hash("%d:%d" % [index, salt]))
	var mod_val: int = abs(h) % 1000
	return float(mod_val) / 1000.0

func _archetype_signage_mod(archetype: String) -> Dictionary:
	var name: String = archetype.to_lower()
	if name.find("marquee") != -1:
		return {"density_mult": 1.35, "stripe_bonus": 1, "color_shift": 0.18}
	if name.find("bodega") != -1:
		return {"density_mult": 1.22, "stripe_bonus": 0, "color_shift": 0.1}
	if name.find("glass_tower") != -1:
		return {"density_mult": 1.12, "stripe_bonus": 1, "color_shift": 0.04}
	if name.find("stone_tower") != -1:
		return {"density_mult": 0.68, "stripe_bonus": -1, "color_shift": -0.08}
	if name.find("warehouse") != -1:
		return {"density_mult": 0.56, "stripe_bonus": -1, "color_shift": -0.12}
	return {"density_mult": 1.0, "stripe_bonus": 0, "color_shift": 0.0}

func _draw_hud(map_size: Vector2) -> void:
	var text := "Tool: %s   |   Money: $%d   |   Pop: %d   |   Jobs: %d" % [
		TOOL_NAMES[selected_tool], money, population, jobs
	]
	var speed_text := "Paused" if sim_paused else ("%.1fx" % sim_speed)
	text += "   |   Sim: %s" % speed_text
	text += "   |   Svc P/F/S/T: %d/%d/%d/%d" % [
		int(round(float(service_levels.get("police", 0.0)))),
		int(round(float(service_levels.get("fire", 0.0)))),
		int(round(float(service_levels.get("sanitation", 0.0)))),
		int(round(float(service_levels.get("transit", 0.0))))
	]
	draw_string(
		ThemeDB.fallback_font,
		Vector2(16, map_size.y + 36),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		map_size.x - 32,
		22,
		_retro_ui_color(Color(0.83, 0.86, 0.93, 0.92), 0.26)
	)

	var sim_text := "Connected Zones - Res: %d  Com: %d  Ind: %d" % [
		connected_residential, connected_commercial, connected_industrial
	]
	sim_text += "   |   Roads: %d clusters   |   Efficiency: %.2f   |   Commute Penalty: %.2f" % [
		road_cluster_count, road_efficiency, avg_commute_penalty
	]
	draw_string(
		ThemeDB.fallback_font,
		Vector2(16, map_size.y + 64),
		sim_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		map_size.x - 32,
		20,
		_retro_ui_color(Color(0.73, 0.78, 0.9, 0.92), 0.18)
	)

func _draw_tool_legend(map_size: Vector2) -> void:
	var text := "1 Road  2 Res  3 Com  4 Ind  5 Bulldoze   |   LMB drag: paint   |   Ctrl+Z/Y: Undo/Redo   |   Arrows: pan   |   Wheel: zoom"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(16, map_size.y + 92),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		map_size.x - 32,
		20,
		_retro_ui_color(Color(0.63, 0.69, 0.81, 0.95), 0.15)
	)

func _draw_atmosphere_background(map_size: Vector2) -> void:
	var bands := 7
	for band in range(bands):
		var t: float = float(band) / float(max(bands - 1, 1))
		var y0: float = map_size.y * t
		var y1: float = map_size.y * float(band + 1) / float(bands)
		var color: Color = HAZE_SKY_COLOR.lerp(HAZE_HORIZON_COLOR, t)
		draw_rect(Rect2(0.0, y0, map_size.x, y1 - y0), color, true)
	draw_rect(Rect2(Vector2.ZERO, map_size), BACKDROP_COLOR, true)

func _draw_atmosphere_foreground(map_size: Vector2) -> void:
	var event_haze_bonus := 0.0
	if active_event_id == EVENT_HEATWAVE:
		event_haze_bonus = 0.07
	elif active_event_id == EVENT_BLACKOUT:
		event_haze_bonus = 0.04
	var noise_haze: float = clamp(avg_noise / 260.0, 0.02, 0.32)
	var pulse: float = 0.5 + 0.5 * sin(atmosphere_time * 1.3)
	var haze_alpha: float = clamp(noise_haze + event_haze_bonus + pulse * 0.02, 0.04, 0.38)
	draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.79, 0.64, 0.38, haze_alpha), true)
	_draw_sodium_pools()
	_draw_scanlines(map_size)

func _draw_sodium_pools() -> void:
	for y in range(rows):
		for x in range(columns):
			var i := _to_index(Vector2i(x, y))
			var should_glow := false
			var zone: int = zone_by_index[i]
			if road_by_index[i]:
				should_glow = _tile_noise01(i, 73) > 0.56
			elif zone == Tool.COMMERCIAL and building_level_by_index[i] > 0:
				should_glow = _tile_noise01(i, 91) > 0.42
			if not should_glow:
				continue
			var center := (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_size
			var radius: float = cell_size * (0.22 + _tile_noise01(i, 33) * 0.24)
			var alpha_scale: float = 0.8 + (0.2 * (0.5 + 0.5 * sin(atmosphere_time * 2.6 + float(i) * 0.03)))
			draw_circle(center, radius, Color(SODIUM_LIGHT_COLOR.r, SODIUM_LIGHT_COLOR.g, SODIUM_LIGHT_COLOR.b, SODIUM_LIGHT_COLOR.a * alpha_scale))
			if zone == Tool.COMMERCIAL:
				draw_circle(center, radius * 0.58, Color(RETRO_TEAL_COLOR.r, RETRO_TEAL_COLOR.g, RETRO_TEAL_COLOR.b, RETRO_TEAL_COLOR.a * 0.45))

func _draw_scanlines(map_size: Vector2) -> void:
	var stride := int(max(5.0, round(cell_size / 10.0)))
	var line_color := Color(0.0, 0.0, 0.0, 0.07)
	for y in range(0, int(map_size.y), stride):
		draw_line(Vector2(0.0, float(y)), Vector2(map_size.x, float(y)), line_color, 1.0)

func _retro_ui_color(base: Color, accent_mix: float) -> Color:
	var pulse: float = 0.5 + 0.5 * sin(atmosphere_time * 2.2)
	var accent := Color(0.91, 0.62, 0.25, base.a)
	return base.lerp(accent, clamp(accent_mix * (0.75 + pulse * 0.25), 0.0, 0.45))

func _paint_at_mouse_position() -> void:
	var local_mouse := to_local(get_global_mouse_position())
	var cell := Vector2i(floor(local_mouse.x / cell_size), floor(local_mouse.y / cell_size))
	if not _is_in_bounds(cell):
		return

	var index := _to_index(cell)
	match selected_tool:
		Tool.ROAD:
			if not road_by_index[index]:
				_mark_edit_if_needed()
				road_by_index[index] = true
				zone_by_index[index] = Tool.BULLDOZE
				building_level_by_index[index] = 0
				archetype_by_index[index] = "road_segment"
				money -= 8
				stroke_dirty = true
		Tool.BULLDOZE:
			if road_by_index[index] or zone_by_index[index] != Tool.BULLDOZE or building_level_by_index[index] > 0:
				_mark_edit_if_needed()
				road_by_index[index] = false
				zone_by_index[index] = Tool.BULLDOZE
				building_level_by_index[index] = 0
				archetype_by_index[index] = "vacant_lot"
				money -= 3
				stroke_dirty = true
		_:
			if zone_by_index[index] != selected_tool or road_by_index[index]:
				_mark_edit_if_needed()
				road_by_index[index] = false
				zone_by_index[index] = selected_tool
				building_level_by_index[index] = 0
				archetype_by_index[index] = _default_archetype_for_cell(index, selected_tool)
				money -= 5
				stroke_dirty = true

	if stroke_dirty:
		queue_redraw()

func _run_sim_step() -> void:
	var pop_capacity := 0
	var job_capacity := 0
	var road_upkeep_cost := 0.0
	var zone_upkeep_cost := 0.0
	var service_upkeep_cost := 0.0
	var tax_income_raw := 0.0
	var district_stats := {}
	var road_graph: Dictionary = _build_road_graph_metrics()
	var component_by_index: Array = road_graph.get("component_by_index", [])
	var component_sizes: Array = road_graph.get("component_sizes", [])
	var component_penalties: Dictionary = _build_component_commute_penalties(component_by_index, component_sizes)
	var penalty_sum := 0.0
	var penalty_count := 0
	var land_sum := 0.0
	var noise_sum := 0.0
	var crime_sum := 0.0
	var metric_samples := 0
	var road_count: int = int(road_graph.get("road_count", 0))
	road_cluster_count = int(road_graph.get("component_count", 0))
	largest_road_cluster = int(road_graph.get("largest_cluster", 0))
	road_efficiency = 1.0 if road_count <= 0 else float(largest_road_cluster) / float(road_count)

	connected_residential = 0
	connected_commercial = 0
	connected_industrial = 0

	for y in rows:
		for x in columns:
			var cell := Vector2i(x, y)
			var i := _to_index(cell)

			if road_by_index[i]:
				var road_district_id: String = district_id_by_index[i]
				var district_upkeep_hook: float = float(district_upkeep_hook_map.get(road_district_id, 1.0))
				road_upkeep_cost += 2.0 * _district_upkeep_multiplier(road_district_id) * district_upkeep_hook * _event_upkeep_multiplier(road_district_id)
				land_value_by_index[i] = 42.0
				noise_by_index[i] = 26.0
				crime_by_index[i] = 14.0 + (1.0 - _service_norm("police")) * 18.0
				continue

			var zone := zone_by_index[i]
			if zone == Tool.BULLDOZE:
				building_level_by_index[i] = 0
				land_value_by_index[i] = 32.0 + _service_norm("sanitation") * 10.0
				noise_by_index[i] = 14.0
				crime_by_index[i] = 18.0 + (1.0 - _service_norm("police")) * 16.0
				land_sum += land_value_by_index[i]
				noise_sum += noise_by_index[i]
				crime_sum += crime_by_index[i]
				metric_samples += 1
				continue

			var adjacent_component: int = _adjacent_road_component(cell, component_by_index)
			var connected := adjacent_component != -1
			var commute_penalty: float = _component_penalty(adjacent_component, component_penalties)
			var district_id: String = district_id_by_index[i]
			_ensure_district_stat(district_stats, district_id)
			var stat: Dictionary = district_stats[district_id]
			stat["zone_total"] = int(stat["zone_total"]) + 1
			if connected:
				stat["connected"] = int(stat["connected"]) + 1

			if not connected:
				building_level_by_index[i] = max(building_level_by_index[i] - 1, 0)
				land_value_by_index[i] = clamp(24.0 + _service_norm("sanitation") * 9.0 - commute_penalty * 26.0, 0.0, 100.0)
				noise_by_index[i] = clamp(22.0 + (18.0 if zone == Tool.INDUSTRIAL else 8.0) + commute_penalty * 22.0, 0.0, 100.0)
				crime_by_index[i] = clamp(34.0 + (1.0 - _service_norm("police")) * 38.0 + commute_penalty * 20.0, 0.0, 100.0)
				land_sum += land_value_by_index[i]
				noise_sum += noise_by_index[i]
				crime_sum += crime_by_index[i]
				metric_samples += 1
				district_stats[district_id] = stat
				continue

			building_level_by_index[i] = min(building_level_by_index[i] + 1, 3)
			var level := building_level_by_index[i]
			var style_profile: String = style_profile_by_index[i]
			var policy_id: String = get_district_policy(district_id)
			var identity_profile: Dictionary = _identity_profile_for(district_id)
			var identity_growth_mult: float = _identity_growth_multiplier(zone, identity_profile)
			var identity_tax_mult: float = _identity_tax_multiplier(zone, identity_profile)
			var identity_noise_mult: float = _identity_noise_penalty_multiplier(identity_profile)
			var road_commute_mult: float = _road_commute_multiplier(adjacent_component, component_sizes) * (1.0 - commute_penalty)
			var zone_service_mult: float = _zone_service_multiplier(zone)
			var growth_mult := _growth_multiplier(style_profile) * _policy_growth_multiplier(policy_id) * road_commute_mult * zone_service_mult * _event_growth_multiplier(zone, district_id) * identity_growth_mult
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
			var district_hook: float = float(district_upkeep_hook_map.get(district_id, 1.0))
			var live_upkeep_hook: float = clamp(1.0 + commute_penalty * 0.35 + (1.0 - zone_service_mult) * 0.28, 0.85, 1.7)
			tax_income_raw += tile_output * _district_tax_multiplier(district_id) * _policy_tax_multiplier(policy_id) * _event_tax_multiplier(district_id) * identity_tax_mult
			zone_upkeep_cost += 1.0 * _district_upkeep_multiplier(district_id) * _policy_upkeep_multiplier(policy_id) * district_hook * live_upkeep_hook * _event_upkeep_multiplier(district_id)
			service_upkeep_cost += _zone_service_cost(zone)
			stat["level_sum"] = int(stat["level_sum"]) + level
			stat["traffic_penalty_sum"] = float(stat["traffic_penalty_sum"]) + commute_penalty
			stat["traffic_samples"] = int(stat["traffic_samples"]) + 1
			stat["service_penalty_sum"] = float(stat["service_penalty_sum"]) + (1.0 - zone_service_mult)
			stat["service_samples"] = int(stat["service_samples"]) + 1
			stat["upkeep_load_sum"] = float(stat["upkeep_load_sum"]) + live_upkeep_hook
			stat["upkeep_samples"] = int(stat["upkeep_samples"]) + 1
			var archetype: String = archetype_by_index[i]
			var counts_v: Variant = stat.get("archetype_counts", {})
			var counts: Dictionary = counts_v if typeof(counts_v) == TYPE_DICTIONARY else {}
			counts[archetype] = int(counts.get(archetype, 0)) + 1
			stat["archetype_counts"] = counts
			district_stats[district_id] = stat
			penalty_sum += commute_penalty
			penalty_count += 1

			var land_base := 48.0
			if zone == Tool.RESIDENTIAL:
				land_base = 52.0
			elif zone == Tool.COMMERCIAL:
				land_base = 58.0
			elif zone == Tool.INDUSTRIAL:
				land_base = 44.0
			var noise_base := 12.0
			if zone == Tool.INDUSTRIAL:
				noise_base = 34.0
			elif zone == Tool.COMMERCIAL:
				noise_base = 18.0
			var police_norm := _service_norm("police")
			var sanitation_norm := _service_norm("sanitation")
			var transit_norm := _service_norm("transit")
			var fire_norm := _service_norm("fire")
			land_value_by_index[i] = clamp(
				land_base + float(level) * 5.5 + transit_norm * 10.0 + sanitation_norm * 8.0
				- commute_penalty * 28.0 - noise_base * 0.15,
				0.0, 100.0
			)
			noise_by_index[i] = clamp(
				(noise_base + commute_penalty * 26.0 + (1.0 - sanitation_norm) * 12.0 + (1.0 - transit_norm) * 6.0 + _event_noise_bonus(district_id)) * identity_noise_mult,
				0.0, 100.0
			)
			crime_by_index[i] = clamp(
				16.0 + (1.0 - police_norm) * 44.0 + (1.0 - fire_norm) * 10.0 + commute_penalty * 18.0 + _event_crime_bonus(district_id),
				0.0, 100.0
			)
			land_sum += land_value_by_index[i]
			noise_sum += noise_by_index[i]
			crime_sum += crime_by_index[i]
			metric_samples += 1

	var target_population: int = min(pop_capacity, int(round(job_capacity * 0.9)))
	population = int(lerp(float(population), float(target_population), 0.42))
	jobs = int(lerp(float(jobs), float(job_capacity), 0.35))

	var tax_income := int(round(population * 0.7 + jobs * 0.45 + tax_income_raw))
	var upkeep := int(round(road_upkeep_cost + zone_upkeep_cost + service_upkeep_cost))
	var net_cashflow := tax_income - upkeep
	money += net_cashflow
	if net_cashflow > 0:
		positive_cashflow_streak += 1
	else:
		positive_cashflow_streak = 0
	avg_commute_penalty = 0.0 if penalty_count == 0 else penalty_sum / float(penalty_count)
	avg_land_value = 0.0 if metric_samples == 0 else land_sum / float(metric_samples)
	avg_noise = 0.0 if metric_samples == 0 else noise_sum / float(metric_samples)
	avg_crime = 0.0 if metric_samples == 0 else crime_sum / float(metric_samples)
	sim_tick += 1
	_rebuild_district_upkeep_hooks(district_stats)
	_update_event_system(district_stats)
	_push_economy_point()
	_update_district_demand_snapshot(district_stats)
	_update_active_alerts()

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

func _build_road_graph_metrics() -> Dictionary:
	var total_cells := columns * rows
	var component_by_index: Array[int] = []
	component_by_index.resize(total_cells)
	for i in range(total_cells):
		component_by_index[i] = -1

	var component_sizes: Array[int] = []
	var component_count := 0
	var road_count := 0
	var largest_cluster := 0

	for y in range(rows):
		for x in range(columns):
			var cell := Vector2i(x, y)
			var idx := _to_index(cell)
			if not road_by_index[idx]:
				continue
			road_count += 1
			if component_by_index[idx] != -1:
				continue

			var size := _flood_fill_road_component(cell, component_count, component_by_index)
			component_sizes.append(size)
			largest_cluster = max(largest_cluster, size)
			component_count += 1

	return {
		"component_by_index": component_by_index,
		"component_sizes": component_sizes,
		"component_count": component_count,
		"largest_cluster": largest_cluster,
		"road_count": road_count
	}

func _flood_fill_road_component(start_cell: Vector2i, component_id: int, component_by_index: Array[int]) -> int:
	var stack: Array[Vector2i] = [start_cell]
	var size := 0
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		if not _is_in_bounds(cell):
			continue
		var idx := _to_index(cell)
		if not road_by_index[idx]:
			continue
		if component_by_index[idx] != -1:
			continue

		component_by_index[idx] = component_id
		size += 1
		stack.append(cell + Vector2i(1, 0))
		stack.append(cell + Vector2i(-1, 0))
		stack.append(cell + Vector2i(0, 1))
		stack.append(cell + Vector2i(0, -1))
	return size

func _adjacent_road_component(cell: Vector2i, component_by_index: Array) -> int:
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
		if road_by_index[idx]:
			return int(component_by_index[idx])
	return -1

func _road_commute_multiplier(component_id: int, component_sizes: Array) -> float:
	if component_id < 0 or component_id >= component_sizes.size():
		return 0.75
	var size := int(component_sizes[component_id])
	if size <= 0:
		return 0.75
	return clamp(float(size) / 40.0, 0.5, 1.25)

func _build_component_commute_penalties(component_by_index: Array, component_sizes: Array) -> Dictionary:
	var component_balances := {}
	for y in range(rows):
		for x in range(columns):
			var idx := _to_index(Vector2i(x, y))
			if road_by_index[idx]:
				continue
			var zone := zone_by_index[idx]
			if zone == Tool.BULLDOZE:
				continue
			var component_id: int = _adjacent_road_component(Vector2i(x, y), component_by_index)
			if component_id == -1:
				continue
			if not component_balances.has(component_id):
				component_balances[component_id] = {"res_load": 0.0, "job_load": 0.0}

			var load_bucket: Dictionary = component_balances[component_id]
			var level: int = max(1, building_level_by_index[idx])
			if zone == Tool.RESIDENTIAL:
				load_bucket["res_load"] = float(load_bucket["res_load"]) + float(level)
			else:
				load_bucket["job_load"] = float(load_bucket["job_load"]) + float(level)
			component_balances[component_id] = load_bucket

	var penalties: Dictionary = {}
	for comp_key in component_balances.keys():
		var component_id: int = int(comp_key)
		var loads: Dictionary = component_balances[component_id]
		var res_load: float = float(loads.get("res_load", 0.0))
		var job_load: float = float(loads.get("job_load", 0.0))
		var total_load: float = max(1.0, res_load + job_load)
		var imbalance: float = abs(res_load - job_load) / total_load

		var size: int = 1
		if component_id >= 0 and component_id < component_sizes.size():
			size = int(component_sizes[component_id])
		var size_penalty: float = clamp(1.0 - (float(size) / 26.0), 0.0, 0.35)
		var penalty: float = clamp(imbalance * 0.5 + size_penalty, 0.0, 0.45)
		penalties[component_id] = penalty
	return penalties

func _component_penalty(component_id: int, penalties: Dictionary) -> float:
	if component_id < 0:
		return 0.3
	if penalties.has(component_id):
		return float(penalties[component_id])
	return 0.0

func _init_tiles() -> void:
	zone_by_index.clear()
	road_by_index.clear()
	building_level_by_index.clear()
	district_id_by_index.clear()
	style_profile_by_index.clear()
	archetype_by_index.clear()
	land_value_by_index.clear()
	noise_by_index.clear()
	crime_by_index.clear()

	for i in columns * rows:
		zone_by_index.append(Tool.BULLDOZE)
		road_by_index.append(false)
		building_level_by_index.append(0)
		district_id_by_index.append("outer_borough_mix")
		style_profile_by_index.append("default_mixed")
		archetype_by_index.append("mixed_block_generic")
		land_value_by_index.append(30.0)
		noise_by_index.append(10.0)
		crime_by_index.append(10.0)

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
	district_policy_map.clear()
	economy_history.clear()
	active_alerts.clear()
	positive_cashflow_streak = 0
	objectives_complete = false
	objectives_complete_tick = -1
	road_cluster_count = 0
	largest_road_cluster = 0
	road_efficiency = 1.0
	avg_commute_penalty = 0.0
	avg_land_value = 0.0
	avg_noise = 0.0
	avg_crime = 0.0
	district_upkeep_hook_map.clear()
	service_levels["police"] = 55.0
	service_levels["fire"] = 55.0
	service_levels["sanitation"] = 55.0
	service_levels["transit"] = 55.0
	active_event_id = ""
	active_event_district = ""
	active_event_ticks_left = 0
	event_cooldown_ticks = 0
	recent_events.clear()
	undo_stack.clear()
	redo_stack.clear()
	sim_tick = 0
	sim_timer = 0.0
	atmosphere_time = 0.0
	atmosphere_redraw_accum = 0.0
	sim_speed = 1.0
	sim_paused = false
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
		var archetype: String = String(record.get("archetype", _default_archetype_for_district(district_id)))
		zone_by_index[index] = zone
		building_level_by_index[index] = clampi(int(record.get("seed_level", 1)), 1, 3)
		district_id_by_index[index] = district_id
		style_profile_by_index[index] = style_profile
		archetype_by_index[index] = archetype
		if not district_policy_map.has(district_id):
			district_policy_map[district_id] = POLICY_BALANCED
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
			archetype_by_index[idx] = "road_segment"
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
		"level_sum": 0,
		"traffic_penalty_sum": 0.0,
		"traffic_samples": 0,
		"service_penalty_sum": 0.0,
		"service_samples": 0,
		"upkeep_load_sum": 0.0,
		"upkeep_samples": 0,
		"archetype_counts": {}
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
		var traffic_samples: int = int(stat["traffic_samples"])
		var traffic_stress: float = 0.0 if traffic_samples == 0 else float(stat["traffic_penalty_sum"]) / float(traffic_samples)
		var service_samples: int = int(stat["service_samples"])
		var service_stress: float = 0.0 if service_samples == 0 else float(stat["service_penalty_sum"]) / float(service_samples)
		var upkeep_hook: float = float(district_upkeep_hook_map.get(district_id, 1.0))
		var archetype_counts: Dictionary = Dictionary(stat.get("archetype_counts", {}))
		var primary_archetype: String = _primary_archetype(archetype_counts, district_id)
		var maturity_factor: float = clamp(avg_level / 3.0, 0.0, 1.0)

		var traffic_penalty_points: float = traffic_stress * 34.0
		var service_penalty_points: float = service_stress * 28.0
		var res_demand: float = clamp(50.0 + (housing_pressure - 1.0) * 38.0 + (1.0 - res_share) * 10.0 + (connected_ratio - 0.5) * 14.0 - traffic_penalty_points - service_penalty_points, 0.0, 100.0)
		var com_demand: float = clamp(50.0 + (job_pressure - 1.0) * 32.0 + (1.0 - com_share) * 8.0 + (connected_ratio - 0.5) * 10.0 - traffic_penalty_points - service_penalty_points, 0.0, 100.0)
		var ind_demand: float = clamp(42.0 + (job_pressure - 1.0) * 24.0 + (1.0 - ind_share) * 12.0 - maturity_factor * 12.0 - traffic_penalty_points * 0.8 - service_penalty_points, 0.0, 100.0)
		var composite: float = clamp((res_demand * 0.4) + (com_demand * 0.35) + (ind_demand * 0.25), 0.0, 100.0)
		var policy_id: String = get_district_policy(district_id)

		district_demand_snapshot.append(
			{
				"district_id": district_id,
				"policy_id": policy_id,
				"demand_index": composite,
				"traffic_stress": traffic_stress,
				"service_stress": service_stress,
				"upkeep_hook": upkeep_hook,
				"active_event": _event_label_for_district(district_id),
				"primary_archetype": primary_archetype,
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

func set_district_policy(district_id: String, policy_id: String) -> void:
	if district_id == "":
		return
	if not _is_valid_policy(policy_id):
		return
	district_policy_map[district_id] = policy_id

func get_district_policy(district_id: String) -> String:
	if district_policy_map.has(district_id):
		return String(district_policy_map[district_id])
	return POLICY_BALANCED

func _is_valid_policy(policy_id: String) -> bool:
	return policy_id in [POLICY_BALANCED, POLICY_GROWTH, POLICY_PROFIT]

func _policy_growth_multiplier(policy_id: String) -> float:
	return float(POLICY_GROWTH_MULT.get(policy_id, 1.0))

func _policy_tax_multiplier(policy_id: String) -> float:
	return float(POLICY_TAX_MULT.get(policy_id, 1.0))

func _policy_upkeep_multiplier(policy_id: String) -> float:
	return float(POLICY_UPKEEP_MULT.get(policy_id, 1.0))

func set_service_level(service_id: String, level: float) -> void:
	if not service_levels.has(service_id):
		return
	service_levels[service_id] = clamp(level, 0.0, 100.0)

func get_service_levels() -> Dictionary:
	return service_levels.duplicate(true)

func set_overlay_mode(mode: String) -> void:
	if mode in [OVERLAY_NONE, OVERLAY_LAND_VALUE, OVERLAY_NOISE, OVERLAY_CRIME]:
		overlay_mode = mode
		queue_redraw()

func get_overlay_mode() -> String:
	return overlay_mode

func get_overlay_metrics() -> Dictionary:
	return {
		"avg_land_value": avg_land_value,
		"avg_noise": avg_noise,
		"avg_crime": avg_crime,
		"avg_commute_penalty": avg_commute_penalty
	}

func set_district_identity_profiles(payload: Dictionary) -> void:
	district_identity_profiles = payload.duplicate(true)

func get_district_identity(district_id: String) -> Dictionary:
	return _identity_profile_for(district_id).duplicate(true)

func _identity_profile_for(district_id: String) -> Dictionary:
	if district_identity_profiles.is_empty():
		return {}
	var districts_v: Variant = district_identity_profiles.get("districts", {})
	if typeof(districts_v) != TYPE_DICTIONARY:
		return {}
	var districts: Dictionary = districts_v
	if districts.has(district_id):
		return Dictionary(districts[district_id])
	var fallback_v: Variant = district_identity_profiles.get("fallback", {})
	if typeof(fallback_v) == TYPE_DICTIONARY:
		return Dictionary(fallback_v)
	return {}

func _identity_color(profile: Dictionary, key: String, fallback: Color) -> Color:
	var color_value: Variant = profile.get(key, "")
	if typeof(color_value) == TYPE_STRING:
		var color_text: String = String(color_value)
		if color_text != "":
			return Color.from_string(color_text, fallback)
	return fallback

func _identity_signage_density(profile: Dictionary) -> float:
	return clamp(float(profile.get("signage_density", 0.0)), 0.0, 1.0)

func _identity_growth_multiplier(zone: int, profile: Dictionary) -> float:
	if zone == Tool.COMMERCIAL:
		return clamp(float(profile.get("commercial_growth_mult", 1.0)), 0.85, 1.25)
	return 1.0

func _identity_tax_multiplier(zone: int, profile: Dictionary) -> float:
	if zone == Tool.COMMERCIAL:
		return clamp(float(profile.get("commercial_tax_mult", 1.0)), 0.85, 1.3)
	return 1.0

func _identity_noise_penalty_multiplier(profile: Dictionary) -> float:
	return clamp(float(profile.get("noise_penalty_mult", 1.0)), 0.8, 1.25)

func _default_archetype_for_district(district_id: String) -> String:
	var profile: Dictionary = _identity_profile_for(district_id)
	var archetypes_v: Variant = profile.get("archetypes", [])
	if typeof(archetypes_v) == TYPE_ARRAY:
		var archetypes: Array = archetypes_v
		if not archetypes.is_empty():
			return String(archetypes[0])
	return "mixed_block_generic"

func _default_archetype_for_cell(index: int, zone: int) -> String:
	var district_id: String = district_id_by_index[index]
	if zone == Tool.INDUSTRIAL:
		return "warehouse_conversion_row"
	if zone == Tool.COMMERCIAL:
		return _default_archetype_for_district(district_id)
	if zone == Tool.RESIDENTIAL:
		return "walkup_residential_row"
	return "mixed_block_generic"

func _service_norm(service_id: String) -> float:
	return clamp(float(service_levels.get(service_id, 0.0)) / 100.0, 0.0, 1.0)

func _zone_service_multiplier(zone: int) -> float:
	if zone == Tool.RESIDENTIAL:
		var police := _service_norm("police")
		var transit := _service_norm("transit")
		return clamp(0.62 + police * 0.20 + transit * 0.20, 0.65, 1.15)
	if zone == Tool.COMMERCIAL:
		var transit_c := _service_norm("transit")
		var sanitation_c := _service_norm("sanitation")
		var police_c := _service_norm("police")
		return clamp(0.60 + transit_c * 0.2 + sanitation_c * 0.12 + police_c * 0.1, 0.62, 1.16)
	if zone == Tool.INDUSTRIAL:
		var fire_i := _service_norm("fire")
		var sanitation_i := _service_norm("sanitation")
		var transit_i := _service_norm("transit")
		return clamp(0.58 + fire_i * 0.22 + sanitation_i * 0.16 + transit_i * 0.1, 0.6, 1.15)
	return 1.0

func _zone_service_cost(zone: int) -> float:
	if zone == Tool.RESIDENTIAL:
		return 0.55 * (_service_norm("police") + _service_norm("transit"))
	if zone == Tool.COMMERCIAL:
		return 0.5 * (_service_norm("police") + _service_norm("sanitation") + _service_norm("transit"))
	if zone == Tool.INDUSTRIAL:
		return 0.58 * (_service_norm("fire") + _service_norm("sanitation") + _service_norm("transit"))
	return 0.0

func _rebuild_district_upkeep_hooks(stats: Dictionary) -> void:
	district_upkeep_hook_map.clear()
	for district_key in stats.keys():
		var district_id: String = String(district_key)
		var stat: Dictionary = stats[district_id]
		var traffic_samples: int = int(stat.get("traffic_samples", 0))
		var service_samples: int = int(stat.get("service_samples", 0))
		var upkeep_samples: int = int(stat.get("upkeep_samples", 0))
		var traffic_stress: float = 0.0 if traffic_samples == 0 else float(stat.get("traffic_penalty_sum", 0.0)) / float(traffic_samples)
		var service_stress: float = 0.0 if service_samples == 0 else float(stat.get("service_penalty_sum", 0.0)) / float(service_samples)
		var upkeep_load: float = 1.0 if upkeep_samples == 0 else float(stat.get("upkeep_load_sum", 0.0)) / float(upkeep_samples)
		var hook: float = clamp(0.88 + upkeep_load * 0.12 + traffic_stress * 0.28 + service_stress * 0.26, 0.8, 1.6)
		district_upkeep_hook_map[district_id] = hook

func _update_event_system(stats: Dictionary) -> void:
	if active_event_id != "":
		active_event_ticks_left -= 1
		if active_event_ticks_left <= 0:
			_record_event(active_event_id, active_event_district, "ended")
			active_event_id = ""
			active_event_district = ""
			active_event_ticks_left = 0
			event_cooldown_ticks = 6
		return

	if event_cooldown_ticks > 0:
		event_cooldown_ticks -= 1
		return

	if sim_tick < 18:
		return
	if stats.is_empty():
		return
	if sim_rng.randf() > 0.055:
		return

	var district_candidates: Array[String] = []
	for key in stats.keys():
		district_candidates.append(String(key))
	if district_candidates.is_empty():
		return

	var target_district := district_candidates[sim_rng.randi_range(0, district_candidates.size() - 1)]
	var event_pool := [EVENT_BLACKOUT, EVENT_STRIKE, EVENT_HEATWAVE]
	active_event_id = String(event_pool[sim_rng.randi_range(0, event_pool.size() - 1)])
	active_event_district = target_district
	active_event_ticks_left = int(EVENT_BASE_DURATION.get(active_event_id, 8))
	_record_event(active_event_id, active_event_district, "started")

func _record_event(event_id: String, district_id: String, state: String) -> void:
	recent_events.append(
		{
			"tick": sim_tick,
			"event_id": event_id,
			"event_title": String(EVENT_TITLES.get(event_id, event_id.capitalize())),
			"district_id": district_id,
			"state": state
		}
	)
	while recent_events.size() > MAX_EVENT_HISTORY:
		recent_events.remove_at(0)

func _event_applies_to_district(district_id: String) -> bool:
	if active_event_id == "":
		return false
	if district_id == "":
		return false
	return district_id == active_event_district

func _event_growth_multiplier(zone: int, district_id: String) -> float:
	if not _event_applies_to_district(district_id):
		return 1.0
	if active_event_id == EVENT_BLACKOUT:
		return 0.76 if zone == Tool.COMMERCIAL else 0.88
	if active_event_id == EVENT_STRIKE:
		return 0.78 if zone in [Tool.RESIDENTIAL, Tool.COMMERCIAL] else 0.9
	if active_event_id == EVENT_HEATWAVE:
		return 0.86
	return 1.0

func _event_tax_multiplier(district_id: String) -> float:
	if not _event_applies_to_district(district_id):
		return 1.0
	if active_event_id == EVENT_BLACKOUT:
		return 0.82
	if active_event_id == EVENT_STRIKE:
		return 0.84
	if active_event_id == EVENT_HEATWAVE:
		return 0.9
	return 1.0

func _event_upkeep_multiplier(district_id: String) -> float:
	if not _event_applies_to_district(district_id):
		return 1.0
	if active_event_id == EVENT_BLACKOUT:
		return 1.32
	if active_event_id == EVENT_STRIKE:
		return 1.25
	if active_event_id == EVENT_HEATWAVE:
		return 1.22
	return 1.0

func _event_noise_bonus(district_id: String) -> float:
	if not _event_applies_to_district(district_id):
		return 0.0
	if active_event_id == EVENT_STRIKE:
		return 9.0
	if active_event_id == EVENT_HEATWAVE:
		return 6.0
	return 0.0

func _event_crime_bonus(district_id: String) -> float:
	if not _event_applies_to_district(district_id):
		return 0.0
	if active_event_id == EVENT_BLACKOUT:
		return 15.0
	if active_event_id == EVENT_STRIKE:
		return 8.0
	if active_event_id == EVENT_HEATWAVE:
		return 5.0
	return 0.0

func _event_label_for_district(district_id: String) -> String:
	if not _event_applies_to_district(district_id):
		return "None"
	return String(EVENT_TITLES.get(active_event_id, active_event_id.capitalize()))

func _average_upkeep_hook() -> float:
	if district_upkeep_hook_map.is_empty():
		return 1.0
	var sum := 0.0
	for key in district_upkeep_hook_map.keys():
		sum += float(district_upkeep_hook_map[key])
	return sum / float(max(district_upkeep_hook_map.size(), 1))

func _primary_archetype(counts: Dictionary, district_id: String) -> String:
	var best_name := ""
	var best_count := -1
	for key in counts.keys():
		var name: String = String(key)
		var count: int = int(counts[key])
		if count > best_count:
			best_name = name
			best_count = count
	if best_name != "":
		return best_name
	return _default_archetype_for_district(district_id)

func get_event_snapshot() -> Dictionary:
	return {
		"active_event_id": active_event_id,
		"active_event_title": String(EVENT_TITLES.get(active_event_id, "None")) if active_event_id != "" else "None",
		"active_event_district": active_event_district,
		"ticks_left": active_event_ticks_left,
		"cooldown_ticks": event_cooldown_ticks,
		"recent_events": recent_events.duplicate(true)
	}

func trigger_random_event() -> bool:
	if active_event_id != "":
		return false
	if district_demand_snapshot.is_empty():
		return false
	var target_district: String = String(district_demand_snapshot[sim_rng.randi_range(0, district_demand_snapshot.size() - 1)].get("district_id", "outer_borough_mix"))
	var event_pool := [EVENT_BLACKOUT, EVENT_STRIKE, EVENT_HEATWAVE]
	active_event_id = String(event_pool[sim_rng.randi_range(0, event_pool.size() - 1)])
	active_event_district = target_district
	active_event_ticks_left = int(EVENT_BASE_DURATION.get(active_event_id, 8))
	_record_event(active_event_id, active_event_district, "started")
	return true

func export_state() -> Dictionary:
	return {
		"columns": columns,
		"rows": rows,
		"cell_size": cell_size,
		"money": money,
		"population": population,
		"jobs": jobs,
		"selected_tool": int(selected_tool),
		"zone_by_index": zone_by_index.duplicate(),
		"road_by_index": road_by_index.duplicate(),
		"building_level_by_index": building_level_by_index.duplicate(),
		"district_id_by_index": district_id_by_index.duplicate(),
		"style_profile_by_index": style_profile_by_index.duplicate(),
		"archetype_by_index": archetype_by_index.duplicate(),
		"land_value_by_index": land_value_by_index.duplicate(),
		"noise_by_index": noise_by_index.duplicate(),
		"crime_by_index": crime_by_index.duplicate(),
		"district_policy_map": district_policy_map.duplicate(true),
		"district_upkeep_hook_map": district_upkeep_hook_map.duplicate(true),
		"district_identity_profiles": district_identity_profiles.duplicate(true),
		"service_levels": service_levels.duplicate(true),
		"overlay_mode": overlay_mode,
		"active_event_id": active_event_id,
		"active_event_district": active_event_district,
		"active_event_ticks_left": active_event_ticks_left,
		"event_cooldown_ticks": event_cooldown_ticks,
		"recent_events": recent_events.duplicate(true),
		"sim_speed": sim_speed,
		"sim_paused": sim_paused,
		"sim_tick": sim_tick,
		"economy_history": economy_history.duplicate(true),
		"positive_cashflow_streak": positive_cashflow_streak,
		"objectives_complete": objectives_complete,
		"objectives_complete_tick": objectives_complete_tick
	}

func import_state(state: Dictionary) -> bool:
	if int(state.get("columns", -1)) != columns:
		return false
	if int(state.get("rows", -1)) != rows:
		return false

	var zones_v: Variant = state.get("zone_by_index", [])
	var roads_v: Variant = state.get("road_by_index", [])
	var levels_v: Variant = state.get("building_level_by_index", [])
	var districts_v: Variant = state.get("district_id_by_index", [])
	var styles_v: Variant = state.get("style_profile_by_index", [])
	var archetypes_v: Variant = state.get("archetype_by_index", null)
	var land_v: Variant = state.get("land_value_by_index", [])
	var noise_v: Variant = state.get("noise_by_index", [])
	var crime_v: Variant = state.get("crime_by_index", [])
	var policies_v: Variant = state.get("district_policy_map", {})
	var upkeep_hooks_v: Variant = state.get("district_upkeep_hook_map", {})
	var identity_profiles_v: Variant = state.get("district_identity_profiles", null)
	var services_v: Variant = state.get("service_levels", {})
	var recent_events_v: Variant = state.get("recent_events", [])
	var history_v: Variant = state.get("economy_history", [])

	if typeof(zones_v) != TYPE_ARRAY:
		return false
	if typeof(roads_v) != TYPE_ARRAY:
		return false
	if typeof(levels_v) != TYPE_ARRAY:
		return false
	if typeof(districts_v) != TYPE_ARRAY:
		return false
	if typeof(styles_v) != TYPE_ARRAY:
		return false
	if typeof(land_v) != TYPE_ARRAY:
		return false
	if typeof(noise_v) != TYPE_ARRAY:
		return false
	if typeof(crime_v) != TYPE_ARRAY:
		return false
	if typeof(policies_v) != TYPE_DICTIONARY:
		return false
	if typeof(upkeep_hooks_v) != TYPE_DICTIONARY:
		return false
	if typeof(services_v) != TYPE_DICTIONARY:
		return false
	if typeof(recent_events_v) != TYPE_ARRAY:
		return false
	if typeof(history_v) != TYPE_ARRAY:
		return false

	var expected_size := columns * rows
	var zones: Array = zones_v
	var roads: Array = roads_v
	var levels: Array = levels_v
	var districts: Array = districts_v
	var styles: Array = styles_v
	var archetypes: Array = []
	if typeof(archetypes_v) == TYPE_ARRAY:
		archetypes = archetypes_v
	var land_values: Array = land_v
	var noise_values: Array = noise_v
	var crime_values: Array = crime_v
	if zones.size() != expected_size:
		return false
	if roads.size() != expected_size:
		return false
	if levels.size() != expected_size:
		return false
	if districts.size() != expected_size:
		return false
	if styles.size() != expected_size:
		return false
	if not archetypes.is_empty() and archetypes.size() != expected_size:
		return false
	if land_values.size() != expected_size:
		return false
	if noise_values.size() != expected_size:
		return false
	if crime_values.size() != expected_size:
		return false

	zone_by_index.clear()
	road_by_index.clear()
	building_level_by_index.clear()
	district_id_by_index.clear()
	style_profile_by_index.clear()
	archetype_by_index.clear()
	land_value_by_index.clear()
	noise_by_index.clear()
	crime_by_index.clear()

	for i in range(expected_size):
		zone_by_index.append(int(zones[i]))
		road_by_index.append(bool(roads[i]))
		building_level_by_index.append(int(levels[i]))
		district_id_by_index.append(String(districts[i]))
		style_profile_by_index.append(String(styles[i]))
		if archetypes.is_empty():
			archetype_by_index.append(_default_archetype_for_district(String(districts[i])))
		else:
			archetype_by_index.append(String(archetypes[i]))
		land_value_by_index.append(float(land_values[i]))
		noise_by_index.append(float(noise_values[i]))
		crime_by_index.append(float(crime_values[i]))

	district_policy_map = Dictionary(policies_v).duplicate(true)
	district_upkeep_hook_map = Dictionary(upkeep_hooks_v).duplicate(true)
	if typeof(identity_profiles_v) == TYPE_DICTIONARY:
		district_identity_profiles = Dictionary(identity_profiles_v).duplicate(true)
	var service_dict: Dictionary = Dictionary(services_v)
	service_levels["police"] = clamp(float(service_dict.get("police", 55.0)), 0.0, 100.0)
	service_levels["fire"] = clamp(float(service_dict.get("fire", 55.0)), 0.0, 100.0)
	service_levels["sanitation"] = clamp(float(service_dict.get("sanitation", 55.0)), 0.0, 100.0)
	service_levels["transit"] = clamp(float(service_dict.get("transit", 55.0)), 0.0, 100.0)
	overlay_mode = String(state.get("overlay_mode", OVERLAY_NONE))
	if overlay_mode not in [OVERLAY_NONE, OVERLAY_LAND_VALUE, OVERLAY_NOISE, OVERLAY_CRIME]:
		overlay_mode = OVERLAY_NONE
	active_event_id = String(state.get("active_event_id", ""))
	active_event_district = String(state.get("active_event_district", ""))
	active_event_ticks_left = int(state.get("active_event_ticks_left", 0))
	event_cooldown_ticks = int(state.get("event_cooldown_ticks", 0))
	if active_event_id != "" and not EVENT_TITLES.has(active_event_id):
		active_event_id = ""
		active_event_district = ""
		active_event_ticks_left = 0
	recent_events.clear()
	var loaded_recent_events: Array = recent_events_v
	for event_v in loaded_recent_events:
		if typeof(event_v) != TYPE_DICTIONARY:
			continue
		recent_events.append(Dictionary(event_v).duplicate(true))
	while recent_events.size() > MAX_EVENT_HISTORY:
		recent_events.remove_at(0)

	money = int(state.get("money", 8000))
	population = int(state.get("population", 0))
	jobs = int(state.get("jobs", 0))
	selected_tool = int(state.get("selected_tool", int(Tool.ROAD)))
	sim_speed = float(state.get("sim_speed", 1.0))
	sim_paused = bool(state.get("sim_paused", false))
	sim_tick = int(state.get("sim_tick", 0))
	positive_cashflow_streak = int(state.get("positive_cashflow_streak", 0))
	objectives_complete = bool(state.get("objectives_complete", false))
	objectives_complete_tick = int(state.get("objectives_complete_tick", -1))
	economy_history.clear()
	var history_arr: Array = history_v
	for point_variant in history_arr:
		if typeof(point_variant) != TYPE_DICTIONARY:
			continue
		var point: Dictionary = point_variant
		economy_history.append(point.duplicate(true))
	while economy_history.size() > MAX_HISTORY:
		economy_history.remove_at(0)
	connected_residential = 0
	connected_commercial = 0
	connected_industrial = 0
	district_demand_snapshot.clear()
	road_cluster_count = 0
	largest_road_cluster = 0
	road_efficiency = 1.0
	avg_commute_penalty = 0.0
	avg_land_value = 0.0
	avg_noise = 0.0
	avg_crime = 0.0
	undo_stack.clear()
	redo_stack.clear()
	sim_timer = 0.0
	atmosphere_time = 0.0
	atmosphere_redraw_accum = 0.0
	queue_redraw()
	return true

func set_sim_speed(new_speed: float) -> void:
	sim_speed = clamp(new_speed, 0.25, 5.0)
	sim_paused = false
	queue_redraw()

func set_sim_paused(paused: bool) -> void:
	sim_paused = paused
	queue_redraw()

func is_sim_paused() -> bool:
	return sim_paused

func get_sim_speed() -> float:
	return sim_speed

func _push_economy_point() -> void:
	economy_history.append(
		{
			"tick": sim_tick,
			"money": money,
			"population": population,
			"jobs": jobs
		}
	)
	if economy_history.size() > MAX_HISTORY:
		economy_history.remove_at(0)

func get_economy_snapshot() -> Dictionary:
	var latest_money := money
	var latest_pop := population
	var latest_jobs := jobs

	var delta_money := 0
	var delta_pop := 0
	var delta_jobs := 0
	if economy_history.size() >= 2:
		var prev: Dictionary = economy_history[economy_history.size() - 2]
		delta_money = latest_money - int(prev.get("money", latest_money))
		delta_pop = latest_pop - int(prev.get("population", latest_pop))
		delta_jobs = latest_jobs - int(prev.get("jobs", latest_jobs))

	var housing_pressure: float = clamp((float(latest_jobs) + 1.0) / (float(latest_pop) + 1.0), 0.5, 2.0)
	var job_pressure: float = clamp((float(latest_pop) + 1.0) / (float(latest_jobs) + 1.0), 0.5, 2.0)

	return {
		"money": latest_money,
		"population": latest_pop,
		"jobs": latest_jobs,
		"delta_money": delta_money,
		"delta_population": delta_pop,
		"delta_jobs": delta_jobs,
		"housing_pressure": housing_pressure,
		"job_pressure": job_pressure,
		"avg_upkeep_hook": _average_upkeep_hook(),
		"active_event_title": String(EVENT_TITLES.get(active_event_id, "None")) if active_event_id != "" else "None",
		"active_event_district": active_event_district,
		"event_ticks_left": active_event_ticks_left,
		"sim_tick": sim_tick
	}

func _update_active_alerts() -> void:
	active_alerts.clear()

	var housing_pressure: float = clamp((float(jobs) + 1.0) / (float(population) + 1.0), 0.5, 2.0)
	var job_pressure: float = clamp((float(population) + 1.0) / (float(jobs) + 1.0), 0.5, 2.0)

	if money < 0:
		_push_alert("critical", "Budget Deficit", "City treasury is negative.")
	elif money < 1200:
		_push_alert("warning", "Low Treasury", "Cash reserves are running low.")

	if connected_residential == 0:
		_push_alert("warning", "No Housing Growth", "No connected residential zones.")
	if connected_commercial + connected_industrial == 0:
		_push_alert("warning", "No Employment Growth", "No connected job zones.")
	if road_cluster_count > 3 and road_efficiency < 0.55:
		_push_alert("warning", "Fragmented Roads", "Road network is split into many clusters.")
	if avg_commute_penalty > 0.22:
		_push_alert("warning", "Commute Stress", "Road capacity is hurting district growth.")
	if float(service_levels.get("police", 0.0)) < 40.0:
		_push_alert("warning", "Police Coverage Low", "Safety service level is below target.")
	if float(service_levels.get("fire", 0.0)) < 40.0:
		_push_alert("warning", "Fire Coverage Low", "Fire response coverage is below target.")
	if float(service_levels.get("sanitation", 0.0)) < 40.0:
		_push_alert("warning", "Sanitation Low", "Cleanliness service level is below target.")
	if float(service_levels.get("transit", 0.0)) < 40.0:
		_push_alert("warning", "Transit Coverage Low", "Mobility service level is below target.")
	if avg_noise > 58.0:
		_push_alert("warning", "High Noise", "City-wide noise levels are elevated.")
	if avg_crime > 52.0:
		_push_alert("warning", "High Crime", "Crime pressure is hurting district quality.")
	if active_event_id != "":
		_push_alert(
			"warning",
			"Active Event",
			"%s in %s (%d ticks left)." % [
				String(EVENT_TITLES.get(active_event_id, active_event_id.capitalize())),
				active_event_district,
				active_event_ticks_left
			]
		)

	if housing_pressure > 1.25:
		_push_alert("warning", "Housing Pressure", "Jobs are outpacing residents.")
	elif housing_pressure < 0.8:
		_push_alert("info", "Housing Surplus", "Residential growth is outpacing jobs.")

	if job_pressure > 1.25:
		_push_alert("warning", "Job Pressure", "Population is outpacing jobs.")
	elif job_pressure < 0.8:
		_push_alert("info", "Job Surplus", "Jobs are outpacing population.")

	if active_alerts.is_empty():
		_push_alert("ok", "Stable", "No major systemic pressure detected.")

func _push_alert(level: String, title: String, detail: String) -> void:
	active_alerts.append(
		{
			"level": level,
			"title": title,
			"detail": detail
		}
	)

func get_active_alerts() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for alert in active_alerts:
		output.append(alert.duplicate(true))
	return output

func get_objective_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	var completed_count := 0
	for objective_v in OBJECTIVES:
		var objective: Dictionary = objective_v
		var id: String = String(objective.get("id", ""))
		var title: String = String(objective.get("title", "Objective"))
		var complete := false
		var progress_text := ""

		match id:
			"pop_500":
				complete = population >= 500
				progress_text = "%d / 500" % population
			"jobs_350":
				complete = jobs >= 350
				progress_text = "%d / 350" % jobs
			"cash_12000":
				complete = money >= 12000
				progress_text = "$%d / $12000" % money
			"cashflow_20":
				complete = positive_cashflow_streak >= 20
				progress_text = "%d / 20 ticks" % positive_cashflow_streak
			_:
				progress_text = "-"

		snapshot.append(
			{
				"id": id,
				"title": title,
				"complete": complete,
				"progress": progress_text
			}
		)
		if complete:
			completed_count += 1

	var just_completed := false
	if completed_count == OBJECTIVES.size() and not objectives_complete:
		objectives_complete = true
		objectives_complete_tick = sim_tick
		just_completed = true
	elif completed_count < OBJECTIVES.size() and objectives_complete:
		objectives_complete = false
		objectives_complete_tick = -1

	snapshot.append(
		{
			"id": "__meta__",
			"title": "meta",
			"complete": objectives_complete,
			"progress": "%d/%d" % [completed_count, OBJECTIVES.size()],
			"completed_count": completed_count,
			"total_count": OBJECTIVES.size(),
			"just_completed": just_completed,
			"complete_tick": objectives_complete_tick
		}
	)
	return snapshot

func is_objectives_complete() -> bool:
	return objectives_complete

func get_objectives_complete_tick() -> int:
	return objectives_complete_tick

func get_road_metrics() -> Dictionary:
	return {
		"cluster_count": road_cluster_count,
		"largest_cluster": largest_road_cluster,
		"efficiency": road_efficiency,
		"avg_commute_penalty": avg_commute_penalty
	}

func undo_edit() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append(_capture_edit_state())
	var previous: Dictionary = undo_stack.pop_back()
	_restore_edit_state(previous)
	queue_redraw()

func redo_edit() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(_capture_edit_state())
	var next_state: Dictionary = redo_stack.pop_back()
	_restore_edit_state(next_state)
	queue_redraw()

func _begin_edit_stroke() -> void:
	stroke_capture_active = true
	stroke_dirty = false

func _end_edit_stroke() -> void:
	stroke_capture_active = false
	stroke_dirty = false

func _mark_edit_if_needed() -> void:
	if stroke_capture_active:
		if stroke_dirty:
			return
		undo_stack.append(_capture_edit_state())
		_trim_undo_stack()
		redo_stack.clear()
		return

	undo_stack.append(_capture_edit_state())
	_trim_undo_stack()
	redo_stack.clear()

func _trim_undo_stack() -> void:
	while undo_stack.size() > MAX_EDIT_HISTORY:
		undo_stack.remove_at(0)

func _capture_edit_state() -> Dictionary:
	return {
		"zone_by_index": zone_by_index.duplicate(),
		"road_by_index": road_by_index.duplicate(),
		"building_level_by_index": building_level_by_index.duplicate(),
		"district_id_by_index": district_id_by_index.duplicate(),
		"style_profile_by_index": style_profile_by_index.duplicate(),
		"archetype_by_index": archetype_by_index.duplicate(),
		"land_value_by_index": land_value_by_index.duplicate(),
		"noise_by_index": noise_by_index.duplicate(),
		"crime_by_index": crime_by_index.duplicate(),
		"money": money
	}

func _restore_edit_state(state: Dictionary) -> void:
	var zones_v: Variant = state.get("zone_by_index", [])
	var roads_v: Variant = state.get("road_by_index", [])
	var levels_v: Variant = state.get("building_level_by_index", [])
	var districts_v: Variant = state.get("district_id_by_index", [])
	var styles_v: Variant = state.get("style_profile_by_index", [])
	var archetypes_v: Variant = state.get("archetype_by_index", null)
	var land_v: Variant = state.get("land_value_by_index", [])
	var noise_v: Variant = state.get("noise_by_index", [])
	var crime_v: Variant = state.get("crime_by_index", [])
	if typeof(zones_v) != TYPE_ARRAY:
		return
	if typeof(roads_v) != TYPE_ARRAY:
		return
	if typeof(levels_v) != TYPE_ARRAY:
		return
	if typeof(districts_v) != TYPE_ARRAY:
		return
	if typeof(styles_v) != TYPE_ARRAY:
		return
	if typeof(land_v) != TYPE_ARRAY:
		return
	if typeof(noise_v) != TYPE_ARRAY:
		return
	if typeof(crime_v) != TYPE_ARRAY:
		return

	zone_by_index.clear()
	road_by_index.clear()
	building_level_by_index.clear()
	district_id_by_index.clear()
	style_profile_by_index.clear()
	archetype_by_index.clear()
	land_value_by_index.clear()
	noise_by_index.clear()
	crime_by_index.clear()

	var zones: Array = zones_v
	var roads: Array = roads_v
	var levels: Array = levels_v
	var districts: Array = districts_v
	var styles: Array = styles_v
	var archetypes: Array = []
	if typeof(archetypes_v) == TYPE_ARRAY:
		archetypes = archetypes_v
	var land_values: Array = land_v
	var noise_values: Array = noise_v
	var crime_values: Array = crime_v
	if roads.size() != zones.size():
		return
	if levels.size() != zones.size():
		return
	if districts.size() != zones.size():
		return
	if styles.size() != zones.size():
		return
	if not archetypes.is_empty() and archetypes.size() != zones.size():
		return
	if land_values.size() != zones.size():
		return
	if noise_values.size() != zones.size():
		return
	if crime_values.size() != zones.size():
		return

	for i in range(zones.size()):
		zone_by_index.append(int(zones[i]))
		road_by_index.append(bool(roads[i]))
		building_level_by_index.append(int(levels[i]))
		district_id_by_index.append(String(districts[i]))
		style_profile_by_index.append(String(styles[i]))
		if archetypes.is_empty():
			archetype_by_index.append(_default_archetype_for_district(String(districts[i])))
		else:
			archetype_by_index.append(String(archetypes[i]))
		land_value_by_index.append(float(land_values[i]))
		noise_by_index.append(float(noise_values[i]))
		crime_by_index.append(float(crime_values[i]))

	money = int(state.get("money", money))
