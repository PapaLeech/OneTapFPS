extends CanvasLayer

var _ammo_label: Label
var _mags_label: Label

func _ready() -> void:
	# Container anchored bottom-right
	var container := VBoxContainer.new()
	container.anchor_left = 1.0
	container.anchor_top = 1.0
	container.anchor_right = 1.0
	container.anchor_bottom = 1.0
	container.offset_left = -160.0
	container.offset_top = -70.0
	container.offset_right = -20.0
	container.offset_bottom = -20.0
	container.alignment = BoxContainer.ALIGNMENT_END
	add_child(container)

	# Ammo label e.g. "30 / 30"
	_ammo_label = Label.new()
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.add_theme_font_size_override("font_size", 22)
	_ammo_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	container.add_child(_ammo_label)

	# Mags label e.g. "| | |  3 mags"
	_mags_label = Label.new()
	_mags_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mags_label.add_theme_font_size_override("font_size", 13)
	_mags_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.8))
	container.add_child(_mags_label)

	# Connect to weapon controller
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var wc := player.get_node_or_null("Components/WeaponController")
		if wc and wc.has_signal("ammo_changed"):
			wc.ammo_changed.connect(_on_ammo_changed)

func _on_ammo_changed(current: int, max_ammo: int, mags: int) -> void:
	if _ammo_label:
		_ammo_label.text = "%d / %d" % [current, max_ammo]
	if _mags_label:
		var bars := ""
		for i in range(mags):
			bars += "| "
		var mag_word := "mag" if mags == 1 else "mags"
		_mags_label.text = "%s %d %s" % [bars.strip_edges(), mags, mag_word]
