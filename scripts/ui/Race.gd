extends Node
## Race screen root.
##
## Scene tree it builds:
##   RaceManager (Node3D)          - track, cars, lap rules, networking
##   HUD (CanvasLayer)             - fixed overlay, never rotates with camera
##     TouchControls               - on-screen driving input
##     PauseMenu                   - overlay when paused
##
## The HUD lives on a CanvasLayer so it is completely independent of the 3D
## camera, which is what keeps it readable on a phone.

var manager: RaceManager
var hud: CanvasLayer
var touch: TouchControls
var speedometer: Speedometer
var minimap: Minimap
var pause_menu: Control

var _lap_label: Label
var _position_label: Label
var _timer_label: Label
var _best_label: Label
var _countdown_label: Label
var _opponent_box: VBoxContainer
var _message_label: Label
var _pause_button: Button
var _gear_label: Label

var _laps: int = 12
var _race_time: float = 0.0
var _countdown_value: int = -1
var _results_shown: bool = false


func _ready() -> void:
	_build_manager()
	_build_hud()
	_connect_manager()
	Audio.stop_music()


func _build_manager() -> void:
	manager = RaceManager.new()
	manager.name = "RaceManager"
	add_child(manager)

	var mode_name := str(SceneRouter.take("mode", "ai"))
	var track_id := str(SceneRouter.take("track", Settings.selected_track))
	var difficulty := str(SceneRouter.take("difficulty", Settings.difficulty))
	_laps = int(SceneRouter.take("laps", TrackData.LAPS))
	var ai_count := int(SceneRouter.take("ai", 3))

	var mode := RaceManager.Mode.AI
	match mode_name:
		"solo": mode = RaceManager.Mode.SOLO
		"ai": mode = RaceManager.Mode.AI
		"host": mode = RaceManager.Mode.HOST
		"client": mode = RaceManager.Mode.CLIENT

	manager.configure(mode, track_id, difficulty, _laps, ai_count)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	add_child(hud)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	# ---- top left: lap / position / time -------------------------------
	var top_left := UITheme.make_vbox(4)
	top_left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_left.position = Vector2(20, 16)
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_left)

	_lap_label = UITheme.make_label("LAP 1/%d" % _laps, 34, UITheme.TEXT, true)
	top_left.add_child(_lap_label)
	_position_label = UITheme.make_label("POSITION 1/4", 22, UITheme.ACCENT_WARM, true)
	top_left.add_child(_position_label)
	_timer_label = UITheme.make_label("00:00.000", 24, UITheme.TEXT, true)
	top_left.add_child(_timer_label)
	_best_label = UITheme.make_label("Best lap  --:--.---", 16, UITheme.TEXT_DIM)
	top_left.add_child(_best_label)
	_gear_label = UITheme.make_label("GEAR 1", 18, UITheme.TEXT_DIM)
	top_left.add_child(_gear_label)

	# ---- top right: opponents + minimap --------------------------------
	var top_right := UITheme.make_vbox(6)
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.position = Vector2(-250, 16)
	top_right.custom_minimum_size = Vector2(230, 0)
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_right)

	_opponent_box = UITheme.make_vbox(3)
	top_right.add_child(_opponent_box)

	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(220, 170)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.add_child(minimap)

	# ---- bottom right: speedometer -------------------------------------
	speedometer = Speedometer.new()
	speedometer.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speedometer.position = Vector2(-230, -230)
	speedometer.custom_minimum_size = Vector2(210, 210)
	speedometer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(speedometer)

	# ---- pause ---------------------------------------------------------
	_pause_button = UITheme.make_button("II", UITheme.ACCENT, 54.0)
	_pause_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_button.position = Vector2(-76, 200)
	_pause_button.custom_minimum_size = Vector2(56, 54)
	_pause_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pause_button.pressed.connect(_toggle_pause)
	root.add_child(_pause_button)

	# ---- touch controls ------------------------------------------------
	touch = TouchControls.new()
	touch.name = "TouchControls"
	root.add_child(touch)
	touch.set_enabled(false)

	# ---- centre messages -----------------------------------------------
	_countdown_label = UITheme.make_label("", 120, Color(1, 1, 1, 0.95), true)
	_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_label.position = Vector2(-140, -100)
	_countdown_label.custom_minimum_size = Vector2(280, 200)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_countdown_label)

	_message_label = UITheme.make_label("", 26, UITheme.ACCENT_WARM, true)
	_message_label.set_anchors_preset(Control.PRESET_CENTER)
	_message_label.position = Vector2(-300, 120)
	_message_label.custom_minimum_size = Vector2(600, 60)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_message_label)

	pause_menu = _build_pause_menu()
	pause_menu.visible = false
	root.add_child(pause_menu)


