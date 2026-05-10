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

@export var scope_overlay: Node

var current_weapon_model: Node3D
var _anim_player: AnimationPlayer
var _gun_sound: AudioStreamPlayer3D
var _bolt_sound: AudioStreamPlayer3D
var _scope_overlay: Node
var _sound_tween: Tween
var _is_aiming: bool = false
var _is_firing: bool = false
var _is_firing_locked: bool = false
var _is_reloading: bool = false
var _is_sprinting: bool = false
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
	_scope_overlay = get_parent().get_parent().get_node_or_null("ScopeUI")
	print("scope overlay: ", _scope_overlay)

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
	_is_firing_locked = false
	_fire_timer = 0.0
	if _anim_player:
		_anim_player.stop()
	spawn_weapon_model()

func _physics_process(delta):
	if not _scope_overlay:
		_scope_overlay = scope_overlay
		print("scope overlay assigned: ", _scope_overlay)
	_is_aiming = Input.is_action_pressed("aim")
	if _is_aiming:
		print("aiming, scope overlay: ", _scope_overlay, " current weapon: ", current_weapon.weapon_name if current_weapon else "none", " has_scope: ", current_weapon.has_scope if current_weapon else "none")
	_mouse_movement = _mouse_movement.lerp(Vector2.ZERO, 10 * delta)

	# Scope overlay for sniper
	if _scope_overlay and current_weapon:
		if _is_aiming and current_weapon.has_scope:
			_scope_overlay.show_scope()
			if current_weapon_model:
				current_weapon_model.visible = false
		else:
			_scope_overlay.hide_scope()
			if current_weapon_model:
				current_weapon_model.visible = true
	
	if current_weapon:
		_sway_weapon(delta)

	# Sprint animation
	if current_weapon and not _is_reloading and not _is_firing_locked and not _is_meleeing:
		var sprinting = Input.is_action_pressed("sprint") and Input.is_action_pressed("move_forward")
		if sprinting and not _is_sprinting:
			_is_sprinting = true
			if current_weapon.has_sprint_anim:
				_create_sprint_animation()
				if _anim_player and _anim_player.has_animation("sprint_lib/sprint"):
					_anim_player.stop()
					_anim_player.play("sprint_lib/sprint")
		elif not sprinting and _is_sprinting:
			_is_sprinting = false
			if current_weapon.has_sprint_anim and _anim_player and _anim_player.has_animation("fire_lib/fire"):
				_anim_player.play("fire_lib/fire")
				_anim_player.seek(0.0, true)
				_anim_player.pause()
	# Sprint tilt on weapon_model_parent
	if weapon_model_parent and current_weapon:
		var target_pos := current_weapon.weapon_position
		if _is_sprinting:
			var bob_time := Time.get_ticks_msec() / 1000.0
			var bob_y := sin(bob_time * current_weapon.sprint_bob_speed) * current_weapon.sprint_bob_y
			var bob_x := sin(bob_time * current_weapon.sprint_bob_speed * 0.5) * current_weapon.sprint_bob_x
			var bob_z := sin(bob_time * current_weapon.sprint_bob_speed * 0.5 + current_weapon.sprint_bob_direction) * current_weapon.sprint_bob_y
			target_pos += current_weapon.sprint_position_offset + Vector3(bob_x, bob_y, bob_z)
		# Gentle idle sway side to side
		var sway_time := Time.get_ticks_msec() / 1000.0
		var sway_x := sin(sway_time * 0.8) * 0.004
		var sway_y := cos(sway_time * 0.8) * 0.003
		target_pos += Vector3(sway_x, sway_y, 0.0)
		weapon_model_parent.position = weapon_model_parent.position.lerp(target_pos, 8.0 * delta)

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
		if Input.is_action_just_pressed("fire") and not _is_firing_locked:
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
		_bolt_sound = current_weapon_model.find_child("BoltSoundPlayer", true, false)
		if _bolt_sound and current_weapon.bolt_sound:
			_bolt_sound.stream = current_weapon.bolt_sound
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
		if current_weapon and not current_weapon.full_auto:
			_is_firing_locked = true
			var anim_length: float = _anim_player.get_animation("fire_lib/fire").length
			get_tree().create_timer(anim_length).timeout.connect(func(): _is_firing_locked = false)
	if _gun_sound and current_weapon.fire_sound and not current_weapon.full_auto:
		if _sound_tween:
			_sound_tween.kill()
		_gun_sound.stop()
		_gun_sound.stream = current_weapon.fire_sound
		_gun_sound.volume_db = 0.0
		_gun_sound.play()
		if _bolt_sound and current_weapon.bolt_sound:
			var fire_length: float = current_weapon.fire_sound.get_length() - 2.0
			get_tree().create_timer(fire_length).timeout.connect(func():
				if _bolt_sound and not _bolt_sound.playing:
					_bolt_sound.play()
			)
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
	if not current_weapon:
		return
	_is_meleeing = true
	_is_firing = false
	if _gun_sound and _gun_sound.playing:
		if _sound_tween:
			_sound_tween.kill()
		_gun_sound.stop()
	# Find knife weapon
	var melee_weapon := current_weapon
	for w in weapons:
		if w.is_melee:
			melee_weapon = w
			break
	var melee_length: float = melee_weapon.anim_melee_end - melee_weapon.anim_melee_start
	if melee_weapon != current_weapon:
		# Swap to knife temporarily
		var saved_weapon := current_weapon
		var saved_index := _current_index
		current_weapon = melee_weapon
		spawn_weapon_model()
		if _anim_player:
			_create_melee_animation_from(melee_weapon, _anim_player)
		if _anim_player and _anim_player.has_animation("melee_lib/melee"):
			_anim_player.stop()
			_anim_player.play("melee_lib/melee")
		if _gun_sound and melee_weapon.melee_sound:
			_gun_sound.volume_db = 0.0
			_gun_sound.stream = melee_weapon.melee_sound
			_gun_sound.play()
		get_tree().create_timer(melee_length).timeout.connect(func():
			current_weapon = saved_weapon
			_current_index = saved_index
			spawn_weapon_model()
			_on_melee_finished()
		)
	else:
		# Already on knife
		if _anim_player:
			_create_melee_animation_from(melee_weapon, _anim_player)
		if _anim_player and _anim_player.has_animation("melee_lib/melee"):
			_anim_player.stop()
			_anim_player.play("melee_lib/melee")
		if _gun_sound and melee_weapon.melee_sound:
			_gun_sound.volume_db = 0.0
			_gun_sound.stream = melee_weapon.melee_sound
			_gun_sound.play()
		get_tree().create_timer(melee_length).timeout.connect(_on_melee_finished)

