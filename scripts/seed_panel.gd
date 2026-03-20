extends CanvasLayer

@export var district_generator_path: NodePath = ^"../DistrictGenerator"

@onready var input_seed: LineEdit = $Panel/VBox/SeedRow/SeedInput
@onready var apply_button: Button = $Panel/VBox/Controls/ApplySeedButton
@onready var random_button: Button = $Panel/VBox/Controls/RandomSeedButton
@onready var status_label: Label = $Panel/VBox/StatusLabel

var district_generator: Node2D
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	district_generator = get_node_or_null(district_generator_path)
	if district_generator == null:
		status_label.text = "DistrictGenerator not found."
		apply_button.disabled = true
		random_button.disabled = true
		return

	input_seed.text = str(district_generator.call("get_world_seed"))
	status_label.text = "Ready."
	apply_button.pressed.connect(_on_apply_seed)
	random_button.pressed.connect(_on_random_seed)
	input_seed.text_submitted.connect(_on_text_submitted)

func _on_text_submitted(_value: String) -> void:
	_on_apply_seed()

func _on_apply_seed() -> void:
	var text: String = input_seed.text.strip_edges()
	if text == "":
		status_label.text = "Enter a seed."
		return

	if not text.is_valid_int():
		status_label.text = "Seed must be an integer."
		return

	var seed_value: int = int(text)
	district_generator.call("regenerate", seed_value, false)
	status_label.text = "Regenerated with seed %d." % seed_value

func _on_random_seed() -> void:
	var seed_value: int = rng.randi_range(1000, 9999999)
	input_seed.text = str(seed_value)
	district_generator.call("regenerate", seed_value, false)
	status_label.text = "Random seed %d applied." % seed_value
