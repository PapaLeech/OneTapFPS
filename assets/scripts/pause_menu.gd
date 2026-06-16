extends CanvasLayer

const MAIN_MENU := "res://assets/ui/main_menu.tscn"

@onready var _panel        : Control = $Panel
@onready var _resume_btn   : Button  = $Panel/VBox/ResumeBtn
@onready var _menu_btn     : Button  = $Panel/VBox/MenuBtn
@onready var _settings_btn : Button  = $Panel/VBox/SettingsBtn
@onready var _quit_btn     : Button  = $Panel/VBox/QuitBtn
@onready var _settings_panel : Control = $SettingsPanel
@onready var _sens_slider    : HSlider = $SettingsPanel/VBox/SensSlider
@onready var _ads_sens_slider : HSlider = $SettingsPanel/VBox/ADSSensSlider
@onready var _back_btn       : Button  = $SettingsPanel/VBox/BackBtn
@onready var _death_panel    : Control = $DeathPanel

var _respawn_btn : Button
var _death_menu_btn : Button
var _death_settings_btn : Button
var _death_quit_btn : Button
var _master_vol_slider : HSlider = null

enum Screen { NONE, PAUSE, SETTINGS, DEATH, DEATH_SETTINGS }
var _screen : Screen = Screen.NONE

func _ready() -> void:
	_panel.visible = false
	_settings_panel.visible = false
	_death_panel.visible = false
	_build_death_panel()
	_resume_btn.pressed.connect(_close)
	_menu_btn.pressed.connect(_go_to_menu)
	_settings_btn.pressed.connect(_open_settings)
	_quit_btn.pressed.connect(_exit_game)
	_back_btn.pressed.connect(_close_settings)
	_sens_slider.value = PresenceManager.load_setting("mouse_sensitivity", 1.0)
	_sens_slider.value_changed.connect(func(v): PresenceManager.save_setting("mouse_sensitivity", v))
	_ads_sens_slider.value = PresenceManager.load_setting("ads_sensitivity", 1.0)
	_ads_sens_slider.value_changed.connect(func(v): PresenceManager.save_setting("ads_sensitivity", v))
	_build_graphics_presets()
	_style_panels()
	# Add Keyboard / Mouse button to settings panel
	var kb_btn := Button.new()
	kb_btn.text = "Keyboard / Mouse"
	var vbox := $SettingsPanel/VBox
	vbox.add_child_at_position(kb_btn, vbox.get_child_count() - 1) if vbox.has_method("add_child_at_position") else vbox.add_child(kb_btn)
	vbox.move_child(kb_btn, vbox.get_child_count() - 2)
	kb_btn.pressed.connect(func(): _show_keybindings())

func _build_death_panel() -> void:
	var vbox := VBoxContainer.new()
	_death_panel.add_child(vbox)
	var title := Label.new()
	title.text = "YOU DIED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 1.0))
	vbox.add_child(title)
	_respawn_btn = Button.new()
	_respawn_btn.text = "Respawn"
	_respawn_btn.pressed.connect(_respawn)
	vbox.add_child(_respawn_btn)
	_death_menu_btn = Button.new()
	_death_menu_btn.text = "Return to Main Menu"
	_death_menu_btn.pressed.connect(_go_to_menu)
	vbox.add_child(_death_menu_btn)
	_death_settings_btn = Button.new()
	_death_settings_btn.text = "Settings"
	_death_settings_btn.pressed.connect(_open_death_settings)
	vbox.add_child(_death_settings_btn)
	_death_quit_btn = Button.new()
	_death_quit_btn.text = "Exit Game"
	_death_quit_btn.pressed.connect(_exit_game)
	vbox.add_child(_death_quit_btn)

