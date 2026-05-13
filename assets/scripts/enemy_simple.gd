extends StaticBody3D

@onready var _health : Node = $Health
@onready var _anim_player : AnimationPlayer = $Terrorist/AnimationPlayer

func _ready() -> void:
	_health.died.connect(_on_died)

func _on_died() -> void:
	if _anim_player:
		var anims = _anim_player.get_animation_list()
		for anim in anims:
			if "die" in anim.to_lower() or "death" in anim.to_lower():
				_anim_player.play(anim)
				return
	# Face the player then fall forward
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var dir = (player.global_position - global_position)
		dir.y = 0
		look_at(global_position + dir, Vector3.UP)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation_degrees", Vector3(rotation_degrees.x + 70, rotation_degrees.y, rotation_degrees.z), 0.6).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position", position + Vector3(0, -1.2, 0.8), 0.6).set_ease(Tween.EASE_IN)
	$CollisionShape3D.disabled = true
