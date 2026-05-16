extends Control

const GAME_SCENE := "res://levels/level_001.tscn"
const DOG_TAG_SCENE := preload("res://assets/ui/DogTag.tscn")
const BULLET_SLOT_SCENE := preload("res://ui/BulletSlot.tscn")
const MAX_LOBBY := 5
enum Mode { NONE, DEATHMATCH, SEARCH_AND_DESTROY }
enum ChatFocus { NONE, CHAT, TERMINAL }

var _lobby_players    : Array[String] = []
var _dog_tag_nodes    : Array = []
var _active_mode      : Mode = Mode.NONE
var _timer            : SceneTreeTimer = null
var _count            : int = 3
var _quit_dialog_open : bool = false
var _chat_focus       : ChatFocus = ChatFocus.NONE
var _invite_sender    : String = ""
var _friends_header   : Label = null

# Invite notification nodes (built in code, hidden until an invite arrives)
var _invite_panel   : PanelContainer = null
var _invite_label   : Label = null
var _invite_accept  : Button = null
var _invite_decline : Button = null

@onready var _dm_btn             : PanelContainer = $CaseInner/Middle/DeathmatchBtn
@onready var _sd_btn             : PanelContainer = $CaseInner/Middle/SearchDestroyBtn
@onready var _dm_desc            : Label          = $CaseInner/Middle/DeathmatchBtn/VBox/Body/Desc
@onready var _sd_desc            : Label          = $CaseInner/Middle/SearchDestroyBtn/VBox/Body/Desc
@onready var _dm_countdown       : HBoxContainer  = $CaseInner/Middle/DeathmatchBtn/VBox/Body/Countdown
@onready var _sd_countdown       : HBoxContainer  = $CaseInner/Middle/SearchDestroyBtn/VBox/Body/Countdown
@onready var _dm_num             : Label          = $CaseInner/Middle/DeathmatchBtn/VBox/Body/Countdown/Num
@onready var _sd_num             : Label          = $CaseInner/Middle/SearchDestroyBtn/VBox/Body/Countdown/Num
@onready var _dm_cancel          : Button         = $CaseInner/Middle/DeathmatchBtn/VBox/Body/Countdown/CancelBtn
@onready var _sd_cancel          : Button         = $CaseInner/Middle/SearchDestroyBtn/VBox/Body/Countdown/CancelBtn
@onready var _play_btn           : Button         = $CaseInner/Middle/PlayBtn
@onready var _bg_texture         : TextureRect    = $Background
@onready var _settings_btn       : Button         = $SettingsBtn
@onready var _exit_btn           : Button         = $ExitBtn
@onready var _dog_tags_container : Control        = $CaseInner/Right/LobbyPanel/VBox/DogTags
@onready var _lobby_join_sound   : AudioStreamPlayer = $LobbyJoinSound2
@onready var _bullet_list        : VBoxContainer  = $CaseInner/Right/FriendsPanel/VBox/Scroll/BulletList
@onready var _join_btn           : Button         = $CaseInner/Right/LobbyPanel/VBox/BtnRow/JoinBtn
@onready var _leave_btn          : Button         = $CaseInner/Right/LobbyPanel/VBox/BtnRow/LeaveBtn
@onready var _chat_tab_btn       : Button         = $CaseInner/Left/ChatTerminalPanel/VBox/TabBar/ChatTab
@onready var _term_tab_btn       : Button         = $CaseInner/Left/ChatTerminalPanel/VBox/TabBar/TerminalTab
@onready var _chat_output        : RichTextLabel  = $CaseInner/Left/ChatTerminalPanel/VBox/ChatOutput
@onready var _term_output        : RichTextLabel  = $CaseInner/Left/ChatTerminalPanel/VBox/TerminalOutput
@onready var _input_line         : LineEdit       = $CaseInner/Left/ChatTerminalPanel/VBox/InputLine

# ─── Ready ───────────────────────────────────────────────────────────────────

