class_name CityMultimeshManager
## Gestor de MultiMesh - Extraído de generador_ciudad.gd

var _lotes: Dictionary = {}
var _sector_padre: Dictionary = {}
var _cont_sectores: Node3D = null
var _mm_cache: Dictionary = {}
var _mm_datos: Dictionary = {}
var lado_sector: float = 42.0
var usar_multimesh: bool = true
var agrupar_por_sector: bool = true
var _modelos: Dictionary

func _init(modelos: Dictionary, config: Dictionary):
	_modelos = modelos
	lado_sector = config.get("lado_sector", 42.0)
	usar_multimesh = config.get("usar_multimesh", true)
	agrupar_por_sector = config.get("agrupar_por_sector", true)

func crear_contenedor_sectores(padre: Node3D) -> Node3D:
	if _cont_sectores == null:
		_cont_sectores = Node3D.new()
		_cont_sectores.name = "Sectores"
		padre.add_child(_cont_sectores)
	return _cont_sectores

func clave_sector(p: Vector3) -> String:
	return CityUtils.clave_sector(p, lado_sector)

func colocar(pieza: String, xf: Transform3D, padre: Node3D) -> void:
	if not usar_multimesh:
		_instanciar_pieza(pieza, xf, padre)
		return
	var clave := clave_sector(xf.origin) if agrupar_por_sector else "global"
	if not _lotes.has(pieza):
		_lotes[pieza] = {}
	if not _lotes[pieza].has(clave):
		_lotes[pieza][clave] = {"pistas": [], "padre": padre, "clave": clave}
	_lotes[pieza][clave]["pistas"].append(xf)

func _instanciar_pieza(pieza: String, xf: Transform3D, padre: Node3D) -> Node3D:
	if not _modelos.has(pieza): return null
	var escena: PackedScene = _modelos[pieza]["escena"]
	if escena == null: return null
	var inst := escena.instantiate() as Node3D
	if inst == null: return null
	inst.transform = xf
	padre.add_child(inst)
	return inst

func volcar_lotes(cont_sectores: Node3D) -> void:
	for pieza in _lotes.keys():
		for clave in _lotes[pieza].keys():
			_volcar_lote(pieza, _lotes[pieza][clave], cont_sectores)

func _volcar_lote(pieza: String, lote: Dictionary, cont_sectores: Node3D) -> void:
	var pistas: Array = lote["pistas"]
	if pistas.is_empty(): return
	if not _modelos.has(pieza): return
	var padre: Node3D = lote["padre"]
	if agrupar_por_sector:
		var clave: String = lote["clave"]
		if not _sector_padre.has(clave):
			var sector := Node3D.new()
			sector.name = "Sector_%s" % clave
			cont_sectores.add_child(sector)
			_sector_padre[clave] = sector
		padre = _sector_padre[clave]
	for xf in pistas:
		_instanciar_pieza(pieza, xf, padre)

func limpiar():
	_lotes.clear()
	_sector_padre.clear()
	_cont_sectores = null
