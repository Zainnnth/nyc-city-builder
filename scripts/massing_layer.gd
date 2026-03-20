extends Node2D

@export var district_generator_path: NodePath = ^"../DistrictGenerator"
@export var city_grid_path: NodePath = ^"../CityGrid"
@export var massing_profile_path := "res://data/runtime/massing_profiles.json"
@export var landmark_pack_path := "res://data/runtime/landmark_pack.json"
@export var landmark_assets_path := "res://data/runtime/landmark_assets.json"
@export var prefab_sets_path := "res://data/runtime/prefab_sets.json"
@export var optimization_profile_path := "res://data/runtime/render_optimization.json"
@export var cel_shader_path := "res://shaders/cel_massing.gdshader"
@export var use_cel_shader := true
@export_range(2.0, 8.0, 1.0) var cel_shade_steps := 4.0
@export_range(0.8, 1.6, 0.01) var cel_shade_contrast := 1.08
@export_range(0.0, 1.0, 0.01) var cel_band_mix := 0.7
@export var enabled := true

var district_generator: Node2D
var city_grid: Node2D
var massing_profiles: Dictionary = {}
var landmark_pack: Dictionary = {}
var landmark_assets: Dictionary = {}
var prefab_sets: Dictionary = {}
var optimization_profile: Dictionary = {}
var massing_instances: Array[Dictionary] = []
var imported_landmark_nodes: Array[Node2D] = []
var last_render_stats := {
	"total_instances": 0,
	"visible_instances": 0,
	"drawn_instances": 0,
	"landmark_details": 0,
	"imported_landmarks": 0
}

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
const DEFAULT_OPTIMIZATION_PROFILE := {
	"enable_viewport_culling": true,
	"cull_margin_px": 220.0,
	"max_draw_instances": 900,
	"max_lod0_details": 220,
	"max_lod1_details": 420
}

func _ready() -> void:
	district_generator = get_node_or_null(district_generator_path)
	city_grid = get_node_or_null(city_grid_path)
	massing_profiles = _load_massing_profiles()
	landmark_pack = _load_landmark_pack()
	landmark_assets = _load_landmark_assets()
	prefab_sets = _load_prefab_sets()
	optimization_profile = _load_optimization_profile()
	_apply_cel_shader()
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
	var view_rect: Rect2 = _view_cull_rect()
	var use_culling: bool = bool(optimization_profile.get("enable_viewport_culling", true))
	var max_draw_instances: int = max(1, int(optimization_profile.get("max_draw_instances", 900)))
	var max_lod0_details: int = max(0, int(optimization_profile.get("max_lod0_details", 220)))
	var max_lod1_details: int = max(0, int(optimization_profile.get("max_lod1_details", 420)))
	var total_instances: int = massing_instances.size()
	var visible_instances := 0
	var drawn_instances := 0
	var detail_count := 0
	var lod0_detail_count := 0
	var lod1_detail_count := 0
	for inst in massing_instances:
		var bounds_v: Variant = inst.get("bounds", Rect2())
		var bounds: Rect2 = bounds_v if typeof(bounds_v) == TYPE_RECT2 else Rect2()
		if use_culling and not view_rect.intersects(bounds):
			continue
		visible_instances += 1
		if drawn_instances >= max_draw_instances:
			break
		draw_colored_polygon(inst["left"], inst["left_color"])
		draw_colored_polygon(inst["right"], inst["right_color"])
		draw_colored_polygon(inst["front"], inst["front_color"])
		draw_colored_polygon(inst["top"], inst["top_color"])
		draw_polyline(inst["top_outline"], inst["outline_color"], 1.0)
		drawn_instances += 1
		if String(inst.get("landmark_name", "")) != "":
			if bool(inst.get("landmark_has_import", false)):
				continue
			var lod_id: String = _landmark_lod_for_inst(inst)
			if lod_id == "lod0":
				if lod0_detail_count >= max_lod0_details:
					continue
				lod0_detail_count += 1
				detail_count += 1
			elif lod_id == "lod1":
				if lod1_detail_count >= max_lod1_details:
					continue
				lod1_detail_count += 1
				detail_count += 1
			_draw_landmark_detail(inst, lod_id)

	last_render_stats["total_instances"] = total_instances
	last_render_stats["visible_instances"] = visible_instances
	last_render_stats["drawn_instances"] = drawn_instances
	last_render_stats["landmark_details"] = detail_count
	last_render_stats["imported_landmarks"] = imported_landmark_nodes.size()