func _build_pause_menu() -> Control:
	var overlay := Control.new()
	overlay.name = "PauseMenu"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.72)
	overlay.add_child(dim)

	var panel := UITheme.make_panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-220, -220)
	panel.custom_minimum_size = Vector2(440, 0)
	overlay.add_child(panel)

	var box := UITheme.make_vbox(12)
	panel.add_child(box)
	var title := UITheme.make_title("PAUSED", 40)
	box.add_child(title)

	var resume := UITheme.make_button("Resume", UITheme.ACCENT, 54.0)
	resume.pressed.connect(func(): _toggle_pause())
	box.add_child(resume)

	var restart := UITheme.make_button("Restart race", UITheme.ACCENT_WARM, 54.0)
	restart.pressed.connect(_confirm_restart)
	box.add_child(restart)

	var settings := UITheme.make_button("Settings", UITheme.ACCENT, 54.0)
	settings.pressed.connect(func():
		Audio.play_ui("click")
		# Unpause so the settings screen is interactive, then come back here.
		manager.set_paused(false)
		SceneRouter.go_to("settings"))
	box.add_child(settings)

	var quit := UITheme.make_button("Return to menu", UITheme.ACCENT_DANGER, 54.0)
	quit.pressed.connect(_return_to_menu)
	box.add_child(quit)

	var confirm := _build_confirm_overlay()
	confirm.name = "RestartConfirm"
	confirm.visible = false
	overlay.add_child(confirm)

	return overlay


func _build_confirm_overlay() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.8)
	overlay.add_child(dim)
	var panel := UITheme.make_panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-240, -110)
	panel.custom_minimum_size = Vector2(480, 0)
	overlay.add_child(panel)
	var box := UITheme.make_vbox(12)
	panel.add_child(box)
	box.add_child(UITheme.make_label("Restart the race from lap 1?", 24, UITheme.TEXT, true))
	var row := UITheme.make_hbox(12)
	box.add_child(row)
	var cancel := UITheme.make_button("Cancel", UITheme.ACCENT, 50.0)
	cancel.pressed.connect(func():
		Audio.play_ui("back")
		overlay.visible = false)
	row.add_child(cancel)
	var yes := UITheme.make_button("Restart", UITheme.ACCENT_DANGER, 50.0)
	yes.pressed.connect(func():
		Audio.play_ui("click")
		overlay.visible = false
		pause_menu.visible = false
		manager.set_paused(false)
		manager.restart_race()
		_results_shown = false
		_race_time = 0.0)
	row.add_child(yes)
	return overlay


func _connect_manager() -> void:
	manager.countdown_tick.connect(_on_countdown)
	manager.race_started.connect(_on_race_started)
	manager.race_finished.connect(_on_race_finished)
	manager.lap_changed.connect(_on_lap_changed)
	touch.steer_changed.connect(func(v: float): _set_steer(v))
	touch.throttle_changed.connect(func(v: float): manager.player_car.throttle = v)
	touch.brake_changed.connect(func(v: float): manager.player_car.brake_input = v)
	touch.drift_changed.connect(func(v: bool): manager.player_car.drifting = v)
	touch.gear_up_pressed.connect(func(): manager.player_car.shift_up())
	touch.gear_down_pressed.connect(func(): manager.player_car.shift_down())


func _set_steer(value: float) -> void:
	if manager != null and manager.player_car != null:
		manager.player_car.steer_input = value


func _on_countdown(value: int) -> void:
	_countdown_value = value
	if value > 0:
		_countdown_label.text = str(value)
		_countdown_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	elif value == 0:
		_countdown_label.text = "GO!"
		_countdown_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.45))


func _on_race_started() -> void:
	_countdown_label.text = ""
	touch.set_enabled(true)
	if minimap != null:
		minimap.set_track(manager.track, manager.player_car)
	_message_label.text = ""


func _on_lap_changed(car: Car, lap: int, lap_time: float) -> void:
	if car == manager.player_car:
		_lap_label.text = "LAP %d/%d" % [mini(lap, _laps), _laps]
		if lap_time > 0.0:
			_message_label.text = "Lap %d: %s" % [lap, _format_time(lap_time)]
			get_tree().create_timer(1.6).timeout.connect(func():
				if is_instance_valid(_message_label):
					_message_label.text = "")
	_refresh_standings()


