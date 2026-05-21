extends Node

const PORT := 7777
const MAX_PLAYERS := 8
const SERVER_IP := "161.35.41.206"

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed
signal connected_to_server

var players: Dictionary = {}  # peer_id -> username

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

func connect_to_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(SERVER_IP, PORT)
	if err != OK:
		push_error("Failed to connect to server: " + str(err))
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	print("Connecting to dedicated server %s:%d" % [SERVER_IP, PORT])

func disconnect_from_game() -> void:
	players.clear()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: ", peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: ", peer_id)
	var username := players.get(peer_id, "Unknown")
	if not multiplayer.is_server():
		NetworkSyncLogger.log_peer_disconnected(peer_id, username)
	players.erase(peer_id)
	player_disconnected.emit(peer_id)

func _on_connected_to_server() -> void:
	print("Connected to server!")
	var my_id := multiplayer.get_unique_id()
	players[my_id] = PresenceManager.username
	# Send our username to the server only
	_register_username.rpc_id(1, PresenceManager.username)
	connected_to_server.emit()
	var timer := Timer.new()
	add_child(timer)
	timer.wait_time = 5.0
	timer.autostart = true
	timer.timeout.connect(_log_ping)

func _log_ping() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	LagCompensationLogger.log_ping(PresenceManager.username, 0.0)

func _on_connection_failed() -> void:
	print("Connection failed.")
	connection_failed.emit()

# Client -> Server: register my username
@rpc("any_peer", "reliable")
func _register_username(username: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	players[sender_id] = username
	print("Player registered: %s (id %d)" % [username, sender_id])
	# Broadcast this player's username to all existing clients
	_broadcast_username.rpc(sender_id, username)
	# Send all existing usernames to the new client
	for id in players:
		if id != sender_id:
			_broadcast_username.rpc_id(sender_id, id, players[id])
	# Don't emit player_connected here - spawning is triggered by _client_ready in level_001.gd
	# once the client confirms its level scene is loaded and ready to receive RPCs

# Server -> All clients: here is a player's username
@rpc("authority", "call_local", "reliable")
func _broadcast_username(peer_id: int, username: String) -> void:
	players[peer_id] = username
	print("Player known: %s (id %d)" % [username, peer_id])