func _build_graphics_presets() -> void:
	var vbox := _settings_panel.get_node("VBox")
	var gfx_label := Label.new()
	gfx_label.text = "Graphics Preset"
	vbox.add_child(gfx_label)
	var gfx_row := HBoxContainer.new()
	gfx_row.add_theme_constant_override("separation", 8)
	vbox.add_child(gfx_row)
	var preset_labels := ["Low", "Medium", "High"]
	var current_preset : int = GraphicsManager.current_preset()
	var preset_btns : Array = []
	for i in range(3):
		var pbtn := Button.new()
		pbtn.text = preset_labels[i]
		pbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pbtn.toggle_mode = true
		pbtn.button_pressed = (i == current_preset)
		var idx := i
		pbtn.pressed.connect(func():
			GraphicsManager.apply_preset(idx)
			GraphicsManager.save_preset(idx)
			for b in preset_btns:
				b.button_pressed = false
			preset_btns[idx].button_pressed = true
		)
		gfx_row.add_child(pbtn)
		preset_btns.append(pbtn)
	# Move BackBtn to end so it stays at the bottom
	var back := vbox.get_node_or_null("BackBtn")
	if back:
		vbox.move_child(back, vbox.get_child_count() - 1)

	# ── Master Volume ──────────────────────────────────────────────
	var master_label := Label.new()
	master_label.text = "Master Volume"
	vbox.add_child(master_label)
	_master_vol_slider = HSlider.new()
	_master_vol_slider.min_value = 0.0
	_master_vol_slider.max_value = 1.0
	_master_vol_slider.step = 0.05
	_master_vol_slider.value = PresenceManager.load_setting("master_volume", 1.0)
	# Apply saved volume immediately on load
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(_master_vol_slider.value))
	_master_vol_slider.value_changed.connect(func(v):
		PresenceManager.save_setting("master_volume", v)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(v))
	)
	vbox.add_child(_master_vol_slider)
	# Move BackBtn to very end
	if back:
		vbox.move_child(back, vbox.get_child_count() - 1)

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
	_death_panel.add_theme_stylebox_override("panel", style.duplicate())

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("exit"):
		# Don't handle Esc if chat is open — level_001 handles it first
		var level := get_tree().get_root().get_node_or_null("Node3D")
		if level and level.get("_chat_focus") != null and level._chat_focus != 0:
			return
		get_viewport().set_input_as_handled()
		if _screen == Screen.SETTINGS:
			_close_settings()
		elif _screen == Screen.DEATH_SETTINGS:
			_open_death_menu()
		elif _screen == Screen.PAUSE:
			_close()
		elif _screen == Screen.DEATH:
			pass
		else:
			_open()

func _open() -> void:
	_screen = Screen.PAUSE
	_panel.visible = true
	_settings_panel.visible = false
	_death_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Disable chat while pause menu is open
	var level := get_tree().get_root().get_node_or_null("Node3D")
	if level and level.has_method("set_chat_enabled"):
		level.set_chat_enabled(false)
	# Hide crosshair via weapon controller
	var wc := get_parent().get_node_or_null("Components/WeaponController")
	if wc and wc.get("_crosshair"): wc._crosshair.hide()

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
	# Re-enable chat when pause menu closes
	var level := get_tree().get_root().get_node_or_null("Node3D")
	if level and level.has_method("set_chat_enabled"):
		level.set_chat_enabled(true)
	# Show crosshair via weapon controller
	var wc := get_parent().get_node_or_null("Components/WeaponController")
	if wc and wc.get("_crosshair"): wc._crosshair.show()


func _open_settings() -> void:
	_screen = Screen.SETTINGS
	_panel.visible = false
	_settings_panel.visible = true
	# Reload values fresh in case username wasn't set at _ready time
	_sens_slider.value = PresenceManager.load_setting("mouse_sensitivity", 1.0)
	_ads_sens_slider.value = PresenceManager.load_setting("ads_sensitivity", 1.0)
	if _master_vol_slider:
		_master_vol_slider.value = PresenceManager.load_setting("master_volume", 1.0)
	_back_btn.grab_focus()

func _close_settings() -> void:
	_open()

func _close_death_for_round_end() -> void:
	# Hide death panel so round end message is visible
	_death_panel.visible = false
	_screen = Screen.NONE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Re-enable chat
	var level := get_tree().get_root().get_node_or_null("Node3D")
	if level and level.has_method("set_chat_enabled"):
		level.set_chat_enabled(true)

