@tool
extends Node3D
class_name PlayerSpawnPoint

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	queue_free()
