class_name RaceManager
extends Node3D
## Owns one race: builds the circuit, spawns cars, runs the countdown, keeps
## score, and decides the winner.
##
## Modes
##   SOLO   one player, no opponents
##   AI     one player plus N AI drivers
##   HOST   LAN host: local player + one remote player, host validates results
##   CLIENT LAN client: local player only, state mirrored from the host
##
## The host is the only node that declares a winner. A client reports progress
## through Net.push_lap() and Net.host_report_finish() is never reachable from
## a client because it returns early when Net.is_host() is false.

signal countdown_tick(value: int)
signal race_started()
signal race_finished(results: Array)
signal lap_changed(car: Car, lap: int, lap_time: float)
signal paused_changed(paused: bool)

enum Mode { SOLO, AI, HOST, CLIENT }

const COUNTDOWN_SECONDS := 3

var mode: Mode = Mode.AI
var track_id: String = "city_circuit"
var difficulty: String = "normal"
var total_laps: int = 12
var ai_count: int = 3

var track: TrackBuilder
var lap_tracker: LapTracker
var player_car: Car
var cars: Array[Car] = []

var race_time: float = 0.0
var running: bool = false
var countdown: float = 0.0
var finished_results: Array = []

var _ai_drivers: Array[AIDriver] = []
var _remote_cars: Dictionary = {}      # peer id -> Car
var _state_send_accum: float = 0.0
var _camera: ChaseCamera
var _started_once: bool = false


# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------

func configure(p_mode: Mode, p_track_id: String, p_difficulty: String,
		p_laps: int, p_ai: int) -> void:
	mode = p_mode
	track_id = p_track_id
	difficulty = p_difficulty
	total_laps = p_laps
	ai_count = p_ai


func _ready() -> void:
	_build_track()
	_spawn_cars()
	_build_camera()
	_connect_net()
	_begin_countdown()


func _build_track() -> void:
	track = TrackBuilder.new()
	track.name = "Track"
	add_child(track)
	track.build(track_id)

	lap_tracker = LapTracker.new()
	lap_tracker.name = "LapTracker"
	add_child(lap_tracker)
	lap_tracker.setup(track, total_laps)
	lap_tracker.lap_completed.connect(_on_lap_completed)
	lap_tracker.car_finished.connect(_on_car_finished)


func _spawn_cars() -> void:
	var my_id := Net.my_id()
	var is_net := Net.is_online()

	# --- local player -----------------------------------------------------
	player_car = _make_car("Player", Settings.selected_car, Settings.paint_colour, true)
	var slot := 0
	var grid_total := 1 + (ai_count if mode == Mode.AI else 0) + (1 if is_net else 0)
	_place_on_grid(player_car, slot, grid_total)
	add_child(player_car)
	lap_tracker.register_car(player_car)
	player_car.lap_progress.connect(_on_player_lap)
	player_car.race_completed.connect(_on_player_completed)
	player_car.crashed.connect(_on_player_crash)

	# --- AI opponents -----------------------------------------------------
	if mode == Mode.AI:
		var spec: Array = Settings.CAR_SPECS
		for i in ai_count:
			var idx: int = (Settings.car_index(Settings.selected_car) + i + 1) % spec.size()
			var ai_car := _make_car("AI_%d" % (i + 1), spec[idx]["id"], spec[idx]["colour"], false)
			_place_on_grid(ai_car, i + 1, grid_total)
			add_child(ai_car)
			lap_tracker.register_car(ai_car)
			ai_car.race_completed.connect(_on_car_finished_signal)

			var driver := AIDriver.new()
			driver.name = "AIDriver%d" % (i + 1)
			add_child(driver)
			driver.setup(ai_car, track, AIDriver.from_string(difficulty), hash(track_id) + i * 7919)
			_ai_drivers.append(driver)
			cars.append(ai_car)

	# --- LAN: existing peers become remote cars ---------------------------
	if is_net:
		for id in Net.player_ids():
			if id == my_id:
				continue
			_spawn_remote_car(id, grid_total)

	cars.push_front(player_car)


