class_name TrackBuilder
extends Node3D
## Turns a TrackData control polygon into a fully playable circuit:
## road ribbon, kerbs, barriers with collision, checkpoints, start/finish
## gantry, scenery, lighting, AI waypoints and a corner-aware racing line.
##
## The layout is smoothed with Chaikin corner cutting, which stays inside the
## convex hull of the control polygon. That property is what guarantees the
## generated centreline can never self-intersect, so checkpoint ordering and
## the AI racing line stay valid for every layout in TrackData.

const SAMPLE_SPACING := 4.0      # metres between centreline samples
const SMOOTH_PASSES := 3         # Chaikin iterations for the drivable line
const RACING_PASSES := 7         # extra passes -> a corner-cutting racing line
const BARRIER_HEIGHT := 3.2       # a sliding car must not be able to ride up over it
const BARRIER_THICKNESS := 1.6
const KERB_WIDTH := 1.6

var track_id: String = "city_circuit"
var track: Dictionary = {}
var theme: Dictionary = {}

var centerline := PackedVector3Array()
var tangents := PackedVector3Array()
var normals := PackedVector3Array()
var curvature := PackedFloat32Array()
var racing_line := PackedVector3Array()
var length: float = 0.0
var spacing: float = SAMPLE_SPACING

var start_transform := Transform3D()
var checkpoint_transforms: Array[Transform3D] = []

var _mesh_root: Node3D
var _props_root: Node3D
var _checkpoint_root: Node3D
var _materials: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func build(id: String) -> void:
	track_id = id
	track = TrackData.get_track(id)
	theme = TrackData.theme_of(track)
	_rng.seed = hash(id)

	_build_centerline()
	# Curvature feeds the racing line, so it must be computed first.
	_build_curvature()
	_build_racing_line()
	_build_materials()
	_build_environment()
	_build_ground()
	_build_road()
	_build_kerbs_and_lines()
	_build_barriers()
	_build_scenery()
	_build_checkpoints()
	_build_start_gantry()


# ---------------------------------------------------------------------------
# geometry
# ---------------------------------------------------------------------------

func _build_centerline() -> void:
	var pts: Array[Vector2] = []
	for p in track["points"]:
		pts.append(p)

	var smoothed := pts
	for i in SMOOTH_PASSES:
		smoothed = _chaikin(smoothed)

	# Resample to even spacing so every downstream system (checkpoints, AI,
	# curvature) can index by distance instead of by control point.
	var poly := PackedVector3Array()
	for p in smoothed:
		poly.append(Vector3(p.x, 0.0, p.y))
	poly = _resample_closed(poly, SAMPLE_SPACING)

	centerline = poly
	var n := centerline.size()
	tangents.resize(n)
	normals.resize(n)
	for i in n:
		var prev := centerline[(i - 1 + n) % n]
		var next := centerline[(i + 1) % n]
		var t := (next - prev)
		t.y = 0.0
		t = t.normalized()
		tangents[i] = t
		normals[i] = t.cross(Vector3.UP).normalized()
	length = 0.0
	for i in n:
		length += centerline[i].distance_to(centerline[(i + 1) % n])
	spacing = length / float(n)

	start_transform = _transform_at(0)
	# Face the direction of travel along the first sample.
	start_transform.basis = Basis.looking_at(tangents[0], Vector3.UP)


