extends Node3D

const PLAYER_SCENE := preload("res://controllers/fps_controller.tscn")

var spawn_positions: Array[Vector3] = [
	Vector3(0, 2, 0),
	Vector3(10, 2, 10),
	Vector3(-10, 2, 10),
	Vector3(10, 2, -10),
]
var spawn_counter: int = 0

@onready var _spawner: MultiplayerSpawner = $PlayerSpawner2

func _ready() -> void:
	print("Level _ready, is_server: ", multiplayer.is_server())
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		_spawner.spawn_function = _spawn_func
		MultiplayerManager.player_connected.connect(_on_player_connected)
		MultiplayerManager.player_disconnected.connect(_remove_player)
		# Spawn any players already connected when level loads
		for id in MultiplayerManager.players:
			_on_player_connected(id)

func _spawn_func(peer_id: int) -> Node:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	var pos := spawn_positions[spawn_counter % spawn_positions.size()]
	spawn_counter += 1
	player.set_deferred("global_position", pos)
	return player

func _on_player_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if get_node_or_null(str(peer_id)) != null:
		return
	print("Server spawning player: ", peer_id)
	_spawner.spawn(peer_id)
	if MultiplayerManager.players.size() == 2:
		var names := MultiplayerManager.players.values()
		SessionLogger.try_start_session(names[0], names[1])
		NetworkSyncLogger.log_peer_connected(peer_id, MultiplayerManager.players.get(peer_id, ""))

func _remove_player(peer_id: int) -> void:
	var username := MultiplayerManager.players.get(peer_id, "Unknown")
	NetworkSyncLogger.log_peer_disconnected(peer_id, username)
	SessionLogger.end_session("player_left: %s" % username)
	var node := get_node_or_null(str(peer_id))
	if node:
		node.queue_free()
