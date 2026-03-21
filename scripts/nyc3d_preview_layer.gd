extends Node2D

@export var mesh_manifest_path := "res://data/processed/nyc3d_district_mesh_manifest.json"
@export var enabled := true
@export var overlay_alpha := 0.78
@export var toggle_key := KEY_H

var viewport_3d: SubViewport
var world_root: Node3D
var camera_3d: Camera3D
var overlay_layer: CanvasLayer
var overlay_rect: TextureRect

func _ready() -> void:
	if not enabled:
		return
	_setup_overlay()
	_setup_3d_world()
	_load_manifest_meshes()
	_fit_camera_to_content()
	_sync_overlay_rect()

func _process(_delta: float) -> void:
	if not enabled:
		return
	_sync_overlay_rect()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == toggle_key:
		overlay_layer.visible = not overlay_layer.visible

func _setup_overlay() -> void:
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 0
	add_child(overlay_layer)

	overlay_rect = TextureRect.new()
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay_rect.stretch_mode = TextureRect.STRETCH_SCALE
	overlay_rect.modulate = Color(1.0, 1.0, 1.0, clamp(overlay_alpha, 0.0, 1.0))
	overlay_layer.add_child(overlay_rect)

func _setup_3d_world() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.disable_3d = false
	viewport_3d.transparent_bg = true
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	add_child(viewport_3d)
	overlay_rect.texture = viewport_3d.get_texture()

	world_root = Node3D.new()
	viewport_3d.add_child(world_root)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.08, 0.12, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.68, 0.72)
	environment.ambient_light_energy = 0.9
	env.environment = environment
	world_root.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-55.0, 28.0, 0.0)
	world_root.add_child(sun)

	camera_3d = Camera3D.new()
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.rotation_degrees = Vector3(-48.0, 38.0, 0.0)
	camera_3d.current = true
	world_root.add_child(camera_3d)

func _sync_overlay_rect() -> void:
	if overlay_rect == null or viewport_3d == null:
		return
	var size: Vector2 = get_viewport_rect().size
	var vsize := Vector2i(max(1, int(size.x)), max(1, int(size.y)))
	if viewport_3d.size != vsize:
		viewport_3d.size = vsize
	overlay_rect.position = Vector2.ZERO
	overlay_rect.size = size