func _on_race_finished(results: Array) -> void:
	if _results_shown:
		return
	_results_shown = true
	touch.set_enabled(false)
	Audio.vibrate(120)
	SceneRouter.go_to("results", {"results": results, "laps": _laps, "track": manager.track_id})


# ---------------------------------------------------------------------------
# per-frame HUD
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if manager == null or manager.player_car == null:
		return
	if manager.running:
		_race_time = manager.race_time

	var car := manager.player_car
	_timer_label.text = _format_time(_race_time)
	_best_label.text = "Best lap  %s" % _format_time(car.best_lap)
	_gear_label.text = "GEAR %s" % ("R" if car.gear == 0 else str(car.gear))

	if speedometer != null:
		speedometer.speed_kmh = car.speed_kmh
		speedometer.rpm = car.rpm
		speedometer.gear = car.gear
		speedometer.drifting = car.drifting_now

	if Input.is_action_just_pressed("pause"):
		_toggle_pause()

	# Keyboard input mirrors the touch controls so desktop testing is identical.
	if manager.running and touch != null:
		_apply_keyboard(car)


func _apply_keyboard(car: Car) -> void:
	var steer := Input.get_axis("steer_left", "steer_right")
	if absf(steer) > 0.05:
		car.steer_input = steer * Settings.control_sensitivity
		touch.steer_value = steer
	elif touch._steer_id == -1:
		car.steer_input = 0.0
		touch.steer_value = 0.0

	if Input.is_action_pressed("accelerate"):
		car.throttle = 1.0
	elif touch._throttle_id == -1:
		car.throttle = 0.0

	if Input.is_action_pressed("brake"):
		car.brake_input = 1.0
	elif touch._brake_id == -1:
		car.brake_input = 0.0

	if Input.is_action_pressed("drift"):
		car.drifting = true
	elif touch._drift_id == -1:
		car.drifting = false

	if Input.is_action_just_pressed("gear_up"):
		car.shift_up()
	if Input.is_action_just_pressed("gear_down"):
		car.shift_down()
	touch.queue_redraw()


func _refresh_standings() -> void:
	if manager == null or manager.lap_tracker == null:
		return
	var order := manager.standings()
	var total := maxi(1, order.size())
	var my_pos := 1
	for i in order.size():
		if order[i] == manager.player_car:
			my_pos = i + 1
	_position_label.text = "POSITION %d/%d" % [my_pos, total]

	if _opponent_box == null:
		return
	for child in _opponent_box.get_children():
		child.queue_free()
	for car in order:
		if car == manager.player_car:
			continue
		var laps := manager.lap_tracker.laps_done(car)
		var gap := manager.lap_tracker.progress_of(manager.player_car) - manager.lap_tracker.progress_of(car)
		var tag := ""
		if gap > 0.01:
			tag = "+%.2f laps" % gap
		elif gap < -0.01:
			tag = "%.2f laps behind" % gap
		var row := UITheme.make_label("%s   L%d   %s" % [car.name, laps + 1, tag],
				15, UITheme.TEXT_DIM)
		_opponent_box.add_child(row)


# ---------------------------------------------------------------------------
# pause / navigation
# ---------------------------------------------------------------------------

func _toggle_pause() -> void:
	if manager == null:
		return
	var now_paused := not get_tree().paused
	manager.set_paused(now_paused)
	pause_menu.visible = now_paused
	touch.set_enabled(not now_paused and manager.running)
	if now_paused:
		Audio.play_ui("back")
	else:
		Audio.play_ui("click")


func _confirm_restart() -> void:
	var confirm := pause_menu.get_node_or_null("RestartConfirm")
	if confirm != null:
		confirm.visible = true


func _return_to_menu() -> void:
	Audio.play_ui("back")
	if Net.is_online():
		Net.leave_room()
	if manager != null:
		manager.set_paused(false)
	SceneRouter.go_to("menu")


func _notification(what: int) -> void:
	# Android suspends the app when it goes to the background. Pause so the race
	# cannot be lost to a timer that keeps running while the player is away.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if manager != null and manager.running and not get_tree().paused:
			manager.set_paused(true)
			pause_menu.visible = true
			touch.set_enabled(false)


static func _format_time(seconds: float) -> String:
	if seconds <= 0.0 or seconds == INF or is_nan(seconds):
		return "--:--.---"
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	var ms := int((seconds - floor(seconds)) * 1000.0)
	return "%d:%02d.%03d" % [m, s, ms]
