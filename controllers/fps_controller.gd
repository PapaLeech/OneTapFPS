class_name PlayerController
extends CharacterBody3D

@export var SPEED : float = 5.0
@export var JUMP_VELOCITY : float = 4.5
@export var MOUSE_SENSITIVITY : float = 0.5
@export var TILT_LOWER_LIMIT := deg_to_rad(-90.0)
@export var TILT_UPPER_LIMIT := deg_to_rad(90.0)
@export var CAMERA_CONTROLLER : Camera3D
@export var ANIMATIONPLAYER : AnimationPlayer

# Lean exportshow 
@export var lean_amount : float = 0.4
@export var lean_tilt : float = 0.08
@export var lean_speed : float = 10.0

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
		MOUSE_SENSITIVITY = PresenceManager.load_setting("mouse_sensitivity", MOUSE_SENSITIVITY)
		var ads_mult: float = PresenceManager.load_setting("ads_sensitivity", 1.0) if _is_aiming else 1.0
		_rotation_input = -event.relative.x * MOUSE_SENSITIVITY * ads_mult
		_tilt_input = -event.relative.y * MOUSE_SENSITIVITY * ads_mult
		mouse_input = event.relative

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		# Let PauseMenu handle it
		pass
	if event.is_action_pressed("kill"):
		var health := get_node_or_null("Health")
		if health:
			health.take_damage(health.max_health)

func _update_camera(delta):
	_mouse_rotation.x += _tilt_input * delta
	_mouse_rotation.x = clamp(_mouse_rotation.x, TILT_LOWER_LIMIT, TILT_UPPER_LIMIT)
	_mouse_rotation.y += _rotation_input * delta
	_player_rotation = Vector3(0.0, _mouse_rotation.y, 0.0)
	_camera_rotation = Vector3(_mouse_rotation.x, 0.0, 0.0)
	CAMERA_CONTROLLER.transform.basis = Basis.from_euler(_camera_rotation)
	global_transform.basis = Basis.from_euler(_player_rotation)
	_rotation_input = 0.0
	_tilt_input = 0.0

func _enter_tree() -> void:
	# Name is the raw peer ID (set by MultiplayerSpawner)
	var peer_id := name.to_int()
	if peer_id > 0:
		set_multiplayer_authority(peer_id, true)

func _ready():
	MOUSE_SENSITIVITY = PresenceManager.load_setting("mouse_sensitivity", MOUSE_SENSITIVITY)
	# Skip local setup on dedicated server
	if OS.has_feature("dedicated_server") or "--dedicated-server" in OS.get_cmdline_args():
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	if _weapon_holder:
		def_weapon_holder_pos = _weapon_holder.position
	var health := get_node_or_null("Health")
	if health:
		health.died.connect(_on_died)
	# Only process input/physics for our own character
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		set_physics_process(false)
		set_process_unhandled_input(false)
		if CAMERA_CONTROLLER:
			CAMERA_CONTROLLER.current = false
		
		# Hide first-person arms/weapon for remote players
		var camera_controller := get_node_or_null("CameraController")
		if camera_controller:
			camera_controller.visible = false
			
		# Show third-person model for remote players
		var terrorist := get_node_or_null("CollisionShape3D/Terrorist")
		if terrorist:
			print("Remote player setup: Showing terrorist")
			terrorist.show()
			var anim_player := terrorist.get_node_or_null("AnimationPlayer")
			if anim_player and anim_player.has_animation("mixamo_com"):
				var anim : Animation = anim_player.get_animation("mixamo_com")
				if anim:
					anim.loop_mode = Animation.LOOP_LINEAR
				anim_player.play("mixamo_com")
			
			# Ensure ALL meshes are on a visible layer for others
			for child in terrorist.find_children("*", "MeshInstance3D", true):
				var mesh := child as MeshInstance3D
				mesh.set_layer_mask_value(1, true)
				mesh.set_layer_mask_value(2, false)
		else:
			print("Remote player setup ERROR: Terrorist node NOT FOUND")
		
		# Hide UI for remote players
		for ui_node in ["ScopeUI", "HudHealth2", "HudAmmo", "PauseMenu"]:
			var ui = get_node_or_null(ui_node)
			if ui:
				ui.hide()
				if ui.has_method("set_process"): ui.set_process(false)
				if ui.has_method("set_input_process"): ui.set_input_process(false)
				if ui is CanvasLayer:
					ui.process_mode = Node.PROCESS_MODE_DISABLED
			
		# Disable WeaponController for remote players
		var weapon_controller := get_node_or_null("Components/WeaponController")
		if weapon_controller:
			weapon_controller.set_physics_process(false)
	else:
		# Local player — activate camera and capture mouse here, not in level script
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		call_deferred("_activate_camera")
		
		# Hide local body (layer 3 = hidden from own camera only)
		var terrorist := get_node_or_null("CollisionShape3D/Terrorist")
		if terrorist:
			for child in terrorist.find_children("*", "MeshInstance3D", true):
				var mesh := child as MeshInstance3D
				mesh.set_layer_mask_value(1, false)
				mesh.set_layer_mask_value(2, false)
				mesh.set_layer_mask_value(3, true)
		
		# Ensure UI visible for local player
		for ui_node in ["ScopeUI", "HudHealth2", "HudAmmo", "PauseMenu"]:
			var ui = get_node_or_null(ui_node)
			if ui: ui.show()

