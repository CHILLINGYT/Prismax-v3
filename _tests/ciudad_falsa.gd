class_name CiudadFalsa
extends Node3D
## Ciudad de mentira para las pruebas de colocación: expone EXACTAMENTE los mismos
## datos que el colocador lee del generador real (`_trazado`, `_est` y
## `_obstaculos_peatones`), con medidas de una ciudad normal (calzada 6 m, acera 3,
## manzana 12, paso 24). No genera nada: sólo responde a lo que se le pregunta.

var _trazado := {
	"calzada": 6.0,
	"acera": 3.0,
	"hw": 6.0,
	"manzana": 12.0,
	"paso": 24.0,
	"ext": Vector2(144.0, 120.0),
	"off": Vector2(-72.0, -60.0),
}
var _est := {"ciudad_lista": 1}
var _obstaculos_peatones: Array = []   ## mismo formato: {"x", "z", "r"}


func obstaculos() -> Array:
	return _obstaculos_peatones


## El generador real marca con `_est["ciudad_lista"]` que ya ha cerrado la ciudad.
func ciudad_lista() -> bool:
	return int(_est.get("ciudad_lista", 0)) == 1


## Cruces (centros de los viales) para que las pruebas comprueben distancias.
func cruces() -> Array:
	var r: Array = []
	var paso: float = _trazado["paso"]
	var ext: Vector2 = _trazado["ext"]
	var off: Vector2 = _trazado["off"]
	var n_x := int(round(ext.x / paso))
	var n_z := int(round(ext.y / paso))
	for i in n_x + 1:
		for j in n_z + 1:
			r.append(Vector2(off.x + float(i) * paso, off.y + float(j) * paso))
	return r