func _ready() -> void:
	get_window().mode = Window.MODE_FULLSCREEN
	_bg_texture.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_style_mission_panel()
	_build_invite_panel()
	_dm_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_sd_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_dm_btn.gui_input.connect(func(e): _on_mode_clicked(e, Mode.DEATHMATCH))
	_sd_btn.gui_input.connect(func(e): _on_mode_clicked(e, Mode.SEARCH_AND_DESTROY))
	_dm_cancel.pressed.connect(_cancel_countdown)
	_sd_cancel.pressed.connect(_cancel_countdown)
	_play_btn.pressed.connect(func(): get_tree().change_scene_to_file(GAME_SCENE))
	_settings_btn.pressed.connect(_show_settings)
	_exit_btn.pressed.connect(func(): get_tree().quit())
	_dm_countdown.visible = false
	_sd_countdown.visible = false
	_style_lobby_buttons()
	_join_btn.pressed.connect(_on_join_pressed)
	_leave_btn.pressed.connect(_on_leave_pressed)
	_clear_placeholder_tags()
	_setup_chat_terminal()
	_setup_add_friend_button()
	if not PresenceManager.has_username():
		_show_username_prompt()
	else:
		_go_online_and_fetch_friends()


# ─── Styling ─────────────────────────────────────────────────────────────────

func _style_mission_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.97)
	style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.8)
	style.shadow_size = 8
	for path in [
		"CaseInner/Left/MissionPanel",
		"CaseInner/Left/ChatTerminalPanel",
		"CaseInner/Right/LobbyPanel",
		"CaseInner/Right/FriendsPanel",
		"CaseInner/Middle/DeathmatchBtn",
		"CaseInner/Middle/SearchDestroyBtn",
	]:
		var node := get_node_or_null(path)
		if node:
			node.add_theme_stylebox_override("panel", style.duplicate())
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.12, 0.12, 0.12, 0.97)
	btn_style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)
	btn_style.shadow_color = Color(0, 0, 0, 0.8)
	btn_style.shadow_size = 8
	var btn_hover := btn_style.duplicate()
	btn_hover.bg_color = Color(0.2, 0.2, 0.2, 0.97)
	for path in ["SettingsBtn", "ExitBtn", "CaseInner/Middle/PlayBtn"]:
		var btn := get_node_or_null(path)
		if btn:
			btn.add_theme_stylebox_override("normal", btn_style.duplicate())
			btn.add_theme_stylebox_override("hover", btn_hover.duplicate())
			btn.add_theme_stylebox_override("pressed", btn_hover.duplicate())
			btn.add_theme_color_override("font_color", Color.WHITE)

# ─── Input ───────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	# Alt+Enter: toggle fullscreen
	if event.keycode == KEY_ENTER and event.alt_pressed:
		var win := get_window()
		win.mode = Window.MODE_FULLSCREEN if win.mode != Window.MODE_FULLSCREEN else Window.MODE_WINDOWED
		get_viewport().set_input_as_handled()
		return
	# I: test invite (TEMP)
	if event.keycode == KEY_I:
		receive_invite("Player 2")
		return
	# Escape: release chat/console focus first; otherwise show quit dialog
	if event.keycode == KEY_ESCAPE:
		if _chat_focus != ChatFocus.NONE:
			_release_chat_focus()
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		if _quit_dialog_open:
			return
		if _active_mode != Mode.NONE:
			_cancel_countdown()
		else:
			_show_quit_dialog()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	# Backtick: toggle between console and chat, or focus console if unfocused
	if event.keycode == KEY_QUOTELEFT:
		if _chat_focus == ChatFocus.TERMINAL:
			_switch_to_tab(ChatFocus.CHAT)
		else:
			_switch_to_tab(ChatFocus.TERMINAL)
		get_viewport().set_input_as_handled()
		return
	# Enter: focus chat (only when nothing is focused)
	if event.keycode == KEY_ENTER and not event.alt_pressed:
		if _chat_focus == ChatFocus.NONE:
			_switch_to_tab(ChatFocus.CHAT)
			get_viewport().set_input_as_handled()

# ─── Invite Notification ─────────────────────────────────────────────────────

