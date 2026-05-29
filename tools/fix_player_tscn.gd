@tool
extends EditorScript

func _run():
	var path = "res://controllers/player.tscn"
	var f = FileAccess.open(path, FileAccess.READ)
	var content = f.get_as_text()
	f.close()
	
	# Fix all remaining old skeleton paths
	content = content.replace(
		"CollisionShape3D/PlayerModel/Sketchfab_model/Generic_Item_mesh (2)_fbx/Object_2/RootNode/Object_4/Skeleton3D",
		"CollisionShape3D/PlayerModel/Sketchfab_model/root/GLTF_SceneRootNode/ArmatureSoldier_43/GLTF_created_0/Skeleton3D"
	)
	
	# Fix bone names and indices
	content = content.replace("bone_name = \"spine upper_012\"\nbone_idx = 12", "bone_name = \"Spinelower_11\"\nbone_idx = 1")
	content = content.replace("bone_name = \"arm left shoulder 2_017\"\nbone_idx = 17", "bone_name = \"ArmUpper.L_3\"\nbone_idx = 5")
	content = content.replace("bone_name = \"arm right shoulder 2_031\"\nbone_idx = 32", "bone_name = \"ArmUpper.R_5\"\nbone_idx = 7")
	content = content.replace("bone_name = \"leg left thigh_03\"\nbone_idx = 3", "bone_name = \"LegThigh.L_8\"\nbone_idx = 9")
	content = content.replace("bone_name = \"leg right thigh_07\"\nbone_idx = 7", "bone_name = \"LegThigh.R_10\"\nbone_idx = 11")
	content = content.replace("bone_name = \"arm left elbow_00\"\nbone_idx = 18", "bone_name = \"ArmLower.L_2\"\nbone_idx = 6")
	content = content.replace("bone_name = \"arm right elbow_032\"\nbone_idx = 33", "bone_name = \"ArmLower.R_4\"\nbone_idx = 8")
	content = content.replace("bone_name = \"arm left wrist_018\"\nbone_idx = 19", "bone_name = \"HandWrist.L_21\"\nbone_idx = 18")
	content = content.replace("bone_name = \"arm right wrist_033\"\nbone_idx = 34", "bone_name = \"HandWrist.R_31\"\nbone_idx = 28")
	content = content.replace("bone_name = \"leg left ankle_05\"\nbone_idx = 5", "bone_name = \"Foot.L_13\"\nbone_idx = 14")
	content = content.replace("bone_name = \"leg right ankle_09\"\nbone_idx = 9", "bone_name = \"Foot.R_23\"\nbone_idx = 24")
	content = content.replace("bone_name = \"leg left knee_04\"\nbone_idx = 4", "bone_name = \"LegShin.L_7\"\nbone_idx = 10")
	content = content.replace("bone_name = \"leg right knee_08\"\nbone_idx = 8", "bone_name = \"LegShin.R_9\"\nbone_idx = 12")
	
	# Remove old AnimationPlayer libraries
	var lines = content.split("\n")
	var out = []
	for line in lines:
		if line.begins_with("libraries/") or line.begins_with("next/mixamo_com"):
			continue
		out.append(line)
	
	var fw = FileAccess.open(path, FileAccess.WRITE)
	fw.store_string("\n".join(out))
	fw.close()
	print("=== DONE ===")
