extends CanvasLayer

var crosshair: Control
var _draw_node: Control

func _ready() -> void:
	crosshair = $Crosshair
	if crosshair:
		crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_draw_node = crosshair.get_node_or_null("CrosshairDraw")

func show_crosshair() -> void:
	if crosshair:
		crosshair.visible = true

func hide_crosshair() -> void:
	if crosshair:
		crosshair.visible = false

## Feed current AK47 spread each frame so lines open as you hold fire
func set_spread(spread: float) -> void:
	if _draw_node and _draw_node.has_method("set_spread"):
		_draw_node.set_spread(spread)

## Flash red + open briefly when a bullet registers a hit on an enemy
func hit_flash() -> void:
	if _draw_node and _draw_node.has_method("hit_flash"):
		_draw_node.hit_flash()
