class_name Speedometer
extends Control
## Circular speedometer with a tachometer ring, gear readout and needle.
##
## Drawn with canvas primitives instead of a texture so it stays crisp at any
## resolution and needs no extra asset. Values are pushed in from the HUD.

const START_ANGLE := deg_to_rad(135.0)
const END_ANGLE := deg_to_rad(405.0)
const MAX_KMH := 200.0
const MAX_RPM := 8000.0

var speed_kmh: float = 0.0
var rpm: float = 900.0
var gear: int = 1
var drifting: bool = false

var _display_speed: float = 0.0
var _display_rpm: float = 900.0


func _process(delta: float) -> void:
	var changed := false
	var new_speed := lerpf(_display_speed, speed_kmh, 1.0 - pow(0.001, delta))
	if absf(new_speed - _display_speed) > 0.05:
		_display_speed = new_speed
		changed = true
	var new_rpm := lerpf(_display_rpm, rpm, 1.0 - pow(0.0005, delta))
	if absf(new_rpm - _display_rpm) > 5.0:
		_display_rpm = new_rpm
		changed = true
	if changed:
		queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 6.0
	if radius <= 4.0:
		return

	# Dial backing
	draw_circle(centre, radius, Color(0.03, 0.05, 0.10, 0.78))
	draw_arc(centre, radius, 0.0, TAU, 64, Color(0.35, 0.45, 0.62, 0.55), 2.0, true)

	# Tachometer ring: fills with revs and turns red near the limiter.
	var rpm_ratio := clampf(_display_rpm / MAX_RPM, 0.0, 1.0)
	var rpm_colour := Color(0.25, 0.85, 1.0)
	if rpm_ratio > 0.82:
		rpm_colour = Color(1.0, 0.32, 0.24)
	elif rpm_ratio > 0.65:
		rpm_colour = Color(1.0, 0.78, 0.20)
	draw_arc(centre, radius - 3.0, START_ANGLE, START_ANGLE + (END_ANGLE - START_ANGLE) * rpm_ratio,
			48, rpm_colour, 5.0, true)

	# Tick marks every 20 km/h.
	for i in 11:
		var t := float(i) / 10.0
		var angle := lerpf(START_ANGLE, END_ANGLE, t)
		var dir := Vector2(cos(angle), sin(angle))
		var inner := centre + dir * (radius - 14.0)
		var outer := centre + dir * (radius - 6.0)
		draw_line(inner, outer, Color(0.62, 0.70, 0.84, 0.75), 2.0, true)

	# Speed needle.
	var speed_ratio := clampf(_display_speed / MAX_KMH, 0.0, 1.0)
	var needle_angle := lerpf(START_ANGLE, END_ANGLE, speed_ratio)
	var needle_dir := Vector2(cos(needle_angle), sin(needle_angle))
	var needle_colour := Color(1.0, 0.35, 0.28) if speed_ratio > 0.9 else Color(0.20, 0.80, 1.0)
	if drifting:
		needle_colour = Color(1.0, 0.72, 0.15)
	draw_line(centre, centre + needle_dir * (radius - 16.0), needle_colour, 3.5, true)
	draw_circle(centre, 6.0, Color(0.10, 0.14, 0.22))
	draw_circle(centre, 3.0, needle_colour)

	var font := UITheme.font_bold()
	var regular := UITheme.font_regular()

	# Numeric readout
	if font != null:
		var speed_text := "%d" % int(round(_display_speed))
		var text_size := font.get_string_size(speed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.62))
		draw_string(font, centre + Vector2(-text_size.x * 0.5, radius * 0.30),
				speed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.62), Color.WHITE)
		var unit := "km/h"
		var unit_size := regular.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.20))
		draw_string(regular, centre + Vector2(-unit_size.x * 0.5, radius * 0.50),
				unit, HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.20), Color(0.65, 0.72, 0.84))

		# Gear badge
		var gear_text := "R" if gear == 0 else str(gear)
		var gear_size := font.get_string_size(gear_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.34))
		var gear_pos := centre + Vector2(-gear_size.x * 0.5, -radius * 0.18)
		draw_string(font, gear_pos, gear_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.34),
				Color(1.0, 0.80, 0.25))
