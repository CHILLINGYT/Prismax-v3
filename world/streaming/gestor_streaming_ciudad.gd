class_name GestorStreamingCiudad
extends Node
## =============================================================================
##  P9-D1a — PROTOTIPO DE STREAMING VISUAL DE LOS SECTORES DE CIUDAD (AISLADO)
## =============================================================================
##  Gestiona EXCLUSIVAMENTE los nodos VISUALES `S_x_y` de `Ciudad/CiudadGenerada/
##  Sectores` (los MultiMesh de "piezas" agrupadas por sector de 42 m). Los libera
##  cuando el jugador se aleja y los reconstruye EXACTAMENTE cuando se acerca.
##
##  DESACTIVADO POR DEFECTO (`activo = false`): con el flag apagado este nodo NO
##  hace absolutamente nada (ni procesa ni captura ni toca la ciudad).
##
##  ALCANCE (deliberadamente acotado)
##  ---------------------------------
##  SOLO sectores visuales. NO toca colisiones, Terrain3D, peatones, minimapa ni
##  los MultiMesh globales (vegetación, macetas, ventanas, marcas). Por tanto, al
##  descargar un sector su COLISIÓN sigue presente (puede quedar un "muro
##  invisible" en esa zona lejana): es una limitación conocida y aceptada en este
##  prototipo (su resolución es P9-D2).
##
##  CÓMO SE RESTAURA EXACTAMENTE (estrategia S1: captura-al-descargar)
##  ------------------------------------------------------------------
##  La generación NO se toca y NO se re-siembra (nada de RNG). Como el generador
##  descarta los datos por sector al terminar (`_lotes.clear()`), este gestor
##  CAPTURA la estructura completa del nodo del sector justo antes de liberarlo:
##  - la posición del nodo del sector (origen; las matrices están en mundo),
##  - por cada `MultiMeshInstance3D` hijo: nombre, malla y `material_override`
##    COMPARTIDOS, `cast_shadow`, `visible`, si usa colores, y TODAS las matrices
##    y colores de instancia.
##  Al cargar se vuelve a construir tal cual. Como la captura solo existe mientras
##  el sector está descargado, hay una sola copia de los datos en todo momento (no
##  se duplican mientras está cargado).
##
##  QUÉ SE LIBERA Y QUÉ NO
##  ----------------------
##  Se liberan: el `Node3D` del sector y sus `MultiMeshInstance3D`, el recurso
##  `MultiMesh` de cada uno (solo lo referencia ese nodo) y su búfer de instancias.
##  NO se liberan las mallas/materiales/texturas COMPARTIDAS del kit. La memoria
##  se MIDE; no se afirma reducción sin evidencia (ver limitaciones en el informe).
##
##  ESTADOS: UNLOADED -> (LOADING) -> READY -> ACTIVE -> (UNLOADING) -> UNLOADED.
##  HISTÉRESIS: activa con `r_activo`, pre-carga con `r_precarga`, descarga solo
##  pasando `r_descarga` (r_activo < r_precarga < r_descarga). PRESUPUESTO por
##  fotograma (prioriza cargas). DIAGNÓSTICO solo si `diagnostico = true`.
##
##  DESACTIVAR/REVERTIR: `activo = false` detiene la actuación; `restaurar_todo()`
##  reconstruye todos los sectores para dejar la ciudad como recién generada.
## =============================================================================

enum Estado { UNLOADED, LOADING, READY, ACTIVE, UNLOADING }

const PREFIJO := "S_"

@export_group("Activación")
## Interruptor maestro. APAGADO por defecto.
@export var activo: bool = false

@export_group("Radios (m)")
## Dentro de este radio el sector está ACTIVE (visible).
@export var r_activo: float = 120.0
## Dentro de este radio (y fuera del activo) se PRE-CARGA el sector (READY, oculto).
@export var r_precarga: float = 200.0
## Pasando este radio el sector se descarga (UNLOADED). Debe ser el mayor.
@export var r_descarga: float = 280.0

@export_group("Presupuesto")
@export var max_ops_por_fotograma: int = 4
@export var intervalo_comprobacion: float = 0.1

@export_group("Referencias")
## Nodo del generador de ciudad (para localizar `Sectores` y leer `lado_sector`).
@export var ruta_ciudad: NodePath = ^"../Ciudad"
@export var ruta_jugador: NodePath = ^"../Jugador"

@export_group("Diagnóstico")
@export var diagnostico: bool = false

