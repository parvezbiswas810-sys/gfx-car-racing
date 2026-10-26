extends Control
## Splash screen: logo, honest progress, then the main menu.
##
## The progress bar reflects real work (preloading the models, textures and
## audio the menus and race need) rather than a fixed timer.

const RESOURCES := [
	"res://assets/models/car_speedster.glb",
	"res://assets/models/car_phantom.glb",
	"res://assets/models/car_viper.glb",
	"res://assets/models/car_inferno.glb",
	"res://assets/models/car_spectre.glb",
	"res://assets/models/car_titan.glb",
	"res://assets/models/wheel.glb",
	"res://assets/textures/asphalt.png",
	"res://assets/textures/grass.png",
	"res://assets/textures/sand.png",
	"res://assets/textures/snow.png",
	"res://assets/textures/curb.png",
	"res://assets/textures/finish_line.png",
	"res://assets/textures/skid.png",
	"res://assets/textures/smoke.png",
	"res://assets/audio/engine_loop.wav",
	"res://assets/audio/skid_loop.wav",
	"res://assets/audio/crash.wav",
	"res://assets/audio/countdown_beep.wav",
	"res://assets/audio/countdown_go.wav",
	"res://assets/audio/checkpoint.wav",
	"res://assets/audio/ui_click.wav",
	"res://assets/audio/ui_back.wav",
	"res://assets/audio/music_menu.wav",
	"res://assets/audio/victory.wav",
]

var _bar: ProgressBar
var _status: Label
var _title: Label
var _logo: TextureRect
var _elapsed: float = 0.0
var _index: int = 0
var _done: bool = false
var _failed: Array[String] = []


func _ready() -> void:
	_build()


func _build() -> void:
	add_child(UITheme.make_background())

	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_theme_constant_override("separation", 18)
	var margin := UITheme.make_margin(40, 40, 40, 40)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(centre)
	add_child(margin)

	_logo = TextureRect.new()
	_logo.custom_minimum_size = Vector2(180, 180)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if ResourceLoader.exists("res://assets/textures/glow.png"):
		_logo.texture = load("res://assets/textures/glow.png")
	_logo.modulate = UITheme.ACCENT
	centre.add_child(_logo)

	_title = UITheme.make_title("GFX OFFLINE RACING", 54)
	centre.add_child(_title)

	var sub := UITheme.make_label("Arcade racing - AI and LAN multiplayer", 20, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	centre.add_child(spacer)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.custom_minimum_size = Vector2(460, 22)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.09, 0.15, 0.9)
	bg.corner_radius_top_left = 11
	bg.corner_radius_top_right = 11
	bg.corner_radius_bottom_left = 11
	bg.corner_radius_bottom_right = 11
	_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.ACCENT
	fill.corner_radius_top_left = 11
	fill.corner_radius_top_right = 11
	fill.corner_radius_bottom_left = 11
	fill.corner_radius_bottom_right = 11
	_bar.add_theme_stylebox_override("fill", fill)
	centre.add_child(_bar)

	_status = UITheme.make_label("Loading...", 16, UITheme.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(_status)

	var hint := UITheme.make_label("Tap or press any key to continue", 15, Color(0.45, 0.52, 0.64))
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.0
	centre.add_child(hint)

	UITheme.add_footer(self, "v1.0.0  -  Godot 4.7")


func _process(delta: float) -> void:
	_elapsed += delta

	# Preload a couple of resources per frame so the bar animates smoothly and
	# the UI thread is never blocked for long.
	var budget := 0
	while budget < 2 and _index < RESOURCES.size():
		var path: String = RESOURCES[_index]
		_index += 1
		budget += 1
		if ResourceLoader.exists(path):
			var res := load(path)
			if res == null:
				_failed.append(path)
		else:
			_failed.append(path)

	var progress := 100.0 * float(_index) / float(maxi(1, RESOURCES.size()))
	_bar.value = lerpf(_bar.value, progress, 0.25)
	if _index < RESOURCES.size():
		_status.text = "Loading %d / %d" % [_index, RESOURCES.size()]
	else:
		_bar.value = lerpf(_bar.value, 100.0, 0.2)
		if not _failed.is_empty():
			_status.text = "%d asset(s) missing - see the log" % _failed.size()
		else:
			_status.text = "Ready"
		if not _done and _elapsed > 1.2:
			_done = true
			var hint := get_node_or_null("MarginContainer/VBoxContainer/Hint")
			if hint == null:
				hint = _find_hint()
			if hint != null:
				hint.modulate.a = 1.0
			Audio.start_music()

	if _done:
		var hint := _find_hint()
		if hint != null and _elapsed > 2.2:
			# Gentle pulse invites the tap without blocking it.
			hint.modulate.a = 0.55 + 0.45 * sin(_elapsed * 3.0)
		if _elapsed > 3.0 or _input_received:
			_go()


var _input_received: bool = false


func _find_hint() -> Label:
	for node in find_children("*", "Label", true, false):
		if node.name == "Hint":
			return node
	return null


func _unhandled_input(event: InputEvent) -> void:
	if not _done:
		return
	if event is InputEventScreenTouch and event.pressed:
		_input_received = true
	elif event is InputEventMouseButton and event.pressed:
		_input_received = true
	elif event is InputEventKey and event.pressed and not event.echo:
		_input_received = true
	elif event is InputEventJoypadButton and event.pressed:
		_input_received = true


func _go() -> void:
	set_process(false)
	if not _failed.is_empty():
		push_warning("Splash: missing assets: %s" % ", ".join(_failed))
	SceneRouter.go_to("menu")
