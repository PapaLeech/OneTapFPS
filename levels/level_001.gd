extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://controllers/player.tscn")

var spawn_positions: Array[Vector3] = []
var spawn_counter: int = 0
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

func _ready() -> void:
	print("Level _ready, is_server: ", multiplayer.is_server())
	# Read spawn positions from spawn_points group
	for point in get_tree().get_nodes_in_group("spawn_points"):
		spawn_positions.append(point.global_position)
	print("Spawn positions loaded: ", spawn_positions.size())
	# Solo play mode - no multiplayer peer at all
	if not multiplayer.has_multiplayer_peer():
		_spawn_solo_player()
		return
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
	# Skip chat setup on dedicated server
	if not OS.has_feature("dedicated_server") and not "--dedicated-server" in OS.get_cmdline_args():
		_setup_chat()

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
	var pos_index := spawn_counter % spawn_positions.size()
	spawn_counter += 1
	spawn_index_map[peer_id] = pos_index
	print("Server spawning player: ", peer_id, " at index ", pos_index)
	# Tell ALL peers (including server) to spawn this player
	_do_spawn.rpc(peer_id, pos_index)
	# Tell the NEW player about all existing players
	for existing_id in spawn_index_map:
		if existing_id != peer_id:
			_do_spawn.rpc_id(peer_id, existing_id, spawn_index_map[existing_id])
	var username: String = MultiplayerManager.players.get(peer_id, "Unknown")
	NetworkSyncLogger.log_peer_connected(peer_id, username)
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
		print("ERROR: No spawn points found! Add Node3D nodes to 'spawn_points' group in level_001.tscn")
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	add_child(player, true)
	player.global_position = spawn_positions[pos_index] + Vector3(0, 1.0, 0)
	print("Spawned player ", peer_id, " at ", spawn_positions[pos_index])

# Solo play mode - spawn player without multiplayer
func _spawn_solo_player() -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = "SoloPlayer"
	add_child(player)
	player.global_position = Vector3(0, -1.5, 0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Zero out velocity so player doesn't fall on spawn
	await get_tree().process_frame
	player.velocity = Vector3.ZERO

func _remove_player(peer_id: int) -> void:
	var username: String = MultiplayerManager.players.get(peer_id, "Unknown")
	NetworkSyncLogger.log_peer_disconnected(peer_id, username)
	SessionLogger.end_session("player_left: %s" % username)
	spawn_index_map.erase(peer_id)
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
	_input_line.editable = true
	_input_line.grab_focus()
	# Show panel fully opaque when focused
	var panel := $HUDLayer/ChatTerminalPanel
	panel.visible = true
	panel.modulate.a = 1.0
	# Freeze player movement and release mouse while typing
	var player := get_tree().get_root().get_node_or_null("Node3D/%s" % str(multiplayer.get_unique_id()))
	if player and player.has_method("set_physics_process"):
		player.set_physics_process(false)
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
	# Restore player movement and recapture mouse
	var player := get_tree().get_root().get_node_or_null("Node3D/%s" % str(multiplayer.get_unique_id()))
	if player and player.has_method("set_physics_process"):
		player.set_physics_process(true)
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
		if text == "":
			return
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
	_lock_btn.pressed.connect(_toggle_chat_lock)
	_resize_handle.button_down.connect(_on_resize_start)
	_drag_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	# Load saved position/size/lock state using bottom-left anchor system
	var pos_x  : float = PresenceManager.load_setting("chat_pos_x",  8.0)
	var pos_y  : float = PresenceManager.load_setting("chat_pos_y",  -212.0)
	var size_x : float = PresenceManager.load_setting("chat_size_x", 162.0)
	var size_y : float = PresenceManager.load_setting("chat_size_y", 124.0)
	_chat_locked = PresenceManager.load_setting("chat_locked", false)
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

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
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
