extends Node2D

@export var city_grid_path: NodePath = ^"../CityGrid"
@export var processed_geojson_path := "res://data/processed/buildings_districted.geojson"
@export var fallback_geojson_path := "res://data/raw/sample_buildings.geojson"
@export var district_config_path := "res://tools/pipeline/config/district_profiles.json"
@export var style_profile_path := "res://data/runtime/style_profiles.json"
@export var world_seed := 1998

var city_grid: Node2D
var overlay_visible := true
var overlay_blocks: Array[Dictionary] = []
var style_profiles: Dictionary = {}
var rng := RandomNumberGenerator.new()
var district_focus_points: Dictionary = {}
const DEFAULT_SAVE_PATH := "user://savegame.json"
const SLOT_SAVE_TEMPLATE := "user://savegame_%d.json"

const DISTRICT_COLORS := {
	"midtown_core": Color(0.94, 0.62, 0.20, 0.38),
	"financial_district": Color(0.91, 0.43, 0.29, 0.36),
	"lower_east_side": Color(0.42, 0.64, 0.95, 0.36),
	"harlem": Color(0.27, 0.70, 0.54, 0.36),
	"queens_west": Color(0.62, 0.50, 0.90, 0.36),
	"outer_borough_mix": Color(0.60, 0.62, 0.71, 0.32)
}
const BULLDOZE_ZONE := 4

