extends Node
## Central audio helper: builds the bus layout at runtime, preloads every
## stream and hands out pooled players.
##
## Buses are created in code (rather than a .tres) so the project has one
## source of truth and no binary resource can drift out of sync.

const SFX := "Master"
const MUSIC_BUS := "Music"
const ENGINE_BUS := "Engine"

const SOUNDS := {
	"click": "res://assets/audio/ui_click.wav",
	"back": "res://assets/audio/ui_back.wav",
	"countdown": "res://assets/audio/countdown_beep.wav",
	"countdown_go": "res://assets/audio/countdown_go.wav",
	"checkpoint": "res://assets/audio/checkpoint.wav",
	"crash": "res://assets/audio/crash.wav",
	"engine": "res://assets/audio/engine_loop.wav",
	"skid": "res://assets/audio/skid_loop.wav",
	"music": "res://assets/audio/music_menu.wav",
	"victory": "res://assets/audio/victory.wav",
}

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _music_target := 0.0
var _music_fade := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_buses()
	_load_streams()
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MUSIC_BUS
	_music_player.name = "MusicPlayer"
	add_child(_music_player)
	_music_target = Settings.music_volume
	if _streams.has("music"):
		_music_player.stream = _streams["music"]


func _process(delta: float) -> void:
	if _music_player == null:
		return
	if _music_fade > 0.0:
		_music_fade = maxf(0.0, _music_fade - delta)
		var t := 1.0 - (_music_fade / 0.6)
		_music_player.volume_db = _to_db(_music_target * t)
	elif _music_player.playing:
		_music_player.volume_db = _to_db(_music_target)


func _build_buses() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(ENGINE_BUS)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, SFX)


func _load_streams() -> void:
	for key in SOUNDS:
		var path: String = SOUNDS[key]
		if not ResourceLoader.exists(path):
			push_warning("Audio: missing stream %s" % path)
			continue
		var stream: AudioStream = load(path)
		if stream is AudioStreamWAV:
			# Loop the two bed loops so they can be held indefinitely.
			if key in ["engine", "skid", "music"]:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_begin = 0
				stream.loop_end = 0
		_streams[key] = stream


func play(key: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	if not _streams.has(key):
		return null
	var player := _get_player()
	player.stream = _streams[key]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.bus = SFX
	player.play()
	return player


func play_ui(key: String) -> void:
	play(key, -6.0)


func make_loop(key: String, bus: String) -> AudioStreamPlayer:
	"""Creates a dedicated looping player (engine, tyres) owned by the caller."""
	if not _streams.has(key):
		return null
	var player := AudioStreamPlayer.new()
	player.stream = _streams[key]
	player.bus = bus
	add_child(player)
	return player


func start_music() -> void:
	if _music_player == null or not _streams.has("music"):
		return
	_music_target = Settings.music_volume
	if not _music_player.playing:
		_music_player.volume_db = _to_db(0.0)
		_music_fade = 0.6
		_music_player.play()
	else:
		_music_player.volume_db = _to_db(_music_target)


func stop_music(fade: bool = true) -> void:
	if _music_player == null:
		return
	if fade:
		_music_target = 0.0
		_music_fade = 0.6
	else:
		_music_player.stop()


func apply_volumes() -> void:
	var master := AudioServer.get_bus_index(SFX)
	if master != -1:
		AudioServer.set_bus_volume_db(master, _to_db(Settings.sfx_volume))
	var music := AudioServer.get_bus_index(MUSIC_BUS)
	if music != -1:
		AudioServer.set_bus_volume_db(music, _to_db(Settings.music_volume))
	_music_target = Settings.music_volume
	var engine := AudioServer.get_bus_index(ENGINE_BUS)
	if engine != -1:
		AudioServer.set_bus_volume_db(engine, _to_db(Settings.sfx_volume))


func _get_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	if _pool.size() >= 16:
		return _pool[0]
	var player := AudioStreamPlayer.new()
	player.bus = SFX
	add_child(player)
	_pool.append(player)
	return player


func _to_db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return linear_to_db(linear)


func vibrate(ms: int = 40) -> void:
	if not Settings.vibration:
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
