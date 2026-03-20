extends Node2D

@export var columns := 24
@export var rows := 16
@export var cell_size := 64.0

var lot_colors: Array[Color] = []

const GRID_LINE_COLOR := Color(0.27, 0.31, 0.39, 0.85)
const BORDER_COLOR := Color(0.9, 0.52, 0.19, 0.9)
const BACKDROP_COLOR := Color(0.08, 0.09, 0.15, 0.98)

var zone_palette := [
	Color(0.26, 0.38, 0.70, 0.55), # residential
	Color(0.73, 0.57, 0.24, 0.55), # commercial
	Color(0.41, 0.32, 0.46, 0.55), # mixed use
	Color(0.19, 0.50, 0.43, 0.55)  # public / park
]

func _ready() -> void:
	_seed_lots()
	queue_redraw()

func _draw() -> void:
	var map_size := Vector2(columns * cell_size, rows * cell_size)
	draw_rect(Rect2(Vector2.ZERO, map_size), BACKDROP_COLOR, true)

	var i := 0
	for y in rows:
		for x in columns:
			var rect := Rect2(Vector2(x, y) * cell_size, Vector2.ONE * cell_size)
			draw_rect(rect, lot_colors[i], true)
			draw_rect(rect, GRID_LINE_COLOR, false, 1.0)
			i += 1

	draw_rect(Rect2(Vector2.ZERO, map_size), BORDER_COLOR, false, 3.0)
	_draw_ui_hint(map_size)

func _draw_ui_hint(map_size: Vector2) -> void:
	var text := "Neon Boroughs Prototype   |   Arrow Keys: Pan   |   Mouse Wheel: Zoom"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(16, map_size.y + 42),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		map_size.x - 32,
		22,
		Color(0.83, 0.86, 0.93, 0.92)
	)

func _seed_lots() -> void:
	lot_colors.clear()
	randomize()

	for i in columns * rows:
		var color: Color = zone_palette[randi() % zone_palette.size()]
		lot_colors.append(color)