func _build_invite_panel() -> void:
	var settings_pos  : Vector2 = _settings_btn.position
	var settings_size : Vector2 = _settings_btn.size
	_invite_panel = PanelContainer.new()
	_invite_panel.position = Vector2(settings_pos.x, settings_pos.y - 110)
	_invite_panel.size     = Vector2(settings_size.x, 100)
	_invite_panel.visible  = false
	add_child(_invite_panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	_invite_panel.add_child(vbox)
	_invite_label = Label.new()
	_invite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_invite_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_invite_label.text = "INVITED BY PLAYER"
	vbox.add_child(_invite_label)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	vbox.add_child(btn_row)
	_invite_accept = Button.new()
	_invite_accept.text = "Accept"
	_invite_accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_accept.pressed.connect(_on_invite_accepted)
	btn_row.add_child(_invite_accept)
	_invite_decline = Button.new()
	_invite_decline.text = "Decline"
	_invite_decline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_decline.pressed.connect(_on_invite_declined)
	btn_row.add_child(_invite_decline)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.12, 0.12, 0.12, 0.97)
	ps.border_color = Color(0.4, 0.4, 0.4, 1.0)
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(4)
	ps.shadow_color = Color(0, 0, 0, 0.8)
	ps.shadow_size = 8
	_invite_panel.add_theme_stylebox_override("panel", ps)
	var bn := StyleBoxFlat.new()
	bn.bg_color = Color(0.12, 0.12, 0.12, 0.97)
	bn.border_color = Color(0.4, 0.4, 0.4, 1.0)
	bn.set_border_width_all(1)
	bn.set_corner_radius_all(4)
	var bh := bn.duplicate()
	bh.bg_color = Color(0.2, 0.2, 0.2, 0.97)
	for btn in [_invite_accept, _invite_decline]:
		btn.add_theme_stylebox_override("normal", bn.duplicate())
		btn.add_theme_stylebox_override("hover", bh.duplicate())
		btn.add_theme_stylebox_override("pressed", bh.duplicate())
		btn.add_theme_color_override("font_color", Color.WHITE)

func receive_invite(sender_name: String) -> void:
	_invite_sender = sender_name
	_invite_label.text = "INVITED BY  %s" % sender_name.to_upper()
	_invite_panel.visible = true

func _on_invite_accepted() -> void:
	_invite_panel.visible = false
	_add_player_tag_at(_invite_sender, 0, true)
	_add_player_tag("Player 1", true)
	_invite_sender = ""

func _on_invite_declined() -> void:
	_invite_panel.visible = false
	_invite_sender = ""

# ─── Settings ────────────────────────────────────────────────────────────────

func _show_settings() -> void:
	var dialog := Window.new()
	dialog.title = "Settings"
	dialog.size = Vector2i(400, 380)
	dialog.unresizable = true
	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.window_input.connect(func(e):
		if e.is_action_pressed("ui_cancel"):
			dialog.queue_free())
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 16)
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
	var keys_label := Label.new()
	keys_label.text = "Keybindings"
	vbox.add_child(keys_label)
	var keys_btn := Button.new()
	keys_btn.text = "Coming Soon"
	keys_btn.disabled = true
	vbox.add_child(keys_btn)
	var username_btn := Button.new()
	username_btn.text = "Change Username (current: %s)" % PresenceManager.username
	username_btn.pressed.connect(func():
		dialog.queue_free()
		_show_username_prompt()
	)
	vbox.add_child(username_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): dialog.queue_free())
	vbox.add_child(close_btn)
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()

func _show_quit_dialog() -> void:
	_quit_dialog_open = true
	var dialog := ConfirmationDialog.new()
	dialog.title = "Leave Game"
	dialog.dialog_text = "Are you sure you want to quit?"
	dialog.ok_button_text = "Cancel"
	dialog.cancel_button_text = "OK"
	dialog.confirmed.connect(func(): _quit_dialog_open = false; dialog.queue_free())
	dialog.canceled.connect(func(): _quit_dialog_open = false; dialog.queue_free())
	dialog.close_requested.connect(func(): _quit_dialog_open = false; dialog.queue_free())
	dialog.get_cancel_button().pressed.connect(func(): get_tree().quit())
	add_child(dialog)
	dialog.popup_centered()
	await get_tree().process_frame
	await get_tree().process_frame
	dialog.get_cancel_button().grab_focus()

# ─── Game Mode / Countdown ───────────────────────────────────────────────────

