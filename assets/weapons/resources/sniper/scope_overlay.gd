extends CanvasLayer

@onready var overlay: ColorRect = $ScopeOverlay

func _ready() -> void:
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/weapons/resources/sniper/scope.gdshader")
	overlay.material = mat
	overlay.visible = false

func show_scope() -> void:
	overlay.visible = true

func hide_scope() -> void:
	overlay.visible = false
