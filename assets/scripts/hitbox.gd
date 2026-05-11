class_name Hitbox
extends Area3D

@export var damage_multiplier: float = 1.0

func take_damage(amount: float) -> void:
	print("HIT: ", name, " multiplier x", damage_multiplier, " = ", amount * damage_multiplier, " damage")
	var parent := get_parent()
	# Walk up the tree to find the enemy root (CharacterBody3D)
	while parent and not parent is CharacterBody3D:
		parent = parent.get_parent()
	if parent:
		var health := parent.get_node_or_null("Health")
		if health:
			health.take_damage(amount * damage_multiplier)
			print("Health remaining: ", health.current_health)
