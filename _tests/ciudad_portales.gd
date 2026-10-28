class_name CiudadPortales
extends CiudadFalsa
## Ciudad de mentira CON PORTALES: los mismos datos que el generador real deja en
## `prueba_portales` / `prueba_portales_dir` (posición y hacia dónde da cada puerta).
## Los tres portales están a distancias bien distintas del origen para poder
## comprobar que la casa de Leo elige la puerta MÁS CERCANA.

var prueba_portales: Array[Vector3] = [
	Vector3(8.0, 0.0, 0.0),
	Vector3(30.0, 0.0, 0.0),
	Vector3(-60.0, 0.0, 0.0),
]
var prueba_portales_dir: Array[Vector3] = [
	Vector3.LEFT, Vector3.LEFT, Vector3.LEFT,
]
var prueba_portales_frente: Array[float] = [0.2, 0.2, 0.2]


func _init() -> void:
	_est["portales"] = prueba_portales.size()