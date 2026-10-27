extends Control
## Results / champion screen.
##
## The winner is whoever the host (or the single-player lap tracker) declared,
## never whoever happened to open this screen. Position, total time, best lap
## and completed laps come straight from that result table.

var _results: Array = []
var _laps: int = 12
var _track_id: String = "city_circuit"
var _trophy_phase: float = 0.0
var _trophy: Trophy
var _headline: Label
var _subhead: Label


func _ready() -> void:
	_results = SceneRouter.take("results", [])
	_laps = int(SceneRouter.take("laps", 12))
	_track_id = str(SceneRouter.take("track", Settings.selected_track))
	_build()
	_record_best_laps()


func _build() -> void:
	add_child(UITheme.make_background())

	var root := UITheme.make_vbox(10)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	var margin := UITheme.make_margin(40, 24, 40, 24)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(root)
	add_child(margin)

	_trophy = Trophy.new()
	_trophy.custom_minimum_size = Vector2(170, 170)
	_trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(_trophy)

	_headline = UITheme.make_title("RACE COMPLETE", 46)
	root.add_child(_headline)

	_subhead = UITheme.make_label("", 20, UITheme.ACCENT_WARM)
	_subhead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_subhead)

	var table_panel := UITheme.make_panel()
	table_panel.custom_minimum_size = Vector2(760, 0)
	table_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(table_panel)

	var table := UITheme.make_vbox(6)
	table_panel.add_child(table)

	# header row
	var header := UITheme.make_hbox(12)
	table.add_child(header)
	for entry in [["POS", 60], ["DRIVER", 220], ["LAPS", 80], ["TOTAL", 130], ["BEST LAP", 140]]:
		var l := UITheme.make_label(str(entry[0]), 16, UITheme.TEXT_DIM, true)
		l.custom_minimum_size = Vector2(float(entry[1]), 24)
		header.add_child(l)

	if _results.is_empty():
		table.add_child(UITheme.make_label("No result data was received.", 18, UITheme.TEXT_DIM))
	else:
		for row in _results:
			table.add_child(_make_row(row))

	# winner / loser summary
	if not _results.is_empty():
		var first: Dictionary = _results[0]
		var last: Dictionary = _results[_results.size() - 1]
		var winner_name := str(first.get("name", "Winner"))
		_subhead.text = "Winner: %s   -   %s" % [winner_name, str(first.get("car_id", ""))]
		if _results.size() > 1:
			_subhead.text += "     |     Last: %s" % str(last.get("name", ""))

	var actions := UITheme.make_hbox(12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(actions)

	var retry := UITheme.make_button("Race again", UITheme.ACCENT_WARM, 56.0)
	retry.custom_minimum_size = Vector2(240, 56)
	retry.pressed.connect(_on_retry)
	actions.add_child(retry)

	var menu := UITheme.make_button("Main menu", UITheme.ACCENT, 56.0)
	menu.custom_minimum_size = Vector2(240, 56)
	menu.pressed.connect(func():
		Audio.play_ui("back")
		if Net.is_online():
			Net.leave_room()
		SceneRouter.go_to("menu"))
	actions.add_child(menu)

	UITheme.add_footer(self, "%s  -  %d laps" % [TrackData.display_name(_track_id), _laps])


func _make_row(row: Dictionary) -> Control:
	var h := UITheme.make_hbox(12)
	var is_player := bool(row.get("is_player", false))
	var colour := UITheme.ACCENT_WARM if is_player else UITheme.TEXT
	var position := int(row.get("position", 0))
	var laps := int(row.get("laps", _laps))
	var total := float(row.get("total_time", 0.0))
	var best := float(row.get("best_lap", INF))

	var cells := [
		["%d" % position, 60],
		[str(row.get("name", "Driver")), 220],
		["%d/%d" % [laps, _laps], 80],
		[_format_time(total), 130],
		[_format_time(best), 140],
	]
	for cell in cells:
		var l := UITheme.make_label(str(cell[0]), 18, colour, is_player)
		l.custom_minimum_size = Vector2(float(cell[1]), 26)
		h.add_child(l)
	return h


func _process(delta: float) -> void:
	_trophy_phase += delta
	if _trophy != null:
		_trophy.phase = _trophy_phase
		_trophy.queue_redraw()


func _record_best_laps() -> void:
	for row in _results:
		if not bool(row.get("is_player", false)):
			continue
		var best := float(row.get("best_lap", INF))
		if best > 0.0 and best != INF:
			Settings.record_lap(_track_id, best)


func _on_retry() -> void:
	Audio.play_ui("click")
	if Net.is_online() and not Net.is_host():
		# A guest cannot restart alone: the host owns race state. Send them back
		# to the lobby where they can retry or leave cleanly.
		SceneRouter.go_to("lobby", {"message": "Ask the host to restart, or leave the room."})
		return
	if Net.is_online() and Net.is_host():
		Net.host_restart_race()
	SceneRouter.go_to("race", {
		"mode": "host" if Net.is_host() else ("client" if Net.is_client() else "ai"),
		"track": _track_id,
		"difficulty": Settings.difficulty,
		"laps": _laps,
		"ai": 3,
	})


static func _format_time(seconds: float) -> String:
	if seconds <= 0.0 or seconds == INF or is_nan(seconds):
		return "--:--.---"
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	var ms := int((seconds - floor(seconds)) * 1000.0)
	return "%d:%02d.%03d" % [m, s, ms]


# ---------------------------------------------------------------------------
# trophy
# ---------------------------------------------------------------------------

class Trophy:
	extends Control
	var phase: float = 0.0

	func _draw() -> void:
		var centre := size * 0.5
		var scale_factor := minf(size.x, size.y) / 170.0
		var bob := sin(phase * 2.2) * 6.0 * scale_factor
		centre.y += bob

		# Glow
		var glow_alpha := 0.25 + 0.15 * sin(phase * 3.0)
		draw_circle(centre, 74.0 * scale_factor, Color(1.0, 0.78, 0.20, glow_alpha))

		# Cup
		var gold := Color(1.0, 0.82, 0.24)
		var gold_dark := Color(0.78, 0.55, 0.10)
		var cup_points := PackedVector2Array([
			centre + Vector2(-34, -40) * scale_factor,
			centre + Vector2(34, -40) * scale_factor,
			centre + Vector2(26, 18) * scale_factor,
			centre + Vector2(-26, 18) * scale_factor,
		])
		draw_colored_polygon(cup_points, gold)
		draw_polyline(PackedVector2Array([cup_points[0], cup_points[1], cup_points[2], cup_points[3], cup_points[0]]),
				gold_dark, 2.0, true)

		# Handles
		draw_arc(centre + Vector2(-34, -22) * scale_factor, 20.0 * scale_factor,
				deg_to_rad(70), deg_to_rad(290), 20, gold_dark, 4.0 * scale_factor, true)
		draw_arc(centre + Vector2(34, -22) * scale_factor, 20.0 * scale_factor,
				deg_to_rad(-110), deg_to_rad(110), 20, gold_dark, 4.0 * scale_factor, true)

		# Stem and base
		draw_rect(Rect2(centre + Vector2(-8, 18) * scale_factor, Vector2(16, 20) * scale_factor), gold_dark, true)
		draw_rect(Rect2(centre + Vector2(-28, 38) * scale_factor, Vector2(56, 12) * scale_factor), gold, true)

		# Sparkles
		for i in 6:
			var a := phase * 1.6 + float(i) * TAU / 6.0
			var r := 62.0 * scale_factor
			var pos := centre + Vector2(cos(a), sin(a) * 0.5) * r
			var alpha := 0.35 + 0.4 * absf(sin(phase * 3.0 + float(i)))
			draw_circle(pos, 3.5 * scale_factor, Color(1.0, 0.95, 0.70, alpha))
