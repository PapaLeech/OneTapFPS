extends Node3D

const PLAYER_SCENE := preload("res://controllers/fps_controller.tscn")

func _ready() -> void:
	print("Level _ready called, is_server: ", multiplayer.is_server(), " has_peer: ", multiplayer.has_multiplayer_peer())
	if not multiplayer.has_multiplayer_peer():
		return
	# Connect to MultiplayerManager's spawn signal (works on all peers)
	MultiplayerManager.spawn_requested.connect(_do_spawn_player)
	if multiplayer.is_server():
		print("Level ready on server, existing players: ", MultiplayerManager.players)
		MultiplayerManager.player_disconnected.connect(_remove_player)
	else:
		# Tell server this client's level is loaded and ready
		print("Client level ready, notifying server")
		MultiplayerManager.client_level_ready.rpc_id(1)

func _do_spawn_player(peer_id: int, spawn_pos: Vector3) -> void:
	print("_do_spawn_player on peer ", multiplayer.get_unique_id(), " for ", peer_id, " at ", spawn_pos)
	if get_node_or_null("Player_%d" % peer_id) != null:
		return
	
	var player := PLAYER_SCENE.instantiate()
	player.name = "Player_%d" % peer_id
	# Use the spawn position provided by the server to ensure separation
	add_child(player)
	player.global_position = spawn_pos
	
	# Set authority after adding to tree or in _enter_tree
	# Using recursive=true to ensure all child nodes inherit authority
	player.set_multiplayer_authority(peer_id, true)
	print("Spawned player ", peer_id, " at ", player.global_position, " is_authority: ", peer_id == multiplayer.get_unique_id())
	
	# Check terrorist visibility using more robust unique name reference
	var terrorist := player.get_node_or_null("%Terrorist")
	print("Terrorist node: ", terrorist, " visible: ", terrorist.visible if terrorist else "NOT FOUND")
	if peer_id == multiplayer.get_unique_id():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		player.call_deferred("_activate_camera")
	if multiplayer.is_server() and MultiplayerManager.players.size() == 2:
		var names := MultiplayerManager.players.values()
		SessionLogger.try_start_session(names[0], names[1])
		NetworkSyncLogger.log_peer_connected(peer_id, MultiplayerManager.players.get(peer_id, ""))

func _remove_player(peer_id: int) -> void:
	var username := MultiplayerManager.players.get(peer_id, "Unknown")
	NetworkSyncLogger.log_peer_disconnected(peer_id, username)
	SessionLogger.end_session("player_left: %s" % username)
	var node := get_node_or_null("Player_%d" % peer_id)
	if node:
		node.queue_free()
