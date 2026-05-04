class_name WeaponController extends Node

@export var current_weapon: Weapon
@export var weapon_model_parent: Node3D

# Reference to gun.gd on WeaponHolder for recoil
@export var gun: Node3D

# ADS recoil multiplier — lower = less recoil when aiming
@export var ads_recoil_multiplier: float = 0.5

var current_weapon_model: Node3D
var _is_aiming: bool = false

func _ready() -> void:
	if current_weapon:
		spawn_weapon_model()

func _physics_process(_delta):
	_is_aiming = Input.is_action_pressed("aim")
	
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

func fire():
	if not gun:
		return
	if _is_aiming:
		gun.recoil_amplitude *= ads_recoil_multiplier
		gun.apply_recoil()
		gun.recoil_amplitude /= ads_recoil_multiplier
	else:
		gun.apply_recoil()
