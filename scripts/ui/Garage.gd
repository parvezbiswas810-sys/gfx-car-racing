extends Control
## Garage: pick a car, repaint it, see real stats. Selection is persisted.

const PALETTE := [
	Color(0.88, 0.13, 0.15), Color(0.16, 0.20, 0.58), Color(0.10, 0.62, 0.26),
	Color(0.96, 0.47, 0.07), Color(0.60, 0.14, 0.78), Color(0.20, 0.22, 0.25),
	Color(0.95, 0.85, 0.20), Color(0.10, 0.70, 0.78), Color(0.95, 0.95, 0.97),
]

var _preview: CarPreview
var _name_label: Label
var _desc_label: Label
var _stat_bars: Dictionary = {}
var _stat_values: Dictionary = {}
var _car_buttons: Array[Button] = []
var _swatches: Array[Button] = []
var _select_button: Button
var _index: int = 0


func _ready() -> void:
	_build()
	_index = Settings.car_index(Settings.selected_car)
	_refresh()


func _build() -> void:
	var page := UITheme.make_screen("GARAGE", "Choose a car and a paint job")
	add_child(page)
	var column := page.get_node("MarginContainer/Content")

	var body := UITheme.make_hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	# ---- car list ------------------------------------------------------
	var list_panel := UITheme.make_panel()
	list_panel.custom_minimum_size = Vector2(280, 0)
	body.add_child(list_panel)
	var list := UITheme.make_vbox(8)
	list_panel.add_child(list)
	for i in Settings.CARS.size():
		var spec: Dictionary = Settings.CARS[i]
		var b := UITheme.make_button(str(spec["name"]), UITheme.ACCENT, 54.0)
		b.pressed.connect(_on_pick.bind(i))
		list.add_child(b)
		_car_buttons.append(b)

	# ---- preview -------------------------------------------------------
	var preview_panel := UITheme.make_panel(Color(0.04, 0.06, 0.11, 0.6))
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(preview_panel)
	var preview_box := UITheme.make_vbox(6)
	preview_panel.add_child(preview_box)

	_name_label = UITheme.make_label("", 30, UITheme.TEXT, true)
	preview_box.add_child(_name_label)
	_desc_label = UITheme.make_label("", 16, UITheme.TEXT_DIM)
	preview_box.add_child(_desc_label)

	_preview = CarPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_box.add_child(_preview)

	# ---- paint ---------------------------------------------------------
	preview_box.add_child(UITheme.make_label("Paint", 17, UITheme.TEXT, true))
	var swatch_row := UITheme.make_hbox(8)
	preview_box.add_child(swatch_row)
	for colour in PALETTE:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(46, 46)
		sw.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = colour
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = Color(1, 1, 1, 0.25)
		for state in ["normal", "hover", "pressed", "focus"]:
			sw.add_theme_stylebox_override(state, sb)
		sw.pressed.connect(_on_paint.bind(colour))
		swatch_row.add_child(sw)
		_swatches.append(sw)

	# ---- stats ---------------------------------------------------------
	var stats_panel := UITheme.make_panel()
	stats_panel.custom_minimum_size = Vector2(340, 0)
	body.add_child(stats_panel)
	var stats_box := UITheme.make_vbox(10)
	stats_panel.add_child(stats_box)
	stats_box.add_child(UITheme.make_label("Performance", 22, UITheme.TEXT, true))
	for key in ["Speed", "Acceleration", "Handling", "Braking"]:
		var row := UITheme.make_hbox(8)
		var label := UITheme.make_label(key, 16, UITheme.TEXT_DIM)
		label.custom_minimum_size = Vector2(120, 20)
		row.add_child(label)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.10, 0.13, 0.20, 0.9)
		bg.corner_radius_top_left = 9
		bg.corner_radius_top_right = 9
		bg.corner_radius_bottom_left = 9
		bg.corner_radius_bottom_right = 9
		bar.add_theme_stylebox_override("background", bg)
		var fill := StyleBoxFlat.new()
		fill.bg_color = UITheme.ACCENT_WARM
		fill.corner_radius_top_left = 9
		fill.corner_radius_top_right = 9
		fill.corner_radius_bottom_left = 9
		fill.corner_radius_bottom_right = 9
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		var value_label := UITheme.make_label("0", 15, UITheme.TEXT_DIM)
		value_label.custom_minimum_size = Vector2(44, 20)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		stats_box.add_child(row)
		_stat_bars[key] = bar
		_stat_values[key] = value_label

	_select_button = UITheme.make_button("Select this car", UITheme.ACCENT_WARM, 56.0)
	_select_button.pressed.connect(_on_select)
	stats_box.add_child(_select_button)

	var note := UITheme.make_label(
		"Spectre and Titan are locked placeholders: they drive, but they are not "
		+ "unlocked by any progression system yet.", 14, Color(0.55, 0.60, 0.70))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_box.add_child(note)

	# ---- actions -------------------------------------------------------
	var actions := UITheme.make_hbox(12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(actions)
	var back := UITheme.make_button("Back to menu", UITheme.ACCENT_DANGER, 54.0)
	back.custom_minimum_size = Vector2(240, 54)
	back.pressed.connect(func():
		Audio.play_ui("back")
		SceneRouter.go_to("menu"))
	actions.add_child(back)


func _on_pick(index: int) -> void:
	Audio.play_ui("click")
	_index = index
	_refresh()


func _on_paint(colour: Color) -> void:
	Audio.play_ui("click")
	Settings.paint_colour = colour
	Settings.save_settings()
	_preview.show_car(Settings.CARS[_index]["id"], colour)
	_refresh_swatch_selection()


func _on_select() -> void:
	Audio.play_ui("click")
	var spec: Dictionary = Settings.CARS[_index]
	if not bool(spec["unlocked"]):
		_desc_label.text = "%s is locked in this build." % spec["name"]
		return
	Settings.selected_car = str(spec["id"])
	Settings.save_settings()
	_select_button.text = "Selected"
	_refresh()


func _refresh() -> void:
	var spec: Dictionary = Settings.CARS[_index]
	_name_label.text = str(spec["name"])
	var unlocked := bool(spec["unlocked"])
	_desc_label.text = "Ready to race" if unlocked else "Locked in this build"
	_preview.show_car(str(spec["id"]), Settings.paint_colour)
	_stat_bars["Speed"].value = float(spec["speed"])
	_stat_bars["Acceleration"].value = float(spec["accel"])
	_stat_bars["Handling"].value = float(spec["handling"])
	_stat_bars["Braking"].value = float(spec["braking"])
	_stat_values["Speed"].text = "%d" % int(float(spec["speed"]) * 100)
	_stat_values["Acceleration"].text = "%d" % int(float(spec["accel"]) * 100)
	_stat_values["Handling"].text = "%d" % int(float(spec["handling"]) * 100)
	_stat_values["Braking"].text = "%d" % int(float(spec["braking"]) * 100)
	for i in _car_buttons.size():
		var is_current := str(Settings.CARS[i]["id"]) == Settings.selected_car
		var accent := UITheme.ACCENT_WARM if i == _index else UITheme.ACCENT
		UITheme.apply_button_style(_car_buttons[i], accent)
		_car_buttons[i].text = str(Settings.CARS[i]["name"]) + (" *" if is_current else "")
	_select_button.text = "Selected" if str(spec["id"]) == Settings.selected_car else "Select this car"
	_select_button.disabled = not unlocked
	_refresh_swatch_selection()


func _refresh_swatch_selection() -> void:
	for i in _swatches.size():
		var sb: StyleBoxFlat = _swatches[i].get_theme_stylebox("normal")
		if sb != null:
			sb.border_color = Color(1, 1, 1, 0.95) if PALETTE[i].is_equal_approx(Settings.paint_colour) else Color(1, 1, 1, 0.25)
			sb.border_width_left = 3 if PALETTE[i].is_equal_approx(Settings.paint_colour) else 2
			sb.border_width_top = sb.border_width_left
			sb.border_width_right = sb.border_width_left
			sb.border_width_bottom = sb.border_width_left
