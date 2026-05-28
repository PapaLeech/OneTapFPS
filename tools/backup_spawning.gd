@tool
extends EditorScript

func _run():
	var files = [
		"res://scripts/server.gd",
		"res://scripts/DedicatedServer.gd",
		"res://scripts/ClientToServer.gd",
		"res://levels/level_001.gd",
	]
	for path in files:
		var src = FileAccess.open(path, FileAccess.READ)
		if not src:
			print("FAILED to open: " + path)
			continue
		var content = src.get_as_text()
		src.close()
		var backup_path = path.replace(".gd", "_BACKUP_spawning.gd")
		var dst = FileAccess.open(backup_path, FileAccess.WRITE)
		dst.store_string(content)
		dst.close()
		print("Backed up: " + backup_path)
	print("=== DONE ===")