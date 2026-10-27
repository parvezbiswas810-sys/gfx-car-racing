class_name AIDriver
extends Node
## Opponent driver.
##
## Follows the track's smoothed racing line continuously: it never teleports,
## it steers toward a look-ahead point and modulates throttle and brakes from
## the measured corner curvature. Difficulty changes speed, corner commitment,
## reaction distance and how often mistakes happen.

enum Difficulty { EASY, NORMAL, HARD }

const PROFILES := {
	Difficulty.EASY: {
		"speed_scale": 0.72,
		"corner_scale": 0.68,
		"look_ahead": 0.95,
		"steer_gain": 1.25,
		"reaction": 0.30,
		"mistake_chance": 0.22,
		"brake_bias": 0.80,
	},
	Difficulty.NORMAL: {
		"speed_scale": 0.86,
		"corner_scale": 0.84,
		"look_ahead": 1.15,
		"steer_gain": 1.55,
		"reaction": 0.16,
		"mistake_chance": 0.10,
		"brake_bias": 1.0,
	},
	Difficulty.HARD: {
		"speed_scale": 0.97,
		"corner_scale": 0.96,
		"look_ahead": 1.35,
		"steer_gain": 1.85,
		"reaction": 0.08,
		"mistake_chance": 0.03,
		"brake_bias": 1.15,
	},
}

var car: Car
var track: TrackBuilder
var difficulty: Difficulty = Difficulty.NORMAL

var _profile: Dictionary = {}
var _index: int = 0
var _stuck_time: float = 0.0
var _reverse_time: float = 0.0
var _mistake_time: float = 0.0
var _mistake_steer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _lane_bias: float = 0.0
var _active: bool = true


func setup(p_car: Car, p_track: TrackBuilder, p_difficulty: Difficulty, seed_value: int = 0) -> void:
	car = p_car
	track = p_track
	difficulty = p_difficulty
	_profile = PROFILES[difficulty]
	_rng.seed = seed_value if seed_value != 0 else randi()
	_lane_bias = _rng.randf_range(-0.22, 0.22)
	_index = track.nearest_index(car.global_position)
	_stuck_time = 0.0
	_reverse_time = 0.0
	_mistake_time = 0.0


func set_active(value: bool) -> void:
	_active = value
	if not value and car != null:
		car.apply_controls(0.0, 0.0, 0.0, false)


static func from_string(name: String) -> Difficulty:
	match name.to_lower():
		"easy": return Difficulty.EASY
		"hard": return Difficulty.HARD
	return Difficulty.NORMAL


func _physics_process(delta: float) -> void:
	if car == null or track == null or not _active:
		return
	if car.finished:
		car.apply_controls(0.0, 0.5, 0.0, false)
		return

	_recover_if_stuck(delta)

	if _reverse_time > 0.0:
		_reverse_time -= delta
		# Back out of the wall while steering away from it.
		car.apply_controls(0.0, 1.0, _mistake_steer, false)
		return

	_advance_index()

	# If the car has ended up off the road, driving at the look-ahead point would
	# just make it circle in the infield, because that point lies across a barrier.
	# Aim straight at the nearest piece of road instead and crawl back on.
	if _is_off_road():
		_recover_to_road()
		return

	var speed := car.speed_kmh
	var look_ahead := clampf(speed * float(_profile["look_ahead"]), 18.0, 105.0)
	var target_index := track.index_at_distance(float(_index) * track.spacing + look_ahead)
	var target := track.racing_point(target_index)

	# Lateral personality: hug a slightly different line so opponents do not
	# drive in a single file train.
	var n := track.centerline.size()
	var normal := track.normals[clampi(target_index, 0, n - 1)]
	target += normal * _lane_bias * float(track.track["width"]) * 0.5

	_steer_toward(target, delta)
	_manage_speed(look_ahead, delta)
	_avoid_walls(delta)


## Keeps the car off the barrier. When the car drifts wide the AI steers back
## toward the line and lifts off, which is enough to stop it grinding along a
## wall for the rest of the lap.
##
## Every lateral measurement here uses the AI's own tracked sample index, never a
## global nearest-point search: where a circuit passes close to itself a global
## search can snap onto the wrong straight and the AI then fights a phantom wall.
func _lateral_offset() -> float:
	var offset := car.global_position - track.centerline[_index]
	return offset.dot(track.normals[_index])


func _avoid_walls(_delta: float) -> void:
	var half := float(track.track["width"]) * 0.5 + 1.6
	var lateral := _lateral_offset()
	# Start correcting well before the kerb: waiting until the car is nearly
	# touching the wall leaves no room to recover at speed.
	var margin := half - 4.0
	if absf(lateral) < margin:
		return
	var excess := clampf((absf(lateral) - margin) / maxf(0.4, half - margin), 0.0, 1.0)
	# normals point to the right of travel, so a positive offset means the car is
	# right of the line and must be steered left, which is a positive steer input.
	var steer := car.steer_input + signf(lateral) * excess * 1.8
	# Lift off near the wall so the car stops pushing itself wide.
	var throttle := car.throttle * (1.0 - 0.7 * excess)
	car.apply_controls(throttle, car.brake_input, clampf(steer, -1.0, 1.0), false)


## True when the car is past the kerb, i.e. out in the run-off area.
func _is_off_road() -> bool:
	var limit := float(track.track["width"]) * 0.5 + 1.6 + 1.0
	return absf(_lateral_offset()) > limit


