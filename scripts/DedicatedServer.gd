extends Node

## OneTapFPS Dedicated Server
## Start with: ./OneTapFPS.x86_64 --headless --dedicated-server

const PORT := 7777
const MAX_PLAYERS := 8

var spawn_positions: Array[Vector3] = [
	Vector3(0, 1, 0),
	Vector3(10, 1, 10),
	Vector3(-10, 1, -10),
	Vector3(10, 1, -10),
	Vector3(5, 1, -5),
	Vector3(-5, 1, 5),
	Vector3(15, 1, 0),
	Vector3(-15, 1, 0),
]

var connected_players: Dictionary = {}
var next_spawn_index: int = 0

func _ready() -> void:
	if not OS.has_feature("dedicated_server") and not "--dedicated-server" in OS.get_cmdline_args():
		print("Not running as dedicated server — skipping.")
		return

	print("=== OneTapFPS Dedicated Server ===")
	print("Starting on port %d, max %d players" % [PORT, MAX_PLAYERS])

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to start server: %s" % str(err))
		get_tree().quit(1)
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	print("Server ready. Waiting for players...")

func _on_player_connected(peer_id: int) -> void:
	print("Player connected: %d" % peer_id)
	connected_players[peer_id] = {
		"username": "Player_%d" % peer_id,
		"spawn_index": next_spawn_index % spawn_positions.size()
	}
	next_spawn_index += 1
	_spawn_on_all_clients.rpc(peer_id, connected_players[peer_id]["spawn_index"])
	for existing_id in connected_players:
		if existing_id != peer_id:
			_spawn_on_all_clients.rpc_id(peer_id, existing_id, connected_players[existing_id]["spawn_index"])

func _on_player_disconnected(peer_id: int) -> void:
	print("Player disconnected: %d" % peer_id)
	connected_players.erase(peer_id)
	_remove_on_all_clients.rpc(peer_id)

@rpc("authority", "reliable", "call_local")
func _spawn_on_all_clients(_peer_id: int, _spawn_index: int) -> void:
	pass

@rpc("authority", "reliable", "call_local")
func _remove_on_all_clients(_peer_id: int) -> void:
	pass

@rpc("any_peer", "reliable")
func register_username(username: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender in connected_players:
		connected_players[sender]["username"] = username
		print("Player %d is: %s" % [sender, username])
