extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://controllers/player.tscn")

var spawn_positions: Array[Vector3] = []
var spawn_counter: int = 0
var spawn_index_map: Dictionary = {}  # peer_id -> pos_index, server only

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
		MultiplayerManager.player_connected.connect(_on_player_connected)
		MultiplayerManager.player_disconnected.connect(_remove_player)
		# Spawn players already registered before level loaded
		for id in MultiplayerManager.players.keys():
			_on_player_connected(id)
	else:
		print("Client level ready, notifying server")
		_client_ready.rpc_id(1)

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
	if MultiplayerManager.players.size() >= 2:
		var names: Array = MultiplayerManager.players.values()
		SessionLogger.try_start_session(names[0], names[1])

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
	player.global_position = spawn_positions[pos_index]
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
