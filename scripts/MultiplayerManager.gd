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
	if multiplayer.is_server():
		_sync_player_name.rpc_id(peer_id, PresenceManager.username)

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
	_sync_player_name.rpc(PresenceManager.username)
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

@rpc("any_peer", "reliable")
func _sync_player_name(username: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	players[sender_id] = username
	print("Player registered: %s (id %d)" % [username, sender_id])
	# Emit player_connected after name is known so level can spawn correctly
	if multiplayer.is_server():
		player_connected.emit(sender_id)

# Called by client when its level scene is ready to receive spawns
@rpc("any_peer", "call_remote", "reliable")
func client_level_ready() -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	print("Server: client ", peer_id, " level ready")
	# Spawn the new player on ALL peers (including existing ones)
	spawn_player_on_all.rpc(peer_id)
	# Also spawn all EXISTING players on the new client
	for existing_id in players.keys():
		if existing_id != peer_id:
			spawn_player_on_all.rpc_id(peer_id, existing_id)

# Called by server on ALL peers to spawn a player
@rpc("authority", "call_local", "reliable")
func spawn_player_on_all(peer_id: int) -> void:
	print("spawn_player_on_all on peer ", multiplayer.get_unique_id(), " for ", peer_id)
	spawn_requested.emit(peer_id)

signal spawn_requested(peer_id: int)
