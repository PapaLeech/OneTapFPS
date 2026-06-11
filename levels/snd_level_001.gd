extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://controllers/player.tscn")

var spawn_positions: Array[Vector3] = []
var spawn_index_map: Dictionary = {}  # peer_id -> pos_index, server only

# ─── Chat ────────────────────────────────────────────────────────────────────
enum ChatFocus { NONE, CHAT, TERMINAL }
var _chat_focus : ChatFocus = ChatFocus.NONE
var _chat_enabled : bool = true

@onready var _chat_tab_btn  : Button        = $HUDLayer/ChatTerminalPanel/VBox/TabBar/ChatTab
@onready var _term_tab_btn  : Button        = $HUDLayer/ChatTerminalPanel/VBox/TabBar/TerminalTab
@onready var _chat_output   : RichTextLabel = $HUDLayer/ChatTerminalPanel/VBox/ChatOutput
@onready var _term_output   : RichTextLabel = $HUDLayer/ChatTerminalPanel/VBox/TerminalOutput
@onready var _input_line    : LineEdit       = $HUDLayer/ChatTerminalPanel/VBox/InputLine
@onready var _lock_btn      : Button         = $HUDLayer/ChatTerminalPanel/VBox/TabBar/LockBtn
@onready var _resize_handle : Button         = $HUDLayer/ResizeHandle
@onready var _chat_panel    : PanelContainer = $HUDLayer/ChatTerminalPanel
@onready var _drag_bar      : Panel          = $HUDLayer/ChatTerminalPanel/VBox/DragBar

# ─── Chat window drag / resize / lock ────────────────────────────────────────
var _chat_locked       : bool    = false
var _dragging          : bool    = false
var _resizing          : bool    = false
var _drag_offset       : Vector2 = Vector2.ZERO
var _resize_start_pos  : Vector2 = Vector2.ZERO
var _resize_start_size : Vector2 = Vector2.ZERO
const CHAT_MIN_SIZE    : Vector2 = Vector2(160, 100)
const CHAT_MAX_SIZE    : Vector2 = Vector2(500, 400)

# ─── Scoreboard ───────────────────────────────────────────────────────────────
var _scoreboard_panel  : PanelContainer = null
var _scoreboard_canvas : CanvasLayer    = null
var _scoreboard_cursor : bool           = false
var _software_cursor   : Control        = null
var _cursor_pos        : Vector2        = Vector2(640, 360)
# stats[peer_id] = {username, kills, deaths, assists, ping}
var _stats             : Dictionary     = {}



func _ready() -> void:
	print("Level _ready, is_server: ", multiplayer.is_server())
	# Read spawn positions from spawn_points group
	for point in get_tree().get_nodes_in_group("spawn_points"):
		spawn_positions.append(point.global_position)
	print("Spawn positions loaded: ", spawn_positions.size())
	# Solo play mode - no multiplayer peer at all
	if not multiplayer.has_multiplayer_peer():
		_spawn_solo_player()
	# Dedicated server or client with peer
	if multiplayer.is_server() and not OS.has_feature("dedicated_server") and not "--dedicated-server" in OS.get_cmdline_args():
		# Running as server in editor - treat as solo
		_spawn_solo_player()
		return
	if multiplayer.is_server():
		MultiplayerManager.player_disconnected.connect(_remove_player)
	else:
		print("Client level ready, notifying server")
		await get_tree().create_timer(0.1).timeout
		_client_ready.rpc_id(1)
		# Client: listen for peer disconnection to remove stale meshes
		multiplayer.peer_disconnected.connect(_client_remove_player)
		_start_ping_timer()
	# Skip chat setup on dedicated server
	if not OS.has_feature("dedicated_server") and not "--dedicated-server" in OS.get_cmdline_args():
		_setup_chat()
		_setup_scoreboard()

# Client tells server it has loaded the level
@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if spawn_index_map.has(peer_id):
		return  # Already spawned, ignore
	# Clean up stale peers not currently connected
	var connected := multiplayer.get_peers()
	for stale_id in spawn_index_map.keys().duplicate():
		if stale_id not in connected:
			print("Removing stale peer: ", stale_id)
			spawn_index_map.erase(stale_id)
			var node := get_node_or_null(str(stale_id))
			if node: node.queue_free()
	print("Server: client ", peer_id, " ready")
	await get_tree().create_timer(0.5).timeout
	_on_player_connected(peer_id)

