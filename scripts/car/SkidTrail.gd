class_name SkidTrail
extends MultiMeshInstance3D
## Ring-buffered skid marks.
##
## Marks are a fixed pool of flat quads written into a MultiMesh, so drifting
## costs one draw call no matter how long the trail gets. The oldest mark is
## overwritten once the pool is full, which keeps memory flat on a phone.

const MAX_MARKS := 420
const MIN_DISTANCE := 0.55

var _next: int = 0
var _last_left := Vector3.ZERO
var _last_right := Vector3.ZERO
var _primed: bool = false


func _ready() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.7)
	multimesh.mesh = quad
	multimesh.instance_count = MAX_MARKS
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists("res://assets/textures/skid.png"):
		mat.albedo_texture = load("res://assets/textures/skid.png")
	mat.albedo_color = Color(0.08, 0.08, 0.10, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.vertex_color_use_as_albedo = true
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var hidden := Transform3D().scaled(Vector3.ZERO)
	for i in MAX_MARKS:
		multimesh.set_instance_transform(i, hidden)
	_primed = false


func drop(left_pos: Vector3, right_pos: Vector3, _delta: float) -> void:
	if multimesh == null:
		return
	if not _primed:
		_last_left = left_pos
		_last_right = right_pos
		_primed = true
		return
	if _last_left.distance_to(left_pos) < MIN_DISTANCE:
		return
	_emit_mark(_last_left, left_pos)
	_emit_mark(_last_right, right_pos)
	_last_left = left_pos
	_last_right = right_pos


func stop_dropping() -> void:
	_primed = false


func _emit_mark(from: Vector3, to: Vector3) -> void:
	var mid := (from + to) * 0.5
	mid.y = 0.03
	var dir := to - from
	var length := dir.length()
	if length < 0.01:
		return
	var basis := Basis()
	var z_axis := dir.normalized()
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	basis = Basis(x_axis, y_axis, z_axis)
	var scale_z := clampf(length / 0.7, 0.5, 3.0)
	var t := Transform3D(basis.scaled(Vector3(1.0, 1.0, scale_z)), mid)
	multimesh.set_instance_transform(_next, t)
	_next = (_next + 1) % MAX_MARKS


func clear_all() -> void:
	if multimesh == null:
		return
	var hidden := Transform3D().scaled(Vector3.ZERO)
	for i in MAX_MARKS:
		multimesh.set_instance_transform(i, hidden)
	_next = 0
	_primed = false
