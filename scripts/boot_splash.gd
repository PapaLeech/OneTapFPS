extends CanvasLayer

func _ready() -> void:
	if OS.has_feature("dedicated_server") or "--dedicated-server" in OS.get_cmdline_args():
		_start_dedicated_server()
		return
	await get_tree().create_timer(3.0).timeout
	_go_to_menu()

func _start_dedicated_server() -> void:
	print("=== OneTapFPS Dedicated Server ===")
	print("Starting ENet server on port 7777...")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(7777, 8)
	if err != OK:
		push_error("Failed to start server: %s" % str(err))
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	print("Server ready. Listening on port 7777.")
	get_tree().change_scene_to_file("res://levels/level_001.tscn")

func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if event.pressed:
			_go_to_menu()

func _go_to_menu() -> void:
	set_process_input(false)
	get_tree().change_scene_to_file("res://assets/ui/main_menu.tscn")
