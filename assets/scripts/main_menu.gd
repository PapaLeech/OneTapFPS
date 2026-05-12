extends Control

const GAME_SCENE := "res://levels/level_001.tscn"
enum Mode { NONE, DEATHMATCH, SEARCH_AND_DESTROY }

@onready var _dm_btn       : PanelContainer = $CaseInner/Middle/DeathmatchBtn
@onready var _sd_btn       : PanelContainer = $CaseInner/Middle/SearchDestroyBtn
@onready var _dm_desc      : Label = $CaseInner/Middle/DeathmatchBtn/VBox/Body/Desc
@onready var _sd_desc      : Label = $CaseInner/Middle/SearchDestroyBtn/VBox/Body/Desc
@onready var _dm_countdown : HBoxContainer = $CaseInner/Middle/DeathmatchBtn/VBox/Body/Countdown
@onready var _sd_countdown : HBoxContainer = $CaseInner/Middle/SearchDestroyBtn/VBox/Body/Countdown
@onready var _dm_num       : Label = $CaseInner/Middle/DeathmatchBtn/VBox/Body/Countdown/Num
@onready var _sd_num       : Label = $CaseInner/Middle/SearchDestroyBtn/VBox/Body/Countdown/Num
@onready var _dm_cancel    : Button = $CaseInner/Middle/DeathmatchBtn/VBox/Body/Countdown/CancelBtn
@onready var _sd_cancel    : Button = $CaseInner/Middle/SearchDestroyBtn/VBox/Body/Countdown/CancelBtn
@onready var _play_btn     : Button = $CaseInner/Middle/PlayBtn
@onready var _bg_texture   : TextureRect = $Background

var _active_mode : Mode = Mode.NONE
var _timer       : SceneTreeTimer = null
var _count       : int = 3

func _ready() -> void:
	_dm_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_sd_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_dm_btn.gui_input.connect(func(e): _on_mode_clicked(e, Mode.DEATHMATCH))
	_sd_btn.gui_input.connect(func(e): _on_mode_clicked(e, Mode.SEARCH_AND_DESTROY))
	_dm_cancel.pressed.connect(_cancel_countdown)
	_sd_cancel.pressed.connect(_cancel_countdown)
	_play_btn.pressed.connect(func(): get_tree().change_scene_to_file(GAME_SCENE))
	_dm_countdown.visible = false
	_sd_countdown.visible = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _active_mode != Mode.NONE:
			_cancel_countdown()
		else:
			_show_quit_dialog()

func _show_quit_dialog() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Leave Game"
	dialog.dialog_text = "Are you sure you want to quit?"
	dialog.ok_button_text = "Cancel"
	dialog.cancel_button_text = "OK"
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): get_tree().quit())
	dialog.close_requested.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
	await get_tree().process_frame
	await get_tree().process_frame
	dialog.get_cancel_button().grab_focus()

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
