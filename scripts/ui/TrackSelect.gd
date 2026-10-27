extends Control
## Track selection with a real layout thumbnail and an honest readiness note.
##
## Every listed track is genuinely playable: they are all generated from
## distinct control polygons in TrackData. The readiness note exists so the
## screen states what has actually been verified rather than implying more.

var _selected: int = 0
var _cards: Array[Button] = []
var _thumb: TrackThumb
var _name_label: Label
var _info_label: Label
var _record_label: Label


func _ready() -> void:
	_build()
	_selected = maxi(0, TrackData.ORDER.find(Settings.selected_track))
	_refresh()


func _build() -> void:
	var page := UITheme.make_screen("TRACK SELECTION", "6 circuits - each a distinct layout")
	add_child(page)
	var column := page.get_node("MarginContainer/Content")

	var body := UITheme.make_hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	# ---- list ----------------------------------------------------------
	var list_panel := UITheme.make_panel()
	list_panel.custom_minimum_size = Vector2(340, 0)
	body.add_child(list_panel)
	var list := UITheme.make_vbox(8)
	list_panel.add_child(list)

	for i in TrackData.ORDER.size():
		var id: String = TrackData.ORDER[i]
		var data := TrackData.get_track(id)
		var b := UITheme.make_button("%s\n%d corners - difficulty %d/5" % [
			data["name"], _corner_count(data), int(data["difficulty"])
		], UITheme.ACCENT, 76.0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_select.bind(i))
		list.add_child(b)
		_cards.append(b)

	# ---- preview -------------------------------------------------------
	var preview_panel := UITheme.make_panel(Color(0.04, 0.06, 0.11, 0.6))
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(preview_panel)

	var preview_box := UITheme.make_vbox(10)
	preview_panel.add_child(preview_box)

	_name_label = UITheme.make_label("", 30, UITheme.TEXT, true)
	preview_box.add_child(_name_label)

	_thumb = TrackThumb.new()
	_thumb.custom_minimum_size = Vector2(320, 300)
	_thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_box.add_child(_thumb)

	_info_label = UITheme.make_label("", 17, UITheme.TEXT_DIM)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_box.add_child(_info_label)

	_record_label = UITheme.make_label("", 17, UITheme.ACCENT)
	preview_box.add_child(_record_label)

	var note := UITheme.make_label(
		"All six circuits are generated from distinct control polygons and share the same "
		+ "12-lap checkpoint rules. Each has its own surface, lighting and scenery theme.",
		15, Color(0.52, 0.59, 0.70))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_box.add_child(note)

	# ---- actions -------------------------------------------------------
	var actions := UITheme.make_hbox(12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(actions)

	var back := UITheme.make_button("Back", UITheme.ACCENT_DANGER, 54.0)
	back.custom_minimum_size = Vector2(200, 54)
	back.pressed.connect(func():
		Audio.play_ui("back")
		SceneRouter.go_to("menu"))
	actions.add_child(back)

	var select := UITheme.make_button("Use this track", UITheme.ACCENT, 58.0)
	select.custom_minimum_size = Vector2(280, 58)
	select.pressed.connect(_confirm)
	actions.add_child(select)


func _corner_count(data: Dictionary) -> int:
	var pts: Array = data["points"]
	var count := 0
	var n := pts.size()
	for i in n:
		var a: Vector2 = pts[(i - 1 + n) % n]
		var b: Vector2 = pts[i]
		var c: Vector2 = pts[(i + 1) % n]
		var v1 := (b - a).normalized()
		var v2 := (c - b).normalized()
		if v1.dot(v2) < 0.985:
			count += 1
	return count


func _on_select(index: int) -> void:
	Audio.play_ui("click")
	_selected = index
	_refresh()


func _refresh() -> void:
	var id: String = TrackData.ORDER[_selected]
	var data := TrackData.get_track(id)
	_name_label.text = str(data["name"])
	_thumb.set_track(id)
	_info_label.text = "%d corners  -  road width %.0f m  -  theme: %s" % [
		_corner_count(data), float(data["width"]), str(data["theme"]).capitalize()
	]
	var best := float(Settings.best_laps.get(id, 0.0))
	if best > 0.0:
		_record_label.text = "Your best lap: %s" % _format_time(best)
	else:
		_record_label.text = "No lap recorded yet"
	for i in _cards.size():
		UITheme.apply_button_style(_cards[i], UITheme.ACCENT_WARM if i == _selected else UITheme.ACCENT)


func _confirm() -> void:
	Audio.play_ui("click")
	Settings.selected_track = TrackData.ORDER[_selected]
	Settings.save_settings()
	SceneRouter.go_to("menu")


static func _format_time(seconds: float) -> String:
	if seconds <= 0.0 or seconds == INF:
		return "--:--.---"
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	var ms := int((seconds - floor(seconds)) * 1000.0)
	return "%d:%02d.%03d" % [m, s, ms]
