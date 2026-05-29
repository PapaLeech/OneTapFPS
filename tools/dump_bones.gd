@tool
extends EditorScript

func _run():
	var path = "res://controllers/player.tscn"
	var f = FileAccess.open(path, FileAccess.READ)
	var content = f.get_as_text()
	f.close()

	var hitboxes = [
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxHead", "1660210420", "SphereShape3D_3og01", "590186302"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxSpine", "1052779222", "CapsuleShape3D_3og01", "2086724427"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxLeftArm", "219803342", "CapsuleShape3D_fyafc", "1669897510"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxRightArm", "815245665", "CapsuleShape3D_tg6sc", "1991057198"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxLeftLeg", "2127274944", "CapsuleShape3D_yvtcv", "327702318"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxRightLeg", "1668127758", "CapsuleShape3D_h7h5r", "2121021120"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxLeftForearm", "1680663162", "CapsuleShape3D_fdopr", "2130464404"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxRightForearm", "1194111266", "CapsuleShape3D_5b0ob", "1823935832"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxLeftHand", "695193422", "CapsuleShape3D_5s75f", "1610300895"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxRightHand", "2057132999", "CapsuleShape3D_bygp4", "1337758955"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxLeftFoot", "1065531772", "CapsuleShape3D_rcx31", "1756693078"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxRightFoot", "134149152", "CapsuleShape3D_57us7", "1878547194"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxLeftCalf", "1664787128", "CapsuleShape3D_5hww7", "2088922165"],
		["CollisionShape3D/PlayerModel/Armature/Skeleton3D/HitboxRightCalf", "1818586389", "CapsuleShape3D_1mod5", "372468557"],
	]

	for h in hitboxes:
		var parent = h[0]
		var cs_uid = h[1]
		var shape = h[2]
		var area_uid = h[3]

		var old_block = "[node name=\"CollisionShape3D\" type=\"CollisionShape3D\" parent=\"" + parent + "\" unique_id=" + cs_uid + "]\nshape = SubResource(\"" + shape + "\")\n\n[node name=\"Area3D\" type=\"Area3D\" parent=\"" + parent + "\" unique_id=" + area_uid + " groups=[\"enemy\"]]\nscript = ExtResource(\"3_3og01\")"

		var new_block = "[node name=\"Area3D\" type=\"Area3D\" parent=\"" + parent + "\" unique_id=" + area_uid + " groups=[\"enemy\"]]\nscript = ExtResource(\"3_3og01\")\n\n[node name=\"CollisionShape3D\" type=\"CollisionShape3D\" parent=\"" + parent + "/Area3D\" unique_id=" + cs_uid + "]\nshape = SubResource(\"" + shape + "\")"

		content = content.replace(old_block, new_block)

	var fw = FileAccess.open(path, FileAccess.WRITE)
	fw.store_string(content)
	fw.close()
	print("=== DONE ===")
