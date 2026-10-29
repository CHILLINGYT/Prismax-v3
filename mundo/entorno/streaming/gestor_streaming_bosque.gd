class_name GestorStreamingBosque
extends Node
## =============================================================================
##  P9-B — PROTOTIPO DE STREAMING DE LOS TROZOS DEL BOSQUE (AISLADO, REVERSIBLE)
## =============================================================================
##  Gestiona EXCLUSIVAMENTE los nodos `Trozo_x_y` de `Bosque` (bosque.gd): los
##  descarga (libera el nodo y su MultiMesh) cuando el jugador se aleja y los
##  reconstruye EXACTAMENTE cuando se acerca.
##
##  DESACTIVADO POR DEFECTO (`activo = false`): con el flag apagado este nodo NO
##  hace absolutamente nada (ni procesa ni captura ni toca el bosque).
##
##  CÓMO SE RESTAURA EXACTAMENTE (sin duplicar los datos)
##  -----------------------------------------------------
##  La generación del bosque NO se toca y NO se re-siembra (nada de RNG). El bosque
##  YA conserva, tras generarse, las matrices y los tintes de cada trozo en
##  `_pistas[clave]` / `_tintes[clave]` (clave = Vector2i), en coordenadas de MUNDO.
##  El gestor reconstruye cada trozo aplicando EXACTAMENTE la misma conversión que
##  `bosque.gd::_volcar()` (mismas mallas y materiales COMPARTIDOS de `Vegetacion`,
##  mismo nombre de trozo, misma posición, mismas matrices locales y colores). Al
##  liberar NO se guarda copia de las matrices: los datos ya viven en el bosque.
##
##  QUÉ SE LIBERA Y QUÉ NO (sin afirmaciones sin evidencia)
##  ------------------------------------------------------
##  Se liberan: el `Node3D` del trozo, sus `MultiMeshInstance3D` hijos y el
##  recurso `MultiMesh` de cada uno (referenciado solo por ese nodo -> se libera).
##  NO se liberan: las mallas, materiales y texturas COMPARTIDAS (cachés estáticas
##  de `Vegetacion`): siguen vivas y se reutilizan al reconstruir. La VRAM asociada
##  a esas mallas/texturas NO baja. La reducción real es de memoria de objetos y de
##  búferes de instancia; su magnitud se MIDE, no se supone.
##
##  ESTADOS: UNLOADED -> (LOADING) -> READY -> ACTIVE -> (UNLOADING) -> UNLOADED.
##  `READY` = trozo creado pero fuera de la zona activa (oculto); `ACTIVE` =
##  visible. Radios con HISTÉRESIS: se activa con `r_activo`, se pre-carga con
##  `r_precarga` y se descarga solo pasando `r_descarga` (r_activo < r_precarga <
##  r_descarga), de modo que un trozo no oscila cerca del límite.
##
##  PRESUPUESTO: como máximo `max_ops_por_fotograma` cargas+descargas por fotograma,
##  dando prioridad a las CARGAS (evita huecos delante del jugador).
##
##  DIAGNÓSTICO: solo imprime si `diagnostico = true`.
##
##  Para desactivar/revertir: poner `activo = false` (el nodo deja de actuar) y, si
##  hay trozos descargados, llamar a `restaurar_todo()` para reconstruirlos y dejar
##  el bosque como estaba. Como no se modifican ni la generación ni los recursos
##  compartidos, el prototipo es totalmente reversible.
## =============================================================================

enum Estado { UNLOADED, LOADING, READY, ACTIVE, UNLOADING }

const PREFIJO_TROZO := "Trozo_"

@export_group("Activación")
## Interruptor maestro. APAGADO por defecto: no cambia el comportamiento del juego.
@export var activo: bool = false

@export_group("Radios (m)")
## Dentro de este radio el trozo está ACTIVE (visible).
@export var r_activo: float = 180.0
## Dentro de este radio (y fuera del activo) se PRE-CARGA el trozo (READY, oculto).
@export var r_precarga: float = 320.0
## Pasando este radio el trozo se descarga (UNLOADED). Debe ser el mayor.
@export var r_descarga: float = 420.0

@export_group("Presupuesto")
## Máximo de cargas+descargas por fotograma (prioriza cargas).
@export var max_ops_por_fotograma: int = 3
## Cada cuántos segundos se reevalúa la distancia (no hace falta cada fotograma).
@export var intervalo_comprobacion: float = 0.1

@export_group("Referencias")
@export var ruta_bosque: NodePath = ^"../Bosque"
@export var ruta_jugador: NodePath = ^"../Jugador"

@export_group("Diagnóstico")
## Si está activo, imprime el estado de las celdas y las métricas de memoria.
@export var diagnostico: bool = false

# --- Estado interno -----------------------------------------------------------
var _bosque: Node3D = null
var _jugador: Node3D = null
var _lado := 200.0
var _iniciado := false
var _acum := 0.0

var _todos: Array[String] = []          ## nombres de trozo (orden canónico)
var _centros: Dictionary = {}           ## nombre -> Vector3 centro (XZ del mundo)
var _espec: Dictionary = {}             ## nombre -> {pos: Vector3, clave: Vector2i}
var _nodos: Dictionary = {}             ## nombre -> Node3D presente (cargado)
var _estado: Dictionary = {}            ## nombre -> Estado

# --- Estadísticas (para el informe) ------------------------------------------
var cargas_total := 0
var descargas_total := 0
var fotogramas_activos := 0


func _ready() -> void:
	if not activo:
		# Desactivado: el nodo no participa en absoluto.
		set_process(false)
		return
	set_process(true)


