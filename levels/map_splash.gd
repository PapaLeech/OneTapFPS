extends Control

const NEXT_SCENE := "res://levels/level_001.tscn"
const DISPLAY_TIME := 2.0

@onready var progress_bar : ProgressBar = $ProgressBar

func _ready() -> void:
	progress_bar.value = 0.0
	var tween := create_tween()
	tween.tween_property(progress_bar, "value", 100.0, DISPLAY_TIME)
	tween.tween_callback(_load_map)

func _load_map() -> void:
	get_tree().change_scene_to_file(NEXT_SCENE)
