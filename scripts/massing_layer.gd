extends Node2D

@export var district_generator_path: NodePath = ^"../DistrictGenerator"
@export var city_grid_path: NodePath = ^"../CityGrid"
@export var massing_profile_path := "res://data/runtime/massing_profiles.json"
@export var landmark_pack_path := "res://data/runtime/landmark_pack.json"
@export var landmark_assets_path := "res://data/runtime/landmark_assets.json"
@export var enabled := true

var district_generator: Node2D
var city_grid: Node2D
var massing_profiles: Dictionary = {}
var landmark_pack: Dictionary = {}
var landmark_assets: Dictionary = {}
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
	landmark_pack = _load_landmark_pack()
	landmark_assets = _load_landmark_assets()
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
		draw_polyline(inst["top_outline"], inst["outline_color"], 1.0)
		if String(inst.get("landmark_name", "")) != "":
			_draw_landmark_detail(inst)

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
	var landmark_assignments: Dictionary = _select_landmark_assignments(seed_records, world_seed)

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
		var archetype: String = String(seed_record.get("archetype", ""))
		var profile: Dictionary = _profile_for(style_profile)
		var landmark_v: Variant = landmark_assignments.get(_cell_key(cell), null)
		var landmark: Dictionary = landmark_v if typeof(landmark_v) == TYPE_DICTIONARY else {}
		if not landmark.is_empty():
			profile = _apply_landmark_profile_overrides(profile, landmark)
		var asset: Dictionary = _asset_for_landmark(landmark)

		var inset: float = clamp(float(profile.get("inset_px", 10.0)), 4.0, cell_size * 0.32)
		var height_per_level: float = clamp(float(profile.get("height_per_level", 18.0)), 10.0, 40.0)
		var height_jitter: float = clamp(float(profile.get("height_jitter", 4.0)), 0.0, 20.0)
		var jitter: float = (_hash01(cell, world_seed, 17) - 0.5) * 2.0 * height_jitter
		var landmark_height_mult: float = clamp(float(landmark.get("height_mult", 1.0)), 0.75, 3.5)
		var asset_height_mult: float = clamp(float(asset.get("height_mult", 1.0)), 0.75, 3.5)
		var height_px: float = max(8.0, float(level) * height_per_level * landmark_height_mult * asset_height_mult + jitter)
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
		if not landmark.is_empty():
			wall_tint = Color.from_string(String(landmark.get("wall_tint", "")), wall_tint)
			roof_tint = Color.from_string(String(landmark.get("roof_tint", "")), roof_tint)
		wall_tint = Color.from_string(String(asset.get("wall_tint", "")), wall_tint)
		roof_tint = Color.from_string(String(asset.get("roof_tint", "")), roof_tint)
		var body: Color = district_base.lerp(wall_tint, 0.42)
		var top_color: Color = body.lightened(0.14).lerp(roof_tint, 0.3)
		if not landmark.is_empty():
			top_color = top_color.lightened(0.05)
		var outline_color := Color(0.08, 0.1, 0.14, 0.72)
		if not landmark.is_empty():
			outline_color = Color(0.92, 0.69, 0.33, 0.85)

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
				"top_color": top_color,
				"outline_color": outline_color,
				"landmark_name": String(landmark.get("name", "")),
				"landmark_asset_id": String(landmark.get("asset_id", "")),
				"archetype": archetype,
				"height_px": height_px,
				"roof_center": (t0 + t1 + t2 + t3) / 4.0
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

func _load_landmark_pack() -> Dictionary:
	if not FileAccess.file_exists(landmark_pack_path):
		return {}
	var fp := FileAccess.open(landmark_pack_path, FileAccess.READ)
	if fp == null:
		return {}
	var parsed: Variant = JSON.parse_string(fp.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return Dictionary(parsed).duplicate(true)

func _load_landmark_assets() -> Dictionary:
	if not FileAccess.file_exists(landmark_assets_path):
		return {}
	var fp := FileAccess.open(landmark_assets_path, FileAccess.READ)
	if fp == null:
		return {}
	var parsed: Variant = JSON.parse_string(fp.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var payload: Dictionary = parsed
	var assets_v: Variant = payload.get("assets", payload)
	if typeof(assets_v) != TYPE_DICTIONARY:
		return {}
	return Dictionary(assets_v).duplicate(true)

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

func _apply_landmark_profile_overrides(profile: Dictionary, landmark: Dictionary) -> Dictionary:
	var merged: Dictionary = profile.duplicate(true)
	var overrides_v: Variant = landmark.get("profile_overrides", {})
	if typeof(overrides_v) != TYPE_DICTIONARY:
		return merged
	var overrides: Dictionary = overrides_v
	for key in overrides.keys():
		merged[key] = overrides[key]
	return merged

func _asset_for_landmark(landmark: Dictionary) -> Dictionary:
	var asset_id: String = String(landmark.get("asset_id", ""))
	if asset_id == "":
		return {}
	if not landmark_assets.has(asset_id):
		return {}
	var asset_v: Variant = landmark_assets.get(asset_id, {})
	if typeof(asset_v) != TYPE_DICTIONARY:
		return {}
	return Dictionary(asset_v)

func _select_landmark_assignments(seed_records: Array, world_seed: int) -> Dictionary:
	var assignments: Dictionary = {}
	var landmarks_v: Variant = landmark_pack.get("landmarks", [])
	if typeof(landmarks_v) != TYPE_ARRAY:
		return assignments
	var landmarks: Array = landmarks_v
	if landmarks.is_empty():
		return assignments

	var district_counts: Dictionary = {}
	var candidates: Array[Dictionary] = []
	for seed_record_v in seed_records:
		if typeof(seed_record_v) == TYPE_DICTIONARY:
			candidates.append(seed_record_v)

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var cell_a: Vector2i = a.get("cell", Vector2i.ZERO)
		var cell_b: Vector2i = b.get("cell", Vector2i.ZERO)
		if cell_a.y == cell_b.y:
			return cell_a.x < cell_b.x
		return cell_a.y < cell_b.y
	)

	for seed_record in candidates:
		var cell: Vector2i = seed_record.get("cell", Vector2i(-1, -1))
		if cell.x < 0 or cell.y < 0:
			continue
		var district_id: String = String(seed_record.get("district_id", "outer_borough_mix"))
		var cell_key: String = _cell_key(cell)
		if assignments.has(cell_key):
			continue

		var matches: Array[Dictionary] = _matching_landmarks(seed_record, landmarks)
		if matches.is_empty():
			continue
		matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("priority", 0)) > int(b.get("priority", 0))
		)

		for landmark in matches:
			var max_per_district: int = max(1, int(landmark.get("max_per_district", 1)))
			var used_count: int = int(district_counts.get(district_id, 0))
			if used_count >= max_per_district:
				continue

			var chance: float = clamp(float(landmark.get("chance", 0.1)), 0.0, 1.0)
			var roll: float = _hash01(cell, world_seed, 111 + int(landmark.get("priority", 0)))
			if roll > chance:
				continue

			assignments[cell_key] = landmark.duplicate(true)
			district_counts[district_id] = used_count + 1
			break
	return assignments