func _show_keybindings() -> void:
	_settings_panel.visible = false
	var win := Window.new()
	win.title = "Keyboard / Mouse"
	win.size = Vector2i(820, 640)
	win.unresizable = true
	win.close_requested.connect(func(): win.queue_free(); _settings_panel.visible = true)
	win.window_input.connect(func(e):
		if e.is_action_pressed("ui_cancel"):
			win.queue_free(); _settings_panel.visible = true)
	var bindings := [
		["Movement", [
			["Move Forward", "move_forward"],
			["Move Backward", "move_backward"],
			["Strafe Left", "move_left"],
			["Strafe Right", "move_right"],
			["Jump", "jump"],
			["Crouch", "CROUCH"],
			["Sprint", "sprint"],
			["Lean Left", "lean_left"],
			["Lean Right", "lean_right"],
		]],
		["Weapons", [
			["Weapon Next", "weapon_next"],
			["Weapon Previous", "weapon_prev"],
		]],
		["Combat", [
			["Fire", "fire"],
			["Aim Down Sights", "aim"],
			["Reload", "reload"],
			["Knife / Melee", "melee"],
		]],
		["Interface", [
			["Pause / Menu", "exit"],
		]],
	]
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(hbox)
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 4)
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(left_vbox)
	hbox.add_child(right_vbox)
	var left_groups := ["Movement", "Weapons"]
	for group in bindings:
		var group_name : String = group[0]
		var actions : Array = group[1]
		var target_vbox := left_vbox if group_name in left_groups else right_vbox
		var section_label := Label.new()
		section_label.text = group_name.to_upper()
		section_label.add_theme_font_size_override("font_size", 11)
		section_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		target_vbox.add_child(section_label)
		var sep := HSeparator.new()
		target_vbox.add_child(sep)
		for action_pair in actions:
			var label_text : String = action_pair[0]
			var action_name : String = action_pair[1]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var lbl := Label.new()
			lbl.text = label_text
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 13)
			row.add_child(lbl)
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(120, 0)
			var events := InputMap.action_get_events(action_name)
			var saved : String = PresenceManager.load_setting("keybind_" + action_name, "")
			if saved != "":
				btn.text = saved
			elif events.size() > 0:
				btn.text = events[0].as_text().split(" (")[0]
			else:
				btn.text = "Unbound"
			var aname := action_name
			var capturing_btn := btn
			btn.pressed.connect(func():
				capturing_btn.text = "Press a key..."
				var capture := func(e: InputEvent):
					if e is InputEventKey and e.pressed:
						if e.keycode == KEY_ESCAPE:
							var orig_events := InputMap.action_get_events(aname)
							capturing_btn.text = orig_events[0].as_text().split(" (")[0] if orig_events.size() > 0 else "Unbound"
						else:
							InputMap.action_erase_events(aname)
							InputMap.action_add_event(aname, e)
							capturing_btn.text = e.as_text().split(" (")[0]
							PresenceManager.save_setting("keybind_" + aname, capturing_btn.text)
						win.set_input_as_handled()
				win.window_input.connect(capture, CONNECT_ONE_SHOT)
			)
			row.add_child(btn)
			target_vbox.add_child(row)
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 8)
		target_vbox.add_child(spacer)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	var reset_btn := Button.new()
	reset_btn.text = "Reset to defaults"
	reset_btn.pressed.connect(func():
		win.queue_free()
		_settings_panel.visible = true
	)
	bottom.add_child(reset_btn)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer2)
	var done_btn := Button.new()
	done_btn.text = "Done"
	done_btn.pressed.connect(func(): win.queue_free(); _settings_panel.visible = true)
	bottom.add_child(done_btn)
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(scroll)
	main_vbox.add_child(bottom)
	win.add_child(main_vbox)
	add_child(win)
	win.popup_centered()

func open_death_menu() -> void:
	_open_death_menu()

func _open_death_menu() -> void:
	_screen = Screen.DEATH
	_panel.visible = false
	_settings_panel.visible = false
	_death_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Disable chat while death menu is open
	var level := get_tree().get_root().get_node_or_null("Node3D")
	if level and level.has_method("set_chat_enabled"):
		level.set_chat_enabled(false)
	# Hide crosshair
	var wc := get_parent().get_node_or_null("Components/WeaponController")
	if wc and wc.get("_crosshair"): wc._crosshair.hide()
	_respawn_btn.focus_neighbor_top = _respawn_btn.get_path_to(_death_quit_btn)
	_respawn_btn.focus_neighbor_bottom = _respawn_btn.get_path_to(_death_menu_btn)
	_death_menu_btn.focus_neighbor_top = _death_menu_btn.get_path_to(_respawn_btn)
	_death_menu_btn.focus_neighbor_bottom = _death_menu_btn.get_path_to(_death_settings_btn)
	_death_settings_btn.focus_neighbor_top = _death_settings_btn.get_path_to(_death_menu_btn)
	_death_settings_btn.focus_neighbor_bottom = _death_settings_btn.get_path_to(_death_quit_btn)
	_death_quit_btn.focus_neighbor_top = _death_quit_btn.get_path_to(_death_settings_btn)
	_death_quit_btn.focus_neighbor_bottom = _death_quit_btn.get_path_to(_respawn_btn)
	_respawn_btn.grab_focus()

func _open_death_settings() -> void:
	_screen = Screen.DEATH_SETTINGS
	_death_panel.visible = false
	_settings_panel.visible = true
	_sens_slider.value = PresenceManager.load_setting("mouse_sensitivity", 1.0)
	_ads_sens_slider.value = PresenceManager.load_setting("ads_sensitivity", 1.0)
	if _master_vol_slider:
		_master_vol_slider.value = PresenceManager.load_setting("master_volume", 1.0)
	_back_btn.grab_focus()

func _respawn() -> void:
	_screen = Screen.NONE
	_death_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Re-enable chat on respawn
	var level := get_tree().get_root().get_node_or_null("Node3D")
	if level and level.has_method("set_chat_enabled"):
		level.set_chat_enabled(true)
	# Show crosshair
	var wc := get_parent().get_node_or_null("Components/WeaponController")
	if wc and wc.get("_crosshair"): wc._crosshair.show()
	var player := get_parent()
	var health := player.get_node_or_null("Health")
	if health:
		health.current_health = health.max_health
		health.emit_signal("health_changed", health.current_health, health.max_health)
	player.set_physics_process(true)
	var cam := player.get_node_or_null("CameraController")
	if cam:
		cam.rotation_degrees.z = 0
		cam.position.y = 1.5
	# Request new random spawn from server
	if level and level.has_method("request_respawn"):
		level.request_respawn.rpc_id(1)

func _go_to_menu() -> void:
	SessionLogger.end_session("returned_to_menu")
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU)

func _exit_game() -> void:
	SessionLogger.end_session("game_exited")
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	get_tree().quit()
