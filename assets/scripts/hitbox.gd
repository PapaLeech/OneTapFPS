class_name Hitbox
extends Area3D

@export var damage_multiplier: float = 1.0

func take_damage(amount: float) -> void:
	print("HIT: ", name, " multiplier x", damage_multiplier, " = ", amount * damage_multiplier, " damage")
	var parent := get_parent()
	while parent and not parent is CharacterBody3D:
		parent = parent.get_parent()
	if parent:
		var health := parent.get_node_or_null("Health")
		if health:
			var old_hp: float = health.current_health
			var dmg := amount * damage_multiplier
			health.take_damage(dmg)
			print("Health remaining: ", health.current_health)
			HitDetectionLogger.log_hit("unknown", parent.name, name, dmg, "unknown")
			HitDetectionLogger.log_damage_dealt("unknown", parent.name, dmg, health.current_health)
			if health.current_health <= 0.0:
				HitDetectionLogger.log_kill("unknown", parent.name, "unknown", name)
