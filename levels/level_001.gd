extends Node3D
const PLAYER_SCENE := preload("res://controllers/fps_controller.tscn")
var spawn_positions: Array[Vector3] = [
	Vector3(-10, 2, -10),
	Vector3(-35, 2, -10),
	Vector3(-10, 2, -35),
	Vector3(-35, 2, -35),
]
func _ready() -> void:
	print("Level _ready called, is_server: ", multiplayer.is_server(), " has_peer: ", multiplayer.has_multiplayer_peer())
	var static_player := get_node_or_null("CharacterBody3D")
	if static_player and multiplayer.has_multiplayer_peer():
		static_player.queue_free()
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		print("Level ready on server, existing players: ", MultiplayerManager.players)
		MultiplayerManager.player_connected.connect(_spawn_player)
		MultiplayerManager.player_disconnected.connect(_remove_player)
		for id in MultiplayerManager.players:
			_spawn_player(id)
	else:
		# Client: wait for server to spawn our player via RPC
		pass
func _spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	print("Server spawning player: ", peer_id)
	_spawn_player_on_all.rpc(peer_id)
	# Check if we now have 2 players and one is Rysiu — start session logging
	if MultiplayerManager.players.size() == 2:
		var names := MultiplayerManager.players.values()
		SessionLogger.try_start_session(names[0], names[1])
		NetworkSyncLogger.log_peer_connected(peer_id, MultiplayerManager.players.get(peer_id, "Unknown"))
func _remove_player(peer_id: int) -> void:
	var username := MultiplayerManager.players.get(peer_id, "Unknown")
	NetworkSyncLogger.log_peer_disconnected(peer_id, username)
	SessionLogger.end_session("player_left: %s" % username)
	var node := get_node_or_null("Player_%d" % peer_id)
	if node:
		node.queue_free()
@rpc("authority", "reliable", "call_local")
func _spawn_player_on_all(peer_id: int) -> void:
	print("Spawning player on all: ", peer_id, " my id: ", multiplayer.get_unique_id())
	var player := PLAYER_SCENE.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
	var idx := MultiplayerManager.players.keys().find(peer_id)
	var spawn_pos := spawn_positions[idx % spawn_positions.size()]
	add_child(player)
	player.global_position = spawn_pos
	# If this is our own player, activate camera and input
	if peer_id == multiplayer.get_unique_id():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var cam := player.get_node_or_null("CameraController/Camera3D") as Camera3D
		if cam:
			cam.current = true