## Steers straight back to the nearest point of road. Called only while the car
## is off the circuit, so the "circle the infield forever" failure cannot happen.
func _recover_to_road() -> void:
	var target := track.centerline[_index]
	var to_target := target - car.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.04:
		car.apply_controls(0.4, 0.0, 0.0, false)
		return
	var forward := -car.global_transform.basis.z
	forward.y = 0.0
	var angle := forward.signed_angle_to(to_target.normalized(), Vector3.UP)
	var steer := clampf(angle * 2.4, -1.0, 1.0)
	# Creep rather than sprint, so the car does not overshoot the road again.
	var throttle := 0.45 if absf(angle) < 1.2 else 0.15
	car.apply_controls(throttle, 0.0, steer, false)


func _advance_index() -> void:
	var count := track.centerline.size()
	var best := _index
	var best_d := INF
	# Search a short window forward: cheap, and it cannot jump the car to a
	# different part of the circuit after a spin.
	for offset in range(-3, 26):
		var i := ((_index + offset) % count + count) % count
		var d := track.racing_point(i).distance_squared_to(car.global_position)
		if d < best_d:
			best_d = d
			best = i
	_index = best


func _steer_toward(target: Vector3, _delta: float) -> void:
	var to_target := target - car.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return
	var forward := -car.global_transform.basis.z
	forward.y = 0.0
	var angle := forward.signed_angle_to(to_target.normalized(), Vector3.UP)
	# Scale the aim angle by speed so the AI does not saw at the wheel.
	var speed_factor := clampf(1.0 - car.speed_kmh / 260.0, 0.35, 1.0)
	var steer := clampf(angle * float(_profile["steer_gain"]) * speed_factor * 2.2, -1.0, 1.0)

	# Occasional human-like wobble keeps Easy genuinely beatable.
	_mistake_time -= 0.016
	if _mistake_time <= 0.0:
		_mistake_time = _rng.randf_range(1.4, 4.0)
		if _rng.randf() < float(_profile["mistake_chance"]):
			_mistake_steer = _rng.randf_range(-0.35, 0.35)
		else:
			_mistake_steer = 0.0
	steer = clampf(steer + _mistake_steer, -1.0, 1.0)

	car.apply_controls(car.throttle, car.brake_input, steer, car.drifting)


func _manage_speed(look_ahead: float, delta: float) -> void:
	var speed := car.speed_kmh
	# Scan at least as far ahead as it takes to brake from the current speed, so
	# the car starts slowing before the corner rather than mid-apex.
	var brake_dist := (speed / 3.6) * (speed / 3.6) / (2.0 * 12.0)
	var scan := clampf(brake_dist + 70.0, 80.0, 300.0)
	var allowed_kmh := _min_corner_speed(scan)
	var target_kmh := minf(allowed_kmh, Car.MAX_SPEED_KMH * float(_profile["speed_scale"]))
	var current := speed

	var throttle := 0.0
	var brake := 0.0
	if current < target_kmh * 0.98:
		throttle = 1.0
	elif current > target_kmh * 1.06:
		brake = clampf((current - target_kmh) / 40.0, 0.15, 1.0) * float(_profile["brake_bias"])
	else:
		throttle = 0.55

	# If the nose is not pointing where it is going, ease off the power.
	var forward := -car.global_transform.basis.z
	var slip := absf(forward.signed_angle_to(car.linear_velocity.normalized(), Vector3.UP)) if car.linear_velocity.length() > 4.0 else 0.0
	if slip > 0.55:
		throttle *= 0.4
		brake = maxf(brake, 0.15)

	# Drift on the tightest corners when the car is quick enough for it to help.
	var want_drift := _worst_curvature(look_ahead) > 0.012 and current > 65.0 and difficulty != Difficulty.EASY

	car.apply_controls(throttle, brake, car.steer_input, want_drift)


## Lowest safe speed, in km/h, over the next `distance` metres of racing line.
## Corner speed comes from the tyre's lateral grip limit: v = sqrt(a_lat / k),
## where k is the track curvature in radians per metre.
func _min_corner_speed(distance: float) -> float:
	var count := track.centerline.size()
	var samples := maxi(3, int(distance / maxf(0.5, track.spacing)))
	var corner_scale := float(_profile["corner_scale"])
	var max_lat := 6.0 * corner_scale
	var slowest := Car.MAX_SPEED_KMH
	for i in samples:
		var idx := (_index + i) % count
		var k := maxf(track.curvature[idx], 1e-4)
		var v_ms := sqrt(max_lat / k)
		slowest = minf(slowest, v_ms * 3.6)
	return slowest


func _worst_curvature(look_ahead: float) -> float:
	var count := track.centerline.size()
	var samples := maxi(3, int(look_ahead / maxf(0.5, track.spacing)))
	var worst := 0.0
	for i in samples:
		var idx := (_index + i) % count
		worst = maxf(worst, track.curvature[idx])
	return worst


func _recover_if_stuck(delta: float) -> void:
	if car.speed_kmh < 2.0:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time > 1.8:
		_stuck_time = 0.0
		_reverse_time = _rng.randf_range(0.7, 1.3)
		# Steer away from whichever side the wall is on.
		var offset := track.centerline[track.nearest_index(car.global_position)] - car.global_position
		var lateral := offset.dot(car.global_transform.basis.x)
		_mistake_steer = signf(lateral) if absf(lateral) > 0.3 else _rng.randf_range(-1.0, 1.0)
