class_name LapTracker
extends Node
## Authoritative lap counting.
##
## A lap only counts when every checkpoint has been passed in order and the car
## then crosses the finish gate. This is what makes reversing over the line,
## re-entering a gate, or bouncing off a barrier unable to inflate the count.
##
## Progress is reported as a monotonic float so race position can be compared
## even when two cars are on different laps.

signal lap_completed(car: Car, lap: int, lap_time: float)
signal car_finished(car: Car, result: Dictionary)
signal standings_changed()

const CHECKPOINT_COUNT := 12

var track: TrackBuilder
var total_laps: int = 12
var cars: Array[Car] = []

var _progress: Dictionary = {}     # car -> next expected checkpoint index
var _laps_done: Dictionary = {}    # car -> completed laps
var _lap_started: Dictionary = {}  # car -> msec
var _lap_times: Dictionary = {}
var _best_lap: Dictionary = {}
var _finished: Dictionary = {}
var _last_gate_ms: Dictionary = {}
var _last_gate_index: Dictionary = {}
var _total_progress: Dictionary = {}
var _race_started_ms: int = 0
var _running: bool = false


func setup(p_track: TrackBuilder, p_laps: int) -> void:
	track = p_track
	total_laps = p_laps
	CHECKPOINT_COUNT  # documented constant; the gate count comes from the track
	_connect_gates()


func _connect_gates() -> void:
	if track == null:
		return
	var root := track.get_node_or_null("Checkpoints")
	if root == null:
		push_error("LapTracker: the track has no Checkpoints node")
		return
	for child in root.get_children():
		if child is Area3D:
			var area := child as Area3D
			area.body_entered.connect(_on_gate_entered.bind(int(area.get_meta("checkpoint_index", -1))))


func register_car(car: Car) -> void:
	if car in cars:
		return
	cars.append(car)
	_progress[car] = 1                    # gate 0 is the finish line, already passed
	_laps_done[car] = 0
	_lap_started[car] = Time.get_ticks_msec()
	_lap_times[car] = []
	_best_lap[car] = INF
	_finished[car] = false
	_last_gate_ms[car] = -1
	_last_gate_index[car] = -1
	_total_progress[car] = 0.0


func unregister_car(car: Car) -> void:
	cars.erase(car)
	_progress.erase(car)
	_laps_done.erase(car)
	_lap_started.erase(car)
	_lap_times.erase(car)
	_best_lap.erase(car)
	_finished.erase(car)
	_last_gate_ms.erase(car)
	_last_gate_index.erase(car)
	_total_progress.erase(car)


func reset() -> void:
	for car in cars:
		_progress[car] = 1
		_laps_done[car] = 0
		_lap_started[car] = Time.get_ticks_msec()
		_lap_times[car] = []
		_best_lap[car] = INF
		_finished[car] = false
		_last_gate_ms[car] = -1
		_last_gate_index[car] = -1
		_total_progress[car] = 0.0
	_running = false


func start() -> void:
	reset()
	_running = true
	_race_started_ms = Time.get_ticks_msec()
	for car in cars:
		_lap_started[car] = _race_started_ms


func stop() -> void:
	_running = false


func is_running() -> bool:
	return _running


# ---------------------------------------------------------------------------
# gate handling
# ---------------------------------------------------------------------------

func _on_gate_entered(body: Node3D, index: int) -> void:
	if not _running or index < 0:
		return
	var car := _as_car(body)
	if car == null or not _progress.has(car):
		return
	if bool(_finished.get(car, false)):
		return

	# Debounce only a repeat of the *same* gate. A car sliding along a trigger
	# can emit several body_entered events; different gates are far apart in time
	# and must never be suppressed.
	var now := Time.get_ticks_msec()
	var last_index := int(_last_gate_index.get(car, -1))
	var last_ms := int(_last_gate_ms.get(car, -1))
	if index == last_index and last_ms >= 0 and now - last_ms < 400:
		return

	var expected := int(_progress[car])
	if index == 0:
		# Finish line. Only valid when the whole checkpoint chain is complete.
		if expected >= CHECKPOINT_COUNT:
			_mark_gate(car, index, now)
			_complete_lap(car)
		return

	if index != expected:
		# Wrong gate, or a gate already passed: ignore it entirely. This is
		# what stops reversing or loitering from advancing the lap counter.
		return

	_mark_gate(car, index, now)
	_progress[car] = expected + 1
	_update_progress(car)
	standings_changed.emit()


