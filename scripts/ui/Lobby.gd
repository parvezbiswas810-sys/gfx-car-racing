extends Control
## LAN lobby: real Create Room / Join Room, live player list, host-controlled
## start. Nothing here is a mock: every button drives ENetMultiplayerPeer.

const DEFAULT_PORT := 7777

var _room_field: LineEdit
var _port_field: LineEdit
var _ip_field: LineEdit
var _host_panel: VBoxContainer
var _join_panel: VBoxContainer
var _status: Label
var _player_list: VBoxContainer
var _start_button: Button
var _ready_button: Button
var _ip_display: Label
var _name_field: LineEdit
var _car_label: Label
var _retry_button: Button


func _ready() -> void:
	Audio.start_music()
	_build()
	_connect_net()
	_refresh()


func _exit_tree() -> void:
	# Leaving the screen must not leave a socket open behind us.
	if Net.is_online():
		Net.leave_room()


func _build() -> void:
	var page := UITheme.make_screen("LOCAL MULTIPLAYER", "Both phones on the same Wi-Fi or hotspot. UDP port %d." % DEFAULT_PORT)
	add_child(page)
	var column := page.get_node("MarginContainer/Content")

	var body := UITheme.make_hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	# ---- create room ---------------------------------------------------
	var host_panel_wrap := UITheme.make_panel()
	host_panel_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(host_panel_wrap)
	_host_panel = UITheme.make_vbox(10)
	host_panel_wrap.add_child(_host_panel)

	_host_panel.add_child(UITheme.make_label("HOST A RACE", 24, UITheme.ACCENT_WARM, true))
	_host_panel.add_child(UITheme.make_label("Room name", 16, UITheme.TEXT_DIM))
	_room_field = UITheme.make_field("GFX Room", "GFX Room")
	_host_panel.add_child(_room_field)
	_host_panel.add_child(UITheme.make_label("Your display name", 16, UITheme.TEXT_DIM))
	_name_field = UITheme.make_field("Player", "Player")
	_host_panel.add_child(_name_field)
	_host_panel.add_child(UITheme.make_label("Port", 16, UITheme.TEXT_DIM))
	_port_field = UITheme.make_field("7777", str(DEFAULT_PORT))
	_port_field.text_submitted.connect(func(_t: String): _on_create())
	_host_panel.add_child(_port_field)

	var create_btn := UITheme.make_button("Create Room", UITheme.ACCENT_WARM, 56.0)
	create_btn.pressed.connect(_on_create)
	_host_panel.add_child(create_btn)

	_ip_display = UITheme.make_label("", 16, UITheme.ACCENT)
	_ip_display.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_panel.add_child(_ip_display)

	var copy_btn := UITheme.make_button("Show my IP again", UITheme.ACCENT, 44.0)
	copy_btn.pressed.connect(func():
		Audio.play_ui("click")
		Net.local_ip = Net.detect_local_ip()
		_update_ip_display())
	_host_panel.add_child(copy_btn)

	# ---- join room -----------------------------------------------------
	var join_panel_wrap := UITheme.make_panel()
	join_panel_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(join_panel_wrap)
	_join_panel = UITheme.make_vbox(10)
	join_panel_wrap.add_child(_join_panel)

	_join_panel.add_child(UITheme.make_label("JOIN A RACE", 24, UITheme.ACCENT, true))
	_join_panel.add_child(UITheme.make_label("Host IP address", 16, UITheme.TEXT_DIM))
	_ip_field = UITheme.make_field("192.168.1.23", "")
	_ip_field.text_submitted.connect(func(_t: String): _on_join())
	_join_panel.add_child(_ip_field)
	_join_panel.add_child(UITheme.make_label("Port", 16, UITheme.TEXT_DIM))
	var join_port := UITheme.make_field("7777", str(DEFAULT_PORT))
	_join_panel.add_child(join_port)

	var join_btn := UITheme.make_button("Join Room", UITheme.ACCENT, 56.0)
	join_btn.pressed.connect(func(): _on_join(join_port.text))
	_join_panel.add_child(join_btn)

	_retry_button = UITheme.make_button("Retry connection", UITheme.ACCENT_WARM, 44.0)
	_retry_button.pressed.connect(func(): _on_join(join_port.text))
	_retry_button.visible = false
	_join_panel.add_child(_retry_button)

	_car_label = UITheme.make_label("", 16, UITheme.TEXT_DIM)
	_join_panel.add_child(_car_label)

	var how := UITheme.make_label(
		"How to play:\n"
		+ "1. Host taps Create Room and reads the IP shown above.\n"
		+ "2. Guest joins the same Wi-Fi network or the host's hotspot.\n"
		+ "3. Guest types that IP and taps Join Room.\n"
		+ "4. Both tap Ready. The host taps Start Race.\n"
		+ "If your carrier blocks hotspot client traffic, turn on the hotspot on the "
		+ "guest device instead and host from the other phone.",
		15, Color(0.55, 0.62, 0.74))
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_panel.add_child(how)

	# ---- shared status / player list -----------------------------------
	var status_panel := UITheme.make_panel()
	status_panel.custom_minimum_size = Vector2(380, 0)
	body.add_child(status_panel)
	var status_box := UITheme.make_vbox(10)
	status_panel.add_child(status_box)

	_status = UITheme.make_label("Not connected", 18, UITheme.TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_box.add_child(_status)

	status_box.add_child(UITheme.make_label("Players", 20, UITheme.TEXT, true))
	_player_list = UITheme.make_vbox(6)
	status_box.add_child(_player_list)

	_ready_button = UITheme.make_button("Ready", UITheme.ACCENT, 52.0)
	_ready_button.toggle_mode = true
	_ready_button.toggled.connect(_on_ready_toggled)
	status_box.add_child(_ready_button)

	_start_button = UITheme.make_button("Start Race", UITheme.ACCENT_WARM, 56.0)
	_start_button.pressed.connect(_on_start)
	status_box.add_child(_start_button)

	var leave := UITheme.make_button("Leave / Back", UITheme.ACCENT_DANGER, 50.0)
	leave.pressed.connect(func():
		Audio.play_ui("back")
		Net.leave_room()
		SceneRouter.go_to("menu"))
	status_box.add_child(leave)

	UITheme.add_footer(self, "ENetMultiplayerPeer  -  UDP")


func _connect_net() -> void:
	Net.room_created.connect(_on_room_created)
	Net.room_create_failed.connect(_on_failed)
	Net.join_succeeded.connect(_on_join_ok)
	Net.join_failed.connect(_on_failed)
	Net.lobby_updated.connect(_refresh)
	Net.peer_joined.connect(func(_id: int, _info: Dictionary): _refresh())
	Net.peer_left.connect(func(_id: int): _refresh())
	Net.host_left.connect(_on_host_left)
	Net.connection_lost.connect(_on_host_left)
	Net.countdown_received.connect(_on_countdown)


func _on_room_created(port: int) -> void:
	Audio.play_ui("click")
	_update_ip_display()
	_refresh()


func _update_ip_display() -> void:
	var ip := Net.local_ip
	if ip.is_empty():
		ip = Net.detect_local_ip()
		Net.local_ip = ip
	if ip.is_empty():
		_ip_display.text = ("Your local IP could not be detected automatically.\n"
			+ "Open Settings > About phone > Status to read it, then share it with the guest.")
	else:
		_ip_display.text = "Your IP:  %s\nPort: %d" % [ip, Net.port]


func _on_create() -> void:
	Audio.play_ui("click")
	var port := DEFAULT_PORT
	if _port_field != null and _port_field.text.strip_edges().is_valid_int():
		port = clampi(int(_port_field.text.strip_edges()), 1, 65535)
	var who := "Host"
	if _name_field != null and not _name_field.text.strip_edges().is_empty():
		who = _name_field.text.strip_edges()
	Net.set_player_name(who)
	var room := "GFX Room"
	if _room_field != null and not _room_field.text.strip_edges().is_empty():
		room = _room_field.text.strip_edges()
	if Net.create_room(room, port):
		_update_ip_display()


func _on_join(port_text: String = "") -> void:
	Audio.play_ui("click")
	var port := DEFAULT_PORT
	if port_text != "":
		port = clampi(int(port_text) if port_text.is_valid_int() else DEFAULT_PORT, 1, 65535)
	Net.set_player_name(_name_field.text if _name_field != null and not _name_field.text.is_empty() else "Player")
	_retry_button.visible = false
	_status.text = "Connecting to %s:%d ..." % [_ip_field.text.strip_edges(), port]
	if not Net.join_room(_ip_field.text, port, _name_field.text):
		pass  # join_failed already fired and updated the status


func _on_join_ok() -> void:
	Audio.play_ui("click")
	_status.text = "Connected. Waiting for the host to start."
	_refresh()


func _on_failed(reason: String) -> void:
	Audio.play_ui("back")
	_status.text = reason
	_retry_button.visible = true


func _on_host_left(_reason: String = "") -> void:
	_status.text = "The host closed the room. You can retry, or go back to the menu."
	_retry_button.visible = true
	_refresh()


func _on_ready_toggled(pressed: bool) -> void:
	Audio.play_ui("click")
	Net.set_ready(pressed)


func _on_start() -> void:
	if not Net.is_host():
		_status.text = "Only the host can start the race."
		return
	if Net.player_count() < 2:
		_status.text = "Wait for at least one guest to join before starting."
		return
	if not Net.host_start_race(TrackData.LAPS):
		_status.text = "Everyone must tap Ready first."
		return
	Audio.play_ui("click")


func _on_countdown(_start_at: float, laps: int) -> void:
	SceneRouter.go_to("race", {
		"mode": "host" if Net.is_host() else "client",
		"track": Settings.selected_track,
		"difficulty": Settings.difficulty,
		"laps": laps,
	})


func _refresh() -> void:
	if _player_list == null:
		return
	for child in _player_list.get_children():
		child.queue_free()

	var ids := Net.player_ids()
	if ids.is_empty():
		_player_list.add_child(UITheme.make_label("No room active", 16, UITheme.TEXT_DIM))
	else:
		for id in ids:
			var info := Net.get_player(id)
			var is_me: bool = id == Net.my_id()
			var tag := " (host)" if bool(info.get("is_host", false)) else ""
			var me := "  <- you" if is_me else ""
			var ready := "Ready" if bool(info.get("ready", false)) else "Not ready"
			var row := UITheme.make_label("%s%s%s   [%s]" % [
				str(info.get("name", "Player")), tag, me, ready
			], 16, UITheme.ACCENT if bool(info.get("ready", false)) else UITheme.TEXT_DIM)
			_player_list.add_child(row)

	if Net.is_online():
		if Net.is_host():
			_status.text = "Room '%s' open on port %d. %d player(s)." % [Net.room_name, Net.port, Net.player_count()]
			_ip_display.text = "Your IP:  %s\nPort: %d" % [Net.local_ip, Net.port]
		else:
			_status.text = "Connected to the host. %d player(s) in the room." % Net.player_count()
		_car_label.text = "Your car: %s  (%s)" % [
			Settings.car_by_id(Settings.selected_car)["name"], Settings.paint_colour.to_html(false)
		]
	else:
		if _status.text.is_empty() or _status.text == "Not connected":
			_status.text = "Not connected. Create a room, or join one with the host's IP."
		_car_label.text = "Your car: %s - change it in the Garage." % Settings.car_by_id(Settings.selected_car)["name"]

	_start_button.visible = Net.is_host()
	_ready_button.visible = Net.is_online()
	if Net.is_online():
		var mine := Net.get_player(Net.my_id())
		_ready_button.button_pressed = bool(mine.get("ready", false))
	_retry_button.visible = _retry_button.visible and not Net.is_online()