func _chaikin(points: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := points.size()
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out


func _resample_closed(poly: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := poly.size()
	var carry := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var seg := a.distance_to(b)
		if seg <= 0.0001:
			continue
		var pos := carry
		while pos < seg:
			out.append(a.lerp(b, pos / seg))
			pos += step
		carry = pos - seg
	return out


func _build_racing_line() -> void:
	# The racing line must share the centreline's parameterisation: same sample
	# count, same indices. Building it as an independent resample gives a line
	# whose index N is a different point of the circuit than the centreline's
	# index N, and the AI would then steer off the road entirely.
	#
	# The correct construction is to displace each centreline sample sideways by
	# an amount proportional to the local curvature: cutting toward the inside of
	# a bend, exactly as a driver does, while staying on the centreline down the
	# straights.
	var n := centerline.size()
	racing_line.resize(n)
	# Keep the cut gentle. A line that reaches the kerb leaves no margin for the
	# AI's tracking error, and the car then scrapes the barrier through every
	# corner instead of completing laps.
	var half_width := float(track["width"]) * 0.5
	var max_cut := minf(1.4, maxf(0.0, half_width - 2.9))
	for i in n:
		var k := curvature[i]
		# Signed turn direction from the change in tangent heading.
		var a := tangents[(i - 1 + n) % n]
		var b := tangents[(i + 1) % n]
		var turn := a.signed_angle_to(b, Vector3.UP)
		var cut := clampf(k * 26.0, 0.0, 1.0)
		# normals[i] points to the left of travel, so a left-hand bend (positive
		# turn) cuts with a negative lateral offset.
		var lateral := -signf(turn) * cut * max_cut
		racing_line[i] = centerline[i] + normals[i] * lateral
	# Light smoothing so the lateral offsets do not produce a kinked line, using
	# a wrap-around pass that preserves the sample count.
	for _pass in 2:
		var smoothed := racing_line.duplicate()
		for i in n:
			smoothed[i] = (racing_line[(i - 1 + n) % n] + racing_line[i] * 2.0
				+ racing_line[(i + 1) % n]) * 0.25
		racing_line = smoothed


func _build_curvature() -> void:
	var n := centerline.size()
	curvature.resize(n)
	for i in n:
		var a := tangents[(i - 1 + n) % n]
		var b := tangents[(i + 1) % n]
		var dot := clampf(a.dot(b), -1.0, 1.0)
		# angle per two samples, converted to a per-metre bend rate
		curvature[i] = acos(dot) / (2.0 * spacing)


func _transform_at(index: int) -> Transform3D:
	var n := centerline.size()
	var i := ((index % n) + n) % n
	var origin := centerline[i]
	var t := tangents[i]
	var basis := Basis.looking_at(t, Vector3.UP)
	return Transform3D(basis, origin)


func sample_point(index: int, lateral: float = 0.0) -> Vector3:
	var n := centerline.size()
	var i := ((index % n) + n) % n
	return centerline[i] + normals[i] * lateral


func racing_point(index: int) -> Vector3:
	if racing_line.is_empty():
		return sample_point(index)
	var n := racing_line.size()
	return racing_line[((index % n) + n) % n]


func index_at_distance(d: float) -> int:
	var n := centerline.size()
	if n == 0 or length <= 0.0:
		return 0
	var wrapped := fposmod(d, length)
	return int(round(wrapped / spacing)) % n


func nearest_index(point: Vector3) -> int:
	"""Linear scan is fine here: only used at spawn and by AI recovery."""
	var best := 0
	var best_d := INF
	for i in centerline.size():
		var d := centerline[i].distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = i
	return best


func nearest_distance_to_centerline(point: Vector3) -> float:
	return centerline[nearest_index(point)].distance_to(point)


# ---------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------

func _build_materials() -> void:
	_materials["road"] = _textured_material("res://assets/textures/asphalt.png",
			Color(0.42, 0.44, 0.48), Vector3(1.0, 8.0, 1.0), 0.9)
	_materials["kerb"] = _textured_material("res://assets/textures/curb.png",
			Color(1, 1, 1), Vector3(1.0, 1.0, 1.0), 0.75)
	_materials["barrier"] = _flat_material(theme["barrier_colour"], 0.45)
	_materials["line"] = _flat_material(Color(0.94, 0.94, 0.96), 0.5)
	_materials["finish"] = _textured_material("res://assets/textures/finish_line.png",
			Color(1, 1, 1), Vector3(4.0, 1.0, 1.0), 0.6)
	_materials["ground"] = _textured_material(theme["ground_texture"],
			theme["ground_tint"], Vector3(90.0, 90.0, 1.0), 1.0)
	_materials["gantry"] = _flat_material(Color(0.22, 0.24, 0.30), 0.4)
	if theme.get("neon", false):
		_materials["gantry"] = _flat_material(Color(0.30, 0.22, 0.55), 0.3, true)


func _flat_material(colour: Color, roughness: float, emissive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	if emissive:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = 0.8
	return m


func _textured_material(path: String, tint: Color, uv_scale: Vector3, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
	m.albedo_color = tint
	m.uv1_scale = uv_scale
	m.roughness = roughness
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# ---------------------------------------------------------------------------
# environment
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = theme["sky_top"]
	sky_mat.sky_horizon_color = theme["sky_horizon"]
	sky_mat.ground_bottom_color = theme["sky_horizon"].darkened(0.45)
	sky_mat.ground_horizon_color = theme["sky_horizon"]
	sky_mat.sun_angle_max = 12.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = theme["ambient"]
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.1
	if theme.get("fog", false) and Settings.preset()["fog"]:
		env.fog_enabled = true
		env.fog_light_color = theme["sky_horizon"]
		env.fog_density = 0.0016
		env.fog_sky_affect = 0.6
	# Glow only on the night theme; it is the one place it earns its cost.
	if theme.get("neon", false):
		env.glow_enabled = true
		env.glow_intensity = 0.6
		env.glow_bloom = 0.15

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = theme["sun_colour"]
	sun.light_energy = theme["sun_energy"]
	var angles: Vector3 = theme["sun_angle"]
	sun.rotation_degrees = angles
	var preset := Settings.preset()
	sun.shadow_enabled = bool(preset["shadows_enabled"])
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.4
	add_child(sun)


# ---------------------------------------------------------------------------
# surfaces
# ---------------------------------------------------------------------------

func _build_ground() -> void:
	var extent := _bounds_extent() + 320.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent * 2.0, extent * 2.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.material_override = _materials["ground"]
	# Slightly below the road ribbon so the two coplanar surfaces cannot z-fight.
	mi.position = _bounds_center() + Vector3(0, -0.03, 0)
	add_child(mi)

	# One large box under the whole circuit is far cheaper than a trimesh and
	# is all a flat arcade track needs for a drivable surface.
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(extent * 2.0, 2.0, extent * 2.0)
	shape.shape = box
	body.add_child(shape)
	# Box is 2 m tall, so its top face lands exactly on y = 0: the same plane
	# the road ribbon is drawn on, and where cars must rest.
	body.position = _bounds_center() + Vector3(0, -1.0, 0)
	add_child(body)


func _bounds_center() -> Vector3:
	if centerline.is_empty():
		return Vector3.ZERO
	var mn := centerline[0]
	var mx := centerline[0]
	for p in centerline:
		mn = mn.min(p)
		mx = mx.max(p)
	return (mn + mx) * 0.5


func _bounds_extent() -> float:
	if centerline.is_empty():
		return 400.0
	var c := _bounds_center()
	var r := 0.0
	for p in centerline:
		r = maxf(r, c.distance_to(p))
	return r


func _build_road() -> void:
	var half := float(track["width"]) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := centerline.size()
	var travelled := 0.0
	for i in n:
		var j := (i + 1) % n
		var a := centerline[i]
		var b := centerline[j]
		var na := normals[i]
		var nb := normals[j]
		var v0 := a + na * -half
		var v1 := a + na * half
		var v2 := b + nb * half
		var v3 := b + nb * -half
		var u0 := travelled / 12.0
		var u1 := (travelled + a.distance_to(b)) / 12.0
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, u0))
		st.add_vertex(v0)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, u0))
		st.add_vertex(v1)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, u1))
		st.add_vertex(v2)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, u0))
		st.add_vertex(v0)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, u1))
		st.add_vertex(v2)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, u1))
		st.add_vertex(v3)
		travelled += a.distance_to(b)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Road"
	mi.mesh = st.commit()
	mi.material_override = _materials["road"]
	add_child(mi)


