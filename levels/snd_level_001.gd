extends "res://levels/level_001.gd"

# SND-specific override: re-grab chat input focus after _switch_chat_tab
# because SearchAndDestroy._build_hud() steals GUI focus via async await.
func _switch_chat_tab(focus) -> void:
	super._switch_chat_tab(focus)
	if focus != ChatFocus.NONE:
		_input_line.call_deferred("grab_focus")