func _on_mode_clicked(event: InputEvent, mode: Mode) -> void:
	if not event is InputEventMouseButton: return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	if _active_mode != Mode.NONE: return
	_start_countdown(mode)

func _start_countdown(mode: Mode) -> void:
	_active_mode = mode
	_count = 3
	_update_display()
	if mode == Mode.DEATHMATCH:
		_dm_desc.visible = false
		_dm_countdown.visible = true
	else:
		_sd_desc.visible = false
		_sd_countdown.visible = true
	_tick()

func _tick() -> void:
	_timer = get_tree().create_timer(1.0)
	_timer.timeout.connect(func():
		_count -= 1
		_update_display()
		if _count <= 0: _load_mode()
		else: _tick()
	)

func _update_display() -> void:
	_dm_num.text = str(_count)
	_sd_num.text = str(_count)

func _cancel_countdown() -> void:
	if _timer:
		for c in _timer.timeout.get_connections():
			_timer.timeout.disconnect(c.callable)
	_reset()

func _reset() -> void:
	_active_mode = Mode.NONE
	_count = 3
	_dm_desc.visible = true
	_sd_desc.visible = true
	_dm_countdown.visible = false
	_sd_countdown.visible = false

func _load_mode() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

# ─── Lobby / Dog Tags ────────────────────────────────────────────────────────

func _style_lobby_buttons() -> void:
	var join_style := StyleBoxFlat.new()
	join_style.bg_color = Color(0.1, 0.45, 0.1, 1.0)
	join_style.border_color = Color(0.15, 0.6, 0.15, 1.0)
	join_style.set_border_width_all(1)
	join_style.set_corner_radius_all(4)
	var join_hover := join_style.duplicate()
	join_hover.bg_color = Color(0.15, 0.55, 0.15, 1.0)
	_join_btn.add_theme_stylebox_override("normal", join_style)
	_join_btn.add_theme_stylebox_override("hover", join_hover)
	_join_btn.add_theme_stylebox_override("pressed", join_hover)
	_join_btn.add_theme_color_override("font_color", Color.WHITE)
	var leave_style := StyleBoxFlat.new()
	leave_style.bg_color = Color(0.45, 0.1, 0.1, 1.0)
	leave_style.border_color = Color(0.6, 0.15, 0.15, 1.0)
	leave_style.set_border_width_all(1)
	leave_style.set_corner_radius_all(4)
	var leave_hover := leave_style.duplicate()
	leave_hover.bg_color = Color(0.55, 0.15, 0.15, 1.0)
	_leave_btn.add_theme_stylebox_override("normal", leave_style)
	_leave_btn.add_theme_stylebox_override("hover", leave_hover)
	_leave_btn.add_theme_stylebox_override("pressed", leave_hover)
	_leave_btn.add_theme_color_override("font_color", Color.WHITE)

func _clear_placeholder_tags() -> void:
	for child in _dog_tags_container.get_children():
		child.queue_free()
	_lobby_players.clear()
	_dog_tag_nodes.clear()

func populate_friends(friends: Array) -> void:
	for child in _bullet_list.get_children():
		child.queue_free()
	for f in friends:
		if f.get("name", "") == PresenceManager.username:
			continue
		var slot := BULLET_SLOT_SCENE.instantiate()
		_bullet_list.add_child(slot)
		slot.friend_name = f.get("name", "Player")
		slot.is_online   = f.get("online", false)
		if f.get("online", false):
			slot.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
					_show_friend_context_menu(slot.friend_name)
			)
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
			slot.tooltip_text = "Right-click to invite"

func _populate_requests(requests: Array) -> void:
	if _friends_header == null:
		return
	if requests.is_empty():
		_friends_header.text = "Friends"
		return
	_friends_header.text = "Friends  (%d pending)" % requests.size()
	for req in requests:
		var hbox := HBoxContainer.new()
		var label := Label.new()
		label.text = req
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		hbox.add_child(label)
		var accept_btn := Button.new()
		accept_btn.text = "Accept"
		accept_btn.pressed.connect(func():
			PresenceManager.accept_friend_request(req, func(): _refresh_friends())
			hbox.queue_free()
		)
		hbox.add_child(accept_btn)
		var decline_btn := Button.new()
		decline_btn.text = "Decline"
		decline_btn.pressed.connect(func():
			PresenceManager.decline_friend_request(req, func(): _refresh_friends())
			hbox.queue_free()
		)
		hbox.add_child(decline_btn)
		_bullet_list.add_child(hbox)

