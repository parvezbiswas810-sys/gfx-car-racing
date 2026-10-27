class_name Car
extends RigidBody3D
## Arcade vehicle controller.
##
## Deliberately not a VehicleBody3D: a rigid body with locked roll/pitch plus a
## hand-written traction model is stable on a phone, is fully deterministic for
## the lap logic, and lets drifting be tuned directly instead of fought.
##
## The body is locked around X and Z so the car can never flip; only yaw is
## free, which is what an arcade racer wants and removes a whole class of
## physics explosions.

signal crashed(impact_speed: float)
signal lap_progress(lap: int, lap_time: float)
signal gear_changed(gear: int)
signal race_completed(result: Dictionary)

const MAX_SPEED_KMH := 200.0
const MAX_SPEED_MS := MAX_SPEED_KMH / 3.6
const REVERSE_SPEED_MS := 12.0
const WHEEL_RADIUS := 0.34

# Gear ratios (index 0 is reverse). Top of 6th gear maps to MAX_SPEED_MS.
const GEAR_RATIOS := [3.4, 3.6, 2.5, 1.85, 1.45, 1.15, 0.92]
const IDLE_RPM := 900.0
const MAX_RPM := 7800.0
const SHIFT_RPM_UP := 6900.0
const SHIFT_RPM_DOWN := 2600.0

@export var is_player: bool = true
@export var car_id: String = "car_speedster"

# --- control inputs, written every frame by a controller -------------------
var throttle: float = 0.0
var brake_input: float = 0.0
var steer_input: float = 0.0
var drifting: bool = false
var manual_gear: int = 0          # 0 = automatic

# --- live state -----------------------------------------------------------
var gear: int = 1
var rpm: float = IDLE_RPM
var speed_kmh: float = 0.0
var forward_speed: float = 0.0
var drifting_now: bool = false
var crash_cooldown: float = 0.0
var controls_enabled: bool = true
var reset_position: Vector3 = Vector3.ZERO
var reset_basis: Basis = Basis.IDENTITY

# --- stats, filled from Settings.CARS ------------------------------------
var stat_speed: float = 0.86
var stat_accel: float = 0.84
var stat_handling: float = 0.72
var stat_braking: float = 0.70

var _body_mesh: MeshInstance3D
var _wheels: Array[MeshInstance3D] = []
var _steer_pivots: Array[Node3D] = []
var _wheel_spin: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _skid: SkidTrail
var _smoke: CPUParticles3D
var _engine_player: AudioStreamPlayer
var _skid_player: AudioStreamPlayer
var _half_length: float = 2.15
var _half_track: float = 0.86
var _wheelbase: float = 2.55

# Remote interpolation target, used when this car is driven by another peer.
var _net_target_pos := Vector3.ZERO
var _net_target_yaw := 0.0
var _net_interp: float = 0.0
var _is_remote: bool = false


func _ready() -> void:
	# Lock roll and pitch: keeps the car flat and the physics solver happy.
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	gravity_scale = 1.0
	mass = 1150.0
	linear_damp = 0.06
	angular_damp = 2.2
	continuous_cd = true
	collision_layer = 2
	collision_mask = 1 | 2
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4

	_apply_stats()
	_build_body()
	_build_wheels()
	_build_effects()
	_build_audio()

	body_entered.connect(_on_body_entered)


func configure(id: String) -> void:
	car_id = id
	if is_inside_tree():
		_apply_stats()
		_refresh_meshes()


func _apply_stats() -> void:
	var spec := Settings.car_by_id(car_id)
	stat_speed = float(spec.get("speed", 0.86))
	stat_accel = float(spec.get("accel", 0.84))
	stat_handling = float(spec.get("handling", 0.72))
	stat_braking = float(spec.get("braking", 0.70))


func set_remote(value: bool) -> void:
	_is_remote = value
	controls_enabled = not value
	if value:
		freeze = false


func set_colour(colour: Color) -> void:
	if _body_mesh == null:
		return
	var mesh: Mesh = _body_mesh.mesh
	if mesh == null:
		return
	# Use per-instance surface overrides: the mesh resource is shared between
	# every car that loads the same model, so writing into the mesh's own
	# materials would repaint all of them at once.
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat is StandardMaterial3D:
			var mat_name := mat.resource_name
			if mat_name == "" or mat_name.to_lower().contains("body"):
				var copy: StandardMaterial3D = mat.duplicate()
				copy.albedo_color = colour
				_body_mesh.set_surface_override_material(s, copy)


# ---------------------------------------------------------------------------
# construction
# ---------------------------------------------------------------------------

