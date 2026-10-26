extends Node
## Runtime test harness.
##
## Run:  godot --headless --path . res://scenes/tools/TestHarness.tscn
##
## This is the executable part of the test suite: it builds every circuit, runs
## a real physics-driven AI race, exercises the lap rules, and checks the
## network code paths. It exits with code 0 only when everything passes.
##
## What it does NOT do: run two devices over a real Wi-Fi link. That needs two
## phones and is reported as NOT TESTED in TEST_REPORT.md.

const AI_RACE_SECONDS := 150.0
const REQUIRED_LAPS := 2

var _failures: Array[String] = []
var _passes: int = 0

var _phase: String = "geometry"
var _elapsed: float = 0.0

var _track: TrackBuilder
var _car: Car
var _ai: AIDriver
var _tracker: LapTracker
var _max_speed_seen: float = 0.0


func _ready() -> void:
	print("=== GFX Offline Racing : runtime tests ===")
	_test_track_geometry()
	_test_lap_rules()
	_test_net_state_roundtrip()
	_start_ai_race()


# ---------------------------------------------------------------------------
# 1. geometry
# ---------------------------------------------------------------------------

func _test_track_geometry() -> void:
	print("\n[geometry]")
	for id in TrackData.ORDER:
		var t := TrackBuilder.new()
		t.name = "TrackCheck"
		add_child(t)
		t.build(id)

		var n := t.centerline.size()
		if n < 120:
			_fail("%s centreline too short (%d samples)" % [id, n])
		else:
			_pass("%s centreline: %d samples, %.0f m" % [id, n, t.length])

		var gap := t.centerline[n - 1].distance_to(t.centerline[0])
		if gap > t.spacing * 2.5:
			_fail("%s loop does not close (gap %.2f m)" % [id, gap])

		# A fold in the centreline would put two distant samples on top of each
		# other and break checkpoint ordering, so check for it explicitly.
		var width := float(t.track["width"])
		var worst := INF
		var worst_pair := ""
		var step := 4
		for i in range(0, n, step):
			for j in range(i + 40, n, step):
				if (n - j) + i < 40:
					continue
				var d := t.centerline[i].distance_to(t.centerline[j])
				if d < worst:
					worst = d
					worst_pair = "%d/%d" % [i, j]
		if worst < width * 0.9:
			_fail("%s centreline folds onto itself: %.2f m at %s (road is %.1f m wide)" % [id, worst, worst_pair, width])
		else:
			_pass("%s no self-intersection (closest approach %.1f m)" % [id, worst])

		var gates := t.get_node_or_null("Checkpoints")
		var gate_count := 0
		if gates != null:
			for c in gates.get_children():
				if c is Area3D:
					gate_count += 1
		if gate_count != TrackData.CHECKPOINTS:
			_fail("%s has %d checkpoints, expected %d" % [id, gate_count, TrackData.CHECKPOINTS])
		else:
			_pass("%s %d checkpoints in order" % [id, gate_count])

		var has_ground := t.get_node_or_null("GroundBody") != null
		var has_barrier := t.get_node_or_null("BarrierBody") != null
		if not (has_ground and has_barrier):
			_fail("%s missing collision bodies (ground=%s barrier=%s)" % [id, has_ground, has_barrier])
		else:
			_pass("%s ground + barrier collision present" % id)

		if t.racing_line.size() < 100:
			_fail("%s racing line too short" % id)
		else:
			_pass("%s racing line: %d points" % [id, t.racing_line.size()])

		t.queue_free()


# ---------------------------------------------------------------------------
# 2. lap rules (the exact 12-lap requirement)
# ---------------------------------------------------------------------------

