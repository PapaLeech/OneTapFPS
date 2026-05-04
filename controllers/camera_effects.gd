class_name CameraEffects
extends Camera3D

@export_category("References")
@export var player: PlayerController

@export_category("Effects")
@export var enable_fall_kick: bool = true

@export_group("Camera Kick")
@export_subgroup("Fall Kick")
@export var fall_time: float = 0.3
@export var fall_kick_amount: float = 0.06
@export var fall_kick_speed: float = 12.0

var _fall_value: float = 0.0
var _fall_timer: float = 0.0
var _was_on_floor: bool = true
var _air_velocity_y: float = 0.0


func _process(delta: float) -> void:
	if not player or not enable_fall_kick:
		return

	# Track downward velocity while airborne
	if not player.is_on_floor():
		_was_on_floor = false
		_air_velocity_y = player.velocity.y
	else:
		# Just landed - trigger kick scaled by impact speed
		if not _was_on_floor:
			var impact = clamp(-_air_velocity_y / 20.0, 0.0, 1.0)
			_fall_value = fall_kick_amount * impact
			_fall_timer = fall_time
		_was_on_floor = true

	# Apply and recover the kick
	if _fall_timer > 0.0:
		_fall_timer -= delta
		position.y = lerp(position.y, -_fall_value, delta * fall_kick_speed)
	else:
		_fall_value = 0.0
		position.y = lerp(position.y, 0.0, delta * fall_kick_speed)
