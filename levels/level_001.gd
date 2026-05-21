extends Node3D

const PLAYER_SCENE := preload("res://controllers/fps_controller.tscn")

var spawn_positions: Array[Vector3] = [
	Vector3(0, 2, 0),
	Vector3(10, 2, 10),
	Vector3(-10, 2, 10),
	Vector3(10, 2, -10),
]
var spawn_counter: int = 0
var spawn_index_map: Dictionary = {}  # peer_id -> pos_index

func _ready() -> void:
	print("Level _ready, is_server: ", multiplayer.is_server())
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		MultiplayerManager.player_disconnected.connect(_remove_player)
		# Spawn any players already registered before this level loaded
		for id in MultiplayerManager.players:
			_on_player_connected(id)
	else:
		# Tell server this client's level is ready to receive spawns
		print("Client level ready, notifying server")
		_client_ready.rpc_id(1)

@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	print("Server: client ", peer_id, " level ready, spawning")
	# Spawn this client and send them all existing players
	_on_player_connected(peer_id)
	# Send all existing spawned players to the new client
	for existing_id in spawn_index_map:
		if existing_id != peer_id:
			_do_spawn.rpc_id(peer_id, existing_id, spawn_index_map[existing_id])

func _on_player_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if get_node_or_null(str(peer_id)) != null:
		return
	var pos_index := spawn_counter % spawn_positions.size()
	spawn_counter += 1
	spawn_index_map[peer_id] = pos_index
	print("Server spawning player: ", peer_id)
	_do_spawn.rpc(peer_id, pos_index)
	if MultiplayerManager.players.size() == 2:
		var names := MultiplayerManager.players.values()
		SessionLogger.try_start_session(names[0], names[1])
		NetworkSyncLogger.log_peer_connected(peer_id, MultiplayerManager.players.get(peer_id, ""))

@rpc("authority", "call_local", "reliable")
func _do_spawn(peer_id: int, pos_index: int) -> void:
	print("_do_spawn called for peer: ", peer_id, " on my peer: ", multiplayer.get_unique_id())
	if get_node_or_null(str(peer_id)) != null:
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_meta("spawn_pos", spawn_positions[pos_index])
	add_child(player)
	player.global_position = spawn_positions[pos_index]

func _remove_player(peer_id: int) -> void:
	var username := MultiplayerManager.players.get(peer_id, "Unknown")
	NetworkSyncLogger.log_peer_disconnected(peer_id, username)
	SessionLogger.end_session("player_left: %s" % username)
	var node := get_node_or_null(str(peer_id))
	if node:
		node.queue_free()
