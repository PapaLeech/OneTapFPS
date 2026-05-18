extends Node3D

const PLAYER_SCENE_PATH := "res://controllers/fps_controller.tscn"
const PLAYER_SCENE := preload("res://controllers/fps_controller.tscn")

var spawn_positions: Array[Vector3] = [
	Vector3(-10, 2, -10),
	Vector3(-35, 2, -10),
	Vector3(-10, 2, -35),
	Vector3(-35, 2, -35),
]

@onready var _spawner : MultiplayerSpawner = $PlayerSpawner

func _ready() -> void:
	print("Level _ready called, is_server: ", multiplayer.is_server(), " has_peer: ", multiplayer.has_multiplayer_peer())
	if not multiplayer.has_multiplayer_peer():
		return
	# Register the player scene so MultiplayerSpawner replicates it to all clients
	_spawner.add_spawnable_scene(PLAYER_SCENE_PATH)
	_spawner.spawn_function = _spawn_func
	if multiplayer.is_server():
		print("Level ready on server, existing players: ", MultiplayerManager.players)
		MultiplayerManager.player_connected.connect(_spawn_player)
		MultiplayerManager.player_disconnected.connect(_remove_player)
		for id in MultiplayerManager.players:
			_spawn_player(id)

func _spawn_func(data: Variant) -> Node:
	var peer_id : int = data
	var player := PLAYER_SCENE.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
	# Pick spawn position
	var keys := MultiplayerManager.players.keys()
	var idx := keys.find(peer_id)
	if idx < 0:
		idx = 0
	var spawn_pos := spawn_positions[idx % spawn_positions.size()]
	player.set_deferred("global_position", spawn_pos)
	# Activate camera and input only for the local player
	if peer_id == multiplayer.get_unique_id():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		player.call_deferred("_activate_camera")
	print("_spawn_func called for peer: ", peer_id, " local: ", multiplayer.get_unique_id(), " is_authority: ", peer_id == multiplayer.get_unique_id())
	return player

func _spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if get_node_or_null("Player_%d" % peer_id) != null:
		print("Player already exists for: ", peer_id)
		return
	print("Server spawning player: ", peer_id)
	_spawner.spawn(peer_id)
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
