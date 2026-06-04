extends Node

## EnemyStateLogger.gd
## Logs enemy/opponent state changes — position, health, alive/dead, animations.

func log_state_change(player: String, old_state: String, new_state: String) -> void:
	SessionLogger.log_event("enemy_state", "STATE | Player: %s | %s -> %s" % [player, old_state, new_state])

func log_position_update(player: String, position: Vector3, velocity: Vector3) -> void:
	SessionLogger.log_event("enemy_state", "POS | Player: %s | Pos: %s | Vel: %s" % [player, position, velocity])

func log_health_change(player: String, old_hp: float, new_hp: float) -> void:
	SessionLogger.log_event("enemy_state", "HP | Player: %s | %.1f -> %.1f" % [player, old_hp, new_hp])

func log_death(player: String, position: Vector3) -> void:
	SessionLogger.log_event("enemy_state", "DEATH | Player: %s | Pos: %s" % [player, position])

func log_spawn(player: String, position: Vector3) -> void:
	SessionLogger.log_event("enemy_state", "SPAWN | Player: %s | Pos: %s" % [player, position])

func log_animation(player: String, animation: String) -> void:
	SessionLogger.log_event("enemy_state", "ANIM | Player: %s | %s" % [player, animation])