func _show_friend_context_menu(friend_name: String) -> void:
	var menu := PopupMenu.new()
	menu.add_item("Invite to lobby", 0)
	menu.id_pressed.connect(func(id):
		if id == 0:
			receive_invite(friend_name)
		menu.queue_free()
	)
	add_child(menu)
	menu.popup(Rect2i(get_viewport().get_mouse_position(), Vector2i(160, 0)))

func _show_add_friend_popup() -> void:
	var dialog := Window.new()
	dialog.title = "Add Friend"
	dialog.size = Vector2i(360, 130)
	dialog.unresizable = true
	dialog.close_requested.connect(func(): dialog.queue_free())
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = "Enter their username:"
	vbox.add_child(label)
	var input := LineEdit.new()
	input.placeholder_text = "Username"
	vbox.add_child(input)
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 12)
	vbox.add_child(status)
	var send = func():
		var val := input.text.strip_edges().to_lower()
		if val == "":
			return
		if val == PresenceManager.username:
			status.text = "That's you!"
			return
		status.text = "Sending..."
		PresenceManager.send_friend_request(val, func(code, data):
			if code == 200:
				status.text = "Request sent!"
			else:
				var msg: String = data.get("detail", "Failed.") if data else "Failed."
				status.text = msg
		)
	var btn := Button.new()
	btn.text = "Send Request"
	btn.pressed.connect(send)
	input.text_submitted.connect(func(_t): send.call())
	vbox.add_child(btn)
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	input.call_deferred("grab_focus")
	var close = func(): dialog.queue_free()
	input.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			close.call()
	)

func _setup_add_friend_button() -> void:
	_friends_header = $CaseInner/Right/FriendsPanel/VBox/Header
	var hbox := HBoxContainer.new()
	var parent := _friends_header.get_parent()
	var idx := _friends_header.get_index()
	parent.remove_child(_friends_header)
	hbox.add_child(_friends_header)
	_friends_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var add_btn := Button.new()
	add_btn.text = "+ Add"
	add_btn.pressed.connect(_show_add_friend_popup)
	hbox.add_child(add_btn)
	parent.add_child(hbox)
	parent.move_child(hbox, idx)

func _on_join_pressed() -> void:
	if _lobby_players.size() >= MAX_LOBBY:
		return
	var player_name := "Player %d" % (_lobby_players.size() + 1)
	_add_player_tag(player_name, true)

func _on_leave_pressed() -> void:
	if _lobby_players.is_empty():
		return
	_lobby_players.pop_back()
	var last_tag := _dog_tag_nodes.pop_back()
	if last_tag:
		_lobby_join_sound.play()
		last_tag.swing_out(func(): last_tag.queue_free())

func _add_player_tag(player_name: String, swing: bool = false) -> void:
	_lobby_players.append(player_name)
	var tag : Control = DOG_TAG_SCENE.instantiate()
	_dog_tags_container.add_child(tag)
	tag.set_player_name(player_name)
	_dog_tag_nodes.append(tag)
	_lobby_join_sound.play()
	if swing:
		tag.call_deferred("swing_in")

func _add_player_tag_at(player_name: String, index: int, swing: bool = false) -> void:
	_lobby_players.insert(index, player_name)
	var tag : Control = DOG_TAG_SCENE.instantiate()
	_dog_tags_container.add_child(tag)
	_dog_tags_container.move_child(tag, index)
	tag.set_player_name(player_name)
	_dog_tag_nodes.insert(index, tag)
	if swing:
		tag.call_deferred("swing_in")

func add_network_player(player_name: String) -> void:
	if _lobby_players.size() >= MAX_LOBBY:
		return
	_add_player_tag(player_name, true)

func remove_network_player(player_name: String) -> void:
	var idx := _lobby_players.find(player_name)
	if idx == -1:
		return
	_lobby_players.remove_at(idx)
	var tag : Control = _dog_tag_nodes[idx]
	_dog_tag_nodes.remove_at(idx)
	if tag:
		tag.queue_free()