func _make_car(node_name: String, car_id: String, colour: Color, is_player: bool) -> Car:
	var car := Car.new()
	car.name = node_name
	car.car_id = car_id
	car.is_player = is_player
	car.total_laps = total_laps
	car.set_meta("colour", colour)
	car.configure(car_id)
	car.set_colour(colour)
	return car


func _place_on_grid(car: Car, slot: int, total: int) -> void:
	var t := track.grid_transform(slot, total)
	# Start slightly above the surface so the first physics step settles the car
	# instead of resolving an initial overlap with the ground.
	t.origin += Vector3.UP * 0.35
	car.reset_position = t.origin
	car.reset_basis = t.basis
	car.transform = t


func _spawn_remote_car(peer_id: int, grid_total: int) -> void:
	if _remote_cars.has(peer_id):
		return
	var info := Net.get_player(peer_id)
	var car_id := str(info.get("car_id", "car_speedster"))
	var colour: Color = info.get("colour", Color(0.85, 0.85, 0.9))
	var car := _make_car("Remote_%d" % peer_id, car_id, colour, false)
	_place_on_grid(car, _remote_cars.size() + 1, grid_total)
	add_child(car)
	car.set_remote(true)
	lap_tracker.register_car(car)
	car.race_completed.connect(_on_car_finished_signal)
	_remote_cars[peer_id] = car
	cars.append(car)


func _build_camera() -> void:
	_camera = ChaseCamera.new()
	_camera.name = "ChaseCamera"
	add_child(_camera)
	_camera.set_target(player_car)
	_camera.current = true
	player_car.crashed.connect(func(speed: float): _camera.add_shake(clampf(speed / 40.0, 0.05, 0.6)))


# ---------------------------------------------------------------------------
# networking
# ---------------------------------------------------------------------------

func _connect_net() -> void:
	if not Net.is_online():
		return
	Net.car_state_received.connect(_on_net_car_state)
	Net.lap_received.connect(_on_net_lap)
	Net.race_finished_received.connect(_on_net_finish)
	Net.race_restart_received.connect(_on_net_restart)
	Net.peer_joined.connect(_on_net_peer_joined)
	Net.peer_left.connect(_on_net_peer_left)
	Net.countdown_received.connect(_on_net_countdown)
	Net.host_left.connect(_on_net_host_left)
	Net.connection_lost.connect(_on_net_host_left)


func _process(delta: float) -> void:
	if countdown > 0.0:
		var previous := int(ceil(countdown))
		countdown -= delta
		var now := int(ceil(countdown))
		if now != previous and now >= 0:
			countdown_tick.emit(now)
			if now > 0:
				Audio.play("countdown", -6.0)
			else:
				Audio.play("countdown_go", -4.0)
		if countdown <= 0.0:
			_start_race()
		return

	if running:
		race_time += delta
		_send_state(delta)


func _begin_countdown() -> void:
	countdown = float(COUNTDOWN_SECONDS) + 0.9
	countdown_tick.emit(int(ceil(countdown)))


func _start_race() -> void:
	countdown = 0.0
	running = true
	race_time = 0.0
	lap_tracker.start()
	_started_once = true
	for car in cars:
		car.controls_enabled = true
	race_started.emit()


func _send_state(delta: float) -> void:
	if not Net.is_online():
		return
	_state_send_accum += delta
	var interval := 1.0 / Net.STATE_HZ
	if _state_send_accum < interval:
		return
	_state_send_accum = 0.0
	Net.push_car_state(player_car.get_net_state())


func _on_net_car_state(id: int, state: Dictionary) -> void:
	var car: Car = _remote_cars.get(id)
	if car == null:
		_spawn_remote_car(id, cars.size() + 1)
		car = _remote_cars.get(id)
	if car != null:
		car.apply_net_state(state)


func _on_net_peer_joined(id: int, _info: Dictionary) -> void:
	if mode != Mode.HOST:
		return
	_spawn_remote_car(id, cars.size() + 1)


