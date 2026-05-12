extends CanvasLayer

const MAIN_MENU := "res://assets/ui/main_menu.tscn"

@onready var _panel        : Control = $Panel
@onready var _resume_btn   : Button  = $Panel/VBox/ResumeBtn
@onready var _menu_btn     : Button  = $Panel/VBox/MenuBtn
@onready var _settings_btn : Button  = $Panel/VBox/SettingsBtn
@onready var _quit_btn     : Button  = $Panel/VBox/QuitBtn
@onready var _settings_panel : Control = $SettingsPanel
@onready var _sens_slider    : HSlider = $SettingsPanel/VBox/SensSlider
@onready var _back_btn       : Button  = $SettingsPanel/VBox/BackBtn

enum Screen { NONE, PAUSE, SETTINGS }
var _screen : Screen = Screen.NONE

func _ready() -> void:
	_panel.visible = false
	_settings_panel.visible = false
	_resume_btn.pressed.connect(_close)
	_menu_btn.pressed.connect(_go_to_menu)
	_settings_btn.pressed.connect(_open_settings)
	_quit_btn.pressed.connect(_exit_game)
	_back_btn.pressed.connect(_close_settings)
	_sens_slider.value = ProjectSettings.get_setting("game/mouse_sensitivity", 1.0)
	_sens_slider.value_changed.connect(func(v): ProjectSettings.set_setting("game/mouse_sensitivity", v))
	_style_panels()

func _style_panels() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.97)
	style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.8)
	style.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", style)
	_settings_panel.add_theme_stylebox_override("panel", style.duplicate())

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _screen == Screen.SETTINGS:
			_close_settings()
		elif _screen == Screen.PAUSE:
			_close()
		else:
			_open()

func _open() -> void:
	_screen = Screen.PAUSE
	_panel.visible = true
	_settings_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume_btn.focus_neighbor_top = _resume_btn.get_path_to(_quit_btn)
	_resume_btn.focus_neighbor_bottom = _resume_btn.get_path_to(_menu_btn)
	_menu_btn.focus_neighbor_top = _menu_btn.get_path_to(_resume_btn)
	_menu_btn.focus_neighbor_bottom = _menu_btn.get_path_to(_settings_btn)
	_settings_btn.focus_neighbor_top = _settings_btn.get_path_to(_menu_btn)
	_settings_btn.focus_neighbor_bottom = _settings_btn.get_path_to(_quit_btn)
	_quit_btn.focus_neighbor_top = _quit_btn.get_path_to(_settings_btn)
	_quit_btn.focus_neighbor_bottom = _quit_btn.get_path_to(_resume_btn)
	_resume_btn.grab_focus()

func _close() -> void:
	_screen = Screen.NONE
	_panel.visible = false
	_settings_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _open_settings() -> void:
	_screen = Screen.SETTINGS
	_panel.visible = false
	_settings_panel.visible = true
	_back_btn.grab_focus()

func _close_settings() -> void:
	_open()

func _go_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU)

func _exit_game() -> void:
	get_tree().quit()
