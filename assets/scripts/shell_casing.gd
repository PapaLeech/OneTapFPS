extends Node3D

func eject() -> void:
	var shell := RigidBody3D.new()
	shell.gravity_scale = 1.0
	shell.linear_damp = 0.2
	shell.collision_layer = 2
	shell.collision_mask = 2

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.008
	col.shape = shape
	shell.add_child(col)

	var casing_packed = ResourceLoader.load("res://assets/weapons/resources/ak47/bullet_casing_trimmed.tscn")
	print("casing loaded: ", casing_packed)
	if casing_packed:
		var casing: Node3D = (casing_packed as PackedScene).instantiate()
		casing.scale = Vector3(0.028125, 0.028125, 0.028125)
		casing.rotation_degrees = Vector3(0, 0, -90)
		shell.add_child(casing)
	else:
		var mesh_inst := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.008
		mesh_inst.mesh = mesh
		shell.add_child(mesh_inst)

	var spawn_pos := global_position
	var cam := get_viewport().get_camera_3d()
	var right := (cam.global_transform.basis.x.normalized() * 0.05) if cam else global_transform.basis.x
	var up := global_transform.basis.y

	get_tree().current_scene.add_child(shell)
	shell.global_position = spawn_pos

	var player := get_tree().get_first_node_in_group("player")
	if player and player is CharacterBody3D:
		shell.linear_velocity = player.velocity

	# Apply impulse on next frame so RigidBody is fully in the scene tree
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(shell):
		return
	shell.apply_central_impulse((right * 0.5 - up * 0.3) * randf_range(1.0, 1.5))
	shell.apply_torque_impulse(-global_transform.basis.y * randf_range(0.08, 0.12))

	get_tree().create_timer(3.0).timeout.connect(func(): if is_instance_valid(shell): shell.queue_free())
