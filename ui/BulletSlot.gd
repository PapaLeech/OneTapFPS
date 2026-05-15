@tool
extends Control

@export var friend_name: String = "Player" : set = set_friend_name
@export var is_online: bool = false : set = set_is_online

const BULLET_HEIGHT: float = 38.0

func set_friend_name(v: String) -> void:
	friend_name = v
	queue_redraw()

func set_is_online(v: bool) -> void:
	is_online = v
	queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(260, BULLET_HEIGHT + 10)
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var cy: float = h * 0.5

	# ── colours ────────────────────────────────────────────────────────
	var brass_bright := Color(0.85, 0.68, 0.25) if is_online else Color(0.52, 0.42, 0.18)
	var brass_mid    := Color(0.72, 0.55, 0.18) if is_online else Color(0.40, 0.32, 0.13)
	var brass_dark   := Color(0.45, 0.33, 0.10) if is_online else Color(0.28, 0.21, 0.08)
	var lead_tip     := Color(0.62, 0.63, 0.65) if is_online else Color(0.38, 0.39, 0.40)
	var lead_high    := Color(0.80, 0.82, 0.84) if is_online else Color(0.50, 0.52, 0.53)
	var lead_shad    := Color(0.30, 0.31, 0.32) if is_online else Color(0.20, 0.21, 0.22)
	var primer_col   := Color(0.90, 0.75, 0.30) if is_online else Color(0.55, 0.45, 0.18)
	var text_col     := Color(0.95, 0.90, 0.70) if is_online else Color(0.60, 0.55, 0.40)

	# ── dimensions ─────────────────────────────────────────────────────
	var br: float = BULLET_HEIGHT * 0.5
	var margin_left: float = 14.0
	var margin_right: float = 14.0

	var x0: float = margin_left
	var x1: float = w - margin_right
	var bullet_len: float = x1 - x0

	var base_w:      float = br * 0.55
	var extractor_w: float = br * 0.18
	var body_w:      float = bullet_len * 0.55
	var shoulder_w:  float = bullet_len * 0.10
	var neck_w:      float = bullet_len * 0.08
	var ogive_w:     float = bullet_len - base_w - extractor_w - body_w - shoulder_w - neck_w

	var seg_base:     float = x0
	var seg_extract:  float = seg_base + base_w
	var seg_body:     float = seg_extract + extractor_w
	var seg_shoulder: float = seg_body + body_w
	var seg_neck:     float = seg_shoulder + shoulder_w
	var seg_ogive:    float = seg_neck + neck_w

	var neck_r: float = br * 0.68

	# ── draw sections ──────────────────────────────────────────────────
	_draw_casing_body(seg_extract, seg_body, cy, br, brass_bright, brass_mid, brass_dark)
	_draw_extractor_groove(seg_extract, extractor_w, cy, br, brass_dark, brass_mid)
	_draw_base(seg_base, base_w, cy, br, brass_bright, brass_mid, brass_dark)
	_draw_primer(seg_base, cy, br, primer_col)
	_draw_shoulder(seg_shoulder, shoulder_w, cy, br, neck_r, brass_bright, brass_mid, brass_dark)
	_draw_neck(seg_neck, neck_w, cy, neck_r, brass_bright, brass_mid, brass_dark)
	_draw_ogive(seg_ogive, ogive_w, cy, neck_r, lead_tip, lead_high, lead_shad)

	# ── name label ─────────────────────────────────────────────────────
	var label_cx: float = seg_extract + (seg_shoulder - seg_extract) * 0.5
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 11
	var ts: float = font.get_string_size(friend_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(label_cx - ts * 0.5, cy + font_size * 0.38),
		friend_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_col)

	# ── online status dot (left of base) ───────────────────────────────
	var dot_col: Color = Color(0.2, 0.9, 0.3) if is_online else Color(0.55, 0.55, 0.55)
	draw_circle(Vector2(seg_base - 8.0, cy), 4.0, dot_col)


# ── drawing helpers ────────────────────────────────────────────────────

func _draw_casing_body(x_start: float, x_end: float, cy: float, br: float,
		bright: Color, mid: Color, dark: Color) -> void:
	var rw: float = x_end - x_start
	draw_rect(Rect2(x_start, cy - br, rw, br * 2.0), mid)
	draw_rect(Rect2(x_start, cy - br, rw, br * 0.28), bright)
	draw_rect(Rect2(x_start, cy + br * 0.72, rw, br * 0.28), dark)
	var seam_x: float = x_start + rw * 0.35
	draw_line(Vector2(seam_x, cy - br + 2), Vector2(seam_x, cy + br - 2),
		bright.lightened(0.15), 0.7)


