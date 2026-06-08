extends Node

@export var max_health: float = 100.0

var current_health: float = max_health
var last_attacker: String = "unknown"
var last_attacker_id: int = -1

signal died
signal health_changed(new_health: float, max_health: float)

func _ready() -> void:
	current_health = max_health
	EnemyStateLogger.log_spawn(str(get_parent().name) if get_parent() else "unknown", get_parent().global_position if get_parent() else Vector3.ZERO)

func take_damage(amount: float) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		# Send damage to the authority (the player who owns this node)
		var authority_id := get_multiplayer_authority()
		_take_damage_rpc.rpc_id(authority_id, amount, "unknown", -1)
		return
	_apply_damage(amount)

@rpc("any_peer", "call_remote", "reliable")
func _take_damage_rpc(amount: float, attacker: String, attacker_id: int) -> void:
	last_attacker = attacker
	last_attacker_id = attacker_id
	_apply_damage(amount)

func _apply_damage(amount: float) -> void:
	var old_hp := current_health
	current_health -= amount
	current_health = max(current_health, 0.0)
	emit_signal("health_changed", current_health, max_health)
	EnemyStateLogger.log_health_change(str(get_parent().name) if get_parent() else "unknown", old_hp, current_health)
	if current_health <= 0.0:
		var victim := str(get_parent().name) if get_parent() else "unknown"
		EnemyStateLogger.log_death(victim, get_parent().global_position if get_parent() else Vector3.ZERO)
		HitDetectionLogger.log_kill(last_attacker, victim, "unknown", "unknown")
		SessionLogger.record_death()
		# Record kill/death in scoreboard
		var level := get_tree().get_root().get_node_or_null("Node3D")
		if level and level.has_method("record_kill"):
			var parent_name := get_parent().name if get_parent() else "unknown"
			var victim_id := int(parent_name) if parent_name.is_valid_int() else -1
			if victim_id > 0:
				level.record_kill(last_attacker_id, victim_id)
		emit_signal("died")

func heal(amount: float) -> void:
	current_health = min(current_health + amount, max_health)
	emit_signal("health_changed", current_health, max_health)

func is_alive() -> bool:
	return current_health > 0.0
