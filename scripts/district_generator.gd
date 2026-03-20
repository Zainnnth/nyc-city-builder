extends Node2D

@export var city_grid_path: NodePath = ^"../CityGrid"
@export var processed_geojson_path := "res://data/processed/buildings_districted.geojson"
@export var fallback_geojson_path := "res://data/raw/sample_buildings.geojson"
@export var district_config_path := "res://tools/pipeline/config/district_profiles.json"

var city_grid: Node2D
var overlay_visible := true
var overlay_blocks: Array[Dictionary] = []

const DISTRICT_COLORS := {
	"midtown_core": Color(0.94, 0.62, 0.20, 0.38),
	"financial_district": Color(0.91, 0.43, 0.29, 0.36),
	"lower_east_side": Color(0.42, 0.64, 0.95, 0.36),
	"harlem": Color(0.27, 0.70, 0.54, 0.36),
	"queens_west": Color(0.62, 0.50, 0.90, 0.36),
	"outer_borough_mix": Color(0.60, 0.62, 0.71, 0.32)
}

func _ready() -> void:
	city_grid = get_node_or_null(city_grid_path)
	if city_grid == null:
		push_warning("DistrictGenerator: CityGrid not found at path: %s" % city_grid_path)
		return

	var records := _load_records()
	if records.is_empty():
		push_warning("DistrictGenerator: no building records loaded.")
		return

	var seeded := _map_records_to_grid(records)
	if seeded.is_empty():
		push_warning("DistrictGenerator: no mapped building records.")
		return

	if city_grid.has_method("apply_district_seed"):
		city_grid.call("apply_district_seed", seeded)
	_build_overlay(seeded)
	queue_redraw()

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
		var props := feature.get("properties", {})
		var geom := feature.get("geometry", {})
		var centroid := _extract_centroid(props, geom)
		var district_id := String(props.get("district_id", ""))
		var style_profile := String(props.get("style_profile", ""))

		if needs_district_lookup or district_id == "":
			var lookup := _lookup_district(centroid.x, centroid.y, districts_cfg, fallback_id)
			district_id = lookup["district_id"]
			style_profile = lookup["style_profile"]

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
	var coords = geom.get("coordinates", [])
	if geometry_type == "Polygon":
		return _polygon_centroid(coords)
	if geometry_type == "MultiPolygon" and coords.size() > 0:
		return _polygon_centroid(coords[0])
	return Vector2.ZERO

func _polygon_centroid(coords) -> Vector2:
	if coords.is_empty():
		return Vector2.ZERO
	var ring = coords[0]
	if ring.is_empty():
		return Vector2.ZERO
	var lon_sum := 0.0
	var lat_sum := 0.0
	var count := 0
	for pt in ring:
		if pt.size() < 2:
			continue
		lon_sum += float(pt[0])
		lat_sum += float(pt[1])
		count += 1
	if count == 0:
		return Vector2.ZERO
	return Vector2(lon_sum / count, lat_sum / count)

func _lookup_district(lon: float, lat: float, districts_cfg: Dictionary, fallback_id: String) -> Dictionary:
	for district in districts_cfg.get("districts", []):
		var bbox = district.get("bbox_lon_lat", [])
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
	var columns := int(city_grid.get("columns"))
	var rows := int(city_grid.get("rows"))
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
		var seed_level := clampi(int(round(float(rec["height_m"]) / 35.0)), 1, 3)

		result.append(
			{
				"cell": Vector2i(cell_x, cell_y),
				"district_id": String(rec["district_id"]),
				"style_profile": String(rec["style_profile"]),
				"seed_level": seed_level
			}
		)
	return result

func _build_overlay(seed_records: Array[Dictionary]) -> void:
	overlay_blocks.clear()
	var cell_size := float(city_grid.get("cell_size"))

	for rec in seed_records:
		var cell: Vector2i = rec["cell"]
		var district_id := String(rec.get("district_id", "outer_borough_mix"))
		var color: Color = DISTRICT_COLORS.get(district_id, DISTRICT_COLORS["outer_borough_mix"])
		var rect := Rect2(Vector2(cell.x, cell.y) * cell_size, Vector2.ONE * cell_size)
		overlay_blocks.append({"rect": rect, "color": color})
