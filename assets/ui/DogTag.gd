extends Control

const TAG_W := 106.05
const TAG_H := 140.895
const BEAD_R := 5.3025
const BEAD_COUNT := 5
const BEAD_GAP := 12.12

@onready var name_label: Label = $NameLabel

func _ready() -> void:
	custom_minimum_size = Vector2(TAG_W, TAG_H + BEAD_COUNT * BEAD_GAP)
	pivot_offset = Vector2(TAG_W / 2.0, BEAD_R)
	queue_redraw()

func set_player_name(player_name: String) -> void:
	name_label.text = player_name

func _draw() -> void:
	var bead_offset := Vector2(TAG_W / 2.0, BEAD_R)

	# Draw chain beads
	for i in range(BEAD_COUNT):
		var by := bead_offset.y + i * BEAD_GAP
		draw_circle(Vector2(bead_offset.x + 0.5, by + 0.5), BEAD_R, Color(0.1, 0.1, 0.1, 0.5))
		draw_circle(Vector2(bead_offset.x, by), BEAD_R, Color(0.75, 0.75, 0.78, 1.0))
		draw_circle(Vector2(bead_offset.x - 1.0, by - 1.0), BEAD_R * 0.5, Color(0.95, 0.95, 0.97, 0.6))

	var tag_y := float(BEAD_COUNT) * BEAD_GAP
	var tag_rect := Rect2(0, tag_y, TAG_W, TAG_H)
	var radius := 10.0

	# Drop shadow
	draw_rect(Rect2(tag_rect.position + Vector2(2, 2), tag_rect.size), Color(0, 0, 0, 0.4), true, -1)

	# Tag border
	_draw_rounded_rect(tag_rect.grow(1), radius + 1, Color(0.25, 0.25, 0.27, 1.0))

	# Tag base
	_draw_rounded_rect(tag_rect, radius, Color(0.55, 0.57, 0.60, 1.0))

	# Tag face
	_draw_rounded_rect(Rect2(tag_rect.position + Vector2(2, 2), tag_rect.size - Vector2(4, 4)), radius - 1, Color(0.78, 0.80, 0.82, 1.0))

	# Specular highlight
	_draw_rounded_rect(Rect2(tag_rect.position + Vector2(4, 4), Vector2(TAG_W * 0.5, TAG_H * 0.4)), radius - 2, Color(0.95, 0.95, 0.97, 0.25))

	# Scratches
	var scratch_color := Color(0.4, 0.4, 0.42, 0.35)
	draw_line(Vector2(12, tag_y + 18), Vector2(38, tag_y + 52), scratch_color, 0.8)
	draw_line(Vector2(20, tag_y + 12), Vector2(56, tag_y + 62), scratch_color, 0.6)
	draw_line(Vector2(8,  tag_y + 35), Vector2(28, tag_y + 72), scratch_color, 0.5)
	draw_line(Vector2(30, tag_y + 10), Vector2(60, tag_y + 45), scratch_color, 0.4)

	# Ring hole
	var ring_pos := Vector2(TAG_W / 2.0, tag_y + 12)
	draw_circle(ring_pos, 6.0, Color(0.2, 0.2, 0.22, 1.0))
	draw_circle(ring_pos, 4.5, Color(0.45, 0.45, 0.48, 1.0))
	draw_arc(ring_pos, 5.0, 0, TAU, 32, Color(0.85, 0.85, 0.88, 0.8), 1.2)

func _draw_rounded_rect(rect: Rect2, radius: float, color: Color) -> void:
	draw_rect(Rect2(rect.position + Vector2(radius, 0), Vector2(rect.size.x - radius * 2, rect.size.y)), color, true)
	draw_rect(Rect2(rect.position + Vector2(0, radius), Vector2(rect.size.x, rect.size.y - radius * 2)), color, true)
	draw_circle(rect.position + Vector2(radius, radius), radius, color)
	draw_circle(rect.position + Vector2(rect.size.x - radius, radius), radius, color)
	draw_circle(rect.position + Vector2(radius, rect.size.y - radius), radius, color)
	draw_circle(rect.position + Vector2(rect.size.x - radius, rect.size.y - radius), radius, color)

func swing_in() -> void:
	rotation_degrees = -12.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation_degrees", 0.0, 1.2)

func swing_out(on_done: Callable) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation_degrees", -12.0, 0.3)
	tween.tween_property(self, "rotation_degrees", 0.0, 0.3)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(on_done)