# Server only — assigns spawn position and broadcasts to all peers
func _on_player_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if spawn_index_map.has(peer_id):
		return  # Already assigned
	_on_player_connected_respawn(peer_id, -1)

func _on_player_connected_respawn(peer_id: int, last_index: int) -> void:
	if not multiplayer.is_server():
		return
	var occupied := spawn_index_map.values()
	var pos_index := randi() % spawn_positions.size()
	if spawn_positions.size() > 1:
		var attempts := 0
		while (pos_index == last_index or pos_index in occupied) and attempts < 10:
			pos_index = randi() % spawn_positions.size()
			attempts += 1
	spawn_index_map[peer_id] = pos_index
	print("Server spawning player: ", peer_id, " at index ", pos_index)
	# If node exists, teleport. Otherwise spawn fresh.
	if get_node_or_null(str(peer_id)) != null:
		_teleport_player.rpc(peer_id, pos_index)
	else:
		_do_spawn.rpc(peer_id, pos_index)
		# Tell the NEW player about all existing players
		for existing_id in spawn_index_map:
			if existing_id != peer_id:
				_do_spawn.rpc_id(peer_id, existing_id, spawn_index_map[existing_id])
	var username: String = MultiplayerManager.players.get(peer_id, "Unknown")
	NetworkSyncLogger.log_peer_connected(peer_id, username)
	# Only initialise stats for new players, preserve existing on respawn
	if not _stats.has(peer_id):
		var team_a := _stats.values().filter(func(s): return s["team"] == "A").size()
		var team_b := _stats.values().filter(func(s): return s["team"] == "B").size()
		var team := "A" if team_a <= team_b else "B"
		_stats[peer_id] = {"username": username, "kills": 0, "deaths": 0, "assists": 0, "ping": 0, "team": team}
	_sync_stats.rpc(var_to_bytes(_stats))
	if MultiplayerManager.players.size() >= 2:
		var names: Array = MultiplayerManager.players.values()
		SessionLogger.start_session_rpc.rpc(names[0], names[1])

# Runs on ALL peers via RPC — spawns the player locally
@rpc("authority", "call_local", "reliable")
func _do_spawn(peer_id: int, pos_index: int) -> void:
	if get_node_or_null(str(peer_id)) != null:
		print("_do_spawn: ", peer_id, " already exists, skipping")
		return
	if pos_index < 0 or pos_index >= spawn_positions.size():
		pos_index = 0
	if spawn_positions.is_empty():
		print("ERROR: No spawn points found!")
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.global_position = spawn_positions[pos_index] + Vector3(0, 1.0, 0)
	add_child(player, true)
	print("Spawned player ", peer_id, " at ", spawn_positions[pos_index])

