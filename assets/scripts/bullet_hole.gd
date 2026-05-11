extends Node

# Spawns a bullet hole decal at a world position, aligned to the surface normal.
# Decals stay until the scene reloads — no timer cleanup.

func spawn(hit_position: Vector3, hit_normal: Vector3, parent: Node) -> void:
	var decal := Decal.new()

	# Size of the hole — tweak to taste
	decal.size = Vector3(0.06, 0.06, 0.12)

	# Add to scene first so global_position and look_at work
	parent.add_child(decal)

	# Offset slightly off the surface so it doesn't z-fight
	decal.global_position = hit_position + hit_normal * 0.005

	# Align decal to face along the surface normal (handle floor/ceiling edge case)
	var up_ref := Vector3.RIGHT if hit_normal.is_equal_approx(Vector3.UP) or hit_normal.is_equal_approx(Vector3.DOWN) else Vector3.UP
	decal.look_at(decal.global_position - hit_normal, up_ref)

	# Basic dark circle texture generated procedurally via a viewport texture
	# We use albedo_texture on the decal. A simple ImageTexture black circle.
	decal.texture_albedo = _make_hole_texture()

	# Only project onto geometry layer 1 (world/map), not player
	decal.lower_fade = 0.0
	decal.upper_fade = 0.0
	decal.albedo_mix = 1.0
	decal.cull_mask = 1


func _make_hole_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size / 2.0

	for y in range(size):
		for x in range(size):
			var dist := Vector2(x, y).distance_to(center)
			if dist < radius * 0.45:
				# Dark bullet hole core
				img.set_pixel(x, y, Color(0.05, 0.03, 0.02, 1.0))
			elif dist < radius * 0.65:
				# Scorch ring — slightly lighter
				var t := (dist - radius * 0.45) / (radius * 0.20)
				var a := lerp(0.85, 0.3, t)
				img.set_pixel(x, y, Color(0.12, 0.08, 0.06, a))
			elif dist < radius:
				# Fade out edge
				var t := (dist - radius * 0.65) / (radius * 0.35)
				var a := lerp(0.3, 0.0, t)
				img.set_pixel(x, y, Color(0.15, 0.10, 0.08, a))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(img)