func _on_seed_records_generated(seed_records: Array, world_seed: int) -> void:
	_rebuild_massing(seed_records, world_seed)

func _rebuild_massing(seed_records: Array, world_seed: int) -> void:
	massing_instances.clear()
	_clear_imported_landmark_nodes()
	if not enabled:
		queue_redraw()
		return

	var cell_size := 64.0
	if city_grid != null:
		cell_size = float(city_grid.get("cell_size"))
	var landmark_assignments: Dictionary = _select_landmark_assignments(seed_records, world_seed)
	var import_requests: Array[Dictionary] = []

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
		var prefab: Dictionary = _select_prefab_config(seed_record, world_seed)
		if not prefab.is_empty():
			profile = _apply_prefab_profile_overrides(profile, prefab)
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
		var prefab_height_mult: float = clamp(float(prefab.get("height_mult", 1.0)), 0.65, 3.5)
		var height_px: float = max(8.0, float(level) * height_per_level * landmark_height_mult * asset_height_mult * prefab_height_mult + jitter)
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
		wall_tint = Color.from_string(String(prefab.get("wall_tint", "")), wall_tint)
		roof_tint = Color.from_string(String(prefab.get("roof_tint", "")), roof_tint)
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
		if not prefab.is_empty():
			outline_color = Color.from_string(String(prefab.get("outline_tint", "")), outline_color)
		if not landmark.is_empty():
			outline_color = Color(0.92, 0.69, 0.33, 0.85)

		massing_instances.append(
			{
				"sort_key": g2.y,
				"cell_key": _cell_key(cell),
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
				"landmark_has_import": false,
				"prefab_id": String(prefab.get("id", "")),
				"archetype": archetype,
				"height_px": height_px,
				"roof_center": (t0 + t1 + t2 + t3) / 4.0,
				"bounds": _polygon_bounds(PackedVector2Array([g0, g1, g2, g3, t0, t1, t2, t3]))
			}
		)
		if not landmark.is_empty() and not asset.is_empty():
			var scene_path: String = String(asset.get("scene_path", ""))
			if scene_path != "":
				import_requests.append(
					{
						"cell_key": _cell_key(cell),
						"scene_path": scene_path,
						"position": (t0 + t1 + t2 + t3) / 4.0,
						"sort_key": g2.y,
						"scene_scale": float(asset.get("scene_scale", 1.0)),
						"offset_x": float(asset.get("scene_offset_x", 0.0)),
						"offset_y": float(asset.get("scene_offset_y", 0.0))
					}
				)

	massing_instances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("sort_key", 0.0)) < float(b.get("sort_key", 0.0))
	)
	_spawn_imported_landmark_scenes(import_requests)
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

