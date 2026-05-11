extends CanvasLayer

const MAIN_MENU := "res://assets/ui/main_menu.tscn"

@onready var _panel      : Control = $Panel
@onready var _resume_btn : Button  = $Panel/VBox/ResumeBtn
@onready var _menu_btn   : Button  = $Panel/VBox/MenuBtn
@onready var _quit_btn   : Button  = $Panel/VBox/QuitBtn

func _ready() -> void:
	_panel.visible = false
	_resume_btn.pressed.connect(_close)
	_menu_btn.pressed.connect(_go_to_menu)
	_quit_btn.pressed.connect(_exit_game)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		if _panel.visible:
			_close()
		else:
			_open()

func _open() -> void:
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close() -> void:
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _go_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU)

func _exit_game() -> void:
	get_tree().quit()