# Solo play mode - spawn player without multiplayer
func _spawn_solo_player() -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = "SoloPlayer"
	add_child(player)
	player.global_position = Vector3(0, -1.5, 0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Add solo player to stats
	_stats[0] = {"username": PresenceManager.username if PresenceManager.username != "" else "Player", "kills": 0, "deaths": 0, "assists": 0, "ping": 0, "team": "A"}
	# Zero out velocity so player doesn't fall on spawn
	await get_tree().process_frame
	player.velocity = Vector3.ZERO

func _remove_player(peer_id: int) -> void:
	var username: String = MultiplayerManager.players.get(peer_id, "Unknown")
	NetworkSyncLogger.log_peer_disconnected(peer_id, username)
	SessionLogger.end_session("player_left: %s" % username)
	spawn_index_map.erase(peer_id)
	_stats.erase(peer_id)
	if multiplayer.is_server():
		_sync_stats.rpc(var_to_bytes(_stats))
	var node := get_node_or_null(str(peer_id))
	if node:
		node.queue_free()

func _client_remove_player(peer_id: int) -> void:
	var node := get_node_or_null(str(peer_id))
	if node:
		print("Client: removing mesh for disconnected peer ", peer_id)
		node.queue_free()

# ─── In-game Chat / Terminal ──────────────────────────────────────────────────────────
func _setup_chat() -> void:
	_chat_tab_btn.pressed.connect(func(): _switch_chat_tab(ChatFocus.CHAT))
	_term_tab_btn.pressed.connect(func(): _switch_chat_tab(ChatFocus.TERMINAL))
	# Use gui_input instead of text_submitted so we control focus
	_input_line.keep_editing_on_text_submit = true
	_input_line.gui_input.connect(_on_chat_line_gui_input)
	_chat_output.visible = true
	_term_output.visible = false
	# Start fully hidden — appears on first Enter press
	var panel := $HUDLayer/ChatTerminalPanel
	panel.modulate.a = 0.0
	panel.visible = false
	_release_chat_focus()
	_setup_chat_window()
	# Hook drag on the drag bar ribbon at top
	_drag_bar.gui_input.connect(_on_tabbar_gui_input)

func set_chat_enabled(enabled: bool) -> void:
	_chat_enabled = enabled
	if not enabled and _chat_focus != ChatFocus.NONE:
		_release_chat_focus()
	if not enabled:
		var panel := $HUDLayer/ChatTerminalPanel
		panel.modulate.a = 0.0
		panel.visible = false

func _switch_chat_tab(focus: ChatFocus) -> void:
	if not _chat_enabled:
		return
	_chat_focus = focus
	_chat_output.visible = (focus == ChatFocus.CHAT)
	_term_output.visible = (focus == ChatFocus.TERMINAL)
	# Make panel visible BEFORE grab_focus so the LineEdit can actually receive focus
	var panel := $HUDLayer/ChatTerminalPanel
	panel.visible = true
	panel.modulate.a = 1.0
	_input_line.editable = true
	_input_line.grab_focus()
	_input_line.call_deferred("grab_focus")
	# Block movement input but keep physics running (preserves idle bobbing)
	var my_id := str(multiplayer.get_unique_id()) if multiplayer.has_multiplayer_peer() else "SoloPlayer"
	var player := get_tree().get_root().get_node_or_null("Node3D/%s" % my_id)
	if player and player.get("_chat_open") != null:
		player._chat_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if focus == ChatFocus.CHAT:
		_input_line.placeholder_text = "Type message, Enter to send, Esc to exit..."
	else:
		_input_line.placeholder_text = "Type command, Enter to run, Esc to exit..."

func _release_chat_focus() -> void:
	_chat_focus = ChatFocus.NONE
	_input_line.editable = false
	_input_line.release_focus()
	_input_line.placeholder_text = "Enter = chat    ` = console"
	# Restore movement input and recapture mouse
	var my_id := str(multiplayer.get_unique_id()) if multiplayer.has_multiplayer_peer() else "SoloPlayer"
	var player := get_tree().get_root().get_node_or_null("Node3D/%s" % my_id)
	if player and player.get("_chat_open") != null:
		player._chat_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Fade to faint if messages exist, otherwise hide completely
	var panel := $HUDLayer/ChatTerminalPanel
	if _chat_output.get_parsed_text().strip_edges() != "":
		panel.visible = true
		panel.modulate.a = 0.25
	else:
		panel.modulate.a = 0.0
		panel.visible = false

func _on_chat_line_gui_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		var text := _input_line.text.strip_edges()
		_input_line.clear()
		if text != "":
			if _chat_focus == ChatFocus.CHAT:
				_send_chat_message.rpc(PresenceManager.username, text)
			elif _chat_focus == ChatFocus.TERMINAL:
				_term_output.append_text("[color=lime]> " + text + "[/color]\n")
				_execute_chat_command(text)
		_input_line.grab_focus()
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_release_chat_focus()

@rpc("any_peer", "call_local", "reliable")
func _send_chat_message(sender: String, message: String) -> void:
	_chat_output.append_text("[color=yellow][b]" + sender + ":[/b][/color] " + message + "\n")

func _execute_chat_command(cmd: String) -> void:
	var parts := cmd.strip_edges().split(" ", false)
	if parts.is_empty():
		return
	match parts[0].to_lower():
		"help":
			_term_output.append_text("Commands: help, clear, version, ping\n")
		"clear":
			_term_output.clear()
		"version":
			_term_output.append_text("OneTapFPS v0.1-dev\n")
		"ping":
			_term_output.append_text("Ping: (coming soon)\n")
		_:
			_term_output.append_text("Unknown command: " + parts[0] + "\n")

# ─── Lock / drag / resize ──────────────────────────────────────────────────────────────
func _setup_chat_window() -> void:
	_resize_handle.visible = false
	_lock_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_lock_btn.pressed.connect(_toggle_chat_lock)
	_resize_handle.button_down.connect(_on_resize_start)
	_drag_bar.custom_minimum_size = Vector2(0, 8)
	_drag_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	# Load saved position/size/lock state using bottom-left anchor system
	var pos_x  : float = PresenceManager.load_setting("chat_pos_x",  8.0)
	var pos_y  : float = PresenceManager.load_setting("chat_pos_y",  -212.0)
	var size_x : float = PresenceManager.load_setting("chat_size_x", 162.0)
	var size_y : float = PresenceManager.load_setting("chat_size_y", 124.0)
	_chat_locked = PresenceManager.load_setting("chat_locked", false)
	# Clamp position to ensure panel is always on screen
	var vp := get_viewport().get_visible_rect().size
	pos_x = clamp(pos_x, 0.0, vp.x - size_x)
	pos_y = clamp(pos_y, -(vp.y - size_y), -size_y)
	_chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_panel.offset_left   = pos_x
	_chat_panel.offset_top    = pos_y
	_chat_panel.offset_right  = pos_x + size_x
	_chat_panel.offset_bottom = pos_y + size_y
	_update_lock_ui()

func _toggle_chat_lock() -> void:
	_chat_locked = not _chat_locked
	PresenceManager.save_setting("chat_locked", _chat_locked)
	_update_lock_ui()

func _update_lock_ui() -> void:
	_lock_btn.text = "☑" if _chat_locked else "☐"
	_resize_handle.visible = not _chat_locked

func _on_resize_start() -> void:
	if _chat_locked:
		return
	_resizing = true
	_resize_start_pos  = get_viewport().get_mouse_position()
	_resize_start_size = Vector2(
		_chat_panel.offset_right  - _chat_panel.offset_left,
		_chat_panel.offset_bottom - _chat_panel.offset_top
	)

func _save_chat_layout() -> void:
	PresenceManager.save_setting("chat_pos_x",  _chat_panel.offset_left)
	PresenceManager.save_setting("chat_pos_y",  _chat_panel.offset_top)
	PresenceManager.save_setting("chat_size_x", _chat_panel.offset_right  - _chat_panel.offset_left)
	PresenceManager.save_setting("chat_size_y", _chat_panel.offset_bottom - _chat_panel.offset_top)

func _process_chat_drag(delta: float) -> void:
	if not (_dragging or _resizing):
		return
	var mouse := get_viewport().get_mouse_position()
	var vp    := get_viewport().get_visible_rect().size
	if _dragging:
		var w := _chat_panel.offset_right  - _chat_panel.offset_left
		var h := _chat_panel.offset_bottom - _chat_panel.offset_top
		# gp is the actual screen top-left of the panel
		var new_x := clamp(mouse.x - _drag_offset.x, 0.0, vp.x - w)
		var new_y := clamp(mouse.y - _drag_offset.y, 0.0, vp.y - h)
		_chat_panel.offset_left   = new_x
		_chat_panel.offset_right  = new_x + w
		# Convert screen Y to bottom-anchored offset
		_chat_panel.offset_top    = new_y - vp.y
		_chat_panel.offset_bottom = _chat_panel.offset_top + h
	elif _resizing:
		var diff := mouse - _resize_start_pos
		var new_w := clamp(_resize_start_size.x + diff.x, CHAT_MIN_SIZE.x, CHAT_MAX_SIZE.x)
		var new_h := clamp(_resize_start_size.y + diff.y, CHAT_MIN_SIZE.y, CHAT_MAX_SIZE.y)
		_chat_panel.offset_right  = _chat_panel.offset_left + new_w
		_chat_panel.offset_bottom = _chat_panel.offset_top  + new_h

func _on_tabbar_gui_input(event: InputEvent) -> void:
	if _chat_locked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			var mouse := get_viewport().get_mouse_position()
			_drag_offset = mouse - _chat_panel.global_position
		else:
			_dragging = false
			_save_chat_layout()

func _process(delta: float) -> void:
	_process_chat_drag(delta)
	if _resizing and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_resizing = false
		_save_chat_layout()
	# Keep resize handle pinned to bottom-right corner of chat panel
	if _resize_handle and _chat_panel and _chat_panel.visible:
		var gp := _chat_panel.global_position
		var sz := _chat_panel.size
		_resize_handle.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_resize_handle.position = Vector2(gp.x + sz.x - 18, gp.y + sz.y - 18)
	# Move software cursor using accumulated delta
	if _software_cursor and _software_cursor.visible:
		_software_cursor.position = _cursor_pos

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.alt_pressed and _chat_enabled:
		if event.keycode == KEY_ENTER:
			if _chat_focus == ChatFocus.CHAT:
				var text := _input_line.text.strip_edges()
				_input_line.clear()
				if text != "":
					if multiplayer.has_multiplayer_peer():
						_send_chat_message.rpc(PresenceManager.username, text)
					else:
						_send_chat_message(PresenceManager.username, text)
				get_viewport().set_input_as_handled()
				return
			elif _chat_focus == ChatFocus.TERMINAL:
				var text := _input_line.text.strip_edges()
				_input_line.clear()
				if text != "":
					_term_output.append_text("[color=lime]> " + text + "[/color]\n")
					_execute_chat_command(text)
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _scoreboard_panel and _scoreboard_panel.visible:
			_scoreboard_cursor = not _scoreboard_cursor
			if _scoreboard_cursor:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				call_deferred("_warp_to_centre")
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return

func _unhandled_input(event: InputEvent) -> void:
	# Right-click while scoreboard open — toggle cursor
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _scoreboard_panel and _scoreboard_panel.visible:
			_scoreboard_cursor = not _scoreboard_cursor
			if _scoreboard_cursor:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				call_deferred("_warp_to_centre")
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
	if not event is InputEventKey:
		return
	# Tab — show/hide scoreboard
	if event.keycode == KEY_TAB:
		if event.pressed:
			PresenceManager.scoreboard_open = true
			_show_scoreboard()
		else:
			PresenceManager.scoreboard_open = false
			_hide_scoreboard()
		get_viewport().set_input_as_handled()
		return
	if not event.pressed:
		return
	if event.keycode == KEY_QUOTELEFT:
		if _chat_enabled:
			if _chat_focus == ChatFocus.TERMINAL:
				_switch_chat_tab(ChatFocus.CHAT)
			else:
				_switch_chat_tab(ChatFocus.TERMINAL)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ENTER and not event.alt_pressed:
		if _chat_enabled and _chat_focus == ChatFocus.NONE:
			_switch_chat_tab(ChatFocus.CHAT)
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		# Chat consumes Esc first — pause menu only gets it when chat is closed
		if _chat_focus != ChatFocus.NONE:
			_release_chat_focus()
			get_viewport().set_input_as_handled()

# ─── Scoreboard ─────────────────────────────────────────────────────────────
func is_scoreboard_open() -> bool:
	return _scoreboard_panel != null and _scoreboard_panel.visible

func _setup_scoreboard() -> void:
	_scoreboard_canvas = CanvasLayer.new()
	_scoreboard_canvas.layer = 128  # Above everything including death menu
	add_child(_scoreboard_canvas)
	_scoreboard_panel = PanelContainer.new()
	_scoreboard_panel.visible = false
	# Style matching pause/death menu
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.12, 0.12, 0.12, 0.97)
	style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.8)
	style.shadow_size  = 8
	_scoreboard_panel.add_theme_stylebox_override("panel", style)
	_scoreboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centre panel dead centre on screen
	_scoreboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	_scoreboard_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scoreboard_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_scoreboard_panel.custom_minimum_size = Vector2(520, 0)
	_scoreboard_canvas.add_child(_scoreboard_panel)
	# Software cursor — arrow label, hidden by default
	_software_cursor = Label.new()
	_software_cursor.text = "\u25B6"
	_software_cursor.add_theme_font_size_override("font_size", 20)
	_software_cursor.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_software_cursor.visible = false
	_software_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard_canvas.add_child(_software_cursor)

