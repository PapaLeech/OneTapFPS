class_name Weapon extends Resource

@export var weapon_name: String = "Pistol"
@export var damage: float = 25.0
@export var max_ammo: int = 12
@export var weapon_model: PackedScene
@export var weapon_position: Vector3 = Vector3(0.2, -0.2, -0.3)

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