func _build_body() -> void:
	# All grip is modelled in code, so the engine's own contact friction must be
	# almost zero. Left at the default 1.0 it silently eats most of the engine
	# force and caps the car far below its top speed.
	var mat := PhysicsMaterial.new()
	mat.friction = 0.02
	mat.bounce = 0.0
	mat.rough = true
	physics_material_override = mat

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var box := BoxShape3D.new()
	box.size = Vector3(_half_track * 2.0, 0.85, _half_length * 2.0)
	shape.shape = box
	shape.position = Vector3(0, 0.42, 0)
	add_child(shape)

	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	add_child(_body_mesh)
	_refresh_meshes()

	# The rigid body's origin sits at the bottom of the collision box, so a ray
	# cast from the origin would start level with the road and never register a
	# hit. Start above the roof and cast down past the wheels instead.
	var probe := RayCast3D.new()
	probe.name = "GroundProbe"
	probe.position = Vector3(0, 0.6, 0)
	probe.target_position = Vector3(0, -1.3, 0)
	probe.collision_mask = 1
	probe.enabled = true
	add_child(probe)


func _refresh_meshes() -> void:
	var spec := Settings.car_by_id(car_id)
	var model_path := str(spec.get("model", ""))
	if _body_mesh != null:
		var mesh := _mesh_from_glb(model_path)
		if mesh != null:
			_body_mesh.mesh = mesh
			var specs := _load_car_specs()
			if specs.has(car_id):
				var s: Dictionary = specs[car_id]
				_half_length = float(s["half_length"])
				_half_track = float(s["half_track"])
				_wheelbase = float(s["wheelbase"])
	set_colour(Settings.paint_colour)


## Extracts the first mesh out of a GLB. Godot imports .glb as a PackedScene
## (a node tree), not as a Mesh resource, so assigning it straight to
## MeshInstance3D.mesh would fail at runtime.
static func _mesh_from_glb(path: String) -> Mesh:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var packed = load(path)
	if packed is Mesh:
		return packed
	if packed is PackedScene:
		var root := (packed as PackedScene).instantiate()
		var found := _find_first_mesh(root)
		root.free()
		return found
	return null


static func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var m := (node as MeshInstance3D).mesh
		if m != null:
			return m
	for child in node.get_children():
		var m := _find_first_mesh(child)
		if m != null:
			return m
	return null


## Used when a car model is missing from disk so the game still runs.
static func _fallback_wheel_mesh() -> Mesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.33
	cyl.bottom_radius = 0.33
	cyl.height = 0.24
	cyl.radial_segments = 16
	cyl.rings = 1
	return cyl


func _load_car_specs() -> Dictionary:
	var out := {}
	var path := "res://assets/models/car_specs.json"
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_ARRAY:
		return out
	for entry in parsed:
		out[str(entry["id"])] = entry
	return out


func _build_wheels() -> void:
	var wheel_mesh: Mesh = _mesh_from_glb("res://assets/models/wheel.glb")
	if wheel_mesh == null:
		wheel_mesh = _fallback_wheel_mesh()
	for i in 4:
		var front := i < 2
		var left := i % 2 == 0
		var pivot := Node3D.new()
		pivot.name = "WheelPivot%d" % i
		add_child(pivot)
		var mi := MeshInstance3D.new()
		mi.name = "Wheel%d" % i
		mi.mesh = wheel_mesh
		pivot.add_child(mi)
		_wheels.append(mi)
		_steer_pivots.append(pivot)
		# Wheel mesh is modelled with its axis on X and rim facing +X.
		if not left:
			mi.rotation.y = PI
		mi.position = Vector3(0, 0, 0)


func _update_wheel_placement() -> void:
	var positions := [
		Vector3(-_half_track * 0.92, WHEEL_RADIUS, _wheelbase * 0.5),
		Vector3(_half_track * 0.92, WHEEL_RADIUS, _wheelbase * 0.5),
		Vector3(-_half_track * 0.92, WHEEL_RADIUS, -_wheelbase * 0.5),
		Vector3(_half_track * 0.92, WHEEL_RADIUS, -_wheelbase * 0.5),
	]
	for i in _steer_pivots.size():
		_steer_pivots[i].position = positions[i]


