extends Control
## Settings. Every control writes straight into Settings and is saved, so the
## screen has no unsaved state to lose.

const QUALITIES := ["low", "medium", "high"]
const FPS_CHOICES := [30, 60, 90, 120, 144, 240]
const STEERING_MODES := ["buttons", "wheel", "tilt"]

var _quality: OptionButton
var _fps: OptionButton
var _music: HSlider
var _sfx: HSlider
var _sensitivity: HSlider
var _vibration: CheckButton
var _shake: CheckButton
var _steering: OptionButton
var _music_value: Label
var _sfx_value: Label
var _sensitivity_value: Label


func _ready() -> void:
	_build()


func _build() -> void:
	var page := UITheme.make_screen("SETTINGS", "Saved automatically")
	add_child(page)
	var column := page.get_node("MarginContainer/Content")

	var panel := UITheme.make_panel()
	panel.custom_minimum_size = Vector2(680, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)
	var box := UITheme.make_vbox(12)
	panel.add_child(box)

	# ---- graphics ------------------------------------------------------
	box.add_child(_section("Graphics"))
	box.add_child(_label("Quality preset"))
	_quality = UITheme.make_option(["Low", "Medium", "High"], QUALITIES.find(Settings.graphics_quality))
	_quality.item_selected.connect(func(i: int):
		Settings.set_value("video", "quality", QUALITIES[i])
		_apply_note("Quality applies the next time a track is loaded."))
	box.add_child(_quality)

	box.add_child(_label("Frame rate limit"))
	_fps = UITheme.make_option(_fps_labels(),
			maxi(0, FPS_CHOICES.find(Settings.fps_limit)))
	_fps.item_selected.connect(func(i: int):
		Settings.set_value("video", "fps_limit", FPS_CHOICES[i]))
	box.add_child(_fps)

	box.add_child(_label("Camera shake"))
	_shake = UITheme.make_check("Shake the camera on impacts and at speed", Settings.camera_shake)
	_shake.toggled.connect(func(v: bool): Settings.set_value("video", "camera_shake", v))
	box.add_child(_shake)

	# ---- audio ---------------------------------------------------------
	box.add_child(_section("Audio"))
	box.add_child(_label("Music volume"))
	var music_row := UITheme.make_hbox(10)
	_music = UITheme.make_slider(0.0, 1.0, 0.05, Settings.music_volume)
	_music.value_changed.connect(func(v: float):
		Settings.music_volume = v
		_music_value.text = "%d%%" % int(v * 100)
		Audio.apply_volumes())
	music_row.add_child(_music)
	_music_value = UITheme.make_label("%d%%" % int(Settings.music_volume * 100), 16, UITheme.TEXT_DIM)
	_music_value.custom_minimum_size = Vector2(56, 20)
	music_row.add_child(_music_value)
	box.add_child(music_row)

	box.add_child(_label("Effects volume"))
	var sfx_row := UITheme.make_hbox(10)
	_sfx = UITheme.make_slider(0.0, 1.0, 0.05, Settings.sfx_volume)
	_sfx.value_changed.connect(func(v: float):
		Settings.sfx_volume = v
		_sfx_value.text = "%d%%" % int(v * 100)
		Audio.apply_volumes())
	sfx_row.add_child(_sfx)
	_sfx_value = UITheme.make_label("%d%%" % int(Settings.sfx_volume * 100), 16, UITheme.TEXT_DIM)
	_sfx_value.custom_minimum_size = Vector2(56, 20)
	sfx_row.add_child(_sfx_value)
	box.add_child(sfx_row)

	box.add_child(_label("Vibration (Android)"))
	_vibration = UITheme.make_check("Vibrate on collisions", Settings.vibration)
	_vibration.toggled.connect(func(v: bool):
		Settings.vibration = v
		Settings.save_settings())
	box.add_child(_vibration)

	# ---- controls ------------------------------------------------------
	box.add_child(_section("Controls"))
	box.add_child(_label("Steering mode"))
	_steering = UITheme.make_option(["Buttons / touch pad", "Fixed wheel", "Tilt"],
			STEERING_MODES.find(Settings.steering_mode))
	_steering.item_selected.connect(func(i: int):
		Settings.set_value("input", "steering_mode", STEERING_MODES[i])
		_apply_note("Steering mode applies the next time you start a race."))
	box.add_child(_steering)

	box.add_child(_label("Steering sensitivity"))
	var sens_row := UITheme.make_hbox(10)
	_sensitivity = UITheme.make_slider(0.3, 2.0, 0.05, Settings.control_sensitivity)
	_sensitivity.value_changed.connect(func(v: float):
		Settings.control_sensitivity = v
		_sensitivity_value.text = "%.2fx" % v
		Settings.save_settings())
	sens_row.add_child(_sensitivity)
	_sensitivity_value = UITheme.make_label("%.2fx" % Settings.control_sensitivity, 16, UITheme.TEXT_DIM)
	_sensitivity_value.custom_minimum_size = Vector2(64, 20)
	sens_row.add_child(_sensitivity_value)
	box.add_child(sens_row)

	var note := UITheme.make_label("", 15, UITheme.ACCENT)
	note.name = "Note"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	# ---- actions -------------------------------------------------------
	var actions := UITheme.make_hbox(12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(actions)

	var back := UITheme.make_button("Back", UITheme.ACCENT, 54.0)
	back.custom_minimum_size = Vector2(200, 54)
	back.pressed.connect(func():
		Audio.play_ui("back")
		SceneRouter.go_to("menu"))
	actions.add_child(back)

	var reset := UITheme.make_button("Reset settings", UITheme.ACCENT_DANGER, 54.0)
	reset.custom_minimum_size = Vector2(220, 54)
	reset.pressed.connect(_on_reset)
	actions.add_child(reset)

	UITheme.add_footer(self, "settings.cfg  -  user://")


func _section(text: String) -> Label:
	var l := UITheme.make_label(text, 24, UITheme.ACCENT_WARM, true)
	return l


func _fps_labels() -> Array:
	var out := []
	for v in FPS_CHOICES:
		out.append("%d FPS" % v)
	return out


func _label(text: String) -> Label:
	return UITheme.make_label(text, 17, UITheme.TEXT)


func _apply_note(text: String) -> void:
	var note := get_node_or_null("MarginContainer/Content/PanelContainer/VBoxContainer/Note")
	if note == null:
		for n in find_children("Note", "Label", true, false):
			note = n
			break
	if note != null:
		note.text = text


func _on_reset() -> void:
	Audio.play_ui("back")
	Settings.reset_to_defaults()
	# Rebuild the screen so every control shows the restored value.
	for child in get_children():
		child.queue_free()
	_build()
	_apply_note("Settings restored to defaults.")
