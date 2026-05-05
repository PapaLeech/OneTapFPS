class_name Weapon extends Resource

@export var weapon_name: String = "Pistol"
@export var damage: float = 25.0
@export var max_ammo: int = 12
@export var weapon_model: PackedScene
@export var weapon_position: Vector3 = Vector3(0.2, -0.2, -0.3)
@export var weapon_scale: Vector3 = Vector3(1.0, 1.0, 1.0)

# Fire settings
@export_group("Fire")
@export var full_auto: bool = false
@export var fire_rate: float = 0.1
@export var anim_fire_start: float = 0.0
@export var anim_fire_end: float = 0.5

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