func _mark_gate(car: Car, index: int, now: int) -> void:
	_last_gate_index[car] = index
	_last_gate_ms[car] = now


func _complete_lap(car: Car) -> void:
	var now := Time.get_ticks_msec()
	var lap_time := float(now - int(_lap_started[car])) / 1000.0
	_lap_started[car] = now
	_progress[car] = 1

	var times: Array = _lap_times[car]
	times.append(lap_time)
	_lap_times[car] = times
	if lap_time < float(_best_lap[car]):
		_best_lap[car] = lap_time
	_laps_done[car] = int(_laps_done[car]) + 1
	_update_progress(car)

	var laps := int(_laps_done[car])
	# Keep the car's own lap state in sync. The HUD reads car.best_lap and
	# car.current_lap, so leaving them untouched would show "no lap time" even
	# though the tracker had recorded every lap.
	car.current_lap = laps + 1
	car.lap_times.append(lap_time)
	if lap_time < car.best_lap:
		car.best_lap = lap_time
	if laps >= total_laps:
		car.finished = true
		car.finish_time = race_elapsed()

	lap_completed.emit(car, laps, lap_time)
	standings_changed.emit()

	if laps >= total_laps:
		_finished[car] = true
		var result := {
			"car": car,
			"name": car.name,
			"laps": laps,
			"best_lap": float(_best_lap[car]),
			"total_time": float(car.finish_time) if car.finish_time > 0.0 else race_elapsed(),
			"lap_times": times.duplicate(),
			"is_player": car.is_player,
			"car_id": car.car_id,
		}
		car_finished.emit(car, result)


func race_elapsed() -> float:
	"""Seconds since the race started, used when a car did not stamp its own time."""
	if _race_started_ms <= 0:
		return 0.0
	return float(Time.get_ticks_msec() - _race_started_ms) / 1000.0


func _as_car(node: Node3D) -> Car:
	if node is Car:
		return node
	var parent := node.get_parent()
	while parent != null:
		if parent is Car:
			return parent
		parent = parent.get_parent()
	return null


func _update_progress(car: Car) -> void:
	var expected := int(_progress[car])
	var laps := int(_laps_done[car])
	var within := float(expected - 1) / float(CHECKPOINT_COUNT)
	_total_progress[car] = float(laps) + within


# ---------------------------------------------------------------------------
# queries
# ---------------------------------------------------------------------------

func laps_done(car: Car) -> int:
	return int(_laps_done.get(car, 0))


func best_lap(car: Car) -> float:
	return float(_best_lap.get(car, INF))


func lap_times(car: Car) -> Array:
	return _lap_times.get(car, [])


func has_finished(car: Car) -> bool:
	return bool(_finished.get(car, false))


func current_lap_number(car: Car) -> int:
	return clampi(int(_laps_done.get(car, 0)) + 1, 1, total_laps)


func progress_of(car: Car) -> float:
	return float(_total_progress.get(car, 0.0))


func standings() -> Array:
	"""Cars ordered by race position: laps first, then progress within the lap."""
	var sorted := cars.duplicate()
	sorted.sort_custom(func(a, b):
		var fa := bool(_finished.get(a, false))
		var fb := bool(_finished.get(b, false))
		if fa != fb:
			return fa
		if fa and fb:
			return a.finish_time < b.finish_time
		var pa := progress_of(a)
		var pb := progress_of(b)
		if absf(pa - pb) > 0.0005:
			return pa > pb
		# Tie on the same gate: the car that has been running longer is ahead.
		return float(_lap_started.get(a, 0)) < float(_lap_started.get(b, 0))
	)
	return sorted


func position_of(car: Car) -> int:
	var order := standings()
	for i in order.size():
		if order[i] == car:
			return i + 1
	return order.size()
