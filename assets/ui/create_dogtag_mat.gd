@tool
extends EditorScript

func _run() -> void:
	var shader := load("res://assets/ui/dogtag_black_remove.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("threshold", 0.35)
	ResourceSaver.save(mat, "res://assets/ui/dogtag_shader_mat.tres")
	print("Saved dogtag_shader_mat.tres")
