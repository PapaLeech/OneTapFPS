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
		print("HIT parent name: ", parent.name, " health: ", health)
		if health:
			var dmg := amount * damage_multiplier
			# In multiplayer, send damage RPC to the player's authority
			if multiplayer.has_multiplayer_peer():
				var target_id := int(parent.name)
				if target_id > 0:
					health._take_damage_rpc.rpc_id(target_id, dmg)
					HitDetectionLogger.log_hit("unknown", parent.name, name, dmg, "unknown")
					return
			health._apply_damage(dmg)
			HitDetectionLogger.log_hit("unknown", parent.name, name, dmg, "unknown")
			HitDetectionLogger.log_damage_dealt("unknown", parent.name, dmg, health.current_health)