func _set_mouse_visible() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _set_mouse_captured() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _warp_to_centre() -> void:
	var centre := get_viewport().get_visible_rect().size / 2.0
	Input.warp_mouse(centre)

func _show_scoreboard() -> void:
	if _scoreboard_panel == null:
		return
	_rebuild_scoreboard()
	_scoreboard_panel.visible = true
	_scoreboard_cursor = false
	PresenceManager.scoreboard_open = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _hide_scoreboard() -> void:
	if _scoreboard_panel == null:
		return
	_scoreboard_panel.visible = false
	_scoreboard_cursor = false
	PresenceManager.scoreboard_open = false
	if _software_cursor:
		_software_cursor.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _rebuild_scoreboard() -> void:
	# Clear previous content
	for child in _scoreboard_panel.get_children():
		child.queue_free()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_scoreboard_panel.add_child(vbox)
	# Title bar
	var title_bar := ColorRect.new()
	title_bar.color = Color(0.08, 0.08, 0.08, 1.0)
	title_bar.custom_minimum_size = Vector2(520, 32)
	vbox.add_child(title_bar)
	var title := Label.new()
	title.text = "DEATHMATCH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_bar.add_child(title)
	# Column header row
	var header := _make_row("PLAYER", "K", "D", "A", "PING", true)
	vbox.add_child(header)
	# Divider
	var div := ColorRect.new()
	div.color = Color(0.4, 0.4, 0.4, 0.5)
	div.custom_minimum_size = Vector2(520, 1)
	vbox.add_child(div)
	# Split players into teams sorted by kills
	var team_a_peers : Array = _stats.keys().filter(func(p): return _stats[p].get("team", "A") == "A")
	var team_b_peers : Array = _stats.keys().filter(func(p): return _stats[p].get("team", "B") == "B")
	team_a_peers.sort_custom(func(a, b): return _stats[a]["kills"] > _stats[b]["kills"])
	team_b_peers.sort_custom(func(a, b): return _stats[a]["kills"] > _stats[b]["kills"])
	# ─ Team A
	var team_a_bar := _make_team_header("TEAM A")
	vbox.add_child(team_a_bar)
	for pid in team_a_peers:
		var s : Dictionary = _stats[pid]
		vbox.add_child(_make_row(s["username"], str(s["kills"]), str(s["deaths"]), str(s["assists"]), str(s["ping"]) + " ms", false))
		var rdiv := ColorRect.new()
		rdiv.color = Color(0.3, 0.3, 0.3, 0.3)
		rdiv.custom_minimum_size = Vector2(520, 1)
		vbox.add_child(rdiv)
	for i in range(6 - team_a_peers.size()):
		vbox.add_child(_make_row("", "", "", "", "", false))
		var bdiv := ColorRect.new()
		bdiv.color = Color(0.3, 0.3, 0.3, 0.3)
		bdiv.custom_minimum_size = Vector2(520, 1)
		vbox.add_child(bdiv)
	# ─ Team B
	var team_b_bar := _make_team_header("TEAM B")
	vbox.add_child(team_b_bar)
	for pid in team_b_peers:
		var s : Dictionary = _stats[pid]
		vbox.add_child(_make_row(s["username"], str(s["kills"]), str(s["deaths"]), str(s["assists"]), str(s["ping"]) + " ms", false))
		var rdiv := ColorRect.new()
		rdiv.color = Color(0.3, 0.3, 0.3, 0.3)
		rdiv.custom_minimum_size = Vector2(520, 1)
		vbox.add_child(rdiv)
	for i in range(6 - team_b_peers.size()):
		vbox.add_child(_make_row("", "", "", "", "", false))
		var bdiv := ColorRect.new()
		bdiv.color = Color(0.3, 0.3, 0.3, 0.3)
		bdiv.custom_minimum_size = Vector2(520, 1)
		vbox.add_child(bdiv)

