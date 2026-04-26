extends Node3D

@export var map_node_path: NodePath = "Map_v12"

func _ready():
	var map = get_node_or_null(map_node_path)
	if map == null:
		print("Map node not found")
		return

	_apply_gi_to_map(map)
	_boost_materials(map)
	_reduce_brightness_25(map)

	print("Map visual boost applied (with 25% brightness reduction)")


# Make sure the map participates in GI (SDFGI or LightmapGI depending on your setup)
func _apply_gi_to_map(root):
	for child in root.get_children():
		if child is MeshInstance3D:
			child.gi_mode = MeshInstance3D.GI_MODE_STATIC
		_apply_gi_to_map(child)


# Slight realism boost: roughness, metallic, normals, specular
func _boost_materials(root):
	for child in root.get_children():
		if child is MeshInstance3D:
			var mat = child.get_active_material(0)
			if mat and mat is StandardMaterial3D:
				mat.roughness = clamp(mat.roughness + 0.1, 0.0, 1.0)
				mat.metallic = clamp(mat.metallic + 0.05, 0.0, 1.0)
				mat.normal_scale *= 1.2
				mat.specular = clamp(mat.specular + 0.1, 0.0, 1.0)
		_boost_materials(child)


# Reduce brightness by exactly 25%
func _reduce_brightness_25(root):
	for child in root.get_children():
		if child is MeshInstance3D:
			var mat = child.get_active_material(0)
			if mat and mat is StandardMaterial3D:
				mat.albedo_color = mat.albedo_color * 0.75
				mat.specular = mat.specular * 0.75
		_reduce_brightness_25(child)
