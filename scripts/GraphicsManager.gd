extends Node

## GraphicsManager — applies Low / Medium / High graphics presets.
## Saved per-player via PresenceManager.save_setting / load_setting.

enum Preset { LOW, MEDIUM, HIGH }

const PRESET_NAMES := ["Low", "Medium", "High"]

# Called once at startup from _ready, and whenever the player changes preset.
func apply_preset(preset: int) -> void:
	match preset:
		Preset.LOW:
			_apply_low()
		Preset.MEDIUM:
			_apply_medium()
		Preset.HIGH:
			_apply_high()

func _apply_low() -> void:
	var vp := get_tree().root
	vp.scaling_3d_scale = 0.75
	vp.msaa_3d = Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(512, true)
	Engine.max_fps = 60

func _apply_medium() -> void:
	var vp := get_tree().root
	vp.scaling_3d_scale = 1.0
	vp.msaa_3d = Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	Engine.max_fps = 0

func _apply_high() -> void:
	var vp := get_tree().root
	vp.scaling_3d_scale = 1.0
	vp.msaa_3d = Viewport.MSAA_2X
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	Engine.max_fps = 0

func save_preset(preset: int) -> void:
	PresenceManager.save_setting("graphics_preset", preset)

func load_and_apply() -> void:
	# Default to HIGH so existing players are unaffected
	var saved : int = PresenceManager.load_setting("graphics_preset", Preset.HIGH)
	apply_preset(saved)

func current_preset() -> int:
	return PresenceManager.load_setting("graphics_preset", Preset.HIGH)
