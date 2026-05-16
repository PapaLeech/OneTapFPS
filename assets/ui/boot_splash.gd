extends CanvasLayer

const MAIN_MENU = "res://assets/ui/main_menu.tscn"

func _ready() -> void:
	if OS.has_feature("dedicated_server") or "--dedicated-server" in OS.get_cmdline_args():
		_start_dedicated_server()
		return
	get_window().mode = Window.MODE_FULLSCREEN
	await get_tree().create_timer(5.0).timeout
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
	multiplayer.peer_connected.connect(func(id): print("Player connected: %d" % id))
	multiplayer.peer_disconnected.connect(func(id): print("Player disconnected: %d" % id))
	print("Server ready. Listening on port 7777.")

func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if event.pressed:
			_go_to_menu()

func _go_to_menu() -> void:
	set_process_input(false)
	var overlay := $FadeOverlay as ColorRect
	var tween := create_tween()
	tween.tween_property(overlay, "color", Color(0, 0, 0, 1), 1.5)
	await tween.finished
	get_tree().change_scene_to_file(MAIN_MENU)
