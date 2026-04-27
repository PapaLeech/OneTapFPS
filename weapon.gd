extends Node3D

# -----------------------------
# WEAPON SETTINGS
# -----------------------------
@export_group("Sway & Bob")
@export var sway_amount := 0.015
@export var sway_smooth := 10.0
@export var bob_amount := 0.02
@export var bob_speed := 12.0
@export var cam_bob_amount := 0.05

@export_group("FX")
@export var fire_sound: AudioStreamPlayer3D

@export_group("Offsets")
@export var hip_offset := Vector3(0.15, -0.15, -0.45)
@export var ads_offset := Vector3(0, -0.1, -0.25)
@export var ads_speed := 12.0
@export var sprint_offset := Vector3(0.25, -0.25, -0.1)
@export var sprint_tilt := Vector3(deg_to_rad(-15), deg_to_rad(10), 0)
@export var crouch_offset := Vector3(0.1, -0.25, -0.45)

@export_group("Melee")
@export var melee_offset := Vector3(0, -0.05, -0.6)
@export var melee_tilt := Vector3(deg_to_rad(-20), 0, 0)
@export var melee_speed := 18.0

@export_group("Combat & Recoil")
@export var hip_recoil := Vector3(0.04, 0.02, 0.05)
@export var ads_recoil := Vector3(0.01, 0.005, 0.02)
@export var recoil_rotation_amount := Vector3(deg_to_rad(5), deg_to_rad(2), 0)
@export var recoil_recover := 8.0
@export var fire_rate := 0.1
@export var muzzle_flash: Node3D
@export var raycast: RayCast3D

@export_group("FOV Settings")
@export var hip_fov := 75.0
@export var ads_fov := 55.0
@export var fov_speed := 12.0

@export_group("Bullets")
@export var bullet_scene: PackedScene
@export var muzzle_front: Node3D
@export var muzzle_side: Node3D

# -----------------------------
# INTERNAL STATE
# -----------------------------
var sway_offset := Vector3.ZERO
var bob_offset := Vector3.ZERO
var bob_time := 0.0
var recoil_offset := Vector3.ZERO
var recoil_rotation := Vector3.ZERO
var mouse_input := Vector2.ZERO

var ads_weight := 0.0
var sprint_weight := 0.0
var crouch_weight := 0.0
var melee_weight := 0.0
var can_shoot := true

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_input = event.relative

func _process(delta: float) -> void:
	# AK (1) -> Holder (2) -> Camera (3) -> Player
	var player = get_parent().get_parent().get_parent()
	
	if not player or not player is CharacterBody3D:
		return

	# Handle Firing Input
	var can_fire_state = sprint_weight < 0.5 and melee_weight < 0.5
	if Input.is_action_pressed("fire") and can_shoot and can_fire_state:
		shoot()

	# Run Handlers
	_handle_ads(delta)
	_handle_sprint(delta, player)
	_handle_crouch(delta, player)
	_handle_melee(delta, player)
	_handle_fov(delta, player)
	_handle_sway(delta)
	_handle_bob(delta, player)
	_handle_camera_bob(delta, player)
	_handle_recoil(delta) # This now has a function to run!
	_apply_final_offset(delta)

# -----------------------------
# STATE HANDLERS
# -----------------------------
func _handle_ads(delta: float) -> void:
	var adsing = Input.is_action_pressed("aim")
	ads_weight = lerp(ads_weight, 1.0 if adsing else 0.0, delta * ads_speed)

func _handle_sprint(delta: float, player: Node) -> void:
	var is_sprinting = player.get("sprinting") == true
	sprint_weight = lerp(sprint_weight, 1.0 if is_sprinting else 0.0, delta * 10.0)

func _handle_crouch(delta: float, player: Node) -> void:
	var is_crouching = player.get("crouching") == true
	crouch_weight = lerp(crouch_weight, 1.0 if is_crouching else 0.0, delta * 10.0)

func _handle_melee(delta: float, player: Node) -> void:
	var is_meleeing = player.get("meleeing") == true
	melee_weight = lerp(melee_weight, 1.0 if is_meleeing else 0.0, delta * melee_speed)

