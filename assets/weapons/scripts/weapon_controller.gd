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
var _sound_tween: Tween
var _is_aiming: bool = false
var _is_firing: bool = false
var _is_reloading: bool = false
var _is_meleeing: bool = false
var _fire_timer: float = 0.0
var _current_index: int = 0
var _current_ammo: int = 0
var _mouse_movement: Vector2
var _random_sway_x: float
var _random_sway_y: float
var _sway_time: float = 0.0

func _ready() -> void:
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

	if Input.is_action_just_pressed("reload") and not _is_reloading:
		_start_reload()
		return

	if _is_reloading:
		return

	if (Input.is_action_just_pressed("melee") or (Input.is_action_just_pressed("fire") and current_weapon and current_weapon.is_melee)) and not _is_meleeing and current_weapon:
		_start_melee()
		return

	if _is_meleeing:
		return

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
				if _gun_sound and not _gun_sound.playing:
					if _sound_tween:
						_sound_tween.kill()
					_gun_sound.volume_db = 0.0
					_gun_sound.play()
					var clip_length: float = _gun_sound.stream.get_length()
					var fade_duration: float = 0.3
					get_tree().create_timer(clip_length - fade_duration).timeout.connect(
						func(): _fade_out_fire_sound(fade_duration)
					)
		else:
			if _is_firing:
				_is_firing = false
				_fire_timer = 0.0
				if _anim_player:
					_anim_player.stop()
				if _gun_sound and _gun_sound.playing:
					_sound_tween = create_tween()
					_sound_tween.tween_property(_gun_sound, "volume_db", -40.0, 0.3)
					_sound_tween.tween_callback(_gun_sound.stop)
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
		current_weapon_model.rotation_degrees = current_weapon.weapon_rotation
		current_weapon_model.scale = current_weapon.weapon_scale
		_current_ammo = current_weapon.max_ammo
		_anim_player = current_weapon_model.find_child("AnimationPlayer", true, false)
		_gun_sound = current_weapon_model.find_child("AudioStreamPlayer3D", true, false)
		if _gun_sound and current_weapon.fire_sound:
			_gun_sound.stream = current_weapon.fire_sound
			if not _gun_sound.finished.is_connected(_on_fire_sound_finished):
				_gun_sound.finished.connect(_on_fire_sound_finished)
		if _anim_player:
			_create_fire_animation()
			if _anim_player.has_animation("fire_lib/fire"):
				_anim_player.play("fire_lib/fire")
				_anim_player.seek(0.0, true)
				_anim_player.pause()

func fire():
	if not gun:
		return
	if _anim_player and _anim_player.has_animation("fire_lib/fire"):
		_anim_player.stop()
		_anim_player.play("fire_lib/fire")
	if _gun_sound and current_weapon.fire_sound and not current_weapon.full_auto:
		if _sound_tween:
			_sound_tween.kill()
		_gun_sound.stop()
		_gun_sound.stream = current_weapon.fire_sound
		_gun_sound.volume_db = 0.0
		_gun_sound.play()
	if _is_aiming:
		gun.recoil_amplitude *= ads_recoil_multiplier
		gun.apply_recoil()
		gun.recoil_amplitude /= ads_recoil_multiplier
	else:
		gun.apply_recoil()
	if current_weapon and not current_weapon.is_melee:
		_current_ammo -= 1
		if _current_ammo <= 0 and not current_weapon.full_auto:
			_start_reload()

func _start_reload() -> void:
	if not _anim_player or not current_weapon:
		return
	_is_reloading = true
	_is_firing = false
	if _gun_sound and _gun_sound.playing:
		if _sound_tween:
			_sound_tween.kill()
		_gun_sound.stop()
	if _gun_sound and current_weapon.reload_sound:
		_gun_sound.volume_db = 0.0
		_gun_sound.stream = current_weapon.reload_sound
		_gun_sound.play()
	_create_reload_animation()
	if _anim_player.has_animation("reload_lib/reload"):
		_anim_player.stop()
		_anim_player.play("reload_lib/reload")
		var reload_length: float = _anim_player.get_animation("reload_lib/reload").length
		get_tree().create_timer(reload_length).timeout.connect(_on_reload_finished)

func _on_reload_finished() -> void:
	_is_reloading = false
	_current_ammo = current_weapon.max_ammo if current_weapon else 0
	if _gun_sound and current_weapon.fire_sound:
		_gun_sound.stream = current_weapon.fire_sound
	if _anim_player and _anim_player.has_animation("fire_lib/fire"):
		_anim_player.play("fire_lib/fire")
		_anim_player.seek(0.0, true)
		_anim_player.pause()

