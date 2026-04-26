@tool
extends EditorScript

func _run():
	for node in get_scene().find_children("*", "MeshInstance3D", true):
		node.create_trimesh_collision()
	print("Done!")
