extends Node

const PORT := 7777
const ADDRESS := "161.35.41.206"

var peer := ENetMultiplayerPeer.new()

signal connected_to_server
signal lobby_joined
signal invite_received(from_username: String)

func _ready() -> void:
	if OS.has_feature("dedicated_server") or "--dedicated-server" in OS.get_cmdline_args():
		return
	var error := peer.create_client(ADDRESS, PORT)
	if error != OK:
		print("failed to connect to server")
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

func _on_connected_to_server() -> void:
	print("connected to server")
	connected_to_server.emit()
	c_register_username.rpc_id(1, PresenceManager.username)

func _on_connection_failed() -> void:
	print("failed to connect to server")

func try_connect_client_to_lobby() -> void:
	print("Client: trying to join lobby")
	c_try_connect_client_to_lobby.rpc_id(1)

func send_invite(to_username: String) -> void:
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
		print("Invite failed: %s not found" % to_username)
		return
	receive_invite_rpc.rpc_id(target_peer, from_username)

@rpc("authority", "call_remote", "reliable")
func receive_invite_rpc(from_username: String) -> void:
	invite_received.emit(from_username)

@rpc("authority", "call_remote", "reliable")
func confirm_lobby_join() -> void:
	lobby_joined.emit()
