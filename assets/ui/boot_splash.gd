extends CanvasLayer

const MAIN_MENU = "res://assets/ui/main_menu.tscn"

func _ready() -> void:
	get_window().mode = Window.MODE_FULLSCREEN
	await get_tree().create_timer(5.0).timeout
	_go_to_menu()

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
