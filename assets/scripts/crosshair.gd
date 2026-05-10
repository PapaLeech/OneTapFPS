extends CanvasLayer

var crosshair: Control

func _ready() -> void:
	crosshair = $Crosshair
	if crosshair:
		crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func show_crosshair() -> void:
	if crosshair:
		crosshair.visible = true

func hide_crosshair() -> void:
	if crosshair:
		crosshair.visible = false