func _matching_landmarks(seed_record: Dictionary, landmarks: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var district_id: String = String(seed_record.get("district_id", "outer_borough_mix"))
	var archetype: String = String(seed_record.get("archetype", "")).to_lower()
	var level: int = int(seed_record.get("seed_level", 1))

	for landmark_v in landmarks:
		if typeof(landmark_v) != TYPE_DICTIONARY:
			continue
		var landmark: Dictionary = landmark_v
		var district_ids_v: Variant = landmark.get("district_ids", [])
		if typeof(district_ids_v) == TYPE_ARRAY:
			var district_ids: Array = district_ids_v
			if not district_ids.is_empty() and district_id not in district_ids:
				continue
		var min_level: int = int(landmark.get("min_level", 1))
		if level < min_level:
			continue
		var archetypes_v: Variant = landmark.get("archetype_contains", [])
		if typeof(archetypes_v) == TYPE_ARRAY:
			var patterns: Array = archetypes_v
			if not patterns.is_empty():
				var any_match := false
				for pattern_v in patterns:
					var pattern: String = String(pattern_v).to_lower()
					if pattern != "" and archetype.find(pattern) != -1:
						any_match = true
						break
				if not any_match:
					continue
		output.append(landmark)
	return output

func _cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]

func _draw_landmark_detail(inst: Dictionary) -> void:
	var asset_id: String = String(inst.get("landmark_asset_id", ""))
	if asset_id == "":
		return
	if not landmark_assets.has(asset_id):
		return
	var asset_v: Variant = landmark_assets.get(asset_id, {})
	if typeof(asset_v) != TYPE_DICTIONARY:
		return
	var asset: Dictionary = asset_v
	var lod_rules_v: Variant = asset.get("lod_rules", {})
	var lod_rules: Dictionary = lod_rules_v if typeof(lod_rules_v) == TYPE_DICTIONARY else {}

	var zoom := 1.0
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		zoom = float(cam.zoom.x)
	var lod_id := "lod1"
	if zoom <= float(lod_rules.get("lod0_max_zoom", 0.8)):
		lod_id = "lod0"
	elif zoom <= float(lod_rules.get("lod1_max_zoom", 1.45)):
		lod_id = "lod1"
	else:
		lod_id = "lod2"

	var top: PackedVector2Array = inst.get("top", PackedVector2Array())
	if top.size() < 4:
		return
	var center: Vector2 = Vector2(inst.get("roof_center", Vector2.ZERO))
	var height_px: float = float(inst.get("height_px", 24.0))
	var accent: Color = Color.from_string(String(asset.get("accent_tint", "#f4c682")), Color(0.94, 0.67, 0.32, 0.92))
	var line_color: Color = accent.darkened(0.35)
	var top_width: float = max(6.0, top[1].x - top[0].x)
	var marker_h: float = clamp(height_px * 0.22, 5.0, 20.0)

	if lod_id == "lod0":
		draw_line(center, center + Vector2(0.0, -marker_h), line_color, 1.4)
		if bool(asset.get("has_antenna", false)):
			draw_line(center + Vector2(0.0, -marker_h), center + Vector2(0.0, -marker_h - 8.0), accent, 1.1)
		var stripes := int(clamp(float(asset.get("stripe_count_lod0", 3)), 1.0, 6.0))
		for i in range(stripes):
			var t := float(i + 1) / float(stripes + 1)
			var y: float = lerpf(top[0].y, top[3].y, t)
			draw_line(Vector2(top[0].x + 2.0, y), Vector2(top[1].x - 2.0, y), accent, 1.0)
	elif lod_id == "lod1":
		draw_line(center + Vector2(-top_width * 0.12, 0.0), center + Vector2(top_width * 0.12, 0.0), line_color, 1.1)
		if bool(asset.get("has_antenna", false)):
			draw_line(center, center + Vector2(0.0, -marker_h * 0.8), accent, 1.0)
	else:
		draw_circle(center, 1.6, accent)

func _hash01(cell: Vector2i, world_seed: int, salt: int) -> float:
	var h: int = int(hash("%d:%d:%d:%d" % [cell.x, cell.y, world_seed, salt]))
	var mod_val: int = abs(h) % 1000
	return float(mod_val) / 1000.0
