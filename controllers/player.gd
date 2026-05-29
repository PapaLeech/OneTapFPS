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

# GDC-style position sync
var _sync_counter: int = 0
var _is_remote: bool = false

var _last_sync_position: Vector3 = Vector3.ZERO
var _last_received_positions: Dictionary = {}

const ANIM_IDLE := "idle/Armature|mixamo_com|Layer0"
const ANIM_WALK := "walk/Armature|mixamo_com|Layer0"
const ANIM_RUN := "run/Armature|mixamo_com|Layer0"
const ANIM_DEAD := "death/Armature|mixamo_com|Layer0"

enum AnimState { IDLE, WALK, RUN, DEAD }
@export var current_anim_state : int = AnimState.IDLE


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
		_is_remote = true
		set_physics_process(false)
		set_process_unhandled_input(false)
		if CAMERA_CONTROLLER:
			CAMERA_CONTROLLER.current = false
		
		# Hide first-person arms/weapon for remote players
		var camera_controller := get_node_or_null("CameraController")
		if camera_controller:
			camera_controller.visible = false
			
		# Show third-person model for remote players
		var terrorist := get_node_or_null("CollisionShape3D/PlayerModel")
		if terrorist:
			print("Remote player setup: Showing terrorist")
			terrorist.show()
		var anim_player := terrorist.get_node_or_null("AnimationPlayer")
		if anim_player:
			anim_player.play(ANIM_IDLE)
			
			# Ensure ALL meshes are on layer 1 only (visible to all cameras)
			for child in terrorist.find_children("*", "MeshInstance3D", true):
				var mesh := child as MeshInstance3D
				mesh.set_layer_mask_value(1, true)
				mesh.set_layer_mask_value(2, false)
				mesh.set_layer_mask_value(3, false)
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
		# Activate camera immediately — CAMERA_CONTROLLER is assigned via @export in scene
		if CAMERA_CONTROLLER:
			CAMERA_CONTROLLER.current = true
		else:
			call_deferred("_activate_camera")
		
		# Hide local body entirely
		var terrorist := get_node_or_null("CollisionShape3D/PlayerModel")
		if terrorist:
			terrorist.hide()
		
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
	if not multiplayer.has_multiplayer_peer():
		return
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
	var is_moving := direction.length() > 0.01
	var is_sprinting := Input.is_action_pressed("sprint") and is_moving

# --- Animation State Selection ---
	var anim_state := AnimState.IDLE
	if is_sprinting:
		anim_state = AnimState.RUN
	elif is_moving:
		anim_state = AnimState.WALK
	
	_set_anim_state(anim_state)
	# --------------------------------



	move_and_slide()

	# GDC-style: send state to server every 3 frames
	_sync_counter += 1
	if _sync_counter >= 3:
		_sync_counter = 0
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			var is_moving := global_position.distance_to(_last_sync_position) > 0.01
			var is_sprinting := Input.is_action_pressed("sprint") and is_moving
			_last_sync_position = global_position
			_send_state.rpc_id(1, global_position, global_rotation.y, is_moving, is_sprinting)

	# Log position sync every 30 physics frames (~0.5s at 60hz)
	if Engine.get_physics_frames() % 30 == 0 and multiplayer.has_multiplayer_peer():
		NetworkSyncLogger.log_position_sent(PresenceManager.username, global_position, Engine.get_physics_frames())

	handle_lean(delta)

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

# Client -> Server: send my position and rotation
@rpc("any_peer", "unreliable_ordered")
func _send_state(pos: Vector3, rot_y: float, is_moving: bool, is_sprinting: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_receive_state.rpc(sender, pos, rot_y, is_moving, is_sprinting)

@rpc("any_peer", "unreliable_ordered")
func _receive_state(peer_id: int, pos: Vector3, rot_y: float, is_moving: bool, is_sprinting: bool) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var player := get_parent().get_node_or_null(str(peer_id))
	print("_receive_state: peer_id=", peer_id, " player=", player, " my_id=", multiplayer.get_unique_id())
	if player:
		var last_pos: Vector3 = _last_received_positions.get(peer_id, Vector3.ZERO)
		var detected_moving := pos.distance_to(last_pos) > 0.01
		var detected_sprinting := detected_moving and is_sprinting
		_last_received_positions[peer_id] = pos
		player.global_position = pos
		player.global_rotation.y = rot_y
		player._update_remote_animation(detected_moving, detected_sprinting)

func _update_remote_animation(is_moving: bool, is_sprinting: bool) -> void:
	var anim_player := get_node_or_null("CollisionShape3D/PlayerModel/AnimationPlayer") as AnimationPlayer
	if not anim_player:
		print("ANIM: no AnimationPlayer found on remote player")
		return
	var target_anim := ANIM_IDLE
	if is_sprinting:
		target_anim = ANIM_RUN
	elif is_moving:
		target_anim = ANIM_WALK
	if anim_player.current_animation != target_anim:
		anim_player.play(target_anim)

var _last_anim_state := -1

func _set_anim_state(new_state: int) -> void:
	if new_state == _last_anim_state:
		return
	_last_anim_state = new_state
	current_anim_state = new_state
	_play_anim_state(new_state)
	_update_anim_state.rpc(new_state)

@rpc("any_peer", "unreliable")
func _update_anim_state(state: int) -> void:
	_play_anim_state(state)

func _play_anim_state(state: int) -> void:
	var anim_player := get_node_or_null("CollisionShape3D/PlayerModel/AnimationPlayer")
	if not anim_player:
		return
	match state:
		AnimState.IDLE: anim_player.play(ANIM_IDLE)
		AnimState.WALK: anim_player.play(ANIM_WALK)
		AnimState.RUN: anim_player.play(ANIM_RUN)
		AnimState.DEAD: anim_player.play(ANIM_DEAD)

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