func _test_lap_rules() -> void:
	print("\n[lap rules]")
	var t := TrackBuilder.new()
	t.name = "LapTrack"
	add_child(t)
	t.build("city_circuit")

	var tracker := LapTracker.new()
	tracker.name = "LapTrackerTest"
	add_child(tracker)
	tracker.setup(t, 12)

	var car := Car.new()
	car.name = "LapCar"
	car.is_player = true
	car.car_id = "car_speedster"
	car.total_laps = 12
	add_child(car)
	car.global_position = t.centerline[0] + Vector3.UP
	tracker.register_car(car)
	tracker.start()

	# (a) a full clean lap requires every checkpoint in order
	for i in range(1, TrackData.CHECKPOINTS):
		tracker._on_gate_entered(car, i)
	tracker._on_gate_entered(car, 0)
	if tracker.laps_done(car) == 1:
		_pass("ordered checkpoints + finish line = 1 lap")
	else:
		_fail("clean lap not counted (got %d)" % tracker.laps_done(car))

	# (b) driving backwards over the finish line must not add a lap
	var before := tracker.laps_done(car)
	tracker._on_gate_entered(car, 0)
	tracker._on_gate_entered(car, 0)
	if tracker.laps_done(car) == before:
		_pass("finish line re-entry without checkpoints adds no lap")
	else:
		_fail("finish line inflated the lap count")

	# (c) out-of-order checkpoints are ignored
	tracker._on_gate_entered(car, 5)
	if tracker.laps_done(car) == before:
		_pass("out-of-order checkpoint ignored")
	else:
		_fail("out-of-order checkpoint advanced the lap")

	# (d) skipping part of the chain must not complete a lap
	for i in range(1, TrackData.CHECKPOINTS - 2):
		tracker._on_gate_entered(car, i)
	tracker._on_gate_entered(car, 0)
	if tracker.laps_done(car) == before:
		_pass("incomplete checkpoint chain blocks the finish line")
	else:
		_fail("finish line accepted an incomplete chain")

	# (e) exactly 12 laps finishes the race, and not one lap sooner
	var finished_at := -1
	for lap in range(1, 14):
		for i in range(1, TrackData.CHECKPOINTS):
			tracker._on_gate_entered(car, i)
		tracker._on_gate_entered(car, 0)
		if tracker.has_finished(car) and finished_at == -1:
			finished_at = tracker.laps_done(car)
	if finished_at == 12:
		_pass("race finishes on exactly lap 12")
	else:
		_fail("race finished at lap %d (expected 12)" % finished_at)
	if tracker.laps_done(car) == 12:
		_pass("lap counter stops at 12 after finishing")
	else:
		_fail("lap counter continued past 12 (got %d)" % tracker.laps_done(car))

	# (f) standings order by progress
	var car2 := Car.new()
	car2.name = "LapCar2"
	car2.car_id = "car_phantom"
	car2.total_laps = 12
	add_child(car2)
	car2.global_position = t.centerline[10] + Vector3.UP
	tracker.register_car(car2)
	tracker.start()
	car2.reset_race_state()
	for i in range(1, 5):
		tracker._on_gate_entered(car2, i)
	var order := tracker.standings()
	if order.size() == 2 and order[0] == car2:
		_pass("standings put the further-along car first")
	else:
		_fail("standings order wrong: %s" % str(order.map(func(c): return c.name)))

	t.queue_free()


# ---------------------------------------------------------------------------
# 3. network payload round trip
# ---------------------------------------------------------------------------

func _test_net_state_roundtrip() -> void:
	print("\n[network]")
	# Net.push_car_state is a no-op offline, so exercise the serialisation and
	# apply path directly: that is the code that runs on the receiving device.
	var t := TrackBuilder.new()
	t.name = "NetTrack"
	add_child(t)
	t.build("forest_track")

	var car := Car.new()
	car.name = "NetCar"
	car.car_id = "car_viper"
	add_child(car)
	car.global_position = t.centerline[20] + Vector3.UP
	car.linear_velocity = Vector3(12, 0, -4)
	car.gear = 4
	car.rpm = 5200.0
	car.drifting_now = true

	var state := car.get_net_state()
	var keys := ["p", "y", "v", "g", "r", "d"]
	var missing: Array[String] = []
	for k in keys:
		if not state.has(k):
			missing.append(k)
	if missing.is_empty():
		_pass("car state payload has all fields (%s)" % ", ".join(keys))
	else:
		_fail("car state missing fields: %s" % ", ".join(missing))

	var mirror := Car.new()
	mirror.name = "MirrorCar"
	mirror.car_id = "car_viper"
	add_child(mirror)
	mirror.set_remote(true)
	mirror.apply_net_state(state)
	if mirror.gear == 4 and absf(mirror.rpm - 5200.0) < 0.01 and mirror.drifting_now:
		_pass("received state applies gear/rpm/drift correctly")
	else:
		_fail("state apply mismatch: gear=%d rpm=%.0f drift=%s" % [mirror.gear, mirror.rpm, mirror.drifting_now])

	if not mirror.controls_enabled:
		_pass("remote car rejects local control")
	else:
		_fail("remote car still accepts local control")

	if not Net.is_online() and not Net.is_host():
		_pass("Net reports offline state correctly before any room exists")
	else:
		_fail("Net reports an online state with no peer")

	t.queue_free()


