extends Node
## LAN connection, lobby state and authoritative race-state relay.
##
## Architecture
##   * The host calls create_room(); the second device calls join_room().
##   * The host is the only authority for lobby state, the countdown, lap
##     validation and the race result. Clients send *requests*, never results.
##   * Frequent vehicle updates travel as unreliable_ordered so a dropped
##     packet is replaced by the next one instead of stalling the race.
##   * Anything that changes the outcome of the race (laps, finish, countdown,
##     room state) travels reliably.
##
## Nothing here touches the internet: ENetMultiplayerPeer is a plain UDP
## socket over the local network or a phone hotspot.

signal room_created(port: int)
signal room_create_failed(reason: String)
signal join_succeeded()
signal join_failed(reason: String)
signal peer_joined(id: int, info: Dictionary)
signal peer_left(id: int)
signal lobby_updated()
signal host_left()
signal connection_lost(reason: String)
signal countdown_received(start_at: float, laps: int)
signal car_state_received(id: int, state: Dictionary)
signal lap_received(id: int, lap: int)
signal race_finished_received(results: Array)
signal race_restart_received()

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const JOIN_TIMEOUT := 8.0
const STATE_HZ := 20.0

enum Mode { OFFLINE, HOST, CLIENT }

var mode: int = Mode.OFFLINE
var room_name: String = "GFX Room"
var port: int = DEFAULT_PORT
var local_ip: String = ""

## id -> {name, ready, car_id, difficulty, is_host}
var players: Dictionary = {}
## Authoritative result table, only meaningful on the host.
var race_results: Array = []

var _join_timer: float = 0.0
var _joining: bool = false
var _expected_peers: int = 0
var _state_accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	local_ip = detect_local_ip()


func _process(delta: float) -> void:
	if _joining:
		_join_timer -= delta
		if _join_timer <= 0.0:
			_joining = false
			_teardown()
			join_failed.emit("Connection timed out. Check both phones are on the same Wi-Fi or hotspot and that the IP is correct.")


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


func is_online() -> bool:
	return mode != Mode.OFFLINE


func my_id() -> int:
	if not is_online():
		return 1
	return multiplayer.get_unique_id()


func player_ids() -> Array:
	var ids := players.keys()
	ids.sort()
	return ids


func player_count() -> int:
	return players.size()


func get_player(id: int) -> Dictionary:
	return players.get(id, {})


func detect_local_ip() -> String:
	"""Best-effort private IPv4 lookup for showing the host address.

	Returns an empty string when nothing reliable is found so the UI can ask
	the host to type the address manually instead of showing a wrong one.
	"""
	var candidates: Array[String] = []
	for addr in IP.get_local_addresses():
		if addr.contains(":"):
			continue  # IPv6 is not used by the ENet peer here
		if addr.begins_with("127.") or addr == "0.0.0.0":
			continue
		candidates.append(addr)
	# Prefer the usual hotspot / home-router ranges, then anything else.
	for prefix in ["192.168.", "10.", "172."]:
		for addr in candidates:
			if addr.begins_with(prefix):
				return addr
	if candidates.size() > 0:
		return candidates[0]
	return ""


# ---------------------------------------------------------------------------
# hosting
# ---------------------------------------------------------------------------

func create_room(p_room_name: String, p_port: int) -> bool:
	_teardown()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p_port, MAX_PLAYERS)
	if err != OK:
		var reason := "Could not open UDP port %d. Try a different port (the range 1024-65535 works best)." % p_port
		if err == ERR_ALREADY_IN_USE:
			reason = "UDP port %d is already in use. Pick another port." % p_port
		room_create_failed.emit(reason)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	port = p_port
	room_name = p_room_name
	players.clear()
	players[1] = _make_info(1, "Host", true)
	local_ip = detect_local_ip()
	room_created.emit(port)
	lobby_updated.emit()
	return true


func _make_info(id: int, p_name: String, p_is_host: bool) -> Dictionary:
	var car := Settings.selected_car if p_is_host else "car_speedster"
	return {
		"name": p_name,
		"ready": p_is_host,
		"car_id": car,
		"colour": Settings.paint_colour if p_is_host else Color(0.8, 0.8, 0.85),
		"difficulty": Settings.difficulty,
		"is_host": p_is_host,
	}


# ---------------------------------------------------------------------------
# joining
# ---------------------------------------------------------------------------

func join_room(ip: String, p_port: int, player_name: String = "Player") -> bool:
	_teardown()
	ip = ip.strip_edges()
	if ip.is_empty():
		join_failed.emit("Enter the host's IP address.")
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, p_port)
	if err != OK:
		join_failed.emit("Could not start a connection to %s:%d." % [ip, p_port])
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	port = p_port
	_my_name = player_name
	_joining = true
	_join_timer = JOIN_TIMEOUT
	return true


var _my_name: String = "Player"


func set_player_name(n: String) -> void:
	_my_name = n


func leave_room() -> void:
	if is_client():
		# Tell the host before dropping the socket so the lobby updates promptly.
		rpc_id(1, "_rpc_client_leaving")
	_teardown()
	players.clear()
	race_results.clear()
	mode = Mode.OFFLINE
	lobby_updated.emit()


func _teardown() -> void:
	_joining = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


# ---------------------------------------------------------------------------
# lobby flow (host authoritative)
# ---------------------------------------------------------------------------

func set_ready(ready: bool) -> void:
	var id := my_id()
	if is_host():
		if players.has(id):
			players[id]["ready"] = ready
			rpc("_rpc_lobby_sync", players)
			lobby_updated.emit()
	else:
		rpc_id(1, "_rpc_request_ready", ready)


