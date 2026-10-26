class_name TouchControls
extends Control
## On-screen driving controls for Android.
##
## Multi-touch is handled by tracking one touch index per control, so steering,
## throttle, brake and drift can all be held at the same time. Every control is
## a plain Control drawing its own shape, which keeps the node count tiny.

signal steer_changed(value: float)
signal throttle_changed(value: float)
signal brake_changed(value: float)
signal drift_changed(pressed: bool)
signal gear_up_pressed()
signal gear_down_pressed()

const STEER_RADIUS := 96.0
const STEER_DEADZONE := 0.10

var steering_mode: String = "buttons"

var steer_value: float = 0.0
var throttle_value: float = 0.0
var brake_value: float = 0.0
var drift_value: bool = false

var _tilt_speed := 0.0

var _steer_id := -1
var _steer_origin := Vector2.ZERO
var _steer_current := Vector2.ZERO

var _throttle_id := -1
var _brake_id := -1
var _drift_id := -1

var _steer_rect := Rect2()
var _throttle_rect := Rect2()
var _brake_rect := Rect2()
var _drift_rect := Rect2()
var _gear_up_rect := Rect2()
var _gear_down_rect := Rect2()

var _enabled := true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	steering_mode = Settings.steering_mode


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		_reset_inputs()


func _reset_inputs() -> void:
	_steer_id = -1
	_throttle_id = -1
	_brake_id = -1
	_drift_id = -1
	steer_value = 0.0
	throttle_value = 0.0
	brake_value = 0.0
	drift_value = false
	steer_changed.emit(0.0)
	throttle_changed.emit(0.0)
	brake_changed.emit(0.0)
	drift_changed.emit(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _layout() -> void:
	var w := size.x
	var h := size.y
	var pad := minf(w, h) * 0.045
	var pedal := clampf(minf(w, h) * 0.30, 150.0, 260.0)
	var steer_size := clampf(minf(w, h) * 0.42, 200.0, 380.0)

	# Steering pad bottom-left, pedals bottom-right (natural thumb layout).
	_steer_rect = Rect2(pad, h - steer_size - pad, steer_size, steer_size)
	_throttle_rect = Rect2(w - pedal - pad, h - pedal * 2.0 - pad * 1.5, pedal, pedal)
	_brake_rect = Rect2(w - pedal * 2.0 - pad * 1.6, h - pedal - pad, pedal, pedal)
	_drift_rect = Rect2(w - pedal - pad, h - pedal * 3.1 - pad * 2.2, pedal * 0.78, pedal * 0.62)
	_gear_up_rect = Rect2(pad, pad, 78.0, 62.0)
	_gear_down_rect = Rect2(pad, pad + 70.0, 78.0, 62.0)


func _process(delta: float) -> void:
	if not _enabled:
		return
	if steering_mode == "tilt":
		_tilt_speed = clampf(_tilt_speed * 0.6 + 0.4, 0.2, 1.0)
		var accel := Input.get_accelerometer()
		# Landscape: rolling the phone left/right steers. Deadzone absorbs the
		# small drift a phone accelerometer always has.
		var raw := clampf(accel.x / 6.0, -1.0, 1.0)
		if absf(raw) < 0.06:
			raw = 0.0
		var target := raw * Settings.control_sensitivity
		steer_value = lerpf(steer_value, target, clampf(delta * 7.0, 0.0, 1.0))
		steer_changed.emit(steer_value)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)
	elif event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var pos: Vector2 = event.position
		if pressed:
			_handle_touch(100, pos, true)
		else:
			_handle_touch(100, pos, false)
	elif event is InputEventMouseMotion and _steer_id == 100:
		_handle_drag(100, event.position)


