extends Node3D

@export var player: CharacterBody3D
@export var weapon_holder: Node3D
@export var bob_speed_walk: float = 8.0
@export var bob_speed_sprint: float = 14.0
@export var bob_amount_h: float = 0.03
@export var bob_amount_v: float = 0.02
@export var bob_smoothing: float = 10.0

var _bob_time: float = 0.0
var _initial_pos: Vector3

func _ready() -> void:
	if weapon_holder:
		_initial_pos = weapon_holder.position

func _process(delta: float) -> void:
	if not player or not weapon_holder:
		return
	
	var velocity = player.velocity
	var speed = Vector2(velocity.x, velocity.z).length()
	
	if speed > 0.1:
		var bob_speed = bob_speed_sprint if speed > 6.0 else bob_speed_walk
		_bob_time += delta * bob_speed
		var target_x = _initial_pos.x + sin(_bob_time) * bob_amount_h
		var target_y = _initial_pos.y + sin(_bob_time * 2.0) * bob_amount_v
		weapon_holder.position.x = lerp(weapon_holder.position.x, target_x, delta * bob_smoothing)
		weapon_holder.position.y = lerp(weapon_holder.position.y, target_y, delta * bob_smoothing)
	else:
		_bob_time = lerp(_bob_time, 0.0, delta * bob_smoothing)
		weapon_holder.position.x = lerp(weapon_holder.position.x, _initial_pos.x, delta * bob_smoothing)
		weapon_holder.position.y = lerp(weapon_holder.position.y, _initial_pos.y, delta * bob_smoothing)
