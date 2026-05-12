extends CanvasLayer

const MAIN_MENU := "res://assets/ui/main_menu.tscn"

@onready var _panel        : Control = $Panel
@onready var _resume_btn   : Button  = $Panel/VBox/ResumeBtn
@onready var _menu_btn     : Button  = $Panel/VBox/MenuBtn
@onready var _settings_btn : Button  = $Panel/VBox/SettingsBtn
@onready var _quit_btn     : Button  = $Panel/VBox/QuitBtn

var _settings_open : bool = false

func _ready() -> void:
	_panel.visible = false
	_resume_btn.pressed.connect(_close)
	_menu_btn.pressed.connect(_go_to_menu)
	_quit_btn.pressed.connect(_exit_game)
	_settings_btn.pressed.connect(_show_settings)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _panel.visible:
			_close()
		else:
			_open()

func _open() -> void:
	_panel.visible = true
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

func _show_settings() -> void:
	_settings_open = true
	var dialog := Window.new()
	dialog.title = "Settings"
	dialog.size = Vector2i(400, 300)
	dialog.unresizable = true
	dialog.close_requested.connect(func(): _settings_open = false; dialog.queue_free())
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 16)
	
	# Mouse Sensitivity
	var sens_label := Label.new()
	sens_label.text = "Mouse Sensitivity"
	vbox.add_child(sens_label)
	var sens_slider := HSlider.new()
	sens_slider.min_value = 0.1
	sens_slider.max_value = 5.0
	sens_slider.step = 0.1
	sens_slider.value = ProjectSettings.get_setting("game/mouse_sensitivity", 1.0)
	sens_slider.value_changed.connect(func(v): ProjectSettings.set_setting("game/mouse_sensitivity", v))
	vbox.add_child(sens_slider)
	
	# Keybindings placeholder
	var keys_label := Label.new()
	keys_label.text = "Keybindings"
	vbox.add_child(keys_label)
	var keys_btn := Button.new()
	keys_btn.text = "Coming Soon"
	keys_btn.disabled = true
	vbox.add_child(keys_btn)
	
	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): _settings_open = false; dialog.queue_free())
	vbox.add_child(close_btn)
	
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()

func _close() -> void:
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _go_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU)

func _exit_game() -> void:
	get_tree().quit()