func _start_melee() -> void:
	if not _anim_player or not current_weapon:
		return
	_is_meleeing = true
	_is_firing = false
	if _gun_sound and _gun_sound.playing:
		if _sound_tween:
			_sound_tween.kill()
		_gun_sound.stop()
	_create_melee_animation()
	if _anim_player.has_animation("melee_lib/melee"):
		_anim_player.stop()
		_anim_player.play("melee_lib/melee")
		if _gun_sound and current_weapon.melee_sound:
			_gun_sound.volume_db = 0.0
			_gun_sound.stream = current_weapon.melee_sound
			_gun_sound.play()
		var melee_length: float = _anim_player.get_animation("melee_lib/melee").length
		get_tree().create_timer(melee_length).timeout.connect(_on_melee_finished)

func _on_melee_finished() -> void:
	_is_meleeing = false
	if _gun_sound and current_weapon.fire_sound:
		_gun_sound.stream = current_weapon.fire_sound

func _create_melee_animation() -> void:
	if _anim_player.has_animation_library("melee_lib"):
		_anim_player.remove_animation_library("melee_lib")
	var anim_name := _anim_player.get_animation_list()[0] if _anim_player.get_animation_list().size() > 0 else ""
	if anim_name == "":
		return
	var source := _anim_player.get_animation(anim_name)
	if not source:
		return
	var start := current_weapon.anim_melee_start
	var end := current_weapon.anim_melee_end
	var melee_anim := Animation.new()
	melee_anim.length = end - start
	melee_anim.loop_mode = Animation.LOOP_NONE
	for i in source.get_track_count():
		var track_type := source.track_get_type(i)
		var track_path := source.track_get_path(i)
		var new_track := melee_anim.add_track(track_type)
		melee_anim.track_set_path(new_track, track_path)
		for j in source.track_get_key_count(i):
			var key_time := source.track_get_key_time(i, j)
			if key_time < start:
				continue
			if key_time > end:
				break
			var key_value: Variant = source.track_get_key_value(i, j) as Variant
			var key_transition := source.track_get_key_transition(i, j)
			melee_anim.track_insert_key(new_track, key_time - start, key_value, key_transition)
	var lib := AnimationLibrary.new()
	lib.add_animation("melee", melee_anim)
	_anim_player.add_animation_library("melee_lib", lib)

func _on_fire_sound_finished() -> void:
	if current_weapon and current_weapon.fire_sound and _gun_sound and not current_weapon.full_auto:
		_gun_sound.stream = current_weapon.fire_sound

func _fade_out_fire_sound(duration: float) -> void:
	if _gun_sound and _gun_sound.playing:
		if _sound_tween:
			_sound_tween.kill()
		_sound_tween = create_tween()
		_sound_tween.tween_property(_gun_sound, "volume_db", -40.0, duration)
		_sound_tween.tween_callback(func():
			_gun_sound.stop()
			if not _is_reloading and current_weapon and current_weapon.full_auto:
				_start_reload()
		)

func _create_reload_animation() -> void:
	if _anim_player.has_animation_library("reload_lib"):
		_anim_player.remove_animation_library("reload_lib")
	var anim_name := _anim_player.get_animation_list()[0] if _anim_player.get_animation_list().size() > 0 else ""
	if anim_name == "":
		return
	var source := _anim_player.get_animation(anim_name)
	if not source:
		return
	var start := current_weapon.anim_reload_start
	var end := current_weapon.anim_reload_end
	var reload_anim := Animation.new()
	reload_anim.length = end - start
	reload_anim.loop_mode = Animation.LOOP_NONE
	for i in source.get_track_count():
		var track_type := source.track_get_type(i)
		var track_path := source.track_get_path(i)
		var new_track := reload_anim.add_track(track_type)
		reload_anim.track_set_path(new_track, track_path)
		for j in source.track_get_key_count(i):
			var key_time := source.track_get_key_time(i, j)
			if key_time < start:
				continue
			if key_time > end:
				break
			var key_value: Variant = source.track_get_key_value(i, j) as Variant
			var key_transition := source.track_get_key_transition(i, j)
			reload_anim.track_insert_key(new_track, key_time - start, key_value, key_transition)
	var lib := AnimationLibrary.new()
	lib.add_animation("reload", reload_anim)
	_anim_player.add_animation_library("reload_lib", lib)

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
