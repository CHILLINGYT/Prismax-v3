class_name CapaVelocidad
extends CanvasLayer

# Controla la intensidad del post-proceso de supervelocidad (shader de pantalla).

var _material: ShaderMaterial
var _intensidad: float = 0.0
var _objetivo: float = 0.0
var _velocidad_subida: float = 6.0
var _velocidad_bajada: float = 3.0
var _tiempo: float = 0.0

func _ready() -> void:
	var cr := get_node_or_null("Distorsion") as ColorRect
	if cr != null:
		_material = cr.material as ShaderMaterial

func set_intensidad(v: float) -> void:
	_objetivo = clampf(v, 0.0, 1.0)

func intensidad_actual() -> float:
	return _intensidad

func _process(delta: float) -> void:
	_tiempo += delta
	var vel := _velocidad_subida if _objetivo > _intensidad else _velocidad_bajada
	_intensidad = move_toward(_intensidad, _objetivo, delta * vel)
	if _material != null:
		_material.set_shader_parameter("intensidad", _intensidad)
		_material.set_shader_parameter("tiempo", _tiempo)
