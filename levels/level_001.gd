extends Node3D
const PLAYER_SCENE := preload("res://controllers/fps_controller.tscn")
var spawn_positions: Array[Vector3] = [
	Vector3(-10, 2, -10),
	Vector3(-35, 2, -10),
	Vector3(-10, 2, -35),
	Vector3(-35, 2, -35),
]
func _ready() -> void:
	# Remove the static CharacterBody3D from scene — multiplayer spawns its own
	var static_player := get_node_or_null("CharacterBody3D")
	if static_player and multiplayer.has_multiplayer_peer():
		static_player.queue_free()
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
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
	var node := get_node_or_null("Players/Player_%d" % peer_id)
	if node:
		node.queue_free()
@rpc("authority", "reliable", "call_local")
func _spawn_player_on_all(peer_id: int) -> void:
	var players_node := get_node_or_null("Players")
	if players_node == null:
		players_node = Node3D.new()
		players_node.name = "Players"
		add_child(players_node)
	var player := PLAYER_SCENE.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
	var idx := MultiplayerManager.players.keys().find(peer_id)
	var spawn_pos := spawn_positions[idx % spawn_positions.size()]
	player.global_position = spawn_pos
	players_node.add_child(player)
	# Configure MultiplayerSynchronizer after adding to scene tree
	var sync := player.get_node_or_null("MultiplayerSynchronizer")
	if sync:
		var config := SceneReplicationConfig.new()
		config.add_property(NodePath(".:position"))
		config.add_property(NodePath(".:rotation"))
		sync.replication_config = config
		sync.set_multiplayer_authority(peer_id)
