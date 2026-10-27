extends Node
## Persistent user settings plus the garage / track selection state.
##
## Everything is written to user://settings.cfg so it survives app restarts on
## Android. Values are clamped on load so a hand-edited or corrupted file can
## never push the game into an invalid state.

const PATH := "user://settings.cfg"

signal changed(section: String, key: String)

const QUALITY_PRESETS := {
	"low": {
		"shadow_size": 1024,
		"shadows_enabled": false,
		"smoke_amount": 0.35,
		"skid_marks": false,
		"fog": false,
		"prop_density": 0.35,
	},
	"medium": {
		"shadow_size": 2048,
		"shadows_enabled": true,
		"smoke_amount": 0.7,
		"skid_marks": true,
		"fog": false,
		"prop_density": 0.7,
	},
	"high": {
		"shadow_size": 4096,
		"shadows_enabled": true,
		"smoke_amount": 1.0,
		"skid_marks": true,
		"fog": true,
		"prop_density": 1.0,
	},
}

const CARS := [
	{
		"id": "car_speedster", "name": "Speedster", "model": "res://assets/models/car_speedster.glb",
		"speed": 0.86, "accel": 0.84, "handling": 0.72, "braking": 0.70,
		"colour": Color(0.88, 0.13, 0.15), "unlocked": true,
	},
	{
		"id": "car_phantom", "name": "Phantom", "model": "res://assets/models/car_phantom.glb",
		"speed": 0.94, "accel": 0.70, "handling": 0.66, "braking": 0.74,
		"colour": Color(0.16, 0.20, 0.58), "unlocked": true,
	},
	{
		"id": "car_viper", "name": "Viper", "model": "res://assets/models/car_viper.glb",
		"speed": 0.74, "accel": 0.90, "handling": 0.92, "braking": 0.82,
		"colour": Color(0.10, 0.62, 0.26), "unlocked": true,
	},
	{
		"id": "car_inferno", "name": "Inferno", "model": "res://assets/models/car_inferno.glb",
		"speed": 0.90, "accel": 0.88, "handling": 0.74, "braking": 0.78,
		"colour": Color(0.96, 0.47, 0.07), "unlocked": true,
	},
	{
		"id": "car_spectre", "name": "Spectre", "model": "res://assets/models/car_spectre.glb",
		"speed": 0.88, "accel": 0.82, "handling": 0.86, "braking": 0.80,
		"colour": Color(0.60, 0.14, 0.78), "unlocked": false,
	},
	{
		"id": "car_titan", "name": "Titan", "model": "res://assets/models/car_titan.glb",
		"speed": 0.80, "accel": 0.76, "handling": 0.68, "braking": 0.96,
		"colour": Color(0.24, 0.26, 0.30), "unlocked": false,
	},
]

var graphics_quality: String = "medium"
var fps_limit: int = 60
var music_volume: float = 0.7
var sfx_volume: float = 0.9
var vibration: bool = true
var control_sensitivity: float = 1.0
var steering_mode: String = "buttons"   # "buttons" | "tilt" | "wheel"
var camera_shake: bool = true

var selected_car: String = "car_speedster"
var paint_colour: Color = Color(0.88, 0.13, 0.15)
var selected_track: String = "city_circuit"
var difficulty: String = "normal"
var best_laps: Dictionary = {}


func _ready() -> void:
	load_settings()


func preset() -> Dictionary:
	return QUALITY_PRESETS.get(graphics_quality, QUALITY_PRESETS["medium"])


func car_by_id(id: String) -> Dictionary:
	for c in CARS:
		if c["id"] == id:
			return c
	return CARS[0]


func car_index(id: String) -> int:
	for i in CARS.size():
		if CARS[i]["id"] == id:
			return i
	return 0


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		apply_runtime()
		return
	graphics_quality = str(cfg.get_value("video", "quality", graphics_quality))
	if not QUALITY_PRESETS.has(graphics_quality):
		graphics_quality = "medium"
	fps_limit = clampi(int(cfg.get_value("video", "fps_limit", fps_limit)), 30, 240)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	vibration = bool(cfg.get_value("audio", "vibration", vibration))
	control_sensitivity = clampf(float(cfg.get_value("input", "sensitivity", control_sensitivity)), 0.3, 2.0)
	steering_mode = str(cfg.get_value("input", "steering_mode", steering_mode))
	if steering_mode not in ["buttons", "tilt", "wheel"]:
		steering_mode = "buttons"
	camera_shake = bool(cfg.get_value("video", "camera_shake", camera_shake))
	selected_car = str(cfg.get_value("garage", "car", selected_car))
	paint_colour = cfg.get_value("garage", "colour", paint_colour)
	if typeof(paint_colour) != TYPE_COLOR:
		paint_colour = car_by_id(selected_car)["colour"]
	selected_track = str(cfg.get_value("race", "track", selected_track))
	difficulty = str(cfg.get_value("race", "difficulty", difficulty))
	if difficulty not in ["easy", "normal", "hard"]:
		difficulty = "normal"
	best_laps = cfg.get_value("records", "best_laps", {})
	if typeof(best_laps) != TYPE_DICTIONARY:
		best_laps = {}
	apply_runtime()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "quality", graphics_quality)
	cfg.set_value("video", "fps_limit", fps_limit)
	cfg.set_value("video", "camera_shake", camera_shake)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "vibration", vibration)
	cfg.set_value("input", "sensitivity", control_sensitivity)
	cfg.set_value("input", "steering_mode", steering_mode)
	cfg.set_value("garage", "car", selected_car)
	cfg.set_value("garage", "colour", paint_colour)
	cfg.set_value("race", "track", selected_track)
	cfg.set_value("race", "difficulty", difficulty)
	cfg.set_value("records", "best_laps", best_laps)
	cfg.save(PATH)


func set_value(section: String, key: String, value: Variant) -> void:
	match section:
		"video":
			match key:
				"quality": graphics_quality = str(value)
				"fps_limit": fps_limit = clampi(int(value), 30, 240)
				"camera_shake": camera_shake = bool(value)
		"audio":
			match key:
				"music": music_volume = clampf(float(value), 0.0, 1.0)
				"sfx": sfx_volume = clampf(float(value), 0.0, 1.0)
				"vibration": vibration = bool(value)
		"input":
			match key:
				"sensitivity": control_sensitivity = clampf(float(value), 0.3, 2.0)
				"steering_mode": steering_mode = str(value)
		"garage":
			match key:
				"car": selected_car = str(value)
				"colour": paint_colour = value
		"race":
			match key:
				"track": selected_track = str(value)
				"difficulty": difficulty = str(value)
	apply_runtime()
	save_settings()
	changed.emit(section, key)


func record_lap(track_id: String, lap_time: float) -> bool:
	"""Returns true when a new personal best was set."""
	var prev := float(best_laps.get(track_id, INF))
	if lap_time < prev:
		best_laps[track_id] = lap_time
		save_settings()
		return true
	return false


func reset_to_defaults() -> void:
	graphics_quality = "medium"
	fps_limit = 60
	music_volume = 0.7
	sfx_volume = 0.9
	vibration = true
	control_sensitivity = 1.0
	steering_mode = "buttons"
	camera_shake = true
	apply_runtime()
	save_settings()
	changed.emit("all", "all")


func apply_runtime() -> void:
	Engine.max_fps = fps_limit
	var p := preset()
	if Audio:
		Audio.apply_volumes()