# ---------------------------------------------------------------------------
# 4. live AI race
# ---------------------------------------------------------------------------

func _start_ai_race() -> void:
	print("\n[ai race]")
	_phase = "race"
	_elapsed = 0.0

	_track = TrackBuilder.new()
	_track.name = "RaceTrack"
	add_child(_track)
	_track.build("city_circuit")

	_tracker = LapTracker.new()
	_tracker.name = "RaceLapTracker"
	add_child(_tracker)
	_tracker.setup(_track, 12)

	_car = Car.new()
	_car.name = "TestPlayer"
	_car.is_player = true
	_car.car_id = "car_speedster"
	_car.total_laps = 12
	add_child(_car)
	var grid := _track.grid_transform(0, 2)
	_car.reset_position = grid.origin
	_car.reset_basis = grid.basis
	_car.reset_to(grid.origin, grid.basis)
	_tracker.register_car(_car)
	_tracker.start()

	# Drive the player car with the AI so the test is deterministic and does not
	# depend on a human being present.
	_ai = AIDriver.new()
	_ai.name = "TestAIDriver"
	add_child(_ai)
	_ai.setup(_car, _track, AIDriver.Difficulty.NORMAL, 4242)


func _physics_process(delta: float) -> void:
	if _phase != "race":
		return
	_elapsed += delta
	_max_speed_seen = maxf(_max_speed_seen, _car.speed_kmh)

	if _elapsed < AI_RACE_SECONDS:
		return

	_phase = "done"
	var laps := _tracker.laps_done(_car)
	if laps >= REQUIRED_LAPS:
		_pass("AI completed %d laps in %.0f s (>= %d required)" % [laps, AI_RACE_SECONDS, REQUIRED_LAPS])
	else:
		_fail("AI only completed %d laps in %.0f s" % [laps, AI_RACE_SECONDS])

	if _max_speed_seen <= Car.MAX_SPEED_KMH + 0.5:
		_pass("speed stayed within the 200 km/h limit (peak %.1f km/h)" % _max_speed_seen)
	else:
		_fail("speed exceeded 200 km/h (peak %.1f)" % _max_speed_seen)

	if _max_speed_seen > 80.0:
		_pass("car reached racing speed (peak %.1f km/h)" % _max_speed_seen)
	else:
		_fail("car never reached racing speed (peak %.1f km/h) - physics or AI is stuck" % _max_speed_seen)

	var off := _track.nearest_distance_to_centerline(_car.global_position)
	if off < float(_track.track["width"]) * 1.5:
		_pass("car stayed near the circuit (%.1f m from centreline)" % off)
	else:
		_fail("car left the circuit (%.1f m from centreline)" % off)

	if _car.best_lap > 0.0 and _car.best_lap < 999.0:
		_pass("lap timing works (best lap %.2f s)" % _car.best_lap)
	else:
		_fail("no valid lap time recorded")

	_finish()


# ---------------------------------------------------------------------------
# reporting
# ---------------------------------------------------------------------------

func _pass(msg: String) -> void:
	_passes += 1
	print("  PASS  %s" % msg)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("  FAIL  %s" % msg)


func _finish() -> void:
	print("\n=== summary ===")
	print("passed : %d" % _passes)
	print("failed : %d" % _failures.size())
	if not _failures.is_empty():
		print("\nFAILURES")
		for f in _failures:
			print("  - %s" % f)
	print("\nRESULT: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	get_tree().quit(0 if _failures.is_empty() else 1)