func _process(delta: float) -> void:
	if not activo:
		return
	if not _iniciar():
		return
	fotogramas_activos += 1
	_acum += delta
	if _acum < intervalo_comprobacion:
		return
	_acum = 0.0
	_aplicar()


## Localiza el bosque y su estructura. Devuelve false mientras no exista (el
## bosque se genera en su _ready, que puede correr después que este nodo).
func _iniciar() -> bool:
	if _iniciado:
		return true
	if _bosque == null or not is_instance_valid(_bosque):
		_bosque = get_node_or_null(ruta_bosque) as Node3D
		if _bosque == null:
			return false
	if _jugador == null or not is_instance_valid(_jugador):
		_jugador = get_node_or_null(ruta_jugador) as Node3D
	_lado = float(_bosque.get("lado_trozo")) if _bosque.get("lado_trozo") != null else 200.0
	_todos.clear()
	_centros.clear()
	_espec.clear()
	_nodos.clear()
	_estado.clear()
	var semi := _lado * 0.5
	for c in _bosque.get_children():
		if c is Node3D and String(c.name).begins_with(PREFIJO_TROZO):
			var nodo := c as Node3D
			var nombre := String(nodo.name)
			_todos.append(nombre)
			_centros[nombre] = nodo.global_position + Vector3(semi, 0.0, semi)
			_espec[nombre] = {"pos": nodo.position, "clave": _parsear_clave(nombre)}
			_nodos[nombre] = nodo
			_estado[nombre] = Estado.ACTIVE
	if _todos.is_empty():
		return false            # el bosque aún no ha creado sus trozos
	_todos.sort()
	_iniciado = true
	if diagnostico:
		print("[StreamingBosque] iniciado: %d trozos | radios a=%.0f p=%.0f d=%.0f | ops/frame=%d" % [
				_todos.size(), r_activo, r_precarga, r_descarga, max_ops_por_fotograma])
	return true


## Reevalúa distancias y aplica cargas/descargas con presupuesto.
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
	# Presupuesto por fotograma: primero las CARGAS (evita huecos delante), luego
	# las descargas.
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


## Reconstruye un trozo desde los datos que conserva el bosque.
func _cargar(nombre: String) -> void:
	var nodo := _crear_trozo(nombre)
	_bosque.add_child(nodo)
	_nodos[nombre] = nodo
	cargas_total += 1


## Libera el nodo del trozo (y su MultiMesh). No guarda copia: los datos de
## restauración ya viven en el bosque.
func _descargar(nombre: String) -> void:
	var nodo: Node3D = _nodos[nombre]
	if not is_instance_valid(nodo):
		_nodos.erase(nombre)
		_estado[nombre] = Estado.UNLOADED
		return
	nodo.free()                    # liberación inmediata (no queue_free)
	_nodos.erase(nombre)
	_estado[nombre] = Estado.UNLOADED
	descargas_total += 1


## "Trozo_3_-2" -> Vector2i(3, -2).
func _parsear_clave(nombre: String) -> Vector2i:
	var partes := nombre.replace(PREFIJO_TROZO, "").split("_", false)
	if partes.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(partes[0]), int(partes[1]))


## Reconstruye el nodo del trozo replicando EXACTAMENTE `bosque.gd::_volcar()`.
func _crear_trozo(nombre: String) -> Node3D:
	var spec: Dictionary = _espec[nombre]
	var clave: Vector2i = spec["clave"]
	var pos: Vector3 = spec["pos"]
	var pistas: Dictionary = _bosque.get("_pistas")
	var tintes: Dictionary = _bosque.get("_tintes")
	var grupo: Dictionary = pistas.get(clave, {})
	var grupo_tinte: Dictionary = tintes.get(clave, {})
	var nodo := Node3D.new()
	nodo.name = nombre
	nodo.position = pos
	var inv := Transform3D(Basis(), pos).affine_inverse()
	var rutas: Array = grupo.keys()
	rutas.sort()
	for ruta: String in rutas:
		var mundo: Array = grupo[ruta]
		var local: Array = []
		local.resize(mundo.size())
		for i in mundo.size():
			local[i] = inv * (mundo[i] as Transform3D)
		var colores: Array = grupo_tinte.get(ruta, [])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Vegetacion.malla()
		if not colores.is_empty():
			mm.use_colors = true              # ANTES de instance_count (exigencia de Godot)
		mm.instance_count = local.size()
		for i in local.size():
			mm.set_instance_transform(i, local[i])
		if not colores.is_empty():
			for i in colores.size():
				mm.set_instance_color(i, colores[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_x%d" % [ruta.get_file().get_basename(), local.size()]
		mmi.multimesh = mm
		mmi.material_override = Vegetacion.material(ruta)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		nodo.add_child(mmi)
	return nodo


# ---------------------------------------------------------------- API pública
## Reconstruye todos los trozos descargados y deja de actuar. Deja el bosque como
## recién generado. Útil para revertir el prototipo sin recargar la escena.
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


## Estado de un trozo por su nombre (para pruebas).
func estado_de(nombre: String) -> int:
	return int(_estado.get(nombre, Estado.UNLOADED))


## Resumen para pruebas/informe.
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
	print("[StreamingBosque] nodos=%d/%d inst=%d | U=%d L=%d R=%d A=%d X=%d | cargas=%d descargas=%d" % [
			r["nodos_presentes"], r["total"], r["instancias_presentes"],
			r["unloaded"], r["loading"], r["ready"], r["active"], r["unloading"],
			r["cargas"], r["descargas"]])