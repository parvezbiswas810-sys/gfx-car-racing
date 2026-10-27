extends Node
## Screen navigation and transient hand-off data between screens.
##
## Screens are swapped through change_scene_to_file so nothing from the previous
## race stays resident on a phone. Anything a screen needs to know is passed in
## `params` and read once in its _ready().

const SCREENS := {
	"splash": "res://scenes/ui/Splash.tscn",
	"menu": "res://scenes/ui/MainMenu.tscn",
	"mode": "res://scenes/ui/ModeSelect.tscn",
	"garage": "res://scenes/ui/Garage.tscn",
	"tracks": "res://scenes/ui/TrackSelect.tscn",
	"settings": "res://scenes/ui/Settings.tscn",
	"lobby": "res://scenes/ui/Lobby.tscn",
	"race": "res://scenes/ui/Race.tscn",
	"results": "res://scenes/ui/Results.tscn",
}

var params: Dictionary = {}


func go_to(screen: String, p_params: Dictionary = {}) -> void:
	params = p_params
	get_tree().paused = false
	if not SCREENS.has(screen):
		push_error("SceneRouter: unknown screen '%s'" % screen)
		return
	var path: String = SCREENS[screen]
	if not ResourceLoader.exists(path):
		push_error("SceneRouter: missing scene %s" % path)
		return
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneRouter: could not load %s (error %d)" % [path, err])


func take(key: String, fallback: Variant = null) -> Variant:
	if params.has(key):
		var value = params[key]
		params.erase(key)
		return value
	return fallback


func peek(key: String, fallback: Variant = null) -> Variant:
	return params.get(key, fallback)


func quit_game() -> void:
	# Android has no meaningful quit: the OS owns the app lifecycle. Sending the
	# notification is still correct so the app leaves cleanly on desktop.
	get_tree().quit()
