extends Node3D

func eject() -> void:
	var shell := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.015
	mesh.height = 0.03
	shell.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.7, 0.0)
	mat.metallic = 0.8
	shell.material_override = mat

	# Spawn in world space at ejector position
	get_tree().current_scene.add_child(shell)
	shell.global_position = global_position

	# Fly right and up then fall
	var direction := global_transform.basis * Vector3(1.0, 0.8, -0.3)
	var speed := randf_range(2.0, 3.5)
	var velocity := direction * speed

	var tween := shell.create_tween()
	var gravity := Vector3(0, -9.8, 0)
	for i in 30:
		var dt := 0.05
		velocity += gravity * dt
		tween.tween_property(shell, "global_position", shell.global_position + velocity * dt, dt)
	tween.tween_callback(shell.queue_free)