func _draw_extractor_groove(x: float, ew: float, cy: float, br: float,
		dark: Color, mid: Color) -> void:
	draw_rect(Rect2(x, cy - br * 0.85, ew, br * 1.7), dark)
	draw_rect(Rect2(x, cy - br * 0.85, ew, 1.5), mid)


func _draw_base(x: float, bw: float, cy: float, br: float,
		bright: Color, mid: Color, dark: Color) -> void:
	var re: float = 2.5
	draw_rect(Rect2(x, cy - br - re, bw, (br + re) * 2.0), mid)
	draw_rect(Rect2(x, cy - br - re, bw, (br + re) * 0.3), bright)
	draw_rect(Rect2(x, cy + br + re * 0.7, bw, (br + re) * 0.3), dark)


func _draw_primer(x: float, cy: float, br: float, pcol: Color) -> void:
	var pr: float = br * 0.40
	draw_circle(Vector2(x + 3.5, cy), pr, pcol.darkened(0.25))
	draw_circle(Vector2(x + 3.5, cy), pr * 0.7, pcol)
	draw_circle(Vector2(x + 2.5, cy - pr * 0.35), pr * 0.18, pcol.lightened(0.5))


func _draw_shoulder(xs: float, sw: float, cy: float, br: float, neck_r: float,
		bright: Color, mid: Color, dark: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(xs,      cy - br),
		Vector2(xs + sw, cy - neck_r),
		Vector2(xs + sw, cy + neck_r),
		Vector2(xs,      cy + br),
	])
	draw_colored_polygon(pts, mid)
	draw_line(Vector2(xs, cy - br), Vector2(xs + sw, cy - neck_r), bright, 1.5)
	draw_line(Vector2(xs, cy + br), Vector2(xs + sw, cy + neck_r), dark, 1.0)


func _draw_neck(xn: float, nw: float, cy: float, neck_r: float,
		bright: Color, mid: Color, dark: Color) -> void:
	draw_rect(Rect2(xn, cy - neck_r, nw, neck_r * 2.0), mid)
	draw_rect(Rect2(xn, cy - neck_r, nw, neck_r * 0.3), bright)
	draw_rect(Rect2(xn, cy + neck_r * 0.7, nw, neck_r * 0.3), dark)


func _draw_ogive(xo: float, ow: float, cy: float, neck_r: float,
		tip: Color, high: Color, shad: Color) -> void:
	var steps: int = 20
	var pts_top: PackedVector2Array
	var pts_bot: PackedVector2Array

	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var r: float = neck_r * (1.0 - t) * (1.0 - t * 0.4)
		var x: float = xo + t * ow
		pts_top.append(Vector2(x, cy - r))
		pts_bot.append(Vector2(x, cy + r))

	var poly := PackedVector2Array()
	for p in pts_top:
		poly.append(p)
	pts_bot.reverse()
	for p in pts_bot:
		poly.append(p)
	draw_colored_polygon(poly, tip)

	# Top highlight
	var hi_pts := PackedVector2Array()
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var r: float = neck_r * (1.0 - t) * (1.0 - t * 0.4)
		hi_pts.append(Vector2(xo + t * ow, cy - r))
	for i in range(steps, -1, -1):
		var t: float = float(i) / float(steps)
		var r: float = neck_r * (1.0 - t) * (1.0 - t * 0.4)
		hi_pts.append(Vector2(xo + t * ow, cy - r * 0.55))
	draw_colored_polygon(hi_pts, high.darkened(0.05))

	# Bottom shadow
	var sh_pts := PackedVector2Array()
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var r: float = neck_r * (1.0 - t) * (1.0 - t * 0.4)
		sh_pts.append(Vector2(xo + t * ow, cy + r * 0.55))
	for i in range(steps, -1, -1):
		var t: float = float(i) / float(steps)
		var r: float = neck_r * (1.0 - t) * (1.0 - t * 0.4)
		sh_pts.append(Vector2(xo + t * ow, cy + r))
	draw_colored_polygon(sh_pts, shad)