func _make_team_header(team_name: String) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0.18, 0.18, 0.18, 1.0)
	bar.custom_minimum_size = Vector2(520, 24)
	var lbl := Label.new()
	lbl.text = team_name
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(lbl)
	return bar

func _make_row(player: String, kills: String, deaths: String, assists: String, ping: String, is_header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(520, 28)
	var cols := [player, kills, deaths, assists, ping]
	var widths := [220, 60, 60, 60, 80]
	for i in range(cols.size()):
		var lbl := Label.new()
		lbl.text = cols[i]
		lbl.custom_minimum_size.x = widths[i]
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if i > 0 else HORIZONTAL_ALIGNMENT_LEFT
		if is_header:
			lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
			lbl.add_theme_font_size_override("font_size", 11)
		else:
			lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)
	return row

# Server broadcasts stats to all clients
@rpc("any_peer", "call_local", "reliable")
func _sync_stats(data: PackedByteArray) -> void:
	_stats = bytes_to_var(data)

# ─── Ping ────────────────────────────────────────────────────────────────────
var _ping_sent_at : float = 0.0

func _start_ping_timer() -> void:
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_send_ping)
	add_child(t)

func _send_ping() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return
	_ping_sent_at = Time.get_ticks_msec()
	_ping_request.rpc_id(1)