func _load_prefab_sets() -> Dictionary:
	if not FileAccess.file_exists(prefab_sets_path):
		return {}
	var fp := FileAccess.open(prefab_sets_path, FileAccess.READ)
	if fp == null:
		return {}
	var parsed: Variant = JSON.parse_string(fp.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return Dictionary(parsed).duplicate(true)

func _load_optimization_profile() -> Dictionary:
	var merged: Dictionary = DEFAULT_OPTIMIZATION_PROFILE.duplicate(true)
	if not FileAccess.file_exists(optimization_profile_path):
		return merged
	var fp := FileAccess.open(optimization_profile_path, FileAccess.READ)
	if fp == null:
		return merged
	var parsed: Variant = JSON.parse_string(fp.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return merged
	var payload: Dictionary = parsed
	var profile_v: Variant = payload.get("profile", payload)
	if typeof(profile_v) != TYPE_DICTIONARY:
		return merged
	var profile: Dictionary = profile_v
	for key in profile.keys():
		merged[key] = profile[key]
	return merged

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

func _apply_prefab_profile_overrides(profile: Dictionary, prefab: Dictionary) -> Dictionary:
	var merged: Dictionary = profile.duplicate(true)
	var overrides_v: Variant = prefab.get("profile_overrides", {})
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

func _select_prefab_config(seed_record: Dictionary, world_seed: int) -> Dictionary:
	if prefab_sets.is_empty():
		return {}
	var district_id: String = String(seed_record.get("district_id", "outer_borough_mix"))
	var district_sets_v: Variant = prefab_sets.get("district_sets", {})
	var district_sets: Dictionary = district_sets_v if typeof(district_sets_v) == TYPE_DICTIONARY else {}
	var set_data_v: Variant = district_sets.get(district_id, {})
	var set_data: Dictionary = set_data_v if typeof(set_data_v) == TYPE_DICTIONARY else {}

	var entries: Array = []
	var entries_v: Variant = set_data.get("entries", [])
	if typeof(entries_v) == TYPE_ARRAY:
		entries = entries_v
	if entries.is_empty():
		var fallback_v: Variant = prefab_sets.get("fallback_set", {})
		if typeof(fallback_v) == TYPE_DICTIONARY:
			var fallback: Dictionary = fallback_v
			var fallback_entries_v: Variant = fallback.get("entries", [])
			if typeof(fallback_entries_v) == TYPE_ARRAY:
				entries = fallback_entries_v
	if entries.is_empty():
		return {}

	var candidates: Array[Dictionary] = []
	var total_weight := 0.0
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		if not _prefab_entry_matches(seed_record, entry):
			continue
		var weight: float = max(0.0, float(entry.get("weight", 0.0)))
		if weight <= 0.0:
			continue
		total_weight += weight
		candidates.append(entry)
	if candidates.is_empty() or total_weight <= 0.0:
		return {}

	var cell: Vector2i = seed_record.get("cell", Vector2i.ZERO)
	var roll_weight: float = _hash01(cell, world_seed, 401) * total_weight
	var accum := 0.0
	for candidate in candidates:
		accum += max(0.0, float(candidate.get("weight", 0.0)))
		if roll_weight <= accum:
			return candidate.duplicate(true)
	return candidates[candidates.size() - 1].duplicate(true)

func _prefab_entry_matches(seed_record: Dictionary, entry: Dictionary) -> bool:
	var level: int = int(seed_record.get("seed_level", 1))
	var style_profile: String = String(seed_record.get("style_profile", "")).to_lower()
	var archetype: String = String(seed_record.get("archetype", "")).to_lower()
	var min_level: int = int(entry.get("min_level", 1))
	if level < min_level:
		return false

	var style_contains_v: Variant = entry.get("style_contains", [])
	if typeof(style_contains_v) == TYPE_ARRAY:
		var style_patterns: Array = style_contains_v
		if not style_patterns.is_empty():
			var style_ok := false
			for pattern_v in style_patterns:
				var pattern: String = String(pattern_v).to_lower()
				if pattern != "" and style_profile.find(pattern) != -1:
					style_ok = true
					break
			if not style_ok:
				return false

	var archetype_contains_v: Variant = entry.get("archetype_contains", [])
	if typeof(archetype_contains_v) == TYPE_ARRAY:
		var archetype_patterns: Array = archetype_contains_v
		if not archetype_patterns.is_empty():
			var archetype_ok := false
			for pattern_v in archetype_patterns:
				var pattern: String = String(pattern_v).to_lower()
				if pattern != "" and archetype.find(pattern) != -1:
					archetype_ok = true
					break
			if not archetype_ok:
				return false
	return true

func _cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]

func _landmark_lod_for_inst(inst: Dictionary) -> String:
	var asset_id: String = String(inst.get("landmark_asset_id", ""))
	if asset_id == "":
		return ""
	if not landmark_assets.has(asset_id):
		return ""
	var asset_v: Variant = landmark_assets.get(asset_id, {})
	if typeof(asset_v) != TYPE_DICTIONARY:
		return ""
	var asset: Dictionary = asset_v
	var lod_rules_v: Variant = asset.get("lod_rules", {})
	var lod_rules: Dictionary = lod_rules_v if typeof(lod_rules_v) == TYPE_DICTIONARY else {}

	var zoom := 1.0
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		zoom = float(cam.zoom.x)
	var lod_id := "lod1"
	if zoom <= float(lod_rules.get("lod0_max_zoom", 0.8)):
		return "lod0"
	elif zoom <= float(lod_rules.get("lod1_max_zoom", 1.45)):
		return "lod1"
	return "lod2"

func _draw_landmark_detail(inst: Dictionary, lod_id: String) -> void:
	if lod_id == "":
		return
	var asset_id: String = String(inst.get("landmark_asset_id", ""))
	if asset_id == "":
		return
	if not landmark_assets.has(asset_id):
		return
	var asset_v: Variant = landmark_assets.get(asset_id, {})
	if typeof(asset_v) != TYPE_DICTIONARY:
		return
	var asset: Dictionary = asset_v
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

func get_render_stats() -> Dictionary:
	return last_render_stats.duplicate(true)

func _clear_imported_landmark_nodes() -> void:
	for node in imported_landmark_nodes:
		if is_instance_valid(node):
			node.queue_free()
	imported_landmark_nodes.clear()

func _spawn_imported_landmark_scenes(requests: Array) -> void:
	if requests.is_empty():
		return
	for request_v in requests:
		if typeof(request_v) != TYPE_DICTIONARY:
			continue
		var request: Dictionary = request_v
		var scene_path: String = String(request.get("scene_path", ""))
		if scene_path == "":
			continue
		var res: Resource = load(scene_path)
		if not (res is PackedScene):
			continue
		var packed: PackedScene = res
		var inst_v: Node = packed.instantiate()
		if not (inst_v is Node2D):
			inst_v.queue_free()
			continue
		var node2d: Node2D = inst_v
		var pos: Vector2 = Vector2(request.get("position", Vector2.ZERO))
		pos.x += float(request.get("offset_x", 0.0))
		pos.y += float(request.get("offset_y", 0.0))
		var scale_mult: float = clamp(float(request.get("scene_scale", 1.0)), 0.1, 4.0)
		node2d.position = pos
		node2d.scale = Vector2.ONE * scale_mult
		node2d.z_index = int(request.get("sort_key", 0.0)) + 200
		add_child(node2d)
		imported_landmark_nodes.append(node2d)
		_mark_instance_imported(String(request.get("cell_key", "")))

func _mark_instance_imported(cell_key: String) -> void:
	if cell_key == "":
		return
	for i in range(massing_instances.size()):
		var item: Dictionary = massing_instances[i]
		var item_cell_key: String = String(item.get("cell_key", ""))
		if item_cell_key != cell_key:
			continue
		item["landmark_has_import"] = true
		massing_instances[i] = item
		return

func _view_cull_rect() -> Rect2:
	var vp_size: Vector2 = get_viewport_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2(Vector2(-100000.0, -100000.0), Vector2(200000.0, 200000.0))
	var zoom: Vector2 = cam.zoom
	var half_world := Vector2(vp_size.x * zoom.x, vp_size.y * zoom.y) * 0.5
	var global_rect := Rect2(cam.global_position - half_world, half_world * 2.0)
	var local_pos := to_local(global_rect.position)
	var local_rect := Rect2(local_pos, global_rect.size)
	var margin: float = max(0.0, float(optimization_profile.get("cull_margin_px", 220.0)))
	return local_rect.grow(margin)

func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var min_x := points[0].x
	var max_x := points[0].x
	var min_y := points[0].y
	var max_y := points[0].y
	for p in points:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_y = min(min_y, p.y)
		max_y = max(max_y, p.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func _apply_cel_shader() -> void:
	if not use_cel_shader:
		material = null
		return
	if cel_shader_path == "":
		material = null
		return
	var shader_res: Resource = load(cel_shader_path)
	if shader_res == null:
		material = null
		return
	if not (shader_res is Shader):
		material = null
		return
	var shader: Shader = shader_res
	var shader_mat: ShaderMaterial = ShaderMaterial.new()
	shader_mat.shader = shader
	shader_mat.set_shader_parameter("shade_steps", cel_shade_steps)
	shader_mat.set_shader_parameter("shade_contrast", cel_shade_contrast)
	shader_mat.set_shader_parameter("band_mix", cel_band_mix)
	material = shader_mat

func _hash01(cell: Vector2i, world_seed: int, salt: int) -> float:
	var h: int = int(hash("%d:%d:%d:%d" % [cell.x, cell.y, world_seed, salt]))
	var mod_val: int = abs(h) % 1000
	return float(mod_val) / 1000.0
