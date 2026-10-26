class_name CarPreview
extends SubViewportContainer
## Rotating 3D car preview for the menu and garage.
##
## Renders into its own SubViewport so the UI can host a live 3D model without
## touching the main viewport. Uses a dedicated World3D, so it never picks up
## the race lighting.

var _viewport: SubViewport
var _world_root: Node3D
var _pivot: Node3D
var _car: Car
var _yaw: float = 0.6
var _dragging: bool = false
var _last_mouse := Vector2.ZERO
var _auto_spin: bool = true


func _ready() -> void:
	stretch = true
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.size = Vector2i(640, 420)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_world_root = Node3D.new()
	_viewport.add_child(_world_root)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.06, 0.11, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.90)
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_world_root.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 38, 0)
	key.light_energy = 1.25
	key.shadow_enabled = false
	_world_root.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, -150, 0)
	rim.light_energy = 0.55
	rim.light_color = Color(0.62, 0.76, 1.0)
	rim.shadow_enabled = false
	_world_root.add_child(rim)

	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_world_root.add_child(_pivot)

	var camera := Camera3D.new()
	camera.fov = 38.0
	camera.position = Vector3(4.6, 2.3, 6.0)
	camera.look_at_from_position(Vector3(4.6, 2.3, 6.0), Vector3(0.0, 0.55, 0.0), Vector3.UP)
	_world_root.add_child(camera)

	# A subtle floor so the car does not float in a void.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(14, 14)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.10, 0.13, 0.20, 0.55)
	floor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	floor_mat.roughness = 0.55
	var floor := MeshInstance3D.new()
	floor.mesh = floor_mesh
	floor.material_override = floor_mat
	floor.position.y = -0.02
	_world_root.add_child(floor)


func show_car(car_id: String, colour: Color) -> void:
	if _car != null:
		_car.queue_free()
		_car = null
	_car = Car.new()
	_car.name = "PreviewCar"
	_car.is_player = false
	_car.car_id = car_id
	_car.configure(car_id)
	_car.set_colour(colour)
	_car.freeze = true
	_car.gravity_scale = 0.0
	# Never simulate: this is a display model only.
	_car.set_physics_process(false)
	_car.position = Vector3.ZERO
	_pivot.add_child(_car)


func _process(delta: float) -> void:
	if _car == null:
		return
	if _auto_spin and not _dragging:
		_yaw += delta * 0.45
	_pivot.rotation.y = _yaw


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_dragging = event.pressed
		_last_mouse = event.position
		if event.pressed:
			_auto_spin = false
		else:
			# Resume the slow turn a moment after the user lets go.
			get_tree().create_timer(2.0).timeout.connect(func(): _auto_spin = true)
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.01
		_pivot.rotation.y = _yaw
	elif event is InputEventScreenTouch:
		_dragging = event.pressed
		_last_mouse = event.position
		if event.pressed:
			_auto_spin = false
		else:
			get_tree().create_timer(2.0).timeout.connect(func(): _auto_spin = true)
	elif event is InputEventScreenDrag:
		_yaw -= event.relative.x * 0.01
		_pivot.rotation.y = _yaw
