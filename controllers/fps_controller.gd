class_name PlayerController
extends CharacterBody3D

@export var SPEED : float = 5.0
@export var JUMP_VELOCITY : float = 4.5
@export var MOUSE_SENSITIVITY : float = 0.5
@export var TILT_LOWER_LIMIT := deg_to_rad(-90.0)
@export var TILT_UPPER_LIMIT := deg_to_rad(90.0)
@export var CAMERA_CONTROLLER : Camera3D
@export var ANIMATIONPLAYER : AnimationPlayer

var _mouse_input : bool = false
var _rotation_input : float
var _tilt_input : float
var _mouse_rotation : Vector3
var _player_rotation : Vector3
var _camera_rotation : Vector3

var _is_crouching : bool = false
var crouching : bool = false
var _crouch_target_height : float = 1.5
var _crouch_target_shape : float = 2.0
const CROUCH_SPEED : float = 10.0

var _is_aiming : bool = false
@export var fov_default : float = 75.0
@export var fov_ads : float = 40.0
@export var ads_speed : float = 10.0
@export var weapon_hip_pos : Vector3 = Vector3(0.0, 0.0, 0.0)
@export var weapon_ads_pos : Vector3 = Vector3(-0.19, 0.12, 0.15)

@onready var _weapon_holder : Node3D = $CameraController/Camera3D/WeaponHolder

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var step_handler = $Components/StepHandlerComponent

func _unhandled_input(event: InputEvent) -> void:
	_mouse_input = event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _mouse_input:
		_rotation_input = -event.relative.x * MOUSE_SENSITIVITY
		_tilt_input = -event.relative.y * MOUSE_SENSITIVITY

func _input(event):
	if event.is_action_pressed("exit"):
		get_tree().quit()

func _update_camera(delta):
	_mouse_rotation.x += _tilt_input * delta
	_mouse_rotation.x = clamp(_mouse_rotation.x, TILT_LOWER_LIMIT, TILT_UPPER_LIMIT)
	_mouse_rotation.y += _rotation_input * delta
	_player_rotation = Vector3(0.0, _mouse_rotation.y, 0.0)
	_camera_rotation = Vector3(_mouse_rotation.x, 0.0, 0.0)
	CAMERA_CONTROLLER.transform.basis = Basis.from_euler(_camera_rotation)
	global_transform.basis = Basis.from_euler(_player_rotation)
	CAMERA_CONTROLLER.rotation.z = 0.0
	_rotation_input = 0.0
	_tilt_input = 0.0

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	_update_camera(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var current_speed = SPEED * 0.6 if _is_crouching else SPEED
	if Input.is_action_pressed("sprint") and not _is_crouching:
		current_speed = SPEED * 1.6

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	var want_crouch = Input.is_action_pressed("CROUCH")
	if want_crouch != _is_crouching:
		toggle_crouch()

	# Smoothly lerp camera and collision shape to crouch targets
	var t = CROUCH_SPEED * delta
	CAMERA_CONTROLLER.position.y = lerp(CAMERA_CONTROLLER.position.y, _crouch_target_height, t)
	$CollisionShape3D.position.y = lerp($CollisionShape3D.position.y, _crouch_target_height, t)
	$CollisionShape3D.shape.height = lerp($CollisionShape3D.shape.height, _crouch_target_shape, t)

	# ADS - smooth FOV zoom and weapon position
	_is_aiming = Input.is_action_pressed("aim")
	var target_fov = fov_ads if _is_aiming else fov_default
	var target_weapon_pos = weapon_ads_pos if _is_aiming else weapon_hip_pos
	CAMERA_CONTROLLER.fov = lerp(CAMERA_CONTROLLER.fov, target_fov, ads_speed * delta)
	if _weapon_holder:
		_weapon_holder.position = _weapon_holder.position.lerp(target_weapon_pos, ads_speed * delta)

	if is_on_floor():
		step_handler.handle_step_climbing()

func toggle_crouch():
	if _is_crouching:
		_crouch_target_height = 1.5
		_crouch_target_shape = 2.0
	else:
		_crouch_target_height = 0.7
		_crouch_target_shape = 1.0
	_is_crouching = !_is_crouching
	crouching = _is_crouching