# --- Estado interno -----------------------------------------------------------
var _ciudad: Node = null
var _sectores: Node3D = null
var _jugador: Node3D = null
var _lado := 42.0
var _iniciado := false
var _acum := 0.0

var _todos: Array[String] = []
var _centros: Dictionary = {}      ## nombre -> Vector3 (XZ del mundo)
var _nodos: Dictionary = {}        ## nombre -> Node3D cargado
var _defs: Dictionary = {}         ## nombre -> Dictionary capturado (descargado)
var _estado: Dictionary = {}

var cargas_total := 0
var descargas_total := 0


func _ready() -> void:
	if not activo:
		set_process(false)
		return
	set_process(true)


func _process(delta: float) -> void:
	if not activo:
		return
	if not _iniciar():
		return
	_acum += delta
	if _acum < intervalo_comprobacion:
		return
	_acum = 0.0
	_aplicar()


func _iniciar() -> bool:
	if _iniciado:
		return true
	if _ciudad == null or not is_instance_valid(_ciudad):
		_ciudad = get_node_or_null(ruta_ciudad)
		if _ciudad == null:
			return false
	if _sectores == null or not is_instance_valid(_sectores):
		_sectores = _ciudad.get_node_or_null("CiudadGenerada/Sectores") as Node3D
		if _sectores == null:
			return false
	if _jugador == null or not is_instance_valid(_jugador):
		_jugador = get_node_or_null(ruta_jugador) as Node3D
	var l: Variant = _ciudad.get("lado_sector")
	_lado = float(l) if l != null else 42.0
	_todos.clear(); _centros.clear(); _nodos.clear(); _defs.clear(); _estado.clear()
	for c in _sectores.get_children():
		if c is Node3D and String(c.name).begins_with(PREFIJO):
			var nodo := c as Node3D
			var nombre := String(nodo.name)
			_todos.append(nombre)
			_centros[nombre] = _centro_de(nombre)
			_nodos[nombre] = nodo
			_estado[nombre] = Estado.ACTIVE
	if _todos.is_empty():
		return false
	_todos.sort()
	_iniciado = true
	if diagnostico:
		print("[StreamingCiudad] iniciado: %d sectores | lado=%.1f | radios a=%.0f p=%.0f d=%.0f | ops/frame=%d" % [
				_todos.size(), _lado, r_activo, r_precarga, r_descarga, max_ops_por_fotograma])
	return true


## Centro (mundo, XZ) del sector a partir de su nombre "S_mx_mz".
func _centro_de(nombre: String) -> Vector3:
	var partes := nombre.substr(PREFIJO.length()).split("_", false)
	if partes.size() < 2:
		return Vector3.ZERO
	return Vector3((float(partes[0]) + 0.5) * _lado, 0.0, (float(partes[1]) + 0.5) * _lado)


func _aplicar() -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var p := _jugador.global_position
	var pend_crear: Array[String] = []
	var pend_liberar: Array[String] = []
	for nombre in _todos:
		var centro: Vector3 = _centros[nombre]
		var d := Vector2(p.x - centro.x, p.z - centro.z).length()
		var cargado := _nodos.has(nombre) and is_instance_valid(_nodos[nombre])
		if cargado:
			if d <= r_activo:
				_estado[nombre] = Estado.ACTIVE
				(_nodos[nombre] as Node3D).visible = true
			elif d <= r_descarga:
				_estado[nombre] = Estado.READY
				(_nodos[nombre] as Node3D).visible = false
			else:
				_estado[nombre] = Estado.UNLOADING
				pend_liberar.append(nombre)
		else:
			if d <= r_precarga:
				_estado[nombre] = Estado.LOADING
				pend_crear.append(nombre)
			else:
				_estado[nombre] = Estado.UNLOADED
	var ops := 0
	for nombre in pend_crear:
		if ops >= max_ops_por_fotograma:
			break
		_cargar(nombre)
		ops += 1
	for nombre in pend_liberar:
		if ops >= max_ops_por_fotograma:
			break
		_descargar(nombre)
		ops += 1
	if diagnostico and ops > 0:
		_resumen_diag()


func _cargar(nombre: String) -> void:
	var nodo := _crear(_defs[nombre])
	_sectores.add_child(nodo)
	_nodos[nombre] = nodo
	_defs.erase(nombre)
	cargas_total += 1


