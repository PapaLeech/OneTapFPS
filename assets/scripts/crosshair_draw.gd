extends Control

const CROSSHAIR_SIZE := 10.0
const CROSSHAIR_GAP := 5.0
const CROSSHAIR_THICKNESS := 2.0
const DOT_SIZE := 2.0
const COLOR := Color(0, 1, 0, 0.9)

func _draw() -> void:
	var center := size / 2.0

	# Centre dot
	draw_circle(center, DOT_SIZE, COLOR)

	# Left line
	draw_rect(Rect2(center.x - CROSSHAIR_GAP - CROSSHAIR_SIZE, center.y - CROSSHAIR_THICKNESS / 2.0, CROSSHAIR_SIZE, CROSSHAIR_THICKNESS), COLOR)
	# Right line
	draw_rect(Rect2(center.x + CROSSHAIR_GAP, center.y - CROSSHAIR_THICKNESS / 2.0, CROSSHAIR_SIZE, CROSSHAIR_THICKNESS), COLOR)
	# Top line
	draw_rect(Rect2(center.x - CROSSHAIR_THICKNESS / 2.0, center.y - CROSSHAIR_GAP - CROSSHAIR_SIZE, CROSSHAIR_THICKNESS, CROSSHAIR_SIZE), COLOR)
	# Bottom line
	draw_rect(Rect2(center.x - CROSSHAIR_THICKNESS / 2.0, center.y + CROSSHAIR_GAP, CROSSHAIR_THICKNESS, CROSSHAIR_SIZE), COLOR)