func set_my_car(car_id: String, colour: Color) -> void:
	var id := my_id()
	if is_host():
		if players.has(id):
			players[id]["car_id"] = car_id
			players[id]["colour"] = colour
			rpc("_rpc_lobby_sync", players)
			lobby_updated.emit()
	else:
		rpc_id(1, "_rpc_request_car", car_id, colour)


func host_start_race(laps: int) -> bool:
	"""Host-only. Returns false when somebody is not ready yet."""
	if not is_host():
		return false
	for id in players:
		if not bool(players[id].get("ready", false)):
			return false
	race_results.clear()
	var start_at := float(Time.get_ticks_msec()) / 1000.0 + 0.35
	rpc("_rpc_begin_countdown", start_at, laps)
	countdown_received.emit(start_at, laps)
	return true


func host_restart_race() -> void:
	if not is_host():
		return
	race_results.clear()
	rpc("_rpc_restart_race")
	race_restart_received.emit()


# ---------------------------------------------------------------------------
# connection callbacks
# ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	# The client registers itself right after connecting; nothing to do until then.
	print("Net: peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		peer_left.emit(id)
		lobby_updated.emit()
		if is_host():
			rpc("_rpc_lobby_sync", players)


func _on_connected_ok() -> void:
	_joining = false
	rpc_id(1, "_rpc_register_player", _my_name, Settings.selected_car, Settings.paint_colour, Settings.difficulty)
	join_succeeded.emit()


func _on_connected_fail() -> void:
	_joining = false
	_teardown()
	mode = Mode.OFFLINE
	join_failed.emit("Could not reach the host. Confirm the IP address, that the host pressed Create Room, and that both devices share the same network.")


func _on_server_disconnected() -> void:
	var was_client := is_client()
	_teardown()
	mode = Mode.OFFLINE
	players.clear()
	if was_client:
		host_left.emit()
		connection_lost.emit("The host closed the room.")


# ---------------------------------------------------------------------------
# RPCs - lobby
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_register_player(p_name: String, car_id: String, colour: Color, difficulty: String) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	if players.size() >= MAX_PLAYERS:
		rpc_id(sender, "_rpc_kicked", "The room is full.")
		return
	var info := {
		"name": _sanitise_name(p_name),
		"ready": false,
		"car_id": car_id,
		"colour": colour,
		"difficulty": difficulty,
		"is_host": false,
	}
	players[sender] = info
	rpc("_rpc_lobby_sync", players)
	peer_joined.emit(sender, info)
	lobby_updated.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_ready(ready: bool) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["ready"] = ready
		rpc("_rpc_lobby_sync", players)
		lobby_updated.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_car(car_id: String, colour: Color) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["car_id"] = car_id
		players[sender]["colour"] = colour
		rpc("_rpc_lobby_sync", players)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_leaving() -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		players.erase(sender)
		peer_left.emit(sender)
		rpc("_rpc_lobby_sync", players)
		lobby_updated.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby_sync(snapshot: Dictionary) -> void:
	players = snapshot
	lobby_updated.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_kicked(reason: String) -> void:
	_teardown()
	mode = Mode.OFFLINE
	players.clear()
	join_failed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_begin_countdown(start_at: float, laps: int) -> void:
	countdown_received.emit(start_at, laps)


@rpc("authority", "call_remote", "reliable")
func _rpc_restart_race() -> void:
	race_restart_received.emit()


# ---------------------------------------------------------------------------
# RPCs - vehicle state (host relays, never trusts a client's race outcome)
# ---------------------------------------------------------------------------

func push_car_state(state: Dictionary) -> void:
	if not is_online():
		return
	if is_host():
		rpc("_rpc_car_state", 1, state)
	else:
		rpc_id(1, "_rpc_car_state_from_client", state)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_car_state_from_client(state: Dictionary) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	rpc("_rpc_car_state", sender, state)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_car_state(id: int, state: Dictionary) -> void:
	car_state_received.emit(id, state)


func push_lap(lap: int, lap_time: float) -> void:
	"""A client reports progress; the host validates before it counts."""
	if not is_online():
		return
	if is_host():
		rpc("_rpc_lap", 1, lap, lap_time)
	else:
		rpc_id(1, "_rpc_lap_from_client", lap, lap_time)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_lap_from_client(lap: int, lap_time: float) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	# Sanity gate: a client may only ever advance one lap at a time.
	var previous := int(players[sender].get("lap", 0))
	if lap < 0 or lap > previous + 1:
		push_warning("Net: rejected lap %d from %d (previous %d)" % [lap, sender, previous])
		return
	players[sender]["lap"] = lap
	rpc("_rpc_lap", sender, lap, lap_time)


@rpc("authority", "call_remote", "reliable")
func _rpc_lap(id: int, lap: int, lap_time: float) -> void:
	lap_received.emit(id, lap)


func host_report_finish(id: int, result: Dictionary) -> void:
	"""Only the host calls this; results are then broadcast to everyone."""
	if not is_host():
		return
	for r in race_results:
		if int(r.get("id", -1)) == id:
			return
	result["id"] = id
	race_results.append(result)
	race_results.sort_custom(func(a, b): return int(a.get("position", 99)) < int(b.get("position", 99)))
	rpc("_rpc_finish", race_results)


@rpc("authority", "call_remote", "reliable")
func _rpc_finish(results: Array) -> void:
	race_results = results
	race_finished_received.emit(results)


func _sanitise_name(raw: String) -> String:
	var cleaned := raw.strip_edges()
	if cleaned.is_empty():
		return "Player"
	return cleaned.substr(0, 16)
