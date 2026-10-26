extends Control
## Mode selection: opponents, difficulty, laps and the chosen track.
##
## Laps are fixed at 12 for the championship (the spec requires exactly 12);
## the row is shown so the rule is visible rather than hidden.

const DIFFICULTIES := ["easy", "normal", "hard"]
const OPPONENT_COUNTS := [1, 2, 3, 5]

var _difficulty_option: OptionButton
var _opponents_option: OptionButton
var _track_option: OptionButton
var _track_ids: Array[String] = []
var _summary: Label


func _ready() -> void:
	_build()


func _build() -> void:
	var page := UITheme.make_screen("PLAY VS AI", "Choose your race, then hit Start")
	add_child(page)
	var column := page.get_node("MarginContainer/Content")

	var panel := UITheme.make_panel()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)

	var box := UITheme.make_vbox(14)
	panel.add_child(box)

	# difficulty
	box.add_child(_row_label("Difficulty"))
	_difficulty_option = UITheme.make_option(["Easy", "Normal", "Hard"],
			DIFFICULTIES.find(Settings.difficulty))
	_difficulty_option.item_selected.connect(func(i: int):
		Settings.difficulty = DIFFICULTIES[i]
		Settings.save_settings()
		_refresh_summary())
	box.add_child(_difficulty_option)

	# opponents
	box.add_child(_row_label("Opponents"))
	var labels := []
	for c in OPPONENT_COUNTS:
		labels.append("%d AI drivers" % c)
	_opponents_option = UITheme.make_option(labels, 2)
	_opponents_option.item_selected.connect(func(_i: int): _refresh_summary())
	box.add_child(_opponents_option)

	# track
	box.add_child(_row_label("Track"))
	_track_ids.clear()
	var track_labels := []
	for id in TrackData.ORDER:
		_track_ids.append(id)
		track_labels.append(TrackData.display_name(id))
	_track_option = UITheme.make_option(track_labels, maxi(0, _track_ids.find(Settings.selected_track)))
	_track_option.item_selected.connect(func(i: int):
		Settings.selected_track = _track_ids[i]
		Settings.save_settings()
		_refresh_summary())
	box.add_child(_track_option)

	# laps (fixed)
	box.add_child(_row_label("Race length"))
	var laps := UITheme.make_label("12 laps  (championship length, fixed)", 18, UITheme.TEXT_DIM)
	box.add_child(laps)

	_summary = UITheme.make_label("", 16, UITheme.ACCENT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)

	var actions := UITheme.make_hbox(12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(actions)

	var back := UITheme.make_button("Back", UITheme.ACCENT_DANGER, 54.0)
	back.custom_minimum_size = Vector2(200, 54)
	back.pressed.connect(func():
		Audio.play_ui("back")
		SceneRouter.go_to("menu"))
	actions.add_child(back)

	var start := UITheme.make_button("START RACE", UITheme.ACCENT_WARM, 60.0)
	start.custom_minimum_size = Vector2(300, 60)
	start.pressed.connect(_start)
	actions.add_child(start)

	_refresh_summary()


func _row_label(text: String) -> Label:
	var l := UITheme.make_label(text, 18, UITheme.TEXT, true)
	return l


func _refresh_summary() -> void:
	var track := TrackData.get_track(Settings.selected_track)
	var opponents: int = OPPONENT_COUNTS[_opponents_option.selected]
	_summary.text = "%s  -  %d laps  -  %d opponents  -  %s" % [
		track["name"], TrackData.LAPS, opponents, Settings.difficulty.capitalize()
	]


func _start() -> void:
	Audio.play_ui("click")
	Settings.selected_track = _track_ids[_track_option.selected]
	Settings.difficulty = DIFFICULTIES[_difficulty_option.selected]
	Settings.save_settings()
	SceneRouter.go_to("race", {
		"mode": "ai",
		"track": Settings.selected_track,
		"difficulty": Settings.difficulty,
		"laps": TrackData.LAPS,
		"ai": OPPONENT_COUNTS[_opponents_option.selected],
	})
