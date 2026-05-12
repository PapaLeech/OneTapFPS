extends Node3D

# -----------------------------
# WEAPON SETTINGS
# -----------------------------
@export var sway_amount := 0.015
@export var sway_smooth := 10.0

@export var bob_amount := 0.015
@export var bob_speed := 8.0

@export var hip_offset := Vector3(0.15, -0.15, -0.45)
@export var ads_offset := Vector3(0, -0.1, -0.25)
@export var ads_speed := 12.0

# COD4 sprint tilt
@export var sprint_offset := Vector3(0.25, -0.25, -0.1)
@export var sprint_tilt := Vector3(deg_to_rad(-15), deg_to_rad(10), 0)

# Crouch lowering
@export var crouch_offset := Vector3(0.1, -0.25, -0.45)

# Melee swing
@export var melee_offset := Vector3(0, -0.05, -0.6)
@export var melee_tilt := Vector3(deg_to_rad(-20), 0, 0)
@export var melee_speed := 18.0

# Recoil
@export var recoil_amount := Vector3(0.02, 0.01, 0)
@export var recoil_recover := 8.0

# Shooting
@export var muzzle_flash: Node3D
@export var raycast: RayCast3D
@export var fire_rate := 0.1
var can_shoot := true

# -----------------------------
# INTERNAL STATE
# -----------------------------
var sway_offset := Vector3.ZERO
var bob_time := 0.0
var recoil_offset := Vector3.ZERO

var ads_weight := 0.0
var sprint_weight := 0.0
var crouch_weight := 0.0
var melee_weight := 0.0

func _process(delta):
	var player = get_parent().get_parent()

	_handle_ads(delta)
	_handle_sprint(delta, player)
	_handle_crouch(delta, player)
	_handle_melee(delta, player)

	_handle_sway(delta)
	_handle_bob(delta, player)
	_handle_recoil(delta)

	_apply_final_offset(delta)

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and can_shoot and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		shoot()

# -----------------------------
# STATE HANDLERS
# -----------------------------
func _handle_ads(delta):
	var adsing = Input.is_action_pressed("aim")
	ads_weight = lerp(ads_weight, 1.0 if adsing else 0.0, delta * ads_speed)

func _handle_sprint(delta, player):
	sprint_weight = lerp(sprint_weight, 1.0 if player.sprinting else 0.0, delta * 10.0)

func _handle_crouch(delta, player):
	crouch_weight = lerp(crouch_weight, 1.0 if player.crouching else 0.0, delta * 10.0)

func _handle_melee(delta, player):
	melee_weight = lerp(melee_weight, 1.0 if player.meleeing else 0.0, delta * melee_speed)

# -----------------------------
# SWAY / BOB / RECOIL
# -----------------------------
func _handle_sway(delta):
	if ads_weight > 0.9:
		sway_offset = sway_offset.lerp(Vector3.ZERO, delta * sway_smooth)
		return

	var mouse = get_viewport().get_mouse_position()
	var center = get_viewport().size / 2.0
	var delta_pos = (mouse - center) / center

	var sway_x = -delta_pos.x * sway_amount
	var sway_y = -delta_pos.y * sway_amount

	sway_offset = sway_offset.lerp(Vector3(sway_y, sway_x, 0), delta * sway_smooth)

func _handle_bob(delta, player):
	if ads_weight > 0.1:
		return

	var speed = player.velocity.length()

	if speed > 0.1 and player.is_on_floor():
		bob_time += delta * bob_speed
		var y = sin(bob_time) * bob_amount
		var x = cos(bob_time * 0.5) * bob_amount * 0.5
		sway_offset += Vector3(x, y, 0)
	else:
		bob_time = 0.0

func _handle_recoil(delta):
	recoil_offset = recoil_offset.lerp(Vector3.ZERO, delta * recoil_recover)

# -----------------------------
# FINAL OFFSET BLENDING
# -----------------------------
func _apply_final_offset(delta):
	var base = hip_offset.lerp(ads_offset, ads_weight)
	base = base.lerp(sprint_offset, sprint_weight)
	base = base.lerp(crouch_offset, crouch_weight)
	base = base.lerp(melee_offset, melee_weight)

	var final_offset = base + sway_offset + recoil_offset
	transform.origin = transform.origin.lerp(final_offset, delta * ads_speed)

	# Rotation blending (tilt)
	var rot = Vector3.ZERO
	rot = rot.lerp(sprint_tilt, sprint_weight)
	rot = rot.lerp(melee_tilt, melee_weight)

	rotation = rotation.lerp(rot, delta * 10.0)

# -----------------------------
# SHOOTING
# -----------------------------
func shoot():
	can_shoot = false

	if muzzle_flash:
		muzzle_flash.visible = true
		await get_tree().create_timer(0.05).timeout
		muzzle_flash.visible = false

	if raycast and raycast.is_colliding():
		var hit = raycast.get_collider()
		print("Hit:", hit)

	recoil_offset += recoil_amount

	await get_tree().create_timer(fire_rate).timeout
	can_shoot = true
