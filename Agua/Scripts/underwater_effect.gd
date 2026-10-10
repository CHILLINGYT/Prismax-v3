extends CanvasLayer
class_name UnderwaterEffect

## Applies a subtle blue underwater look when the active camera dips below the
## water surface: a translucent blue vignette plus softened fog / contrast.
## Everything fades in and out smoothly, and is fully reversible.

@export var water_level: float = -2.0
## Only water inside this area (world XZ) triggers the effect.
@export var water_area: Rect2 = Rect2(-60.0, -256.0, 572.0, 512.0)
@export var fade_speed: float = 1.8
@export var max_overlay_amount: float = 0.46
@export var max_fog_density: float = 0.0085
@export var underwater_fog_color: Color = Color(0.09, 0.34, 0.50)
@export var contrast_at_full_immersion: float = 0.82
@export var saturation_at_full_immersion: float = 0.78

@onready var _overlay: ColorRect = $Overlay

var _amount: float = 0.0
var _env: Environment = null
var _base_fog_density: float = 0.0
var _base_contrast: float = 1.0
var _base_saturation: float = 1.0


func _ready() -> void:
	_env = _find_world_environment()
	if _env != null:
		_base_fog_density = _env.fog_density
		_base_contrast = _env.adjustment_contrast
		_base_saturation = _env.adjustment_saturation
	if _overlay != null and _overlay.material is ShaderMaterial:
		(_overlay.material as ShaderMaterial).set_shader_parameter("amount", 0.0)
		_overlay.visible = false


func _process(p_delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var target: float = 0.0
	if cam != null and is_underwater(cam.global_position):
		target = 1.0
	# Exponential smoothing: quick but never instant, in either direction.
	_amount = lerp(_amount, target, 1.0 - exp(-fade_speed * p_delta))
	if _amount < 0.001:
		_amount = 0.0
	_apply()


func is_underwater(p_world_position: Vector3) -> bool:
	if p_world_position.y >= water_level:
		return false
	return water_area.has_point(Vector2(p_world_position.x, p_world_position.z))


func _apply() -> void:
	if _overlay != null:
		_overlay.visible = _amount > 0.001
		if _overlay.material is ShaderMaterial:
			(_overlay.material as ShaderMaterial).set_shader_parameter(
				"amount", _amount * max_overlay_amount
			)
	if _env == null:
		return
	_env.fog_enabled = _amount > 0.001
	_env.fog_light_color = underwater_fog_color
	_env.fog_density = _base_fog_density + _amount * max_fog_density
	_env.fog_sky_affect = lerp(1.0, 0.35, _amount)
	_env.adjustment_enabled = true
	_env.adjustment_contrast = lerp(_base_contrast, _base_contrast * contrast_at_full_immersion, _amount)
	_env.adjustment_saturation = lerp(_base_saturation, _base_saturation * saturation_at_full_immersion, _amount)


func _find_world_environment() -> Environment:
	var start: Node = get_tree().current_scene
	if start == null:
		start = get_tree().root
	var found: Array = start.find_children("*", "WorldEnvironment", true, false)
	for node in found:
		var we: WorldEnvironment = node as WorldEnvironment
		if we != null and we.environment != null:
			return we.environment
	return null