func _show_username_prompt() -> void:
	var dialog := Window.new()
	dialog.title = "Welcome to OneTap"
	dialog.size = Vector2i(400, 180)
	dialog.unresizable = true
	dialog.close_requested.connect(func(): pass)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = "Enter your username:"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	var input := LineEdit.new()
	input.placeholder_text = "Username"
	input.max_length = 20
	vbox.add_child(input)
	var btn := Button.new()
	btn.text = "Confirm"
	btn.pressed.connect(func():
		var uname := input.text.strip_edges()
		if uname == "":
			return
		PresenceManager.save_username(uname)
		dialog.queue_free()
		_go_online_and_fetch_friends()
	)
	vbox.add_child(btn)
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()

func _go_online_and_fetch_friends() -> void:
	PresenceManager.go_online(PresenceManager.username)
	_refresh_friends()

func _refresh_friends() -> void:
	PresenceManager.get_friends_list(func(friends: Array):
		if friends.is_empty():
			populate_friends([])
			_refresh_pending_requests()
			return
		var names: Array = []
		for f in friends:
			names.append(f.get("username", ""))
		PresenceManager.get_friends_status(names, func(status: Dictionary):
			var friends_array: Array = []
			for f in friends:
				var uname: String = f.get("username", "")
				friends_array.append({"name": uname, "online": status.get(uname, false)})
			populate_friends(friends_array)
			_refresh_pending_requests()
		)
	)

func _refresh_pending_requests() -> void:
	PresenceManager.get_friend_requests(func(requests: Array):
		_populate_requests(requests)
	)

# ─── Chat / Console ──────────────────────────────────────────────────────────

func _setup_chat_terminal() -> void:
	_chat_tab_btn.pressed.connect(func(): _switch_to_tab(ChatFocus.CHAT))
	_term_tab_btn.pressed.connect(func(): _switch_to_tab(ChatFocus.TERMINAL))
	_input_line.text_submitted.connect(_on_input_submitted)
	_chat_output.visible = true
	_term_output.visible = false
	_release_chat_focus()

func _switch_to_tab(focus: ChatFocus) -> void:
	_chat_focus = focus
	_chat_output.visible = (focus == ChatFocus.CHAT)
	_term_output.visible = (focus == ChatFocus.TERMINAL)
	_input_line.editable = true
	_input_line.grab_focus()
	if focus == ChatFocus.CHAT:
		_input_line.placeholder_text = "Type message, Enter to send, Esc to exit..."
	else:
		_input_line.placeholder_text = "Type command, Enter to run, Esc to exit..."

func _release_chat_focus() -> void:
	_chat_focus = ChatFocus.NONE
	_input_line.editable = false
	_input_line.release_focus()
	_input_line.placeholder_text = "Enter = chat    ` = console"

func _on_input_submitted(text: String) -> void:
	if text.strip_edges() == "":
		_input_line.clear()
		return
	if _chat_focus == ChatFocus.CHAT:
		_chat_output.append_text("[color=white][b]You:[/b][/color] " + text + "\n")
	elif _chat_focus == ChatFocus.TERMINAL:
		_term_output.append_text("[color=lime]> " + text + "[/color]\n")
		_execute_terminal_command(text)
	_input_line.clear()
	_input_line.grab_focus()

func _execute_terminal_command(cmd: String) -> void:
	var parts := cmd.strip_edges().split(" ", false)
	if parts.is_empty():
		return
	match parts[0].to_lower():
		"help":
			_term_output.append_text("Commands: help, clear, version, sensitivity <value>\n")
		"clear":
			_term_output.clear()
		"version":
			_term_output.append_text("OneTap v0.1-dev\n")
		"sensitivity":
			if parts.size() > 1 and parts[1].is_valid_float():
				var val := float(parts[1])
				ProjectSettings.set_setting("game/mouse_sensitivity", val)
				_term_output.append_text("Sensitivity set to " + str(val) + "\n")
			else:
				_term_output.append_text("Usage: sensitivity <value>\n")
		_:
			_term_output.append_text("Unknown command: " + parts[0] + "\n")