func _descargar(nombre: String) -> void:
	var nodo: Node3D = _nodos[nombre]
	if not is_instance_valid(nodo):
		_nodos.erase(nombre)
		_estado[nombre] = Estado.UNLOADED
		return
	_defs[nombre] = _capturar(nodo)
	nodo.free()
	_nodos.erase(nombre)
	_estado[nombre] = Estado.UNLOADED
	descargas_total += 1


## Captura todo lo necesario para reconstruir el sector exactamente.
func _capturar(nodo: Node3D) -> Dictionary:
	var hijos: Array = []
	for c in nodo.get_children():
		if c is MultiMeshInstance3D:
			var mmi := c as MultiMeshInstance3D
			var mm := mmi.multimesh
			var n := mm.instance_count
			var mallas: Array = []
			mallas.resize(n)
			var colores: Array = []
			if mm.use_colors:
				colores.resize(n)
			for i in n:
				mallas[i] = mm.get_instance_transform(i)
				if mm.use_colors:
					colores[i] = mm.get_instance_color(i)
			hijos.append({
				"nombre": String(mmi.name),
				"malla": mm.mesh,
				"material": mmi.material_override,
				"cast_shadow": mmi.cast_shadow,
				"visible": mmi.visible,
				"usar_colores": mm.use_colors,
				"mallas": mallas,
				"colores": colores,
			})
	return {"nombre": String(nodo.name), "pos": nodo.position, "hijos": hijos}


## Reconstruye el nodo del sector tal cual se capturó.
func _crear(d: Dictionary) -> Node3D:
	var nodo := Node3D.new()
	nodo.name = String(d["nombre"])
	nodo.position = d["pos"]
	for h in (d["hijos"] as Array):
		var hd: Dictionary = h
		var mallas: Array = hd["mallas"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = hd["malla"]
		if bool(hd["usar_colores"]):
			mm.use_colors = true                  # ANTES de instance_count (Godot)
		mm.instance_count = mallas.size()
		for i in mallas.size():
			mm.set_instance_transform(i, mallas[i])
		if bool(hd["usar_colores"]):
			var colores: Array = hd["colores"]
			for i in colores.size():
				mm.set_instance_color(i, colores[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = String(hd["nombre"])
		mmi.multimesh = mm
		mmi.material_override = hd["material"]
		mmi.cast_shadow = hd["cast_shadow"]
		mmi.visible = bool(hd["visible"])
		nodo.add_child(mmi)
	return nodo


# ---------------------------------------------------------------- API pública
## Reconstruye todos los sectores descargados y los deja visibles.
func restaurar_todo() -> void:
	if not _iniciado:
		return
	for nombre in _todos:
		if not (_nodos.has(nombre) and is_instance_valid(_nodos[nombre])):
			_cargar(nombre)
		(_nodos[nombre] as Node3D).visible = true
		_estado[nombre] = Estado.ACTIVE
	if diagnostico:
		_resumen_diag()


func estado_de(nombre: String) -> int:
	return int(_estado.get(nombre, Estado.UNLOADED))


func resumen() -> Dictionary:
	var por_estado := {Estado.UNLOADED: 0, Estado.LOADING: 0, Estado.READY: 0,
			Estado.ACTIVE: 0, Estado.UNLOADING: 0}
	var nodos := 0
	var instancias := 0
	for nombre in _todos:
		por_estado[_estado.get(nombre, Estado.UNLOADED)] += 1
		if _nodos.has(nombre) and is_instance_valid(_nodos[nombre]):
			nodos += 1
			for c in (_nodos[nombre] as Node3D).get_children():
				if c is MultiMeshInstance3D:
					instancias += (c as MultiMeshInstance3D).multimesh.instance_count
	return {
		"total": _todos.size(),
		"nodos_presentes": nodos,
		"instancias_presentes": instancias,
		"unloaded": por_estado[Estado.UNLOADED],
		"loading": por_estado[Estado.LOADING],
		"ready": por_estado[Estado.READY],
		"active": por_estado[Estado.ACTIVE],
		"unloading": por_estado[Estado.UNLOADING],
		"cargas": cargas_total,
		"descargas": descargas_total,
	}


func _resumen_diag() -> void:
	var r := resumen()
	print("[StreamingCiudad] nodos=%d/%d inst=%d | U=%d L=%d R=%d A=%d X=%d | cargas=%d descargas=%d" % [
			r["nodos_presentes"], r["total"], r["instancias_presentes"],
			r["unloaded"], r["loading"], r["ready"], r["active"], r["unloading"],
			r["cargas"], r["descargas"]])