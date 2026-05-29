@tool
extends EditorScript

func _run():
	var src = FileAccess.open(\"res://controllers/player.tscn\", FileAccess.READ)
	var content = src.get_as_text()
	src.close()
	var dst = FileAccess.open(\"res://controllers/player_BACKUP_pre_mesh_swap.tscn\", FileAccess.WRITE)
	dst.store_string(content)
	dst.close()
	print(\"Backup saved to res://controllers/player_BACKUP_pre_mesh_swap.tscn\")
