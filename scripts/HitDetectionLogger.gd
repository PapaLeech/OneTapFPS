extends Node

## HitDetectionLogger.gd
## Logs every shot fired, what was hit, damage dealt, and kill events.
## Reports to SessionLogger.

func log_shot_fired(shooter: String, weapon: String, position: Vector3) -> void:
	SessionLogger.log_event("hit_detection", "SHOT FIRED | Player: %s | Weapon: %s | Pos: %s" % [shooter, weapon, position])

func log_hit(shooter: String, target: String, hitbox: String, damage: float, weapon: String) -> void:
	SessionLogger.log_event("hit_detection", "HIT | %s -> %s | Hitbox: %s | Dmg: %.1f | Weapon: %s" % [shooter, target, hitbox, damage, weapon])
	SessionLogger.record_shot(true)

func log_miss(shooter: String, weapon: String) -> void:
	SessionLogger.log_event("hit_detection", "MISS | Player: %s | Weapon: %s" % [shooter, weapon])
	SessionLogger.record_shot(false)

func log_kill(killer: String, victim: String, weapon: String, hitbox: String) -> void:
	SessionLogger.log_event("hit_detection", "KILL | %s killed %s | Weapon: %s | Hitbox: %s" % [killer, victim, weapon, hitbox])
	SessionLogger.record_death()

func log_damage_dealt(shooter: String, target: String, damage: float, remaining_hp: float) -> void:
	SessionLogger.log_event("hit_detection", "DAMAGE | %s -> %s | Dmg: %.1f | Target HP remaining: %.1f" % [shooter, target, damage, remaining_hp])
