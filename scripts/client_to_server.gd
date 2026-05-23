extends Node

const PORT := 7777
const ADDRESS := "161.35.41.206"

var peer := ENetMultiplayerPeer.new()

func _ready() -> void:
	var error := peer.create_client(ADDRESS, PORT)
	if error != OK:
		print("failed to connect to server")
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

func _on_connected_to_server() -> void:
	print("connected to server")
	c_register_username.rpc_id(1, PresenceManager.username)

@rpc("any_peer", "call_remote", "reliable")
func c_register_username(username: String) -> void:
	pass

func _on_connection_failed() -> void:
	print("failed to connect to server")

func try_connect_client_to_lobby() -> void:
	c_try_connect_client_to_lobby.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func c_try_connect_client_to_lobby() -> void:
	pass

signal invite_received(from_username: String)

func send_invite(to_username: String) -> void:
	c_send_invite.rpc_id(1, PresenceManager.username, to_username)

@rpc("any_peer", "call_remote", "reliable")
func c_send_invite(from_username: String, to_username: String) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func receive_invite_rpc(from_username: String) -> void:
	invite_received.emit(from_username)