func _build_kerbs_and_lines() -> void:
	var half := float(track["width"]) * 0.5
	_add_ribbon("KerbLeft", -half - KERB_WIDTH * 0.5, KERB_WIDTH, _materials["kerb"], 0.01, 1.0)
	_add_ribbon("KerbRight", half + KERB_WIDTH * 0.5, KERB_WIDTH, _materials["kerb"], 0.01, 1.0)
	_add_ribbon("EdgeLeft", -half + 0.35, 0.22, _materials["line"], 0.012, 1.0)
	_add_ribbon("EdgeRight", half - 0.35, 0.22, _materials["line"], 0.012, 1.0)
	_add_ribbon("CentreLine", 0.0, 0.20, _materials["line"], 0.013, 1.0)


func _add_ribbon(node_name: String, lateral: float, width: float, material: Material,
		height: float, v_scale: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := centerline.size()
	var half_w := width * 0.5
	var travelled := 0.0
	for i in n:
		var j := (i + 1) % n
		var a := centerline[i] + normals[i] * lateral
		var b := centerline[j] + normals[j] * lateral
		var na := normals[i]
		var nb := normals[j]
		var v0 := a + na * -half_w + Vector3.UP * height
		var v1 := a + na * half_w + Vector3.UP * height
		var v2 := b + nb * half_w + Vector3.UP * height
		var v3 := b + nb * -half_w + Vector3.UP * height
		var u0 := travelled * v_scale
		var u1 := (travelled + a.distance_to(b)) * v_scale
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, u0))
		st.add_vertex(v0)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, u0))
		st.add_vertex(v1)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, u1))
		st.add_vertex(v2)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, u0))
		st.add_vertex(v0)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, u1))
		st.add_vertex(v2)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, u1))
		st.add_vertex(v3)
		travelled += a.distance_to(b)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = material
	add_child(mi)


