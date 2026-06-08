extends Node

const PORT := 7777
const ADDRESS := "161.35.41.206"

var peer := ENetMultiplayerPeer.new()

signal connected_to_server
signal lobby_joined
signal invite_received(from_username: String)
signal invite_accepted(from_username: String)
signal lobby_match_starting

func _ready() -> void:
	if OS.has_feature("dedicated_server") or "--dedicated-server" in OS.get_cmdline_args():
		return
	connect_to_game_server()

func connect_to_game_server() -> void:
	# If already connected as a real client, just re-register
	if multiplayer.has_multiplayer_peer() and multiplayer.get_unique_id() != 1:
		print("[CTS] already connected as client, re-registering")
		c_register_username.rpc_id(1, PresenceManager.username)
		connected_to_server.emit()
		return
	# Clear any default/stale peer
	multiplayer.multiplayer_peer = null
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(ADDRESS, PORT)
	print("[CTS] create_client error: ", error)
	if error != OK:
		print("failed to connect to server")
		return
	multiplayer.multiplayer_peer = peer
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)

func _on_connected_to_server() -> void:
	print("connected to server")
	c_register_username.rpc_id(1, PresenceManager.username)
	connected_to_server.emit()

func _on_connection_failed() -> void:
	print("failed to connect to server")

func reconnect() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	connect_to_game_server()

func try_connect_client_to_lobby() -> void:
	print("Client: trying to join lobby")
	c_try_connect_client_to_lobby.rpc_id(1)

func request_snd_match() -> void:
	c_request_snd_match.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func c_request_snd_match() -> void:
	MultiplayerManager.set_mode("snd")

func send_invite(to_username: String) -> void:
	print("[CTS] send_invite called for ", to_username, " has_peer: ", multiplayer.has_multiplayer_peer(), " unique_id: ", multiplayer.get_unique_id())
	if not multiplayer.has_multiplayer_peer() or multiplayer.get_unique_id() == 1:
		connected_to_server.connect(func():
			await get_tree().create_timer(0.3).timeout
			c_send_invite.rpc_id(1, PresenceManager.username, to_username)
		, CONNECT_ONE_SHOT)
		connect_to_game_server()
		return
	c_send_invite.rpc_id(1, PresenceManager.username, to_username)

@rpc("any_peer", "call_remote", "reliable")
func c_register_username(username: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	MultiplayerManager.username_to_peer[username] = sender
	MultiplayerManager.players[sender] = username
	print("registered %s as peer %d" % [username, sender])

@rpc("any_peer", "call_remote", "reliable")
func c_try_connect_client_to_lobby() -> void:
	var client_id := multiplayer.get_remote_sender_id()
	print("Server: lobby join RPC received from %d" % client_id)
	MultiplayerManager.handle_lobby_join(client_id)

@rpc("any_peer", "call_remote", "reliable")
func c_send_invite(from_username: String, to_username: String) -> void:
	var target_peer := MultiplayerManager.username_to_peer.get(to_username, -1)
	if target_peer == -1:
		# Try case-insensitive lookup
		for key in MultiplayerManager.username_to_peer:
			if key.to_lower() == to_username.to_lower():
				target_peer = MultiplayerManager.username_to_peer[key]
				break
	if target_peer == -1:
		print("Invite failed: %s not found in %s" % [to_username, MultiplayerManager.username_to_peer])
		return
	receive_invite_rpc.rpc_id(target_peer, from_username)

@rpc("authority", "call_remote", "reliable")
func receive_invite_rpc(from_username: String) -> void:
	invite_received.emit(from_username)

@rpc("authority", "call_remote", "reliable")
func confirm_lobby_join() -> void:
	lobby_joined.emit()

func accept_invite(from_username: String) -> void:
	c_accept_invite.rpc_id(1, PresenceManager.username, from_username)

func start_lobby_match() -> void:
	c_start_lobby_match.rpc_id(1, PresenceManager.username)

@rpc("any_peer", "call_remote", "reliable")
func c_accept_invite(accepter: String, host_username: String) -> void:
	# Notify host that someone accepted
	var host_peer := MultiplayerManager.username_to_peer.get(host_username, -1)
	if host_peer == -1:
		for key in MultiplayerManager.username_to_peer:
			if key.to_lower() == host_username.to_lower():
				host_peer = MultiplayerManager.username_to_peer[key]
				break
	if host_peer == -1:
		print("accept_invite: host %s not found" % host_username)
		return
	# Tell host someone accepted
	invite_accepted_rpc.rpc_id(host_peer, accepter)
	# Tell accepter to add dogtags
	var accepter_peer := multiplayer.get_remote_sender_id()
	lobby_member_added_rpc.rpc_id(accepter_peer, host_username, accepter)

@rpc("any_peer", "call_remote", "reliable")
func c_start_lobby_match(host_username: String) -> void:
	# Tell all members of this pre-lobby to join the match
	var host_peer := multiplayer.get_remote_sender_id()
	print("Server: start_lobby_match from %s" % host_username)
	# Notify all registered peers that match is starting (simple broadcast for now)
	for uname in MultiplayerManager.username_to_peer:
		var pid: int = MultiplayerManager.username_to_peer[uname]
		lobby_match_starting_rpc.rpc_id(pid)

@rpc("authority", "call_remote", "reliable")
func invite_accepted_rpc(accepter_username: String) -> void:
	invite_accepted.emit(accepter_username)

@rpc("authority", "call_remote", "reliable")
func lobby_member_added_rpc(host_username: String, accepter_username: String) -> void:
	invite_accepted.emit(accepter_username)

@rpc("authority", "call_remote", "reliable")
func lobby_match_starting_rpc() -> void:
	lobby_match_starting.emit()
