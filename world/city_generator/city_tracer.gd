class_name CityTracer
## Trazado urbano - Extraído de generador_ciudad.gd líneas 1595-2305

var _rng: RandomNumberGenerator
var manzanas_x: int = 6
var manzanas_z: int = 6
var tamano_manzana: float = 24.0
var ancho_calzada: float = 12.0
var ancho_acera: float = 3.0
var lado_sector: float = 42.0
var _trazado: Dictionary = {}

func _init(rng: RandomNumberGenerator, config: Dictionary):
	_rng = rng
	manzanas_x = config.get("manzanas_x", 6)
	manzanas_z = config.get("manzanas_z", 6)
	tamano_manzana = config.get("tamano_manzana", 24.0)
	ancho_calzada = config.get("ancho_calzada", 12.0)
	ancho_acera = config.get("ancho_acera", 3.0)
	lado_sector = config.get("lado_sector", 42.0)

func preparar_trazado() -> Dictionary:
	var paso := tamano_manzana + ancho_calzada + 2.0 * ancho_acera
	var total_x := manzanas_x * paso + ancho_calzada + 2.0 * ancho_acera
	var total_z := manzanas_z * paso + ancho_calzada + 2.0 * ancho_acera
	_trazado = {
		"paso": paso, "total_x": total_x, "total_z": total_z,
		"origen_x": -total_x * 0.5, "origen_z": -total_z * 0.5,
		"manzanas_x": manzanas_x, "manzanas_z": manzanas_z,
	}
	return _trazado

func elegir_parques(cantidad: int) -> Array[Vector2i]:
	var todas: Array[Vector2i] = []
	for i in range(manzanas_x):
		for j in range(manzanas_z):
			todas.append(Vector2i(i, j))
	todas.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var centro := Vector2i(manzanas_x / 2, manzanas_z / 2)
		return (Vector2(a) - Vector2(centro)).length_squared() < (Vector2(b) - Vector2(centro)).length_squared()
	)
	var parques: Array[Vector2i] = []
	for k in range(mini(cantidad, todas.size())):
		parques.append(todas[k])
	return parques

func rect_manzana(i: int, j: int) -> Rect2:
	var paso: float = _trazado["paso"]
	var ox: float = _trazado["origen_x"]
	var oz: float = _trazado["origen_z"]
	return Rect2(ox + ancho_acera + ancho_calzada * 0.5 + float(i) * paso + ancho_acera,
				 oz + ancho_acera + ancho_calzada * 0.5 + float(j) * paso + ancho_acera,
				 tamano_manzana, tamano_manzana)
