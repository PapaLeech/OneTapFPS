@tool
extends EditorScript

func _run() -> void:
	# Style the LobbyPanel DogTags container slots via theme
	# We'll create a StyleBoxFlat for the DogTag background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.95)
	style.border_color = Color(0.5, 0.5, 0.5, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 4
	ResourceSaver.save(style, "res://assets/ui/dogtag_slot_style.tres")
	print("Saved dogtag_slot_style.tres")
