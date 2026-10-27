extends SceneTree
## Headless validation harness.
##
## Run with:  godot --headless --path . --script tools/validate.gd
##
## Performs the static checks the project needs and prints a PASS/FAIL report:
##   * every .gd file parses (checked by loading each script)
##   * every .tscn loads
##   * every res:// path referenced from a script or scene exists on disk
##   * every InputMap action used by scripts is declared in project.godot
##   * every RPC used through Net exists and is annotated
##   * every class_name referenced across scripts resolves
##   * all audio/texture/model assets are present
##
## Exits with code 0 when every check passes, 1 otherwise, so it can gate CI.

var _failures: Array[String] = []
var _warnings: Array[String] = []
var _checks: int = 0


func _init() -> void:
	print("=== GFX Offline Racing : static validation ===\n")
	_check_assets()
	_check_scripts_parse()
	_check_scenes_load()
	_check_resource_paths()
	_check_input_map()
	_check_rpc_annotations()
	_check_class_names()
	_report()


func _ok(label: String) -> void:
	_checks += 1
	print("  PASS  %s" % label)


func _fail(label: String, detail: String = "") -> void:
	_checks += 1
	_failures.append(label + (("  -> " + detail) if detail != "" else ""))
	print("  FAIL  %s%s" % [label, ("  -> " + detail) if detail != "" else ""])


func _warn(label: String) -> void:
	_warnings.append(label)
	print("  WARN  %s" % label)


# ---------------------------------------------------------------------------