func _activate_camera() -> void:
	if CAMERA_CONTROLLER:
		CAMERA_CONTROLLER.current = true
		return
	# Fallback: find by exact path
	var cam := get_node_or_null("CameraController/Camera3D") as Camera3D
	if cam:
		cam.current = true
		CAMERA_CONTROLLER = cam

func _on_died() -> void:
	# Disable movement
	set_physics_process(false)
	# Tilt camera to the side and drop it down like falling
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(CAMERA_CONTROLLER, "rotation_degrees", Vector3(CAMERA_CONTROLLER.rotation_degrees.x, CAMERA_CONTROLLER.rotation_degrees.y, 80.0), 0.8).set_ease(Tween.EASE_IN)
	tween.tween_property(CAMERA_CONTROLLER, "position", Vector3(CAMERA_CONTROLLER.position.x, -0.5, CAMERA_CONTROLLER.position.z), 0.8).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.9).timeout
	var pause_menu := get_node_or_null("PauseMenu")
	if pause_menu:
		pause_menu.open_death_menu()

func _physics_process(delta):
	if not is_multiplayer_authority(): return
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
		ClientPredictionLogger.log_input(PresenceManager.username, "move", Engine.get_physics_frames())
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
	# Log position sync every 30 physics frames (~0.5s at 60hz)
	if Engine.get_physics_frames() % 30 == 0 and multiplayer.has_multiplayer_peer():
		NetworkSyncLogger.log_position_sent(PresenceManager.username, global_position, Engine.get_physics_frames())

	handle_lean(delta)
	#weapon_bob(velocity.length(), delta)

	var want_crouch = Input.is_action_pressed("CROUCH")
	if want_crouch != _is_crouching:
		toggle_crouch()

	var t = CROUCH_SPEED * delta
	CAMERA_CONTROLLER.position.y = lerp(CAMERA_CONTROLLER.position.y, _crouch_target_height, t)
	$CollisionShape3D.position.y = lerp($CollisionShape3D.position.y, _crouch_target_height, t)
	$CollisionShape3D.shape.height = lerp($CollisionShape3D.shape.height, _crouch_target_shape, t)

	_is_aiming = Input.is_action_pressed("aim")
	var target_fov = fov_ads if _is_aiming else fov_default
	CAMERA_CONTROLLER.fov = lerp(CAMERA_CONTROLLER.fov, target_fov, ads_speed * delta)

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