func _on_melee_finished() -> void:
	_is_meleeing = false
	if _gun_sound and current_weapon.fire_sound:
		_gun_sound.stream = current_weapon.fire_sound

func _create_melee_animation_from(melee_weapon: Weapon, anim_player: AnimationPlayer) -> void:
	if anim_player.has_animation_library("melee_lib"):
		anim_player.remove_animation_library("melee_lib")
	var anim_name := anim_player.get_animation_list()[0] if anim_player.get_animation_list().size() > 0 else ""
	if anim_name == "":
		return
	var source := anim_player.get_animation(anim_name)
	if not source:
		return
	var start := melee_weapon.anim_melee_start
	var end := melee_weapon.anim_melee_end
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

func _create_sprint_animation() -> void:
	if _anim_player.has_animation_library("sprint_lib"):
		_anim_player.remove_animation_library("sprint_lib")
	var anim_name := _anim_player.get_animation_list()[0] if _anim_player.get_animation_list().size() > 0 else ""
	if anim_name == "":
		return
	var source := _anim_player.get_animation(anim_name)
	if not source:
		return
	var start := current_weapon.anim_sprint_start
	var end := current_weapon.anim_sprint_end
	var sprint_anim := Animation.new()
	sprint_anim.length = end - start
	sprint_anim.loop_mode = Animation.LOOP_LINEAR
	for i in source.get_track_count():
		var track_type := source.track_get_type(i)
		var track_path := source.track_get_path(i)
		var new_track := sprint_anim.add_track(track_type)
		sprint_anim.track_set_path(new_track, track_path)
		for j in source.track_get_key_count(i):
			var key_time := source.track_get_key_time(i, j)
			if key_time < start:
				continue
			if key_time > end:
				break
			var key_value: Variant = source.track_get_key_value(i, j) as Variant
			var key_transition := source.track_get_key_transition(i, j)
			sprint_anim.track_insert_key(new_track, key_time - start, key_value, key_transition)
	var lib := AnimationLibrary.new()
	lib.add_animation("sprint", sprint_anim)
	_anim_player.add_animation_library("sprint_lib", lib)

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
	if _is_aiming:
		base_pos += current_weapon.ads_position_offset

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
		(clamped.x * current_weapon.sway_amount_rotation + (_random_sway_y * current_weapon.idle_sway_rotation_strength)) * delta + (current_weapon.sprint_tilt_y if _is_sprinting else 0.0) + (current_weapon.ads_rotation_offset.y if _is_aiming else 0.0),
		current_weapon.sway_speed_rotation * delta
	)
	weapon_model_parent.rotation_degrees.x = lerp(
		weapon_model_parent.rotation_degrees.x,
		-(clamped.y * current_weapon.sway_amount_rotation + (_random_sway_x * current_weapon.idle_sway_rotation_strength)) * delta + (current_weapon.sprint_tilt_x if _is_sprinting else 0.0) + (current_weapon.ads_rotation_offset.x if _is_aiming else 0.0),
		current_weapon.sway_speed_rotation * delta
	)
	weapon_model_parent.rotation_degrees.z = lerp(
		weapon_model_parent.rotation_degrees.z,
		(clamped.x * current_weapon.sway_amount_rotation * 0.5) * delta + (current_weapon.sprint_tilt_z if _is_sprinting else 0.0) + (current_weapon.ads_rotation_offset.z if _is_aiming else 0.0),
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
