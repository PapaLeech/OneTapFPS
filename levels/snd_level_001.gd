extends "res://levels/level_001.gd"

# After SND builds its HUD, the original InputLine is replaced.
# Rebind _input_line and reconnect gui_input so Enter works again.
func _ready() -> void:
	await super._ready()
	await get_tree().process_frame  # let SearchAndDestroy._build_hud() finish

	var new_input := $HUDLayer/ChatTerminalPanel/VBox/InputLine
	if new_input:
		_input_line = new_input
		if not _input_line.gui_input.is_connected(_on_chat_line_gui_input):
			_input_line.gui_input.connect(_on_chat_line_gui_input)

# SND-specific override: make sure chat keeps focus after HUD shenanigans.
func _switch_chat_tab(focus) -> void:
	super._switch_chat_tab(focus)
	if focus != ChatFocus.NONE:
		await get_tree().process_frame
		if _chat_focus != ChatFocus.NONE:
			_input_line.grab_focus()