func _build_barriers() -> void:
	var half := float(track["width"]) * 0.5 + KERB_WIDTH
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var n := centerline.size()
	for side in [-1.0, 1.0]:
		for i in n:
			var j := (i + 1) % n
			var la: float = half * side
			var a: Vector3 = centerline[i] + normals[i] * la
			var b: Vector3 = centerline[j] + normals[j] * la
			var na: Vector3 = normals[i] * side
			var nb: Vector3 = normals[j] * side
			var up: Vector3 = Vector3.UP * BARRIER_HEIGHT
			var oa: Vector3 = na * BARRIER_THICKNESS * 0.5
			var ob: Vector3 = nb * BARRIER_THICKNESS * 0.5
			# inner wall quad
			var p0: Vector3 = a - oa
			var p1: Vector3 = b - ob
			var p2: Vector3 = b - ob + up
			var p3: Vector3 = a - oa + up
			st.set_normal(-na)
			st.set_uv(Vector2(0, 0))
			st.add_vertex(p0)
			st.set_normal(-na)
			st.set_uv(Vector2(1, 0))
			st.add_vertex(p1)
			st.set_normal(-na)
			st.set_uv(Vector2(1, 1))
			st.add_vertex(p2)
			st.set_normal(-na)
			st.set_uv(Vector2(0, 0))
			st.add_vertex(p0)
			st.set_normal(-na)
			st.set_uv(Vector2(1, 1))
			st.add_vertex(p2)
			st.set_normal(-na)
			st.set_uv(Vector2(0, 1))
			st.add_vertex(p3)
			# top cap so the wall reads as solid from the elevated camera
			var q0: Vector3 = a - oa + up
			var q1: Vector3 = b - ob + up
			var q2: Vector3 = b + ob + up
			var q3: Vector3 = a + oa + up
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0, 0))
			st.add_vertex(q0)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(1, 0))
			st.add_vertex(q1)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(1, 1))
			st.add_vertex(q2)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0, 0))
			st.add_vertex(q0)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(1, 1))
			st.add_vertex(q2)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0, 1))
			st.add_vertex(q3)
			faces.append(p0)
			faces.append(p2)
			faces.append(p1)
			faces.append(p0)
			faces.append(p3)
			faces.append(p2)
			faces.append(q0)
			faces.append(q1)
			faces.append(q2)
			faces.append(q0)
			faces.append(q2)
			faces.append(q3)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Barriers"
	mi.mesh = st.commit()
	mi.material_override = _materials["barrier"]
	add_child(mi)

	# Static trimesh collision: one shape for the whole wall ring, which is
	# dramatically cheaper than thousands of box shapes on a phone.
	var body := StaticBody3D.new()
	body.name = "BarrierBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	add_child(body)


