class_name CityScanner
## Escáner de modelos .gltf/.glb - Extraído de generador_ciudad.gd líneas 878-1500

var _modelos: Dictionary
var _categorias: Dictionary
var _escanear_estado: bool = true
var _aabb_cajas: bool = true
var _leidos_estado: int = 0
var _fallbacks_estado: int = 0

func _init(escanear_estado: bool = true, aabb_cajas: bool = true):
	_escanear_estado = escanear_estado
	_aabb_cajas = aabb_cajas

func resolver_carpeta(carpeta_sugerida: String) -> String:
	if carpeta_sugerida != "" and DirAccess.dir_exists_absolute(carpeta_sugerida):
		return carpeta_sugerida
	var candidatas: Array[String] = []
	_buscar_carpetas_gltf("res://", 0, candidatas)
	for c in candidatas:
		if "Exports" in c and "glTF" in c:
			return c
	if not candidatas.is_empty():
		return candidatas[0]
	return ""

func _buscar_carpetas_gltf(ruta: String, profundidad: int, salida: Array[String]) -> void:
	if profundidad > 4: return
	var da := DirAccess.open(ruta)
	if da == null: return
	for f in da.get_files():
		if f.get_extension().to_lower() in ["gltf", "glb"]:
			salida.append(ruta)
			return
	for d in da.get_directories():
		if d.begins_with("."): continue
		_buscar_carpetas_gltf(ruta.path_join(d), profundidad + 1, salida)

func escanear(carpeta: String, modelos: Dictionary, categorias: Dictionary) -> void:
	_modelos = modelos
	_categorias = categorias
	_modelos.clear()
	_categorias.clear()
	var da := DirAccess.open(carpeta)
	if da == null: return
	for archivo in da.get_files():
		if archivo.get_extension().to_lower() not in ["gltf", "glb"]: continue
		_escanear_archivo(carpeta, archivo)

func _escanear_archivo(carpeta: String, archivo: String) -> void:
	var ruta := carpeta.path_join(archivo)
	var escena: PackedScene = load(ruta) as PackedScene
	if escena == null: return
	var aabb := CityUtils.aabb_modelo_por_cajas(escena.instantiate()) if _aabb_cajas else AABB()
	var nombre := archivo.get_basename()
	_modelos[nombre] = {"escena": escena, "caja": aabb, "categoria": _clasificar(nombre)}
	var cat: String = _modelos[nombre]["categoria"]
	if not _categorias.has(cat):
		_categorias[cat] = []
	_categorias[cat].append(nombre)

func _clasificar(nombre: String) -> String:
	var n := nombre.to_lower()
	if n.begins_with("building_"): return "prefab"
	if "wall" in n: return "pared"
	if "window" in n: return "ventana"
	if "doorframe" in n: return "marco_puerta"
	if "door" in n: return "hoja_puerta"
	if "street" in n: return "tramo_calle"
	if "asphalt" in n: return "plancha_asfalto"
	if "sidewalk" in n: return "acera_recta"
	return "prop"

func construir_listas() -> Dictionary:
	var listas: Dictionary = {"prefabs": [], "paredes": [], "ventanas": [], "familias": {}}
	for nombre in _modelos.keys():
		var cat: String = _modelos[nombre]["categoria"]
		match cat:
			"prefab": listas["prefabs"].append(nombre)
			"pared": listas["paredes"].append(nombre)
			"ventana": listas["ventanas"].append(nombre)
	return listas
