extends CanvasLayer

var _label: Label

func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1, 1, 0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)
	var enabled: bool = PresenceManager.load_setting("fps_counter_enabled", false)
	var corner: int = PresenceManager.load_setting("fps_counter_corner", 0)
	_label.visible = enabled
	set_corner(corner)

func _process(_delta: float) -> void:
	if _label.visible:
		_label.text = "FPS: %d" % Engine.get_frames_per_second()

func set_corner(idx: int) -> void:
	var positions := [
		Vector2(8, 8),
		Vector2(-128, 8),
		Vector2(8, -24),
		Vector2(-128, -24)
	]
	var anchors := [
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(0, 1),
		Vector2(1, 1)
	]
	idx = clamp(idx, 0, 3)
	var a := anchors[idx]
	var p := positions[idx]
	_label.anchor_left = a.x
	_label.anchor_top = a.y
	_label.anchor_right = a.x
	_label.anchor_bottom = a.y
	_label.offset_left = p.x
	_label.offset_top = p.y
	_label.offset_right = p.x + 120
	_label.offset_bottom = p.y + 24

func set_visible(on: bool) -> void:
	_label.visible = on
