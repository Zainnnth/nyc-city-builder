extends Node

@export var city_grid_path: NodePath = ^"../CityGrid"

const SAMPLE_HZ := 44100.0
const BUFFER_SECONDS := 0.2
const STREAM_GAIN_DB := -20.0
const PULSE_GAIN_DB := -26.0

const DISTRICT_BASE_FREQ := {
	"midtown_core": 118.0,
	"financial_district": 98.0,
	"lower_east_side": 132.0,
	"harlem": 112.0,
	"queens_west": 104.0,
	"outer_borough_mix": 108.0
}

const DISTRICT_PAN := {
	"midtown_core": 0.10,
	"financial_district": -0.14,
	"lower_east_side": 0.22,
	"harlem": -0.18,
	"queens_west": 0.26,
	"outer_borough_mix": 0.0
}

var city_grid: Node
var drone_player: AudioStreamPlayer
var pulse_player: AudioStreamPlayer
var drone_playback: AudioStreamGeneratorPlayback
var pulse_playback: AudioStreamGeneratorPlayback

var phase := 0.0
var sub_phase := 0.0
var pulse_phase := 0.0
var pulse_lfo := 0.0

var target_base_freq := 110.0
var current_base_freq := 110.0
var target_pulse_freq := 2.1
var current_pulse_freq := 2.1
var target_pan := 0.0
var current_pan := 0.0
var target_intensity := 0.22
var current_intensity := 0.22
var target_brightness := 0.3
var current_brightness := 0.3

func _ready() -> void:
	city_grid = get_node_or_null(city_grid_path)
	_init_audio_players()

func _process(delta: float) -> void:
	_update_targets()
	current_base_freq = lerpf(current_base_freq, target_base_freq, clamp(delta * 1.8, 0.0, 1.0))
	current_pulse_freq = lerpf(current_pulse_freq, target_pulse_freq, clamp(delta * 1.6, 0.0, 1.0))
	current_pan = lerpf(current_pan, target_pan, clamp(delta * 1.2, 0.0, 1.0))
	current_intensity = lerpf(current_intensity, target_intensity, clamp(delta * 1.9, 0.0, 1.0))
	current_brightness = lerpf(current_brightness, target_brightness, clamp(delta * 1.7, 0.0, 1.0))
	_fill_buffers()

func _init_audio_players() -> void:
	var drone_stream := AudioStreamGenerator.new()
	drone_stream.mix_rate = SAMPLE_HZ
	drone_stream.buffer_length = BUFFER_SECONDS
	drone_player = AudioStreamPlayer.new()
	drone_player.stream = drone_stream
	drone_player.volume_db = STREAM_GAIN_DB
	add_child(drone_player)
	drone_player.play()
	drone_playback = drone_player.get_stream_playback()

	var pulse_stream := AudioStreamGenerator.new()
	pulse_stream.mix_rate = SAMPLE_HZ
	pulse_stream.buffer_length = BUFFER_SECONDS
	pulse_player = AudioStreamPlayer.new()
	pulse_player.stream = pulse_stream
	pulse_player.volume_db = PULSE_GAIN_DB
	add_child(pulse_player)
	pulse_player.play()
	pulse_playback = pulse_player.get_stream_playback()

