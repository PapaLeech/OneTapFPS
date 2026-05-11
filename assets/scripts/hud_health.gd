extends CanvasLayer

@onready var bar: ProgressBar = $HealthBar
@onready var label: Label = $HealthBar/Label

func _ready() -> void:
	# Style the bar green
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.1, 0.85, 0.2, 1.0)
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.05, 0.7)
	bg_style.corner_radius_top_left = 3
	bg_style.corner_radius_top_right = 3
	bg_style.corner_radius_bottom_left = 3
	bg_style.corner_radius_bottom_right = 3
	if bar:
		bar.add_theme_stylebox_override("fill", fill_style)
		bar.add_theme_stylebox_override("background", bg_style)
		if label:
			label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
			label.add_theme_font_size_override("font_size", 11)
	# Find the player's Health node and connect to its signal
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var health := player.get_node_or_null("Health")
		if health:
			health.health_changed.connect(_on_health_changed)
			_on_health_changed(health.current_health, health.max_health)

func _on_health_changed(new_health: float, max_health: float) -> void:
	if bar:
		bar.max_value = max_health
		bar.value = new_health
	if label:
		label.text = "%d / %d" % [int(new_health), int(max_health)]
