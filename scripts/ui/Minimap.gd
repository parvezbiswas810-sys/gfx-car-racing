class_name Minimap
extends Control
## Compact track overview drawn straight from the track centreline.
##
## Everything is redrawn in _draw() from cached data, so there is no per-frame
## node churn and the cost is one canvas item.

const PADDING := 12.0

var track: TrackBuilder
var player: Car

var _points: PackedVector2Array = PackedVector2Array()
var _bounds_min := Vector2.ZERO
var _bounds_size := Vector2.ONE


func set_track(t: TrackBuilder, p_player: Car) -> void:
	track = t
	player = p_player
	_cache_points()
	queue_redraw()


func _cache_points() -> void:
	_points = PackedVector2Array()
	if track == null or track.centerline.is_empty():
		return
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in track.centerline:
		var v := Vector2(p.x, p.z)
		_points.append(v)
		mn = mn.min(v)
		mx = mx.max(v)
	_bounds_min = mn
	_bounds_size = (mx - mn).max(Vector2.ONE)


func _map(point: Vector3) -> Vector2:
	var local := (Vector2(point.x, point.z) - _bounds_min) / _bounds_size
	var inner := size - Vector2(PADDING, PADDING) * 2.0
	return Vector2(PADDING, PADDING) + Vector2(local.x * inner.x, local.y * inner.y)


func _draw() -> void:
	var panel := Rect2(Vector2.ZERO, size)
	draw_rect(panel, Color(0.02, 0.04, 0.08, 0.55), true)
	draw_rect(panel, Color(0.55, 0.72, 1.0, 0.35), false, 1.5)

	if _points.size() < 3 or track == null:
		return

	var mapped := PackedVector2Array()
	for p in _points:
		mapped.append(_map(Vector3(p.x, 0, p.y)))

	var width := maxf(2.0, size.x * 0.035)
	for i in mapped.size():
		var a := mapped[i]
		var b := mapped[(i + 1) % mapped.size()]
		draw_line(a, b, Color(0.10, 0.11, 0.14, 0.95), width, true)
	for i in mapped.size():
		var a := mapped[i]
		var b := mapped[(i + 1) % mapped.size()]
		draw_line(a, b, Color(0.75, 0.78, 0.85, 0.55), 1.0, true)

	var start := _map(track.centerline[0])
	draw_circle(start, maxf(3.0, size.x * 0.022), Color(0.95, 0.95, 0.98, 0.95))

	if player != null and player.is_inside_tree():
		for car in _cars():
			var pos := _map(car.global_position)
			var is_player: bool = car == player
			var colour := Color(1.0, 0.85, 0.15) if is_player else Color(0.95, 0.32, 0.28)
			draw_circle(pos, maxf(3.5, size.x * 0.026) if is_player else maxf(2.5, size.x * 0.020), colour)
			if is_player:
				draw_arc(pos, maxf(6.0, size.x * 0.042), 0.0, TAU, 18, Color(1, 1, 1, 0.55), 1.5, true)


func _cars() -> Array:
	var out: Array = []
	var root := get_tree().current_scene
	if root == null:
		return out
	for node in root.get_children():
		if node is Car:
			out.append(node)
	return out
