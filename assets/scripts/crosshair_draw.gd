extends Control

const CROSSHAIR_SIZE := 10.0
const BASE_GAP := 5.0
const CROSSHAIR_THICKNESS := 2.0
const DOT_SIZE := 2.0
const BASE_COLOR := Color(0, 1, 0, 0.9)
const HIT_COLOR := Color(1, 0, 0, 1.0)  # red flash on enemy hit

# Current dynamic gap — driven externally by weapon spread or hit flash
var _gap: float = BASE_GAP
var _color: Color = BASE_COLOR
var _tween: Tween

func _draw() -> void:
	var center := size / 2.0
	# Centre dot
	draw_circle(center, DOT_SIZE, _color)
	# Left
	draw_rect(Rect2(center.x - _gap - CROSSHAIR_SIZE, center.y - CROSSHAIR_THICKNESS / 2.0, CROSSHAIR_SIZE, CROSSHAIR_THICKNESS), _color)
	# Right
	draw_rect(Rect2(center.x + _gap, center.y - CROSSHAIR_THICKNESS / 2.0, CROSSHAIR_SIZE, CROSSHAIR_THICKNESS), _color)
	# Top
	draw_rect(Rect2(center.x - CROSSHAIR_THICKNESS / 2.0, center.y - _gap - CROSSHAIR_SIZE, CROSSHAIR_THICKNESS, CROSSHAIR_SIZE), _color)
	# Bottom
	draw_rect(Rect2(center.x - CROSSHAIR_THICKNESS / 2.0, center.y + _gap, CROSSHAIR_THICKNESS, CROSSHAIR_SIZE), _color)

## Call this every frame with the current weapon spread (0.0 = tight, 0.06 = max)
func set_spread(spread: float) -> void:
	_gap = BASE_GAP + spread * 300.0
	queue_redraw()

## Call this when a bullet hits an enemy — flashes red and snaps open briefly
func hit_flash() -> void:
	if _tween:
		_tween.kill()
	_color = HIT_COLOR
	_gap = BASE_GAP + 8.0
	queue_redraw()
	_tween = create_tween()
	_tween.tween_interval(0.12)
	_tween.tween_callback(func():
		_color = BASE_COLOR
		_gap = BASE_GAP
		queue_redraw()
	)
