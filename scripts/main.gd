extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var seed_panel: CanvasLayer = $SeedPanel

const CAMERA_SPEED := 700.0
const ZOOM_MIN := 0.55
const ZOOM_MAX := 2.2
const ZOOM_STEP := 0.1

func _ready() -> void:
	if seed_panel.has_signal("district_focus_requested"):
		seed_panel.connect("district_focus_requested", _on_district_focus_requested)

func _process(delta: float) -> void:
	var direction := Vector2.ZERO

	if Input.is_action_pressed("ui_left"):
		direction.x -= 1.0
	if Input.is_action_pressed("ui_right"):
		direction.x += 1.0
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1.0
	if Input.is_action_pressed("ui_down"):
		direction.y += 1.0

	if direction != Vector2.ZERO:
		camera.position += direction.normalized() * CAMERA_SPEED * delta

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(-ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(ZOOM_STEP)

func _apply_zoom(delta: float) -> void:
	var new_zoom: float = clamp(camera.zoom.x + delta, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(new_zoom, new_zoom)

func _on_district_focus_requested(target_pos: Vector2) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "position", target_pos, 0.45)
	tween.parallel().tween_property(camera, "zoom", Vector2(0.9, 0.9), 0.45)