func _handle_fov(delta: float, player: Node) -> void:
	var cam = player.get("CAMERA_CONTROLLER")
	if cam:
		var target_fov = ads_fov if ads_weight > 0.5 else hip_fov
		cam.fov = lerp(cam.fov, target_fov, delta * fov_speed)

func _handle_sway(delta: float) -> void:
	if ads_weight > 0.9:
		sway_offset = sway_offset.lerp(Vector3.ZERO, delta * sway_smooth)
		return
	var target_sway = Vector3(-mouse_input.y * sway_amount, -mouse_input.x * sway_amount, 0)
	sway_offset = sway_offset.lerp(target_sway, delta * sway_smooth)
	mouse_input = Vector2.ZERO

func _handle_bob(delta: float, player: CharacterBody3D) -> void:
	if player.velocity.length() > 0.1 and player.is_on_floor():
		bob_time += delta * bob_speed
		var y = sin(bob_time) * bob_amount
		var x = cos(bob_time * 0.5) * bob_amount * 0.5
		bob_offset = Vector3(x, y, 0)
	else:
		bob_time = 0.0
		bob_offset = bob_offset.lerp(Vector3.ZERO, delta * 10.0)

func _handle_camera_bob(delta: float, player: Node) -> void:
	var cam = player.get("CAMERA_CONTROLLER")
	if not cam: return
	
	if player.is_on_floor() and player.velocity.length() > 0.1:
		cam.h_offset = lerp(cam.h_offset, cos(bob_time * 0.5) * cam_bob_amount * 0.5, delta * 10.0)
		cam.v_offset = lerp(cam.v_offset, sin(bob_time) * cam_bob_amount, delta * 10.0)
	else:
		cam.h_offset = lerp(cam.h_offset, 0.0, delta * 10.0)
		cam.v_offset = lerp(cam.v_offset, 0.0, delta * 10.0)

# MISSING FUNCTION: Fixed the recoil crash
func _handle_recoil(delta: float) -> void:
	recoil_offset = recoil_offset.lerp(Vector3.ZERO, delta * recoil_recover)
	recoil_rotation = recoil_rotation.lerp(Vector3.ZERO, delta * recoil_recover)

func _apply_final_offset(delta: float) -> void:
	var base = hip_offset.lerp(ads_offset, ads_weight)
	base = base.lerp(sprint_offset, sprint_weight)
	base = base.lerp(crouch_offset, crouch_weight)
	base = base.lerp(melee_offset, melee_weight)

	var final_pos = base + sway_offset + bob_offset + recoil_offset
	transform.origin = transform.origin.lerp(final_pos, delta * ads_speed)

	var final_rot = Vector3.ZERO.lerp(sprint_tilt, sprint_weight).lerp(melee_tilt, melee_weight)
	rotation = rotation.lerp(final_rot + recoil_rotation, delta * 10.0)

func shoot() -> void:
	if not can_shoot: return
	
	print("shoot called")
	if fire_sound:
		fire_sound.play()
	
	can_shoot = false
	
	# Recoil Logic
	var is_ads = ads_weight > 0.5
	var applied_recoil = ads_recoil if is_ads else hip_recoil
	recoil_offset += Vector3(randf_range(-applied_recoil.x, applied_recoil.x), applied_recoil.y, applied_recoil.z)
	recoil_rotation += Vector3(recoil_rotation_amount.x, randf_range(-recoil_rotation_amount.y, recoil_rotation_amount.y), 0)

	if raycast and raycast.is_colliding():
		print("Hit:", raycast.get_collider().name)

	# --- Bullet spawn (additive) ---
	if bullet_scene:
		var spawn_parent := get_tree().current_scene
		for muzzle in [muzzle_front, muzzle_side]:
			if muzzle and spawn_parent:
				var b := bullet_scene.instantiate() as Node3D
				spawn_parent.add_child(b)
				b.global_transform = muzzle.global_transform
	# --- end bullet spawn ---

	await get_tree().create_timer(fire_rate).timeout
	can_shoot = true