func _load_manifest_meshes() -> void:
	if not FileAccess.file_exists(mesh_manifest_path):
		return
	var fp := FileAccess.open(mesh_manifest_path, FileAccess.READ)
	if fp == null:
		return
	var parsed_v: Variant = JSON.parse_string(fp.get_as_text())
	if typeof(parsed_v) != TYPE_DICTIONARY:
		return
	var parsed: Dictionary = parsed_v
	var entries_v: Variant = parsed.get("entries", [])
	if typeof(entries_v) != TYPE_ARRAY:
		return
	var entries: Array = entries_v
	for i in range(entries.size()):
		var entry_v: Variant = entries[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var glb_rel: String = String(entry.get("glb_path", "")).strip_edges()
		if glb_rel == "":
			continue
		var glb_res: String = glb_rel
		if not glb_res.begins_with("res://"):
			glb_res = "res://" + glb_res
		if not FileAccess.file_exists(glb_res):
			continue
		var inst: Node = _instantiate_gltf_scene(glb_res)
		if not (inst is Node3D):
			if inst != null:
				inst.queue_free()
			continue
		var root3d: Node3D = inst
		_apply_entry_tint(root3d, entry)
		world_root.add_child(root3d)
		_normalize_chunk_transform(root3d, i)

func _instantiate_gltf_scene(path: String) -> Node:
	var ext: String = path.get_extension().to_lower()
	if ext != "glb" and ext != "gltf":
		var packed_v: Resource = load(path)
		if packed_v is PackedScene:
			var packed: PackedScene = packed_v
			return packed.instantiate()
	# Fallback for raw .glb paths without editor import metadata.
	if not ClassDB.class_exists("GLTFDocument") or not ClassDB.class_exists("GLTFState"):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err: int = doc.append_from_file(path, state)
	if err != OK:
		return null
	return doc.generate_scene(state)

func _apply_entry_tint(root: Node3D, entry: Dictionary) -> void:
	var art_v: Variant = entry.get("art_pass", {})
	var art: Dictionary = art_v if typeof(art_v) == TYPE_DICTIONARY else {}
	var tint: Color = Color.from_string(String(art.get("accent_color", "#b7c4d4")), Color(0.72, 0.76, 0.82))
	_apply_tint_recursive(root, tint)

func _apply_tint_recursive(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.roughness = 0.85
		mat.metallic = 0.02
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mesh_node.material_override = mat
	for child in node.get_children():
		_apply_tint_recursive(child, tint)

func _fit_camera_to_content() -> void:
	if world_root == null or camera_3d == null:
		return
	var has_bounds := false
	var min_v := Vector3.INF
	var max_v := -Vector3.INF
	for child in world_root.get_children():
		if not (child is Node3D):
			continue
		var pair: Array = _bounds_for_node(child)
		if pair.is_empty():
			continue
		var aabb_min: Vector3 = pair[0]
		var aabb_max: Vector3 = pair[1]
		if not has_bounds:
			min_v = aabb_min
			max_v = aabb_max
			has_bounds = true
		else:
			min_v = min_v.min(aabb_min)
			max_v = max_v.max(aabb_max)
	if not has_bounds:
		return
	var center: Vector3 = (min_v + max_v) * 0.5
	var size: Vector3 = max_v - min_v
	camera_3d.position = center + Vector3(0.0, max(size.y * 1.4, 650.0), max(size.z * 0.8, 650.0))
	camera_3d.look_at(center, Vector3.UP)
	camera_3d.size = max(size.x, size.z) * 0.58

func _normalize_chunk_transform(root: Node3D, idx: int) -> void:
	var pair: Array = _bounds_for_node(root)
	if pair.is_empty():
		return
	var min_v: Vector3 = pair[0]
	var max_v: Vector3 = pair[1]
	var center: Vector3 = (min_v + max_v) * 0.5
	var size: Vector3 = max_v - min_v
	var planar: float = max(size.x, size.z)
	if planar <= 0.001:
		planar = 1.0
	var target_planar := 620.0
	var scale_mult: float = clamp(target_planar / planar, 0.0001, 50.0)
	root.scale = Vector3.ONE * scale_mult

	var cols := 3
	var col: int = idx % cols
	var row: int = idx / cols
	var spacing := 760.0
	var offset := Vector3((float(col) - 1.0) * spacing, 0.0, float(row) * spacing)
	root.position = -center * scale_mult + offset

func _bounds_for_node(root: Node) -> Array:
	var has := false
	var min_v := Vector3.INF
	var max_v := -Vector3.INF
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node
			if mesh_node.mesh != null:
				var local_aabb: AABB = mesh_node.mesh.get_aabb()
				var xf: Transform3D = mesh_node.global_transform
				for corner in _aabb_corners(local_aabb):
					var world_v: Vector3 = xf * corner
					if not has:
						min_v = world_v
						max_v = world_v
						has = true
					else:
						min_v = min_v.min(world_v)
						max_v = max_v.max(world_v)
		for child in node.get_children():
			stack.append(child)
	if not has:
		return []
	return [min_v, max_v]

func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p: Vector3 = aabb.position
	var s: Vector3 = aabb.size
	return [
		p,
		p + Vector3(s.x, 0.0, 0.0),
		p + Vector3(0.0, s.y, 0.0),
		p + Vector3(0.0, 0.0, s.z),
		p + Vector3(s.x, s.y, 0.0),
		p + Vector3(s.x, 0.0, s.z),
		p + Vector3(0.0, s.y, s.z),
		p + Vector3(s.x, s.y, s.z)
	]
