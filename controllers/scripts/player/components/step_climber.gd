class_name StepHandlerComponent extends Node

@export_category("References")
@export var player : CharacterBody3D
@export_category("Step Settings")
@export var surface_threshold : float = 0.3
@export var step_height : float = 0.6

@export_group("Step Smoothing")
@export var step_speed : float = 8.0

const MIN_STEP_HEIGHT : float = 0.01
const MIN_MOVEMENT_LENGTH : float = 0.1
const MIN_DOT_VALUE : float = 0.3

var step_status : String = ""
var _target_height : float = 0.0
var _step_smoothing : bool = false
var offset_height : float = 0.0

func smooth_step(height_change: float):
	_target_height -= height_change
	_step_smoothing = true

func process_smoothing(delta: float):
	if _step_smoothing:
		_target_height = lerp(_target_height, 0.0, step_speed * delta)
		if abs(_target_height) < 0.01:
			_target_height = 0.0
			_step_smoothing = false

func handle_step_climbing():
	print("handle called, collisions: ", player.get_slide_collision_count())
	step_status = "No vertical collision detected"
	for i in player.get_slide_collision_count():
		var collision = player.get_slide_collision(i)
		if _is_vertical_surface(collision):
			var measured_height = _measure_step_height(collision)
			print("vertical surface found, measured height: ", measured_height)
			if measured_height > MIN_STEP_HEIGHT and measured_height <= step_height and _is_valid_step_direction(collision):
				player.global_position.y += measured_height
				smooth_step(measured_height)
				step_status = "Step Found! Height: " + str(measured_height)
			else:
				print("step failed - height: ", measured_height, " max: ", step_height, " valid dir: ", _is_valid_step_direction(collision))
				step_status = "Step too high: " + str(measured_height)
			break

func _is_vertical_surface(collision: KinematicCollision3D) -> bool:
	var normal = collision.get_normal()
	print("normal: ", normal)
	return abs(normal.y) < surface_threshold

func _is_valid_step_direction(collision: KinematicCollision3D) -> bool:
	var collision_normal = collision.get_normal()
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var movement_direction = player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	if movement_direction.length() > MIN_MOVEMENT_LENGTH:
		movement_direction = movement_direction.normalized()
		var dot_product = movement_direction.dot(-collision_normal)
		return dot_product > MIN_DOT_VALUE
	return false

func _measure_step_height(collision: KinematicCollision3D) -> float:
	var space_state = player.get_world_3d().direct_space_state
	var collision_point = collision.get_position()
	var player_feet_y = player.global_position.y
	var player_head_y = player.global_position.y + 2.0
	var ray_start = Vector3(collision_point.x, player_head_y, collision_point.z)
	var ray_end = Vector3(collision_point.x, player_feet_y, collision_point.z)
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	var result = space_state.intersect_ray(query)
	if result:
		return result.position.y - player_feet_y
	return 0.0
