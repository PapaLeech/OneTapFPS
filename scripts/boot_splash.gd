extends CanvasLayer

func _ready() -> void:
	await get_tree().create_timer(3.0).timeout
	_go_to_menu()

func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if event.pressed:
			_go_to_menu()

func _go_to_menu() -> void:
	set_process_input(false)
	get_tree().change_scene_to_file("res://assets/ui/main_menu.tscn")