func _build_effects() -> void:
	_skid = SkidTrail.new()
	_skid.name = "SkidTrail"
	add_child(_skid)

	_smoke = CPUParticles3D.new()
	_smoke.name = "TyreSmoke"
	_smoke.emitting = false
	_smoke.amount = 24
	_smoke.lifetime = 0.9
	_smoke.local_coords = false
	_smoke.direction = Vector3(0, 1, 0)
	_smoke.spread = 40.0
	_smoke.initial_velocity_min = 1.2
	_smoke.initial_velocity_max = 3.2
	_smoke.gravity = Vector3(0, 0.6, 0)
	_smoke.scale_amount_min = 0.6
	_smoke.scale_amount_max = 1.9
	_smoke.color = Color(0.86, 0.86, 0.90, 0.45)
	if ResourceLoader.exists("res://assets/textures/smoke.png"):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/textures/smoke.png")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.vertex_color_use_as_albedo = true
		_smoke.mesh = QuadMesh.new()
		_smoke.material_override = m
	add_child(_smoke)


func _build_audio() -> void:
	_engine_player = Audio.make_loop("engine", Audio.ENGINE_BUS)
	if _engine_player != null:
		_engine_player.volume_db = -14.0
		_engine_player.play()
	_skid_player = Audio.make_loop("skid", Audio.SFX)
	if _skid_player != null:
		_skid_player.volume_db = -80.0
		_skid_player.play()


# ---------------------------------------------------------------------------
# controls
# ---------------------------------------------------------------------------

func apply_controls(p_throttle: float, p_brake: float, p_steer: float, p_drift: bool) -> void:
	throttle = clampf(p_throttle, 0.0, 1.0)
	brake_input = clampf(p_brake, 0.0, 1.0)
	steer_input = clampf(p_steer, -1.0, 1.0)
	drifting = p_drift


func reset_to(pos: Vector3, basis: Basis) -> void:
	var t := Transform3D(basis, pos)
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	gear = 1
	rpm = IDLE_RPM
	crash_cooldown = 0.0
	apply_central_impulse(Vector3.ZERO)


func respawn_at_track() -> void:
	reset_to(reset_position, reset_basis)


# ---------------------------------------------------------------------------
# physics
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	crash_cooldown = maxf(0.0, crash_cooldown - delta)

	if _is_remote:
		_interpolate_remote(delta)
		_update_visuals(delta)
		return

	var basis := global_transform.basis
	var forward := -basis.z
	var right := basis.x

	forward_speed = linear_velocity.dot(forward)
	var lateral_speed := linear_velocity.dot(right)
	speed_kmh = absf(forward_speed) * 3.6

	var grounded := _is_grounded()
	var traction := 1.0 if grounded else 0.15

	if controls_enabled:
		_apply_drive(delta, forward, traction)
		_apply_steering(delta, forward_speed, traction)
		_apply_lateral_grip(delta, right, lateral_speed, grounded)
	else:
		# Idle: engine braking only.
		linear_velocity = linear_velocity.move_toward(Vector3.ZERO, 6.0 * delta)

	_update_gearbox(delta)
	_update_visuals(delta)
	_update_effects(delta, lateral_speed, grounded)


func _is_grounded() -> bool:
	var probe := get_node_or_null("GroundProbe") as RayCast3D
	if probe == null:
		return true
	return probe.is_colliding()


func _apply_drive(delta: float, forward: Vector3, traction: float) -> void:
	var engine_scale := 0.55 + 0.45 * stat_accel
	var power := 0.0

	if throttle > 0.01:
		# Torque curve: strong low down, tapering as the limiter approaches.
		var speed_ratio := clampf(absf(forward_speed) / MAX_SPEED_MS, 0.0, 1.0)
		var torque := 1.0 - pow(speed_ratio, 2.2)
		power = throttle * torque * 26000.0 * engine_scale * traction
		# Reverse is only reachable with no throttle input and the brake held.
	elif brake_input > 0.01:
		if forward_speed > 0.5:
			power = -brake_input * 30000.0 * (0.6 + 0.4 * stat_braking) * traction
		else:
			power = -brake_input * 14000.0 * engine_scale * traction

	if absf(power) > 0.01:
		apply_central_force(forward * power)

	# Hard ceiling so no combination of forces can pass 200 km/h downhill.
	if forward_speed > MAX_SPEED_MS:
		var excess := forward_speed - MAX_SPEED_MS
		apply_central_force(forward * -excess * 9000.0)
	elif forward_speed < -REVERSE_SPEED_MS:
		apply_central_force(forward * (-REVERSE_SPEED_MS - forward_speed) * 9000.0)

	# Drag and rolling resistance.
	var drag := 0.0016 * stat_speed
	apply_central_force(-linear_velocity * linear_velocity.length() * drag)
	if throttle < 0.01 and brake_input < 0.01:
		apply_central_force(-forward * forward_speed * 260.0)


