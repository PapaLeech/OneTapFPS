@tool
extends EditorScript

func _run():
	var scene = load('res://Characters/Terrorist/Meshy_AI_Tactical_Stance_biped_Character_output.glb')
	var inst = scene.instantiate()
	_print_tree(inst, '')
	inst.queue_free()
	print('=== DONE ===')

func _print_tree(node: Node, indent: String):
	print(indent + node.name + ' [' + node.get_class() + ']')
	for child in node.get_children():
		_print_tree(child, indent + '  ')

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null
	var files = [
		"res://Characters/Swat/Animations/Idle.fbx",
		"res://Characters/Swat/Animations/Walking.fbx",
		"res://Characters/Swat/Animations/Sprint.fbx",
		"res://Characters/Swat/Animations/Walking Backwards.fbx",
		"res://Characters/Swat/Animations/Crouch Walking.fbx",
		"res://Characters/Player/Meshy_AI_Tactical_Stance_biped_Character_output.glb",
		"res://Characters/Player/Meshy_AI_Tactical_Stance_biped_Animation_Walking_withSkin.glb",
		"res://Characters/Player/Meshy_AI_Tactical_Stance_biped_Animation_Running_withSkin.glb",
		"res://Characters/Player/Meshy_AI_Tactical_Stance_biped_Animation_Dead_withSkin.glb",
		"res://Characters/Player/Meshy_AI_Tactical_Stance_biped_Animation_Crouch_Walk_Left_with_Gun_withSkin.glb",
	]
	for f in files:
		var scene = load(f)
		if not scene:
			print("%s => FAILED TO LOAD" % f.get_file())
			continue
		var inst = scene.instantiate()
		var skel = _find_skeleton(inst)
		var ap = inst.find_child("AnimationPlayer", true, false)
		var anim_names = ap.get_animation_list() if ap else []
		var root_bone = skel.get_bone_name(0) if skel else "NO SKELETON"
		print("%s => root_bone=%s anims=%s" % [f.get_file(), root_bone, anim_names])
		inst.queue_free()
	print("=== DONE ===")

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null