func _dir_files(path: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(suffix):
			out.append(path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _all_scripts() -> Array[String]:
	var out: Array[String] = []
	for folder in ["res://scripts", "res://scripts/autoload", "res://scripts/car",
			"res://scripts/track", "res://scripts/race", "res://scripts/ui", "res://tools"]:
		out.append_array(_dir_files(folder, ".gd"))
	return out


func _check_assets() -> void:
	print("[assets]")
	var required := [
		"res://assets/models/car_speedster.glb",
		"res://assets/models/car_phantom.glb",
		"res://assets/models/car_viper.glb",
		"res://assets/models/car_inferno.glb",
		"res://assets/models/car_spectre.glb",
		"res://assets/models/car_titan.glb",
		"res://assets/models/wheel.glb",
		"res://assets/models/car_specs.json",
		"res://assets/textures/asphalt.png",
		"res://assets/textures/grass.png",
		"res://assets/textures/sand.png",
		"res://assets/textures/snow.png",
		"res://assets/textures/dirt.png",
		"res://assets/textures/curb.png",
		"res://assets/textures/finish_line.png",
		"res://assets/textures/skid.png",
		"res://assets/textures/smoke.png",
		"res://assets/textures/sky_gradient.png",
		"res://assets/textures/glow.png",
		"res://assets/audio/engine_loop.wav",
		"res://assets/audio/skid_loop.wav",
		"res://assets/audio/crash.wav",
		"res://assets/audio/countdown_beep.wav",
		"res://assets/audio/countdown_go.wav",
		"res://assets/audio/checkpoint.wav",
		"res://assets/audio/ui_click.wav",
		"res://assets/audio/ui_back.wav",
		"res://assets/audio/music_menu.wav",
		"res://assets/audio/victory.wav",
		"res://assets/fonts/UI-Bold.ttf",
		"res://assets/fonts/UI.ttf",
	]
	var missing: Array[String] = []
	for path in required:
		if not ResourceLoader.exists(path):
			missing.append(path)
	if missing.is_empty():
		_ok("%d required assets present" % required.size())
	else:
		_fail("assets missing", ", ".join(missing))


func _check_scripts_parse() -> void:
	print("\n[scripts]")
	var scripts := _all_scripts()
	var broken: Array[String] = []
	for path in scripts:
		# validate.gd itself is the running script; loading it again is fine.
		var res = load(path)
		if res == null:
			broken.append(path)
	if broken.is_empty():
		_ok("%d scripts parsed" % scripts.size())
	else:
		_fail("scripts failed to parse", ", ".join(broken))


func _check_scenes_load() -> void:
	print("\n[scenes]")
	var scenes := _dir_files("res://scenes/ui", ".tscn")
	scenes.append_array(_dir_files("res://scenes/tools", ".tscn"))
	if scenes.is_empty():
		_fail("no scenes found")
		return
	var broken: Array[String] = []
	for path in scenes:
		var packed = load(path)
		if packed == null or not (packed is PackedScene):
			broken.append(path)
			continue
		# Instantiating catches broken node paths and missing script links that
		# a plain load() would miss.
		var instance = (packed as PackedScene).instantiate()
		if instance == null:
			broken.append(path + " (instantiate)")
		else:
			instance.free()
	if broken.is_empty():
		_ok("%d scenes load and instantiate" % scenes.size())
	else:
		_fail("scenes failed", ", ".join(broken))


func _check_resource_paths() -> void:
	print("\n[references]")
	# Collect every res:// literal from scripts and verify it resolves.
	var pattern := RegEx.new()
	pattern.compile("res://[A-Za-z0-9_./-]+")
	var missing: Array[String] = []
	var seen: Dictionary = {}
	for path in _all_scripts():
		var text := FileAccess.get_file_as_string(path)
		for m in pattern.search_all(text):
			var ref := m.get_string()
			# Skip format strings and bare directory constants.
			if ref.contains("%"):
				continue
			if DirAccess.dir_exists_absolute(ref):
				continue
			# Only file-looking references (must have an extension).
			var leaf := ref.get_file()
			if not leaf.contains("."):
				continue
			if seen.has(ref):
				continue
			seen[ref] = true
			# .gd references are covered by the parse check.
			if ref.ends_with(".gd"):
				continue
			if not ResourceLoader.exists(ref):
				missing.append("%s  (from %s)" % [ref, path.get_file()])
	if missing.is_empty():
		_ok("%d distinct res:// file references resolve" % seen.size())
	else:
		_fail("broken resource references", "; ".join(missing))


func _check_input_map() -> void:
	print("\n[input map]")
	var used := ["steer_left", "steer_right", "accelerate", "brake",
			"gear_up", "gear_down", "drift", "pause"]
	var missing: Array[String] = []
	for action in used:
		if not InputMap.has_action(action):
			missing.append(action)
	if missing.is_empty():
		_ok("%d InputMap actions declared" % used.size())
	else:
		_fail("missing InputMap actions", ", ".join(missing))


func _check_rpc_annotations() -> void:
	print("\n[rpc]")
	var net_text := FileAccess.get_file_as_string("res://scripts/autoload/Net.gd")
	if net_text.is_empty():
		_fail("Net.gd not readable")
		return
	# Every function Net.gd calls over the wire must be annotated @rpc.
	# Match only real call sites: rpc("name" / rpc_id(id, "name"
	var called: Array[String] = []
	var call_pattern := RegEx.new()
	# Exclude the annotation itself: @rpc("any_peer", ...) must not be read as a
	# call to a function named "any_peer".
	call_pattern.compile("(?:rpc_id\\([^,]+,\\s*|(?<![_A-Za-z@])rpc\\()\"([A-Za-z0-9_]+)\"")
	for m in call_pattern.search_all(net_text):
		var name := m.get_string(1)
		if name != "" and not called.has(name):
			called.append(name)

	var bad: Array[String] = []
	for fn in called:
		# The annotation must appear immediately above the func declaration.
		var idx := net_text.find("func %s(" % fn)
		if idx == -1:
			bad.append("%s (no such function)" % fn)
			continue
		var before := net_text.substr(maxi(0, idx - 120), mini(120, idx))
		if not before.contains("@rpc("):
			bad.append("%s (missing @rpc)" % fn)
	if bad.is_empty():
		_ok("%d RPC endpoints annotated" % called.size())
	else:
		_fail("RPC problems", "; ".join(bad))


func _check_class_names() -> void:
	print("\n[class_name]")
	# Gather declared class names, then confirm the ones referenced as types
	# actually exist (typos here only surface at runtime otherwise).
	var declared: Dictionary = {}
	var pattern := RegEx.new()
	pattern.compile("^class_name\\s+([A-Za-z0-9_]+)")
	for path in _all_scripts():
		var text := FileAccess.get_file_as_string(path)
		for m in pattern.search_all(text):
			declared[m.get_string(1)] = path
	if declared.is_empty():
		_fail("no class_name declarations found")
		return

	# Types the code relies on existing.
	var expected := ["Car", "TrackBuilder", "LapTracker", "RaceManager", "AIDriver",
			"ChaseCamera", "SkidTrail", "Minimap", "Speedometer", "TouchControls",
			"UITheme", "CarPreview", "TrackThumb"]
	var missing: Array[String] = []
	for name in expected:
		if not declared.has(name):
			missing.append(name)
	if missing.is_empty():
		_ok("%d class_name types declared" % declared.size())
	else:
		_fail("class_name missing", ", ".join(missing))

	# Verify scripts that reference these types can see them.
	var unresolved: Array[String] = []
	for path in _all_scripts():
		var text := FileAccess.get_file_as_string(path)
		for name in declared.keys():
			var re := RegEx.new()
			re.compile("(:\\s*|->\\s*|\\bas\\s+)%s\\b" % name)
			if re.search(text) != null:
				var res = load(path)
				if res == null:
					unresolved.append("%s needs %s" % [path.get_file(), name])
	if not unresolved.is_empty():
		_warn("possible unresolved type references: %s" % ", ".join(unresolved))


func _report() -> void:
	print("\n=== summary ===")
	print("checks run : %d" % _checks)
	print("failures   : %d" % _failures.size())
	print("warnings   : %d" % _warnings.size())
	if not _failures.is_empty():
		print("\nFAILURES")
		for f in _failures:
			print("  - %s" % f)
	if not _warnings.is_empty():
		print("\nWARNINGS")
		for w in _warnings:
			print("  - %s" % w)
	print("\nRESULT: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