func _apply_steering(delta: float, forward_speed_now: float, traction: float) -> void:
	if absf(steer_input) < 0.01:
		return
	# Steering authority falls off with speed so the car stays controllable at
	# 200 km/h instead of snapping into a spin.
	var speed_ratio := clampf(absf(forward_speed_now) / MAX_SPEED_MS, 0.0, 1.0)
	var authority := lerpf(1.0, 0.34, speed_ratio)
	var handling := 0.7 + 0.5 * stat_handling
	var direction := signf(forward_speed_now) if absf(forward_speed_now) > 0.4 else 1.0
	var yaw_rate := steer_input * authority * handling * 2.35 * direction * traction
	var sensitivity := Settings.control_sensitivity
	angular_velocity.y = lerpf(angular_velocity.y, yaw_rate * sensitivity, 0.35)


func _apply_lateral_grip(delta: float, right: Vector3, lateral_speed: float, grounded: bool) -> void:
	if not grounded:
		return
	var grip := 0.85 + 0.3 * stat_handling
	drifting_now = drifting and absf(forward_speed) > 8.0
	if drifting_now:
		grip *= 0.28
	# Treat grip as a decay rate: lateral velocity bleeds off with a time
	# constant of 1/(grip * RATE) seconds. Multiplying by mass turns the desired
	# acceleration into the force the solver needs, so the behaviour is
	# independent of the car's mass.
	const RATE := 6.0
	var accel := clampf(-lateral_speed * grip * RATE, -60.0, 60.0)
	apply_central_force(right * accel * mass)
	if absf(lateral_speed) > 3.0:
		# Slight yaw boost makes a drift feel like a drift rather than a slide.
		angular_velocity.y += -signf(lateral_speed) * 0.12 * delta * (6.0 if drifting_now else 1.0)


func _update_gearbox(delta: float) -> void:
	var ratio: float = GEAR_RATIOS[clampi(gear, 0, GEAR_RATIOS.size() - 1)]
	var wheel_rpm := absf(forward_speed) / (TAU * WHEEL_RADIUS) * 60.0
	var target_rpm: float = wheel_rpm * ratio
	if gear == 0:
		target_rpm = clampf(target_rpm, IDLE_RPM, MAX_RPM)
	else:
		target_rpm = clampf(target_rpm, IDLE_RPM, MAX_RPM)
	rpm = lerpf(rpm, target_rpm, 1.0 - pow(0.001, delta))

	if manual_gear > 0:
		if manual_gear != gear:
			gear = clampi(manual_gear, 0, GEAR_RATIOS.size() - 1)
			gear_changed.emit(gear)
		return

	# Automatic: upshift near the limiter, downshift when the revs drop.
	var previous := gear
	if gear >= 1 and rpm > SHIFT_RPM_UP and gear < GEAR_RATIOS.size() - 1:
		gear += 1
	elif gear > 1 and rpm < SHIFT_RPM_DOWN:
		gear -= 1
	elif gear == 1 and forward_speed < -1.0:
		gear = 0
	elif gear == 0 and forward_speed > 1.0:
		gear = 1
	if gear != previous:
		gear_changed.emit(gear)


func shift_up() -> void:
	manual_gear = clampi((gear if manual_gear == 0 else manual_gear) + 1, 1, GEAR_RATIOS.size() - 1)


func shift_down() -> void:
	manual_gear = clampi((gear if manual_gear == 0 else manual_gear) - 1, 0, GEAR_RATIOS.size() - 1)


func use_auto_gearbox() -> void:
	manual_gear = 0


# ---------------------------------------------------------------------------
# visuals
# ---------------------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	_update_wheel_placement()
	var steer_angle := -steer_input * 0.42
	for i in _steer_pivots.size():
		if i < 2:
			_steer_pivots[i].rotation.y = lerpf(_steer_pivots[i].rotation.y, steer_angle, 0.4)
		_wheel_spin[i] += (forward_speed / WHEEL_RADIUS) * delta
		_wheels[i].rotation.x = _wheel_spin[i]

	if _body_mesh != null:
		# Weight transfer: squat under power, dive under braking.
		var squat := clampf(throttle * 0.05 - brake_input * 0.06, -0.08, 0.06)
		_body_mesh.rotation.x = lerpf(_body_mesh.rotation.x, squat, 0.15)
		_body_mesh.rotation.z = lerpf(_body_mesh.rotation.z, -steer_input * 0.035, 0.15)


