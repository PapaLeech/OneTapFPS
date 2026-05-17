class_name Weapon extends Resource

@export var weapon_name: String = "Pistol"
@export var damage: float = 25.0
@export var max_ammo: int = 12
@export var total_mags: int = 3
@export var weapon_model: PackedScene
@export var weapon_position: Vector3 = Vector3(0.2, -0.2, -0.3)
@export var weapon_rotation: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var weapon_scale: Vector3 = Vector3(1.0, 1.0, 1.0)

# Fire settings
@export_group("Fire")
@export var fire_sound: AudioStream
@export var bolt_sound: AudioStream
@export var full_auto: bool = false
@export var fire_rate: float = 0.1
@export var anim_fire_start: float = 0.0
@export var anim_fire_end: float = 0.5

# Reload settings
@export_group("Reload")
@export var reload_sound: AudioStream
@export var anim_reload_start: float = 0.0
@export var anim_reload_end: float = 3.0

# Melee settings
@export_group("Melee")
@export var is_melee: bool = false
@export var melee_sound: AudioStream
@export var anim_melee_start: float = 0.0
@export var anim_melee_end: float = 0.7

# Sprint settings
@export_group("Sprint")
@export var has_sprint_anim: bool = false
@export var anim_sprint_start: float = 0.0
@export var anim_sprint_end: float = 1.0
@export var sprint_position_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var sprint_tilt_x: float = -50.0
@export var sprint_tilt_y: float = 0.0
@export var sprint_tilt_z: float = -20.0
@export var sprint_bob_x: float = 0.06
@export var sprint_bob_y: float = 0.015
@export var sprint_bob_speed: float = 4.0
@export var sprint_bob_direction: float = 1.5

# ADS settings
@export_group("ADS")
@export var has_scope: bool = false
@export var ads_position_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var ads_rotation_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var ads_fov: float = 55.0
@export var ads_speed: float = 12.0

# Sway settings
@export_group("Sway")
@export var sway_min: Vector2 = Vector2(-2.0, -2.0)
@export var sway_max: Vector2 = Vector2(2.0, 2.0)
@export var sway_amount_position: float = 0.002
@export var sway_speed_position: float = 6.0
@export var sway_amount_rotation: float = 0.05
@export var sway_speed_rotation: float = 6.0
@export var idle_sway_adjustment: float = 1.0
@export var idle_sway_rotation_strength: float = 0.5
@export var random_sway_amount: float = 100.0
