extends Node3D
const PLAYER_SCENE := preload("res://controllers/fps_controller.tscn")
var spawn_positions: Array[Vector3] = [
	Vector3(-10, 2, -10),
	Vector3(-35, 2, -10),
	Vector3(-10, 2, -35),
	Vector3(-35, 2, -35),
]
func _ready() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		MultiplayerManager.player_connected.connect(_spawn_player)
		MultiplayerManager.player_disconnected.connect(_remove_player)
		for id in MultiplayerManager.players:
			_spawn_player(id)
	else:
		# Client: take control of the existing player in the scene
		var existing := get_node_or_null("CharacterBody3D") as CharacterBody3D
		if existing:
			var my_id := multiplayer.get_unique_id()
			existing.set_multiplayer_authority(my_id)
			existing.name = "Player_%d" % my_id
			var idx := MultiplayerManager.players.keys().find(my_id)
			existing.global_position = spawn_positions[idx % spawn_positions.size()]
			# Re-activate camera and input now that authority is set
			var cam := existing.get_node_or_null("CameraController/Camera3D") as Camera3D
			if cam:
				cam.current = true
			existing.set_physics_process(true)
			existing.set_process_unhandled_input(true)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_spawn_player_on_all.rpc(peer_id)
func _remove_player(peer_id: int) -> void:
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
