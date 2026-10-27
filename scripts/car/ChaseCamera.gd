class_name ChaseCamera
extends Node3D
## Elevated three-quarter chase camera.
##
## Position and aim are smoothed independently (critically damped-ish lerps) so
## the camera never snaps when the car is hit. Shake is a small additive offset
## that can be switched off in Settings.

const HEIGHT := 4.6
const DISTANCE := 10.5
const LOOK_AHEAD := 13.0
const LOOK_HEIGHT := 1.7

@export var target: Car
@export var shake_enabled: bool = true

## The actual viewport camera. This node only positions itself; the Camera3D
## child rides along and does the rendering.
var camera: Camera3D

var _pos_smooth := Vector3.ZERO
var _look_smooth := Vector3.ZERO
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _speed_blend: float = 0.0
var _initialised: bool = false


func _ready() -> void:
	_rng.randomize()
	shake_enabled = Settings.camera_shake
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 68.0
	camera.near = 0.4
	camera.far = 900.0
	add_child(camera)


## Makes this chase rig the active viewport camera.
func make_current() -> void:
	if camera != null:
		camera.current = true


func set_target(car: Car) -> void:
	target = car
	_initialised = false


func add_shake(amount: float) -> void:
	_shake = minf(1.4, _shake + amount)


func _physics_process(delta: float) -> void:
	if target == null:
		return

	# Pull back and raise slightly as speed builds, for a sense of pace.
	var speed_ratio := clampf(target.speed_kmh / Car.MAX_SPEED_KMH, 0.0, 1.0)
	_speed_blend = lerpf(_speed_blend, speed_ratio, 0.06)
	var distance := DISTANCE + _speed_blend * 3.4
	var height := HEIGHT + _speed_blend * 0.5

	var basis := target.global_transform.basis
	var flat_forward := -basis.z
	flat_forward.y = 0.0
	if flat_forward.length_squared() < 0.001:
		flat_forward = Vector3.FORWARD
	flat_forward = flat_forward.normalized()

	var desired := target.global_position - flat_forward * distance + Vector3.UP * height
	# Keep the camera above the ground so a crash into a barrier cannot push it
	# under the road surface.
	desired.y = maxf(desired.y, 1.6)

	var aim := target.global_position + flat_forward * LOOK_AHEAD + Vector3.UP * LOOK_HEIGHT

	if not _initialised:
		_pos_smooth = desired
		_look_smooth = aim
		_initialised = true
	else:
		var pos_weight := 1.0 - pow(0.0015, delta)
		var look_weight := 1.0 - pow(0.0006, delta)
		_pos_smooth = _pos_smooth.lerp(desired, pos_weight)
		_look_smooth = _look_smooth.lerp(aim, look_weight)

	_shake = maxf(0.0, _shake - delta * 2.6)
	var offset := Vector3.ZERO
	if shake_enabled and _shake > 0.001:
		var m := _shake * _speed_blend * 0.5 + _shake * 0.12
		offset = Vector3(_rng.randf_range(-m, m), _rng.randf_range(-m, m) * 0.7, _rng.randf_range(-m, m))

	global_position = _pos_smooth + offset
	look_at(_look_smooth, Vector3.UP)