func _update_effects(delta: float, lateral_speed: float, grounded: bool) -> void:
	var slipping := grounded and (drifting_now or absf(lateral_speed) > 4.0
			or (throttle > 0.85 and absf(forward_speed) < 6.0 and speed_kmh > 0.5))
	if _smoke != null:
		var amount: float = Settings.preset()["smoke_amount"]
		_smoke.emitting = slipping and amount > 0.05
		# CPUParticles3D scales by particle count; amount_ratio only exists on
		# the GPU variant.
		_smoke.amount = maxi(4, int(round(24.0 * clampf(amount, 0.05, 1.0))))
	if _skid != null:
		if slipping and Settings.preset()["skid_marks"]:
			_skid.drop(_wheels[0].global_position, _wheels[1].global_position, delta)
		else:
			_skid.stop_dropping()

	if _skid_player != null:
		var target := -8.0 if slipping else -80.0
		_skid_player.volume_db = lerpf(_skid_player.volume_db, target, 0.2)
	if _engine_player != null:
		var rev := clampf(rpm / MAX_RPM, 0.0, 1.0)
		var target_pitch := 0.62 + rev * 1.55
		_engine_player.pitch_scale = lerpf(_engine_player.pitch_scale, target_pitch, 0.18)
		var target_db := -20.0 + rev * 9.0
		_engine_player.volume_db = lerpf(_engine_player.volume_db, target_db, 0.12)


# ---------------------------------------------------------------------------
# collisions
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node) -> void:
	if crash_cooldown > 0.0:
		return
	var impact := linear_velocity.length()
	if body is Car:
		impact = maxf(impact, (body as Car).linear_velocity.length())
	if impact < 6.0:
		return
	crash_cooldown = 0.5
	crashed.emit(impact)
	Audio.play("crash", -6.0 + clampf(impact / 30.0, 0.0, 1.0) * 6.0,
			randf_range(0.9, 1.1))
	if is_player:
		Audio.vibrate(int(clampf(impact * 2.0, 20.0, 120.0)))


# ---------------------------------------------------------------------------
# networking
# ---------------------------------------------------------------------------

func get_net_state() -> Dictionary:
	return {
		"p": global_position,
		"y": global_rotation.y,
		"v": linear_velocity,
		"g": gear,
		"r": rpm,
		"d": drifting_now,
	}


func apply_net_state(state: Dictionary) -> void:
	_net_target_pos = state.get("p", global_position)
	_net_target_yaw = float(state.get("y", global_rotation.y))
	var v: Vector3 = state.get("v", Vector3.ZERO)
	linear_velocity = v
	gear = int(state.get("g", gear))
	rpm = float(state.get("r", rpm))
	drifting_now = bool(state.get("d", false))
	_net_interp = 0.0


func _interpolate_remote(delta: float) -> void:
	var weight := clampf(delta * 12.0, 0.0, 1.0)
	global_position = global_position.lerp(_net_target_pos, weight)
	var yaw := lerp_angle(global_rotation.y, _net_target_yaw, weight)
	global_rotation = Vector3(0.0, yaw, 0.0)
	speed_kmh = linear_velocity.length() * 3.6
	forward_speed = linear_velocity.dot(-global_transform.basis.z)


# ---------------------------------------------------------------------------
# lap accounting helpers
# ---------------------------------------------------------------------------

func begin_lap_timer() -> void:
	_lap_started_ms = Time.get_ticks_msec()


var _lap_started_ms: int = 0
var current_lap: int = 1
var total_laps: int = 12
var finished: bool = false
var finish_time: float = 0.0
var best_lap: float = INF
var lap_times: Array[float] = []


func complete_lap(race_time: float) -> void:
	if finished:
		return
	var lap_time := (Time.get_ticks_msec() - _lap_started_ms) / 1000.0
	_lap_started_ms = Time.get_ticks_msec()
	lap_times.append(lap_time)
	if lap_time < best_lap:
		best_lap = lap_time
	current_lap += 1
	lap_progress.emit(current_lap, lap_time)
	if current_lap > total_laps:
		finished = true
		finish_time = race_time
		race_completed.emit({
			"laps": total_laps,
			"time": race_time,
			"best_lap": best_lap,
		})


func reset_race_state() -> void:
	current_lap = 1
	finished = false
	finish_time = 0.0
	best_lap = INF
	lap_times.clear()
	_lap_started_ms = Time.get_ticks_msec()


func telemetry() -> Dictionary:
	return {
		"speed_kmh": speed_kmh,
		"rpm": rpm,
		"gear": gear,
		"lap": current_lap,
		"total_laps": total_laps,
		"best_lap": best_lap,
		"position": 0,
		"drifting": drifting_now,
	}