func _on_net_peer_left(id: int) -> void:
	var car: Car = _remote_cars.get(id)
	if car == null:
		return
	lap_tracker.unregister_car(car)
	cars.erase(car)
	_remote_cars.erase(id)
	car.queue_free()


func _on_net_countdown(start_at: float, laps: int) -> void:
	# Clients mirror the host's countdown so both devices start together.
	total_laps = laps
	for car in cars:
		car.total_laps = laps
	var now := float(Time.get_ticks_msec()) / 1000.0
	countdown = maxf(0.4, start_at - now + float(COUNTDOWN_SECONDS))
	lap_tracker.total_laps = laps


func _on_net_lap(id: int, lap: int) -> void:
	var car: Car = _remote_cars.get(id)
	if car != null:
		lap_changed.emit(car, lap, 0.0)


func _on_net_finish(results: Array) -> void:
	# Clients display whatever the host decided; they never compute a winner.
	finished_results = results
	running = false
	_show_results(results)


func _on_net_restart() -> void:
	restart_race()


func _on_net_host_left() -> void:
	running = false
	countdown = 0.0
	for car in cars:
		car.controls_enabled = false
	finished_results = []
	# A client cannot host, so it goes back to the lobby with a clear message.
	if mode == Mode.CLIENT:
		SceneRouter.go_to("lobby", {"message": "The host closed the room."})


# ---------------------------------------------------------------------------
# race events
# ---------------------------------------------------------------------------

func _on_player_lap(lap: int, lap_time: float) -> void:
	# Report progress to the host. The host re-validates before it counts, so a
	# client cannot inflate its own lap total.
	if Net.is_online():
		Net.push_lap(lap, lap_time)


func _on_lap_completed(car: Car, lap: int, lap_time: float) -> void:
	if lap < total_laps:
		Audio.play("checkpoint", -8.0)
	lap_changed.emit(car, lap, lap_time)


func _on_player_completed(_result: Dictionary) -> void:
	pass


func _on_car_finished_signal(_result: Dictionary) -> void:
	pass


func _on_car_finished(car: Car, result: Dictionary) -> void:
	if not Net.is_online() or Net.is_host():
		_register_finish(car, result)


func _register_finish(car: Car, result: Dictionary) -> void:
	for r in finished_results:
		if r.get("car") == car:
			return
	var entry := result.duplicate()
	entry["position"] = finished_results.size() + 1
	entry["total_time"] = race_time
	entry["is_player"] = car.is_player
	entry["car_id"] = car.car_id
	entry["car_node"] = car
	finished_results.append(entry)

	if Net.is_online() and Net.is_host():
		var net_entry := entry.duplicate()
		net_entry.erase("car_node")
		net_entry.erase("car")
		Net.host_report_finish(Net.my_id() if car.is_player else _peer_of(car), net_entry)

	if car.is_player or finished_results.size() >= cars.size():
		running = false
		_show_results(finished_results)


func _peer_of(car: Car) -> int:
	for id in _remote_cars:
		if _remote_cars[id] == car:
			return id
	return 0


func _on_player_crash(_speed: float) -> void:
	pass


func _show_results(results: Array) -> void:
	Audio.stop_music()
	Audio.play("victory", -4.0)
	race_finished.emit(results)


# ---------------------------------------------------------------------------
# pause / restart
# ---------------------------------------------------------------------------

func set_paused(value: bool) -> void:
	get_tree().paused = value
	paused_changed.emit(value)


func restart_race() -> void:
	if Net.is_online() and not Net.is_host():
		# A client cannot restart alone; the host owns race state.
		return
	if Net.is_online() and Net.is_host():
		Net.host_restart_race()
	get_tree().paused = false
	finished_results.clear()
	race_time = 0.0
	running = false

	for i in cars.size():
		var car := cars[i]
		car.reset_race_state()
		_place_on_grid(car, i, cars.size())
		car.reset_to(car.reset_position, car.reset_basis)
		lap_tracker.reset()
	lap_tracker.start()
	_begin_countdown()


func standings() -> Array:
	return lap_tracker.standings()