func _handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if not pressed:
		if index == _steer_id:
			_steer_id = -1
			steer_value = 0.0
			steer_changed.emit(0.0)
		elif index == _throttle_id:
			_throttle_id = -1
			throttle_value = 0.0
			throttle_changed.emit(0.0)
		elif index == _brake_id:
			_brake_id = -1
			brake_value = 0.0
			brake_changed.emit(0.0)
		elif index == _drift_id:
			_drift_id = -1
			drift_value = false
			drift_changed.emit(false)
		queue_redraw()
		return

	if _steer_rect.has_point(pos) and _steer_id == -1:
		_steer_id = index
		if steering_mode == "wheel":
			_steer_origin = _steer_rect.get_center()
		else:
			_steer_origin = pos
		_steer_current = pos
	elif _throttle_rect.has_point(pos) and _throttle_id == -1:
		_throttle_id = index
		throttle_value = 1.0
		throttle_changed.emit(1.0)
	elif _brake_rect.has_point(pos) and _brake_id == -1:
		_brake_id = index
		brake_value = 1.0
		brake_changed.emit(1.0)
	elif _drift_rect.has_point(pos) and _drift_id == -1:
		_drift_id = index
		drift_value = true
		drift_changed.emit(true)
	elif _gear_up_rect.has_point(pos):
		gear_up_pressed.emit()
	elif _gear_down_rect.has_point(pos):
		gear_down_pressed.emit()
	queue_redraw()


func _handle_drag(index: int, pos: Vector2) -> void:
	if index != _steer_id:
		return
	_steer_current = pos
	var delta := _steer_current - _steer_origin
	var raw := clampf(delta.x / (STEER_RADIUS * 0.7), -1.0, 1.0)
	if absf(raw) < STEER_DEADZONE:
		raw = 0.0
	steer_value = raw * Settings.control_sensitivity
	steer_changed.emit(clampf(steer_value, -1.0, 1.0))
	queue_redraw()


# ---------------------------------------------------------------------------
# drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not _enabled:
		return
	var font := UITheme.font_bold()

	_draw_steer_pad(font)
	_draw_pedal(_throttle_rect, "GAS", Color(0.16, 0.72, 0.36), _throttle_id != -1, font)
	_draw_pedal(_brake_rect, "BRAKE", Color(0.86, 0.22, 0.24), _brake_id != -1, font)
	_draw_pedal(_drift_rect, "DRIFT", Color(0.95, 0.62, 0.12), _drift_id != -1, font)
	_draw_small_button(_gear_up_rect, "GEAR +", _gear_id_active(1), font)
	_draw_small_button(_gear_down_rect, "GEAR -", _gear_id_active(-1), font)


func _gear_id_active(_dir: int) -> bool:
	return false


func _draw_steer_pad(font: FontFile) -> void:
	var centre := _steer_rect.get_center()
	var radius := _steer_rect.size.x * 0.42
	var active := _steer_id != -1
	var ring := Color(0.22, 0.78, 1.0, 0.85) if active else Color(0.55, 0.65, 0.80, 0.35)
	draw_circle(centre, radius, Color(0.04, 0.07, 0.12, 0.32))
	draw_arc(centre, radius, 0.0, TAU, 48, ring, 3.0, true)
	draw_line(centre + Vector2(-radius * 0.8, 0), centre + Vector2(radius * 0.8, 0),
			Color(0.55, 0.65, 0.80, 0.35), 2.0, true)

	# Knob shows the current steering amount, clamped inside the ring.
	var knob := centre + Vector2(clampf(steer_value, -1.0, 1.0) * radius * 0.72, 0.0)
	draw_circle(knob, radius * 0.30, Color(0.22, 0.78, 1.0, 0.9))
	draw_arc(knob, radius * 0.30, 0.0, TAU, 24, Color(1, 1, 1, 0.75), 2.0, true)

	if font != null:
		var text := "STEER"
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(font, centre + Vector2(-ts.x * 0.5, radius + 24.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.70, 0.78, 0.90))


func _draw_pedal(rect: Rect2, text: String, colour: Color, active: bool, font: FontFile) -> void:
	var alpha := 0.55 if active else 0.24
	draw_rect(rect, Color(colour.r, colour.g, colour.b, alpha), true)
	draw_rect(rect, Color(colour.r, colour.g, colour.b, 0.95), false, 3.0)
	if font != null:
		var fs := maxi(1, int(rect.size.y * 0.16))
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, rect.get_center() + Vector2(-ts.x * 0.5, fs * 0.35), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.92))


func _draw_small_button(rect: Rect2, text: String, active: bool, font: FontFile) -> void:
	draw_rect(rect, Color(0.10, 0.14, 0.22, 0.65 if active else 0.45), true)
	draw_rect(rect, Color(0.45, 0.58, 0.78, 0.85), false, 2.0)
	if font != null:
		var fs := maxi(1, int(rect.size.y * 0.34))
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, rect.get_center() + Vector2(-ts.x * 0.5, fs * 0.35), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.90, 0.94, 1.0))
