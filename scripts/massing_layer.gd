extends Node2D

@export var district_generator_path: NodePath = ^"../DistrictGenerator"
@export var city_grid_path: NodePath = ^"../CityGrid"
@export var massing_profile_path := "res://data/runtime/massing_profiles.json"
@export var enabled := true

var district_generator: Node2D
var city_grid: Node2D
var massing_profiles: Dictionary = {}
var massing_instances: Array[Dictionary] = []

const DISTRICT_TINTS := {
	"midtown_core": Color(0.98, 0.86, 0.54, 1.0),
	"financial_district": Color(0.96, 0.79, 0.60, 1.0),
	"lower_east_side": Color(0.70, 0.82, 0.98, 1.0),
	"harlem": Color(0.68, 0.90, 0.76, 1.0),
	"queens_west": Color(0.84, 0.76, 0.97, 1.0),
	"outer_borough_mix": Color(0.85, 0.87, 0.92, 1.0)
}

const DEFAULT_PROFILE := {
	"inset_px": 10.0,
	"height_per_level": 18.0,
	"height_jitter": 5.0,
	"iso_skew_x": 0.42,
	"iso_skew_y": 1.0,
	"roof_tint": "#d8b691",
	"wall_tint": "#8aa0bf"
}

func _ready() -> void:
	district_generator = get_node_or_null(district_generator_path)
	city_grid = get_node_or_null(city_grid_path)
	massing_profiles = _load_massing_profiles()
	if district_generator != null and district_generator.has_signal("seed_records_generated"):
		district_generator.connect("seed_records_generated", _on_seed_records_generated)
	if district_generator != null and district_generator.has_method("get_seed_records_snapshot"):
		var seed_records_v: Variant = district_generator.call("get_seed_records_snapshot")
		if typeof(seed_records_v) == TYPE_ARRAY:
			_rebuild_massing(seed_records_v, int(district_generator.call("get_world_seed")))
	else:
		queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	for inst in massing_instances:
		draw_colored_polygon(inst["left"], inst["left_color"])
		draw_colored_polygon(inst["right"], inst["right_color"])
		draw_colored_polygon(inst["front"], inst["front_color"])
		draw_colored_polygon(inst["top"], inst["top_color"])
		draw_polyline(inst["top_outline"], Color(0.08, 0.1, 0.14, 0.72), 1.0)

func _on_seed_records_generated(seed_records: Array, world_seed: int) -> void:
	_rebuild_massing(seed_records, world_seed)

func _rebuild_massing(seed_records: Array, world_seed: int) -> void:
	massing_instances.clear()
	if not enabled:
		queue_redraw()
		return

	var cell_size := 64.0
	if city_grid != null:
		cell_size = float(city_grid.get("cell_size"))

	for seed_record_v in seed_records:
		if typeof(seed_record_v) != TYPE_DICTIONARY:
			continue
		var seed_record: Dictionary = seed_record_v
		var cell: Vector2i = seed_record.get("cell", Vector2i(-1, -1))
		if cell.x < 0 or cell.y < 0:
			continue

		var level: int = int(seed_record.get("seed_level", 1))
		if level <= 0:
			continue
		var style_profile: String = String(seed_record.get("style_profile", "default_mixed"))
		var district_id: String = String(seed_record.get("district_id", "outer_borough_mix"))
		var profile: Dictionary = _profile_for(style_profile)

		var inset: float = clamp(float(profile.get("inset_px", 10.0)), 4.0, cell_size * 0.32)
		var height_per_level: float = clamp(float(profile.get("height_per_level", 18.0)), 10.0, 40.0)
		var height_jitter: float = clamp(float(profile.get("height_jitter", 4.0)), 0.0, 20.0)
		var jitter: float = (_hash01(cell, world_seed, 17) - 0.5) * 2.0 * height_jitter
		var height_px: float = max(8.0, float(level) * height_per_level + jitter)
		var skew_x: float = clamp(float(profile.get("iso_skew_x", 0.42)), 0.2, 0.8)
		var skew_y: float = clamp(float(profile.get("iso_skew_y", 1.0)), 0.65, 1.35)
		var lift := Vector2(-height_px * skew_x, -height_px * skew_y)

		var cell_origin := Vector2(cell.x, cell.y) * cell_size
		var g0 := cell_origin + Vector2(inset, inset)
		var g1 := cell_origin + Vector2(cell_size - inset, inset)
		var g2 := cell_origin + Vector2(cell_size - inset, cell_size - inset)
		var g3 := cell_origin + Vector2(inset, cell_size - inset)
		var t0 := g0 + lift
		var t1 := g1 + lift
		var t2 := g2 + lift
		var t3 := g3 + lift

		var district_base: Color = DISTRICT_TINTS.get(district_id, DISTRICT_TINTS["outer_borough_mix"])
		var wall_tint: Color = Color.from_string(String(profile.get("wall_tint", "#8aa0bf")), district_base)
		var roof_tint: Color = Color.from_string(String(profile.get("roof_tint", "#d8b691")), district_base.lightened(0.18))
		var body: Color = district_base.lerp(wall_tint, 0.42)

		massing_instances.append(
			{
				"sort_key": g2.y,
				"left": PackedVector2Array([g0, g3, t3, t0]),
				"right": PackedVector2Array([g1, g2, t2, t1]),
				"front": PackedVector2Array([g3, g2, t2, t3]),
				"top": PackedVector2Array([t0, t1, t2, t3]),
				"top_outline": PackedVector2Array([t0, t1, t2, t3, t0]),
				"left_color": body.darkened(0.24),
				"right_color": body.darkened(0.32),
				"front_color": body.darkened(0.14),
				"top_color": body.lightened(0.14).lerp(roof_tint, 0.3)
			}
		)

	massing_instances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("sort_key", 0.0)) < float(b.get("sort_key", 0.0))
	)
	queue_redraw()

func _load_massing_profiles() -> Dictionary:
	if not FileAccess.file_exists(massing_profile_path):
		return {}
	var fp := FileAccess.open(massing_profile_path, FileAccess.READ)
	if fp == null:
		return {}
	var parsed: Variant = JSON.parse_string(fp.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var payload: Dictionary = parsed
	var profiles_v: Variant = payload.get("profiles", payload)
	if typeof(profiles_v) != TYPE_DICTIONARY:
		return {}
	return Dictionary(profiles_v).duplicate(true)

func _profile_for(style_profile: String) -> Dictionary:
	if massing_profiles.has(style_profile):
		return _merged_profile(Dictionary(massing_profiles[style_profile]))
	if massing_profiles.has("default_mixed"):
		return _merged_profile(Dictionary(massing_profiles["default_mixed"]))
	return DEFAULT_PROFILE.duplicate(true)

func _merged_profile(profile: Dictionary) -> Dictionary:
	var merged: Dictionary = DEFAULT_PROFILE.duplicate(true)
	for key in profile.keys():
		merged[key] = profile[key]
	return merged

func _hash01(cell: Vector2i, world_seed: int, salt: int) -> float:
	var h: int = int(hash("%d:%d:%d:%d" % [cell.x, cell.y, world_seed, salt]))
	var mod_val: int = abs(h) % 1000
	return float(mod_val) / 1000.0
