extends Control
## Main menu.
##
## Every entry here is wired to a real action: nothing is decorative.

const CAROUSEL_CARS := ["car_speedster", "car_phantom", "car_viper", "car_inferno", "car_spectre", "car_titan"]

var _preview: CarPreview
var _car_name: Label
var _stat_rows: Dictionary = {}
var _carousel_index: int = 0


func _ready() -> void:
	Audio.start_music()
	_build()
	_carousel_index = Settings.car_index(Settings.selected_car)
	_refresh_preview()


func _build() -> void:
	add_child(UITheme.make_background())

	var root := UITheme.make_hbox(0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# ---- left: menu -----------------------------------------------------
	var left_margin := UITheme.make_margin(46, 40, 24, 40)
	left_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_margin.size_flags_stretch_ratio = 1.15
	root.add_child(left_margin)

	var column := UITheme.make_vbox(10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	left_margin.add_child(column)

	var title := UITheme.make_title("GFX OFFLINE RACING", 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(title)

	var tagline := UITheme.make_label("12-lap championship  -  AI opponents  -  LAN 1v1", 18, UITheme.TEXT_DIM)
	column.add_child(tagline)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	column.add_child(gap)

	var entries := [
		["Play vs AI", "ai", UITheme.ACCENT],
		["Local Multiplayer (LAN)", "lan", UITheme.ACCENT_WARM],
		["Garage", "garage", UITheme.ACCENT],
		["Track Selection", "tracks", UITheme.ACCENT],
		["Settings", "settings", UITheme.ACCENT],
	]
	for entry in entries:
		var b := UITheme.make_button(entry[0], entry[2], 56.0)
		b.pressed.connect(_on_menu.bind(entry[1]))
		column.add_child(b)

	var quit := UITheme.make_button("Exit", UITheme.ACCENT_DANGER, 50.0)
	quit.pressed.connect(_on_menu.bind("exit"))
	column.add_child(quit)
	if OS.has_feature("android") or OS.has_feature("web"):
		# Android and the web build have no meaningful exit; the OS owns the
		# app lifecycle, so the button would be a dead control.
		quit.visible = false

	var hint := UITheme.make_label("Keyboard: A/D steer, W/S pedals, Space drift, E/Q gears, Esc pause", 15,
			Color(0.50, 0.57, 0.68))
	column.add_child(hint)

	# ---- right: live car preview ---------------------------------------
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)

	var preview_holder := UITheme.make_panel(Color(0.04, 0.06, 0.11, 0.55))
	preview_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(preview_holder)

	_preview = CarPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_holder.add_child(_preview)

	var nav := UITheme.make_hbox(8)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(nav)
	var prev := UITheme.make_button("<", UITheme.ACCENT, 48.0)
	prev.custom_minimum_size = Vector2(64, 48)
	prev.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	prev.pressed.connect(_on_carousel.bind(-1))
	nav.add_child(prev)
	_car_name = UITheme.make_label("", 24, UITheme.TEXT, true)
	_car_name.custom_minimum_size = Vector2(240, 48)
	_car_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_car_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.add_child(_car_name)
	var next := UITheme.make_button(">", UITheme.ACCENT, 48.0)
	next.custom_minimum_size = Vector2(64, 48)
	next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next.pressed.connect(_on_carousel.bind(1))
	nav.add_child(next)

	var stats := UITheme.make_panel()
	right.add_child(stats)
	var stat_box := UITheme.make_vbox(4)
	stats.add_child(stat_box)
	for key in ["Speed", "Acceleration", "Handling", "Braking"]:
		var row := UITheme.make_hbox(10)
		var label := UITheme.make_label(key, 16, UITheme.TEXT_DIM)
		label.custom_minimum_size = Vector2(130, 22)
		row.add_child(label)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = 0.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(180, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.10, 0.13, 0.20, 0.9)
		bg.corner_radius_top_left = 8
		bg.corner_radius_top_right = 8
		bg.corner_radius_bottom_left = 8
		bg.corner_radius_bottom_right = 8
		bar.add_theme_stylebox_override("background", bg)
		var fill := StyleBoxFlat.new()
		fill.bg_color = UITheme.ACCENT
		fill.corner_radius_top_left = 8
		fill.corner_radius_top_right = 8
		fill.corner_radius_bottom_left = 8
		fill.corner_radius_bottom_right = 8
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		stat_box.add_child(row)
		_stat_rows[key] = bar

	UITheme.add_footer(self, "v1.0.0  -  offline")


func _refresh_preview() -> void:
	var car_id: String = CAROUSEL_CARS[_carousel_index]
	var spec := Settings.car_by_id(car_id)
	_car_name.text = str(spec["name"])
	if not bool(spec["unlocked"]):
		_car_name.text += "  (locked)"
	_preview.show_car(car_id, spec["colour"])
	_stat_rows["Speed"].value = float(spec["speed"])
	_stat_rows["Acceleration"].value = float(spec["accel"])
	_stat_rows["Handling"].value = float(spec["handling"])
	_stat_rows["Braking"].value = float(spec["braking"])


func _on_carousel(direction: int) -> void:
	Audio.play_ui("click")
	_carousel_index = wrapi(_carousel_index + direction, 0, CAROUSEL_CARS.size())
	_refresh_preview()


func _on_menu(action: String) -> void:
	Audio.play_ui("click")
	match action:
		"ai":
			SceneRouter.go_to("mode")
		"lan":
			SceneRouter.go_to("lobby")
		"garage":
			SceneRouter.go_to("garage")
		"tracks":
			SceneRouter.go_to("tracks")
		"settings":
			SceneRouter.go_to("settings")
		"exit":
			SceneRouter.quit_game()
