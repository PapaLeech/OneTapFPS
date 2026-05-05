class_name WeaponController extends Node

@export var current_weapon: Weapon
@export var weapon_model_parent: Node3D
@export var weapons: Array[Weapon] = []

# Reference to gun.gd on WeaponHolder for recoil
@export var gun: Node3D

# ADS recoil multiplier — lower = less recoil when aiming
@export var ads_recoil_multiplier: float = 0.5

# Sway
@export var sway_noise: NoiseTexture2D
@export var sway_speed: float = 1.2

var current_weapon_model: Node3D
var _anim_player: AnimationPlayer
var _gun_sound: AudioStreamPlayer3D
var _is_aiming: bool = false
var _is_firing: bool = false
var _fire_timer: float = 0.0
var _current_index: int = 0
var _mouse_movement: Vector2
var _random_sway_x: float
var _random_sway_y: float
var _sway_time: float = 0.0

func _ready() -> void:
	_gun_sound = get_node_or_null("../../CameraController/Camera3D/WeaponHolder/GunShotSound")
	if weapons.size() > 0:
		current_weapon = weapons[0]
	if current_weapon:
		spawn_weapon_model()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_mouse_movement = event.relative
	if event is InputEventMouseButton:
		if event.pressed:
			print("mouse button: ", event.button_index)
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_switch_weapon(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_switch_weapon(1)

func _switch_weapon(direction: int) -> void:
	print("switch weapon called, direction: ", direction, " weapons: ", weapons.size())
	if weapons.size() <= 1:
		return
	_current_index = wrapi(_current_index + direction, 0, weapons.size())
	current_weapon = weapons[_current_index]
	_is_firing = false
	_fire_timer = 0.0
	if _anim_player:
		_anim_player.stop()
	spawn_weapon_model()

func _physics_process(delta):
	_is_aiming = Input.is_action_pressed("aim")
	_mouse_movement = _mouse_movement.lerp(Vector2.ZERO, 10 * delta)
	
	if not _is_aiming and current_weapon:
		_sway_weapon(delta)

	if current_weapon and current_weapon.full_auto:
		if Input.is_action_pressed("fire"):
			_fire_timer -= delta
			if _fire_timer <= 0.0:
				fire()
				_fire_timer = current_weapon.fire_rate
			if not _is_firing:
				_is_firing = true
				if _anim_player and _anim_player.has_animation("fire_lib/fire"):
					_anim_player.play("fire_lib/fire")
		else:
			if _is_firing:
				_is_firing = false
				_fire_timer = 0.0
				if _anim_player:
					_anim_player.stop()
	else:
		if Input.is_action_just_pressed("fire"):
			fire()

func spawn_weapon_model():
	if current_weapon_model:
		current_weapon_model.queue_free()
	print("weapon model scene: ", current_weapon.weapon_model)
	print("weapon_model_parent: ", weapon_model_parent)
	if current_weapon.weapon_model:
		current_weapon_model = current_weapon.weapon_model.instantiate()
		weapon_model_parent.add_child(current_weapon_model)
		current_weapon_model.position = current_weapon.weapon_position
		current_weapon_model.scale = current_weapon.weapon_scale
		_anim_player = current_weapon_model.find_child("AnimationPlayer", true, false)
		if _anim_player:
			_create_fire_animation()

func fire():
	if not gun:
		return
	if _anim_player and _anim_player.has_animation("fire_lib/fire"):
		_anim_player.stop()
		_anim_player.play("fire_lib/fire")
	if _gun_sound:
		_gun_sound.play()
	if _is_aiming:
		gun.recoil_amplitude *= ads_recoil_multiplier
		gun.apply_recoil()
		gun.recoil_amplitude /= ads_recoil_multiplier
	else:
		gun.apply_recoil()

func _create_fire_animation() -> void:
	var anim_name := _anim_player.get_animation_list()[0] if _anim_player.get_animation_list().size() > 0 else ""
	if anim_name == "":
		return
	var source := _anim_player.get_animation(anim_name)
	if not source:
		return
	var start := current_weapon.anim_fire_start
	var end := current_weapon.anim_fire_end
	var fire_anim := Animation.new()
	fire_anim.length = end - start
	fire_anim.loop_mode = Animation.LOOP_LINEAR if current_weapon.full_auto else Animation.LOOP_NONE
	for i in source.get_track_count():
		var track_type := source.track_get_type(i)
		var track_path := source.track_get_path(i)
		var new_track := fire_anim.add_track(track_type)
		fire_anim.track_set_path(new_track, track_path)
		for j in source.track_get_key_count(i):
			var key_time := source.track_get_key_time(i, j)
			if key_time < start:
				continue
			if key_time > end:
				break
			var key_value: Variant = source.track_get_key_value(i, j) as Variant
			var key_transition := source.track_get_key_transition(i, j)
			fire_anim.track_insert_key(new_track, key_time - start, key_value, key_transition)
	var lib := AnimationLibrary.new()
	lib.add_animation("fire", fire_anim)
	_anim_player.add_animation_library("fire_lib", lib)

func _sway_weapon(delta: float) -> void:
	if not weapon_model_parent:
		return
	var sway_random: float = _get_sway_noise()
	var sway_random_adjusted: float = sway_random * current_weapon.idle_sway_adjustment

	_sway_time += delta * (sway_speed + sway_random)
	_random_sway_x = sin(_sway_time * 1.5 + sway_random_adjusted) / current_weapon.random_sway_amount
	_random_sway_y = sin(_sway_time - sway_random_adjusted) / current_weapon.random_sway_amount

	var clamped := _mouse_movement.clamp(current_weapon.sway_min, current_weapon.sway_max)
	var base_pos := current_weapon.weapon_position

	weapon_model_parent.position.x = lerp(
		weapon_model_parent.position.x,
		base_pos.x - (clamped.x * current_weapon.sway_amount_position + _random_sway_x) * delta,
		current_weapon.sway_speed_position * delta
	)
	weapon_model_parent.position.y = lerp(
		weapon_model_parent.position.y,
		base_pos.y + (clamped.y * current_weapon.sway_amount_position + _random_sway_y) * delta,
		current_weapon.sway_speed_position * delta
	)
	weapon_model_parent.rotation_degrees.y = lerp(
		weapon_model_parent.rotation_degrees.y,
		(clamped.x * current_weapon.sway_amount_rotation + (_random_sway_y * current_weapon.idle_sway_rotation_strength)) * delta,
		current_weapon.sway_speed_rotation * delta
	)
	weapon_model_parent.rotation_degrees.x = lerp(
		weapon_model_parent.rotation_degrees.x,
		-(clamped.y * current_weapon.sway_amount_rotation + (_random_sway_x * current_weapon.idle_sway_rotation_strength)) * delta,
		current_weapon.sway_speed_rotation * delta
	)

func _get_sway_noise() -> float:
	if not sway_noise or not sway_noise.noise:
		return 0.0
	var pos := Vector3.ZERO
	if not Engine.is_editor_hint():
		var player = get_tree().get_first_node_in_group("player")
		if player:
			pos = player.global_position
	return sway_noise.noise.get_noise_2d(pos.x, pos.y)
