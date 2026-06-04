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
@onready var _input_line    : LineEdit      = $HUDLayer/ChatTerminalPanel/VBox/InputLine

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
	_input_line.text_submitted.connect(_on_chat_input_submitted)
	_chat_output.visible = true
	_term_output.visible = false
	# Start fully hidden — appears on first Enter press
	var panel := $HUDLayer/ChatTerminalPanel
	panel.modulate.a = 0.0
	panel.visible = false
	_release_chat_focus()

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

func _on_chat_input_submitted(text: String) -> void:
	if text.strip_edges() == "":
		_input_line.clear()
		return
	if _chat_focus == ChatFocus.CHAT:
		_send_chat_message.rpc(PresenceManager.username, text)
	elif _chat_focus == ChatFocus.TERMINAL:
		_term_output.append_text("[color=lime]> " + text + "[/color]\n")
		_execute_chat_command(text)
	_input_line.clear()
	# Stay focused after sending — Esc required to close
	_input_line.grab_focus()

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