func _ready() -> void:
	city_grid = get_node_or_null(city_grid_path)
	if city_grid == null:
		push_warning("DistrictGenerator: CityGrid not found at path: %s" % city_grid_path)
		return
	style_profiles = _load_style_profiles()
	regenerate(world_seed, true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		overlay_visible = not overlay_visible
		queue_redraw()

func _draw() -> void:
	if not overlay_visible:
		return

	for block in overlay_blocks:
		draw_rect(block["rect"], block["color"], true)
		draw_rect(block["rect"], Color(0.05, 0.06, 0.1, 0.9), false, 1.0)

func _load_records() -> Array[Dictionary]:
	var processed = _load_geojson(processed_geojson_path)
	if not processed.is_empty():
		return _extract_records(processed, false)

	var fallback = _load_geojson(fallback_geojson_path)
	if fallback.is_empty():
		return []
	return _extract_records(fallback, true)

func _load_geojson(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var fp := FileAccess.open(path, FileAccess.READ)
	if fp == null:
		return {}
	var parsed = JSON.parse_string(fp.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _extract_records(payload: Dictionary, needs_district_lookup: bool) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var districts_cfg := _load_geojson(district_config_path)
	var fallback_id := "outer_borough_mix"
	if districts_cfg.has("fallback_district_id"):
		fallback_id = String(districts_cfg["fallback_district_id"])

	for feature in payload.get("features", []):
		var feat: Dictionary = feature
		var props: Dictionary = feat.get("properties", {})
		var geom: Dictionary = feat.get("geometry", {})
		var centroid: Vector2 = _extract_centroid(props, geom)
		var district_id := String(props.get("district_id", ""))
		var style_profile := String(props.get("style_profile", ""))

		if needs_district_lookup or district_id == "":
			var lookup: Dictionary = _lookup_district(centroid.x, centroid.y, districts_cfg, fallback_id)
			district_id = String(lookup.get("district_id", fallback_id))
			style_profile = String(lookup.get("style_profile", "default_mixed"))

		var height_m := float(props.get("height_m", 12.0))
		records.append(
			{
				"lon": centroid.x,
				"lat": centroid.y,
				"district_id": district_id,
				"style_profile": style_profile,
				"height_m": height_m
			}
		)
	return records

func _extract_centroid(props: Dictionary, geom: Dictionary) -> Vector2:
	if props.has("centroid_lon") and props.has("centroid_lat"):
		return Vector2(float(props["centroid_lon"]), float(props["centroid_lat"]))

	var geometry_type := String(geom.get("type", ""))
	var coords: Array = geom.get("coordinates", [])
	if geometry_type == "Polygon":
		return _polygon_centroid(coords)
	if geometry_type == "MultiPolygon" and coords.size() > 0:
		return _polygon_centroid(coords[0])
	return Vector2.ZERO

func _polygon_centroid(coords) -> Vector2:
	if coords.is_empty():
		return Vector2.ZERO
	var ring: Array = coords[0]
	if ring.is_empty():
		return Vector2.ZERO
	var lon_sum := 0.0
	var lat_sum := 0.0
	var count := 0
	for point in ring:
		var pt: Array = point
		if pt.size() < 2:
			continue
		lon_sum += float(pt[0])
		lat_sum += float(pt[1])
		count += 1
	if count == 0:
		return Vector2.ZERO
	return Vector2(lon_sum / count, lat_sum / count)

func _lookup_district(lon: float, lat: float, districts_cfg: Dictionary, fallback_id: String) -> Dictionary:
	for district_data in districts_cfg.get("districts", []):
		var district: Dictionary = district_data
		var bbox: Array = district.get("bbox_lon_lat", [])
		if bbox.size() != 4:
			continue
		var min_lon := float(bbox[0])
		var min_lat := float(bbox[1])
		var max_lon := float(bbox[2])
		var max_lat := float(bbox[3])
		if lon >= min_lon and lon <= max_lon and lat >= min_lat and lat <= max_lat:
			return {
				"district_id": String(district.get("district_id", fallback_id)),
				"style_profile": String(district.get("style_profile", "default_mixed"))
			}
	return {"district_id": fallback_id, "style_profile": "default_mixed"}

func _map_records_to_grid(records: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var columns_v: Variant = city_grid.get("columns")
	var rows_v: Variant = city_grid.get("rows")
	if typeof(columns_v) != TYPE_INT:
		return result
	if typeof(rows_v) != TYPE_INT:
		return result
	var columns: int = columns_v
	var rows: int = rows_v
	if columns <= 0 or rows <= 0:
		return result

	var min_lon := INF
	var max_lon := -INF
	var min_lat := INF
	var max_lat := -INF
	for rec in records:
		var lon := float(rec["lon"])
		var lat := float(rec["lat"])
		min_lon = min(min_lon, lon)
		max_lon = max(max_lon, lon)
		min_lat = min(min_lat, lat)
		max_lat = max(max_lat, lat)

	if is_equal_approx(min_lon, max_lon):
		max_lon += 0.0001
	if is_equal_approx(min_lat, max_lat):
		max_lat += 0.0001

	for rec in records:
		var lon_t := inverse_lerp(min_lon, max_lon, float(rec["lon"]))
		var lat_t := inverse_lerp(min_lat, max_lat, float(rec["lat"]))
		var cell_x := int(round(lon_t * float(columns - 1)))
		var cell_y := int(round((1.0 - lat_t) * float(rows - 1)))
		var district_id: String = String(rec["district_id"])
		var style_profile: String = String(rec["style_profile"])
		var style_cfg: Dictionary = _style_cfg(style_profile)
		var level_bias: float = float(style_cfg.get("seed_level_bias", 0.0))
		var seed_level := clampi(int(round(float(rec["height_m"]) / 35.0 + level_bias)), 1, 3)

		result.append(
			{
				"cell": Vector2i(cell_x, cell_y),
				"district_id": district_id,
				"style_profile": style_profile,
				"seed_level": seed_level
			}
		)
	return _expand_seed_clusters(result, columns, rows)

func _expand_seed_clusters(base_records: Array[Dictionary], columns: int, rows: int) -> Array[Dictionary]:
	var expanded: Array[Dictionary] = []
	var occupied := {}
	for rec in base_records:
		var cell: Vector2i = rec.get("cell", Vector2i(-1, -1))
		expanded.append(rec)
		occupied[_key(cell)] = true

	for rec in base_records:
		var style_profile: String = String(rec.get("style_profile", "default_mixed"))
		var style_cfg: Dictionary = _style_cfg(style_profile)
		var spread_radius: int = int(style_cfg.get("spread_radius", 1))
		var infill_chance: float = float(style_cfg.get("infill_chance", 0.2))
		var base_cell: Vector2i = rec.get("cell", Vector2i(-1, -1))

		for y in range(base_cell.y - spread_radius, base_cell.y + spread_radius + 1):
			for x in range(base_cell.x - spread_radius, base_cell.x + spread_radius + 1):
				var cell := Vector2i(x, y)
				if cell.x < 0 or cell.y < 0 or cell.x >= columns or cell.y >= rows:
					continue
				var k: String = _key(cell)
				if occupied.has(k):
					continue
				if rng.randf() > infill_chance:
					continue

				var growth_level := clampi(int(rec.get("seed_level", 1)) - 1, 1, 3)
				var seeded := {
					"cell": cell,
					"district_id": String(rec.get("district_id", "outer_borough_mix")),
					"style_profile": style_profile,
					"seed_level": growth_level
				}
				expanded.append(seeded)
				occupied[k] = true

	return expanded

func _style_cfg(style_profile: String) -> Dictionary:
	if style_profiles.has(style_profile):
		return style_profiles[style_profile]
	if style_profiles.has("default_mixed"):
		return style_profiles["default_mixed"]
	return {}

func _load_style_profiles() -> Dictionary:
	var payload: Dictionary = _load_geojson(style_profile_path)
	if payload.is_empty():
		return {}
	var profiles: Dictionary = payload.get("profiles", {})
	return profiles

func _key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]

func _build_overlay(seed_records: Array[Dictionary]) -> void:
	overlay_blocks.clear()
	district_focus_points.clear()
	var cell_size := float(city_grid.get("cell_size"))
	var accum := {}

	for rec in seed_records:
		var cell: Vector2i = rec["cell"]
		var district_id: String = String(rec.get("district_id", "outer_borough_mix"))
		var color: Color = DISTRICT_COLORS.get(district_id, DISTRICT_COLORS["outer_borough_mix"])
		var rect := Rect2(Vector2(cell.x, cell.y) * cell_size, Vector2.ONE * cell_size)
		overlay_blocks.append({"rect": rect, "color": color})

		var center_local := Vector2(cell.x + 0.5, cell.y + 0.5) * cell_size
		if not accum.has(district_id):
			accum[district_id] = {"sum": Vector2.ZERO, "count": 0}
		var bucket: Dictionary = accum[district_id]
		bucket["sum"] = Vector2(bucket["sum"]) + center_local
		bucket["count"] = int(bucket["count"]) + 1
		accum[district_id] = bucket

	for district_key in accum.keys():
		var district_id: String = String(district_key)
		var bucket: Dictionary = accum[district_id]
		var count: int = int(bucket.get("count", 0))
		if count <= 0:
			continue
		var avg_local: Vector2 = Vector2(bucket["sum"]) / float(count)
		district_focus_points[district_id] = avg_local + position

func get_world_seed() -> int:
	return int(world_seed)

func has_district_focus_point(district_id: String) -> bool:
	return district_focus_points.has(district_id)

func get_district_focus_point(district_id: String) -> Vector2:
	if district_focus_points.has(district_id):
		return district_focus_points[district_id]
	return position

func regenerate(new_seed: int = -1, initial_load: bool = false) -> void:
	if new_seed >= 0:
		world_seed = new_seed
	rng.seed = int(world_seed)

	if not initial_load and city_grid.has_method("reset_grid"):
		city_grid.call("reset_grid")

	var records: Array[Dictionary] = _load_records()
	if records.is_empty():
		push_warning("DistrictGenerator: no building records loaded.")
		return

	var seeded: Array[Dictionary] = _map_records_to_grid(records)
	if seeded.is_empty():
		push_warning("DistrictGenerator: no mapped building records.")
		return

	if city_grid.has_method("apply_district_seed"):
		city_grid.call("apply_district_seed", seeded)
	_build_overlay(seeded)
	queue_redraw()

func save_to_file(path: String = DEFAULT_SAVE_PATH) -> bool:
	if city_grid == null:
		return false
	if not city_grid.has_method("export_state"):
		return false

	var city_state: Dictionary = city_grid.call("export_state")
	var payload := {
		"version": 1,
		"world_seed": int(world_seed),
		"city_state": city_state
	}

	var fp := FileAccess.open(path, FileAccess.WRITE)
	if fp == null:
		return false
	fp.store_string(JSON.stringify(payload, "  "))
	return true

func save_to_slot(slot: int) -> bool:
	if slot < 1 or slot > 3:
		return false
	return save_to_file(SLOT_SAVE_TEMPLATE % slot)

func load_from_file(path: String = DEFAULT_SAVE_PATH) -> bool:
	if city_grid == null:
		return false
	if not city_grid.has_method("import_state"):
		return false
	if not FileAccess.file_exists(path):
		return false

	var fp := FileAccess.open(path, FileAccess.READ)
	if fp == null:
		return false
	var parsed: Variant = JSON.parse_string(fp.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var payload: Dictionary = parsed
	var city_state_v: Variant = payload.get("city_state", {})
	if typeof(city_state_v) != TYPE_DICTIONARY:
		return false

	world_seed = int(payload.get("world_seed", world_seed))
	rng.seed = int(world_seed)
	var ok: bool = city_grid.call("import_state", city_state_v)
	if not ok:
		return false
	_rebuild_overlay_from_city_grid()
	queue_redraw()
	return true

func load_from_slot(slot: int) -> bool:
	if slot < 1 or slot > 3:
		return false
	return load_from_file(SLOT_SAVE_TEMPLATE % slot)

func has_slot(slot: int) -> bool:
	if slot < 1 or slot > 3:
		return false
	return FileAccess.file_exists(SLOT_SAVE_TEMPLATE % slot)

func _rebuild_overlay_from_city_grid() -> void:
	overlay_blocks.clear()
	district_focus_points.clear()
	if city_grid == null:
		return

	var columns: int = city_grid.get("columns")
	var rows: int = city_grid.get("rows")
	var cell_size: float = city_grid.get("cell_size")
	var zones: Array = city_grid.get("zone_by_index")
	var districts: Array = city_grid.get("district_id_by_index")
	var accum := {}

	for y in range(rows):
		for x in range(columns):
			var i := y * columns + x
			var zone := int(zones[i])
			if zone == BULLDOZE_ZONE:
				continue
			var district_id: String = String(districts[i])
			var color: Color = DISTRICT_COLORS.get(district_id, DISTRICT_COLORS["outer_borough_mix"])
			var rect := Rect2(Vector2(x, y) * cell_size, Vector2.ONE * cell_size)
			overlay_blocks.append({"rect": rect, "color": color})

			var center_local := Vector2(x + 0.5, y + 0.5) * cell_size
			if not accum.has(district_id):
				accum[district_id] = {"sum": Vector2.ZERO, "count": 0}
			var bucket: Dictionary = accum[district_id]
			bucket["sum"] = Vector2(bucket["sum"]) + center_local
			bucket["count"] = int(bucket["count"]) + 1
			accum[district_id] = bucket

	for district_key in accum.keys():
		var district_id: String = String(district_key)
		var bucket: Dictionary = accum[district_id]
		var count: int = int(bucket.get("count", 0))
		if count <= 0:
			continue
		var avg_local: Vector2 = Vector2(bucket["sum"]) / float(count)
		district_focus_points[district_id] = avg_local + position
