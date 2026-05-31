## weapon_3p.gd
## Attaches the correct third-person weapon mesh to the player's right hand.
## Attach to a Node3D child of the RightHand BoneAttachment3D in player.tscn.
## On remote players this shows the weapon the other player is holding.

extends Node3D

const WEAPON_MESHES := {
	"ak47":    "res://assets/weapons/resources/Cristian-AK47.glb",
	"pistol":  "res://assets/weapons/resources/DJMaesen-deagle.glb",
	"knife":   "res://assets/weapons/resources/knife/DJ-knife.glb",
	"sniper":  "res://assets/weapons/resources/sniper/sniper_animated.glb",
}

var _current_mesh: Node3D = null
var _current_weapon_id: String = ""

func show_weapon(weapon_id: String) -> void:
	if weapon_id == _current_weapon_id:
		return
	_current_weapon_id = weapon_id

	# Remove old mesh
	if _current_mesh:
		_current_mesh.queue_free()
		_current_mesh = null

	if not WEAPON_MESHES.has(weapon_id):
		return

	var scene := load(WEAPON_MESHES[weapon_id]) as PackedScene
	if not scene:
		return

	_current_mesh = scene.instantiate()
	add_child(_current_mesh)

func hide_weapon() -> void:
	if _current_mesh:
		_current_mesh.queue_free()
		_current_mesh = null
	_current_weapon_id = ""
