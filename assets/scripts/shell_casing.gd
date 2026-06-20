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

	var casing_packed = ResourceLoader.load("res://assets/weapons/resources/ak47/realistic_ak-47_bullet_3d_model.glb")
	print("casing loaded: ", casing_packed)
	if casing_packed:
		var casing: Node3D = (casing_packed as PackedScene).instantiate()
		casing.scale = Vector3(0.05, 0.05, 0.05)
		shell.add_child(casing)
	else:
		var mesh_inst := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.008
		mesh_inst.mesh = mesh
		shell.add_child(mesh_inst)

	var spawn_pos := global_position
	var right := global_transform.basis.x
	var up := global_transform.basis.y

	get_tree().current_scene.add_child(shell)
	shell.global_position = spawn_pos

	# Apply impulse on next frame so RigidBody is fully in the scene tree
	await get_tree().process_frame
	shell.apply_central_impulse((right * 3.0 + up * 1.0) * randf_range(1.0, 1.5))
	shell.apply_torque_impulse(global_transform.basis.z * randf_range(0.08, 0.12))

	get_tree().create_timer(3.0).timeout.connect(func(): if is_instance_valid(shell): shell.queue_free())
