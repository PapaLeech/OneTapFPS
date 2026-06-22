extends Node

const PORT := 7777
const ADDRESS := "161.35.41.206"
const MAX_LOBBIES := 5
const MAX_PLAYERS_PER_LOBBY := 5

var peer := ENetMultiplayerPeer.new()

var lobbies: Array[Lobby] = []
var idle_clients: Array[int] = []
var username_to_peer: Dictionary = {}
var players: Dictionary = {}
var _mode : String = "deathmatch"  # default; switches to "snd" when requested

func set_mode(mode: String) -> void:
	_mode = mode
	print("Server: mode set to %s" % _mode)
	if OS.has_feature("dedicated_server") or "--dedicated-server" in OS.get_cmdline_args():
		var scene := "res://levels/level_001.tscn"
		if _mode == "snd":
			scene = "res://levels/snd_level_001.tscn"
		print("Server reloading scene: ", scene)
		get_tree().change_scene_to_file.call_deferred(scene)

func get_mode() -> String:
	return _mode

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed
signal connected_to_server

func _ready() -> void:
	if not OS.has_feature("dedicated_server") and not "--dedicated-server" in OS.get_cmdline_args():
		return
	print("=== OneTapFPS MultiplayerManager starting on port %d ==="  % PORT)
	var error := peer.create_server(PORT)
	if error != OK:
		print("failed to start server: %s" % str(error))
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Server ready. Listening on port %d" % PORT)
	var scene := "res://levels/level_001.tscn"
	if _mode == "snd":
		scene = "res://levels/snd_level_001.tscn"
	print("Server loading scene: ", scene)
	get_tree().change_scene_to_file.call_deferred(scene)


func _on_connected_to_server() -> void:
	print("connected to server")

func _on_peer_connected(id: int) -> void:
	idle_clients.append(id)
	print("client %d connected to server" % id)

func _on_peer_disconnected(id: int) -> void:
	var maybe_lobby := get_lobby_from_client_id(id)

	if maybe_lobby:
		maybe_lobby.remove_client(id)

		if maybe_lobby.clients.is_empty():
			lobbies.erase(maybe_lobby)
			maybe_lobby.queue_free()

	idle_clients.erase(id)

	for uname in username_to_peer.keys():
		if username_to_peer[uname] == id:
			username_to_peer.erase(uname)
			break

	players.erase(id)
	player_disconnected.emit(id)

	print("client %d disconnected from server" % id)

	# If the server is now completely empty, reset SND controller state
	# so the next session starts fresh (fixes stale ready-up phase).
	if players.is_empty():
		var tree : SceneTree = Engine.get_main_loop()
		if tree:
			var root : Node = tree.root
			var level : Node = root.get_node_or_null("Node3D")
			if level:
				var snd : Node = level.get_node_or_null("SearchAndDestroyController")
				if snd and snd.has_method("reset_state"):
					snd.reset_state()
					print("Server: SND controller state reset (lobby empty)")
				var lag_comp : Node = level.get_node_or_null("LagCompensator")
				if lag_comp and lag_comp.has_method("clear_history"):
					lag_comp.clear_history()

func _on_connection_failed() -> void:
	print("failed to connect to server")

func get_lobby_from_client_id(id: int) -> Lobby:
	for lobby in lobbies:
		if lobby.clients.has(id):
			return lobby
	return null

func handle_lobby_join(client_id: int) -> void:
	var maybe_lobby := get_non_full_lobby()
	if maybe_lobby:
		maybe_lobby.add_client(client_id)
		idle_clients.erase(client_id)
		print("client %d connected to lobby %s" % [client_id, maybe_lobby.name])
		player_connected.emit(client_id)
		ClientToServer.confirm_lobby_join.rpc_id(client_id)
	else:
		print("No available lobby for client %d" % client_id)

func get_non_full_lobby() -> Lobby:
	for lobby in lobbies:
		if lobby.clients.size() < MAX_PLAYERS_PER_LOBBY:
			return lobby

	if lobbies.size() < MAX_LOBBIES:
		var new_lobby := Lobby.new()
		lobbies.append(new_lobby)
		new_lobby.name = str(new_lobby.get_instance_id())
		add_child(new_lobby)
		return new_lobby

	print("lobbies full")
	return null
