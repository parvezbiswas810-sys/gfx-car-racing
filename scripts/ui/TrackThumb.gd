class_name TrackThumb
extends Control
## Draws a track layout outline from the same control polygon the track builder
## uses, so the thumbnail always matches the circuit you actually drive.

const PADDING := 18.0

var track_id: String = "city_circuit"
var _points: PackedVector2Array = PackedVector2Array()
var _bounds_min := Vector2.ZERO
var _bounds_size := Vector2.ONE


func set_track(id: String) -> void:
	track_id = id
	_cache()
	queue_redraw()


func _cache() -> void:
	_points = PackedVector2Array()
	var data: Dictionary = TrackData.get_track(track_id)
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in data["points"]:
		_points.append(p)
		mn = mn.min(p)
		mx = mx.max(p)
	_bounds_min = mn
	_bounds_size = (mx - mn).max(Vector2.ONE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var panel := Rect2(Vector2.ZERO, size)
	draw_rect(panel, Color(0.03, 0.05, 0.09, 0.85), true)
	draw_rect(panel, Color(0.30, 0.40, 0.56, 0.55), false, 1.5)
	if _points.size() < 3:
		return

	# Fit the polygon into the box while preserving aspect ratio.
	var inner := size - Vector2(PADDING, PADDING) * 2.0
	var scale_factor := minf(inner.x / _bounds_size.x, inner.y / _bounds_size.y)
	var offset := (size - _bounds_size * scale_factor) * 0.5

	var mapped := PackedVector2Array()
	for p in _points:
		mapped.append((p - _bounds_min) * scale_factor + offset)

	# Closed outline plus the smoothing hint (dashed inner line) so the
	# thumbnail communicates the drivable line, not just the raw corners.
	for i in mapped.size():
		var a := mapped[i]
		var b := mapped[(i + 1) % mapped.size()]
		draw_line(a, b, Color(0.24, 0.72, 1.0, 0.9), 3.0, true)

	var centre := Vector2.ZERO
	for p in mapped:
		centre += p
	centre /= float(mapped.size())

	# Corner dots make the number of turns readable at a glance.
	var n := mapped.size()
	for i in n:
		var a := mapped[(i - 1 + n) % n]
		var b := mapped[i]
		var c := mapped[(i + 1) % n]
		var v1 := (b - a).normalized()
		var v2 := (c - b).normalized()
		if v1.dot(v2) < 0.985:
			draw_circle(b, 4.0, Color(1.0, 0.66, 0.20, 0.95))

	var start := mapped[0]
	draw_circle(start, 7.0, Color(0.16, 0.92, 0.42, 0.95))
	draw_arc(start, 9.0, 0.0, TAU, 20, Color(1, 1, 1, 0.7), 1.5, true)