# ---------------------------------------------------------------------------
# scenery
# ---------------------------------------------------------------------------

func _build_scenery() -> void:
	var kind: String = theme["prop"]
	var density: float = Settings.preset()["prop_density"]
	var wanted := int(float(theme["prop_count"]) * density)
	if wanted <= 0:
		return

	var mesh := _prop_mesh(kind)
	if mesh == null:
		return
	var material := _prop_material(kind)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = wanted

	var half := float(track["width"]) * 0.5 + KERB_WIDTH + BARRIER_THICKNESS + 6.0
	var radius := _bounds_extent() + 40.0
	var centre := _bounds_center()
	var placed := 0
	var attempts := 0
	var max_attempts := wanted * 14
	while placed < wanted and attempts < max_attempts:
		attempts += 1
		var angle := _rng.randf() * TAU
		var dist := sqrt(_rng.randf()) * radius
		var pos := centre + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		if centerline[nearest_index(pos)].distance_to(pos) < half + 3.0:
			continue
		var scale := _rng.randf_range(0.8, 1.6)
		var t := Transform3D()
		t = t.rotated(Vector3.UP, _rng.randf() * TAU)
		t = t.scaled(Vector3(scale, scale, scale))
		t.origin = pos
		mm.set_instance_transform(placed, t)
		placed += 1
	if placed < wanted:
		mm.instance_count = placed

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Scenery"
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _prop_mesh(kind: String) -> Mesh:
	match kind:
		"tree":
			var arr := ArrayMesh.new()
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.28
			trunk.bottom_radius = 0.42
			trunk.height = 3.4
			trunk.radial_segments = 6
			trunk.rings = 1
			trunk.material = _flat_material(Color(0.28, 0.20, 0.13), 0.95)
			var trunk_mi := MeshInstance3D.new()
			trunk_mi.mesh = trunk
			var canopy := SphereMesh.new()
			canopy.radius = 2.1
			canopy.height = 4.4
			canopy.radial_segments = 8
			canopy.rings = 4
			canopy.material = _flat_material(Color(0.16, 0.42, 0.18), 0.9)
			var canopy_mi := MeshInstance3D.new()
			canopy_mi.mesh = canopy
			canopy_mi.position = Vector3(0, 3.6, 0)
			var scene := Node3D.new()
			scene.add_child(trunk_mi)
			scene.add_child(canopy_mi)
			return _merge_prop([trunk_mi, canopy_mi])
		"rock":
			var s := SphereMesh.new()
			s.radius = 1.4
			s.height = 1.8
			s.radial_segments = 6
			s.rings = 3
			return s
		"building":
			var box := BoxMesh.new()
			box.size = Vector3(9.0, 22.0, 9.0)
			return box
		"stand":
			var b := BoxMesh.new()
			b.size = Vector3(24.0, 7.0, 8.0)
			return b
	return null


func _merge_prop(parts: Array) -> Mesh:
	# MultiMesh needs a single mesh, so merge the prop parts into one surface
	# set using the parts' own materials via separate surfaces.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var m: Mesh = part.mesh
		var offset: Vector3 = part.position
		var mat: Material = m.material
		for s in m.get_surface_count():
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx.resize(verts.size())
				for k in verts.size():
					idx[k] = k
			var i := 0
			while i + 2 < idx.size():
				for k in 3:
					var vi: int = idx[i + k]
					st.set_normal(nrm[vi] if vi < nrm.size() else Vector3.UP)
					if uv.size() > vi:
						st.set_uv(uv[vi])
					st.add_vertex(verts[vi] + offset)
				i += 3
	var out := st.commit()
	if out != null:
		out.surface_set_material(0, parts[0].mesh.material)
	return out