@rpc("any_peer", "reliable")
func _ping_request() -> void:
	if not multiplayer.is_server():
		return
	_ping_response.rpc_id(multiplayer.get_remote_sender_id())

@rpc("authority", "reliable")
func _ping_response() -> void:
	var rtt := int(Time.get_ticks_msec() - _ping_sent_at)
	var my_id := multiplayer.get_unique_id()
	if _stats.has(my_id):
		_stats[my_id]["ping"] = rtt
		_update_ping.rpc_id(1, my_id, rtt)

@rpc("any_peer", "reliable")
func _update_ping(peer_id: int, rtt: int) -> void:
	if not multiplayer.is_server():
		return
	if _stats.has(peer_id):
		_stats[peer_id]["ping"] = rtt
		_sync_stats.rpc(var_to_bytes(_stats))

func record_kill(killer_id: int, victim_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_record_kill_rpc.rpc_id(1, killer_id, victim_id)
		return
	_do_record_kill(killer_id, victim_id)
@rpc("any_peer", "reliable")
func _record_kill_rpc(killer_id: int, victim_id: int) -> void:
	if not multiplayer.is_server():
		return
	_do_record_kill(killer_id, victim_id)

func _do_record_kill(killer_id: int, victim_id: int) -> void:
	if _stats.has(killer_id):
		_stats[killer_id]["kills"] += 1
	if _stats.has(victim_id):
		_stats[victim_id]["deaths"] += 1
	_sync_stats.rpc(var_to_bytes(_stats))

func record_assist(assister_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _stats.has(assister_id):
		_stats[assister_id]["assists"] += 1
	_sync_stats.rpc(var_to_bytes(_stats))

@rpc("any_peer", "reliable")
func request_respawn() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var last_idx : int = spawn_index_map.get(peer_id, -1)
	spawn_index_map.erase(peer_id)
	_on_player_connected_respawn(peer_id, last_idx)

@rpc("authority", "call_local", "reliable")
func _remove_node_for_respawn(peer_id: int) -> void:
	# Only free remote players - local player is handled by pause_menu._respawn()
	if not multiplayer.is_server() and peer_id == multiplayer.get_unique_id():
		return
	var node := get_node_or_null(str(peer_id))
	if node:
		node.queue_free()

@rpc("authority", "call_local", "reliable")
func _teleport_player(peer_id: int, pos_index: int) -> void:
	var node := get_node_or_null(str(peer_id))
	if node:
		node.global_position = spawn_positions[pos_index] + Vector3(0, 1.0, 0)