func _update_targets() -> void:
	if city_grid == null:
		target_base_freq = 108.0
		target_pulse_freq = 1.8
		target_pan = 0.0
		target_intensity = 0.14
		target_brightness = 0.22
		return

	var district_id := "outer_borough_mix"
	var demand_index := 50.0
	var service_stress := 0.0
	var traffic_stress := 0.0

	if city_grid.has_method("get_district_demand_snapshot"):
		var snapshot_v: Variant = city_grid.call("get_district_demand_snapshot")
		if typeof(snapshot_v) == TYPE_ARRAY:
			var snapshot: Array = snapshot_v
			if not snapshot.is_empty() and typeof(snapshot[0]) == TYPE_DICTIONARY:
				var top: Dictionary = snapshot[0]
				district_id = String(top.get("district_id", district_id))
				demand_index = float(top.get("demand_index", demand_index))
				service_stress = float(top.get("service_stress", 0.0))
				traffic_stress = float(top.get("traffic_stress", 0.0))

	var event_risk := 0.0
	if city_grid.has_method("get_event_snapshot"):
		var event_v: Variant = city_grid.call("get_event_snapshot")
		if typeof(event_v) == TYPE_DICTIONARY:
			var event_data: Dictionary = event_v
			var event_id: String = String(event_data.get("active_event_id", ""))
			if event_id == "blackout":
				event_risk = 0.46
			elif event_id == "strike":
				event_risk = 0.3
			elif event_id == "heatwave":
				event_risk = 0.22

	var pressure := 0.0
	if city_grid.has_method("get_economy_snapshot"):
		var econ_v: Variant = city_grid.call("get_economy_snapshot")
		if typeof(econ_v) == TYPE_DICTIONARY:
			var econ: Dictionary = econ_v
			var housing_p: float = float(econ.get("housing_pressure", 1.0))
			var job_p: float = float(econ.get("job_pressure", 1.0))
			pressure = clamp(abs(housing_p - 1.0) + abs(job_p - 1.0), 0.0, 1.2)

	var district_freq: float = float(DISTRICT_BASE_FREQ.get(district_id, 108.0))
	var mood_tension: float = clamp((service_stress + traffic_stress) * 0.9 + event_risk + pressure * 0.5, 0.0, 1.35)
	var demand_drive: float = clamp((demand_index - 50.0) / 50.0, -1.0, 1.0)

	target_base_freq = district_freq + demand_drive * 18.0 + mood_tension * 9.0
	target_pulse_freq = clamp(1.2 + mood_tension * 1.9 + max(0.0, demand_drive) * 0.6, 0.8, 4.0)
	target_pan = float(DISTRICT_PAN.get(district_id, 0.0))
	target_intensity = clamp(0.16 + mood_tension * 0.22, 0.08, 0.42)
	target_brightness = clamp(0.24 + max(0.0, demand_drive) * 0.35 - service_stress * 0.12, 0.16, 0.7)

func _fill_buffers() -> void:
	if drone_playback == null or pulse_playback == null:
		return
	var drone_frames: int = drone_playback.get_frames_available()
	var pulse_frames: int = pulse_playback.get_frames_available()
	var frames: int = mini(drone_frames, pulse_frames)
	if frames <= 0:
		return
	for i in range(frames):
		var drone_frame: Vector2 = _next_drone_frame()
		var pulse_frame: Vector2 = _next_pulse_frame()
		drone_playback.push_frame(drone_frame)
		pulse_playback.push_frame(pulse_frame)

func _next_drone_frame() -> Vector2:
	phase = wrapf(phase + TAU * current_base_freq / SAMPLE_HZ, 0.0, TAU)
	sub_phase = wrapf(sub_phase + TAU * (current_base_freq * 0.5) / SAMPLE_HZ, 0.0, TAU)
	pulse_lfo = wrapf(pulse_lfo + TAU * 0.08 / SAMPLE_HZ, 0.0, TAU)

	var s0: float = sin(phase)
	var s1: float = sin(sub_phase) * 0.45
	var shimmer: float = sin(phase * 0.5 + pulse_lfo) * current_brightness * 0.25
	var mono: float = (s0 + s1 + shimmer) * current_intensity
	var left: float = mono * (1.0 - max(0.0, current_pan * 0.8))
	var right: float = mono * (1.0 + min(0.0, current_pan * 0.8))
	return Vector2(clamp(left, -0.95, 0.95), clamp(right, -0.95, 0.95))

func _next_pulse_frame() -> Vector2:
	pulse_phase = wrapf(pulse_phase + TAU * current_pulse_freq / SAMPLE_HZ, 0.0, TAU)
	var gate: float = max(0.0, sin(pulse_phase))
	var click: float = pow(gate, 3.0) * (0.11 + current_intensity * 0.14)
	var left: float = click * (1.0 + max(0.0, current_pan * 0.7))
	var right: float = click * (1.0 - min(0.0, current_pan * 0.7))
	return Vector2(clamp(left, -0.9, 0.9), clamp(right, -0.9, 0.9))