func _prop_material(kind: String) -> StandardMaterial3D:
	match kind:
		"tree":
			return _flat_material(Color(0.20, 0.44, 0.22), 0.9)
		"rock":
			return _flat_material(Color(0.58, 0.52, 0.44), 0.95)
		"building":
			if theme.get("neon", false):
				return _flat_material(Color(0.16, 0.18, 0.30), 0.5, true)
			return _flat_material(Color(0.62, 0.63, 0.68), 0.7)
		"stand":
			return _flat_material(Color(0.72, 0.74, 0.78), 0.8)
	return _flat_material(Color.WHITE, 0.8)


# ---------------------------------------------------------------------------
# checkpoints, start line
# ---------------------------------------------------------------------------

func _build_checkpoints() -> void:
	_checkpoint_root = Node3D.new()
	_checkpoint_root.name = "Checkpoints"
	add_child(_checkpoint_root)

	var n := centerline.size()
	var count := int(TrackData.CHECKPOINTS)
	checkpoint_transforms.clear()
	for i in count:
		# index 0 is the start/finish line; the rest are ordered checkpoints
		var idx := int(round(float(i) * float(n) / float(count))) % n
		var t := _transform_at(idx)
		checkpoint_transforms.append(t)
		var area := Area3D.new()
		area.name = "Checkpoint%d" % i
		area.collision_layer = 0
		# Cars are on physics layer 2, so the gate must *mask* bit 2 to see them.
		# Masking 4 would watch layer 3 and the gate would never fire.
		area.collision_mask = 2
		area.monitoring = true
		area.monitorable = false
		area.set_meta("checkpoint_index", i)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# Wide enough to span the full road plus kerbs so a car hugging a wall
		# still triggers the gate, thin so it cannot be skipped at speed.
		box.size = Vector3(float(track["width"]) + KERB_WIDTH * 2.0 + 2.0, 4.0, 3.0)
		shape.shape = box
		area.add_child(shape)
		area.transform = t
		_checkpoint_root.add_child(area)


func _build_start_gantry() -> void:
	var t := start_transform
	var width := float(track["width"]) + KERB_WIDTH * 2.0
	var root := Node3D.new()
	root.name = "StartGantry"
	root.transform = t

	var left := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.6, 7.0, 0.6)
	left.mesh = lb
	left.position = Vector3(-width * 0.5 - 1.0, 3.5, 0.0)
	left.material_override = _materials["gantry"]
	root.add_child(left)

	var right := MeshInstance3D.new()
	right.mesh = lb
	right.position = Vector3(width * 0.5 + 1.0, 3.5, 0.0)
	right.material_override = _materials["gantry"]
	root.add_child(right)

	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(width + 2.6, 1.1, 0.7)
	beam.mesh = bb
	beam.position = Vector3(0, 7.2, 0.0)
	beam.material_override = _materials["gantry"]
	root.add_child(beam)

	var banner := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width + 2.0, 1.4)
	banner.mesh = q
	banner.position = Vector3(0, 6.2, 0.0)
	banner.rotate_x(-PI * 0.5)
	banner.material_override = _materials["finish"]
	root.add_child(banner)

	add_child(root)

	# Painted start/finish strip on the tarmac.
	var strip := MeshInstance3D.new()
	var strip_mesh := QuadMesh.new()
	strip_mesh.size = Vector2(float(track["width"]), 3.0)
	strip.mesh = strip_mesh
	strip.material_override = _materials["finish"]
	strip.transform = t
	strip.position.y = 0.02
	strip.rotate_x(-PI * 0.5)
	add_child(strip)


# ---------------------------------------------------------------------------
# grid helpers
# ---------------------------------------------------------------------------

func grid_transform(slot: int, total: int) -> Transform3D:
	"""Staggered two-column grid behind the start line."""
	var row := slot / 2
	var column := slot % 2
	var back := 8.0 + float(row) * 7.0
	var lateral := (-1.0 if column == 0 else 1.0) * float(track["width"]) * 0.22
	var idx := index_at_distance(-back)
	var t := _transform_at(idx)
	t.origin += normals[idx] * lateral
	return t


func get_ai_waypoints() -> Array:
	var out: Array = []
	for i in centerline.size():
		out.append(racing_point(i))
	return out


func get_centreline_points() -> PackedVector3Array:
	return centerline
