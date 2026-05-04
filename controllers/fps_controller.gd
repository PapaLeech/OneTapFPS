class_name PlayerController
extends CharacterBody3D

@export var SPEED : float = 5.0
@export var JUMP_VELOCITY : float = 4.5
@export var MOUSE_SENSITIVITY : float = 0.5
@export var TILT_LOWER_LIMIT := deg_to_rad(-90.0)
@export var TILT_UPPER_LIMIT := deg_to_rad(90.0)
@export var CAMERA_CONTROLLER : Camera3D
@export var ANIMATIONPLAYER : AnimationPlayer

# Lean exports
@export var lean_amount : float = 0.4
@export var lean_tilt : float = 0.08
@export var lean_speed : float = 10.0

# Sway exports
@export var weapon_sway_amount : float = 0.01
@export var weapon_rotation_amount : float = 0.003

var _mouse_input : bool = false
var _rotation_input : float
var _tilt_input : float
var _mouse_rotation : Vector3
var _player_rotation : Vector3
var _camera_rotation : Vector3

# Sway variable
var mouse_input : Vector2

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

# Bob baseline
var def_weapon_holder_pos : Vector3

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var step_handler = $Components/StepHandlerComponent

func _unhandled_input(event: InputEvent) -> void:
	_mouse_input = event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _mouse_input:
		_rotation_input = -event.relative.x * MOUSE_SENSITIVITY
		_tilt_input = -event.relative.y * MOUSE_SENSITIVITY
		mouse_input = event.relative

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
	# DELETE THE LINE BELOW
	CAMERA_CONTROLLER.rotation.z = 0.0
	_rotation_input = 0.0
	_tilt_input = 0.0

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _weapon_holder:
		def_weapon_holder_pos = _weapon_holder.position

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

	handle_lean(delta)
	weapon_sway(delta)
	weapon_bob(velocity.length(), delta)

	var want_crouch = Input.is_action_pressed("CROUCH")
	if want_crouch != _is_crouching:
		toggle_crouch()

	var t = CROUCH_SPEED * delta
	CAMERA_CONTROLLER.position.y = lerp(CAMERA_CONTROLLER.position.y, _crouch_target_height, t)
	$CollisionShape3D.position.y = lerp($CollisionShape3D.position.y, _crouch_target_height, t)
	$CollisionShape3D.shape.height = lerp($CollisionShape3D.shape.height, _crouch_target_shape, t)

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

func handle_lean(delta):
	var lean_dir = 0.0
	if Input.is_action_pressed("lean_left"):
		lean_dir = -1.0
	elif Input.is_action_pressed("lean_right"):
		lean_dir = 1.0

	if CAMERA_CONTROLLER:
		CAMERA_CONTROLLER.position.x = lerp(
			CAMERA_CONTROLLER.position.x,
			lean_dir * lean_amount,
			lean_speed * delta
		)
		CAMERA_CONTROLLER.rotation.z = lerp(
			CAMERA_CONTROLLER.rotation.z,
			lean_dir * lean_tilt,
			lean_speed * delta
		)

func weapon_sway(delta):
	mouse_input = lerp(mouse_input, Vector2.ZERO, 10 * delta)
	if _weapon_holder:
		_weapon_holder.rotation.x = lerp(
			_weapon_holder.rotation.x,
			mouse_input.y * weapon_rotation_amount,
			10 * delta
		)
		_weapon_holder.rotation.y = lerp(
			_weapon_holder.rotation.y,
			mouse_input.x * weapon_rotation_amount,
			10 * delta
		)

func weapon_bob(vel : float, delta):
	if _is_aiming:
		return
	if _weapon_holder:
		if vel > 0 or is_on_floor():
			var bob_amount : float = 0.01
			var bob_freq : float = 0.01
			_weapon_holder.position.y = lerp(
				_weapon_holder.position.y,
				def_weapon_holder_pos.y + sin(Time.get_ticks_msec() * bob_freq) * bob_amount,
				10 * delta
			)
			_weapon_holder.position.x = lerp(
				_weapon_holder.position.x,
				def_weapon_holder_pos.x + sin(Time.get_ticks_msec() * bob_freq * 0.5) * bob_amount,
				10 * delta
			)
		else:
			_weapon_holder.position.y = lerp(_weapon_holder.position.y, def_weapon_holder_pos.y, 10 * delta)
			_weapon_holder.position.x = lerp(_weapon_holder.position.x, def_weapon_holder_pos.x, 10 * delta)
