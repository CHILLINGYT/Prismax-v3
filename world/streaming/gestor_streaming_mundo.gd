class_name GestorStreamingMundo
extends Node
## =============================================================================
##  P10 — GESTOR CENTRAL DE STREAMING DEL MUNDO (interruptor + orquestación)
## =============================================================================
##  Orquesta el streaming por proximidad de las zonas del mundo que PUEDEN
##  descargarse con seguridad, reutilizando los dos gestores ya probados:
##    · Ciudad: `GestorStreamingCiudad` (sectores visuales `S_x_y`, P9-D1a).
##    · Bosque: `GestorStreamingBosque` (trozos `Trozo_x_y`, P9-B).
##
##  NO reimplementa nada: crea esos dos gestores como hijos suyos cuando se
##  ACTIVA, les pasa los radios y el presupuesto, y los mantiene apagados mientras
##  el interruptor central esté en off.
##
##  INTERRUPTOR CENTRAL (`activo`, APAGADO por defecto)
##  ---------------------------------------------------
##  Con `activo = false` este nodo NO crea subgestores, NO procesa y NO toca el
##  mundo: el juego se comporta EXACTAMENTE igual que antes (comportamiento
##  original). Se puede activar/desactivar en caliente con `set_activo(bool)`.
##
##  QUÉ *NO* SE DESCARGA (mantenido cargado, documentado)
##  ------------------------------------------------------
##  Terreno (Terrain3D, ya tiene su propio streaming), Océano (superficie global
##  única: quitarla dejaría un agujero de mar), Barco y Muelle (objetos únicos),
##  Límites del mundo y Farolas (luz global + un MultiMesh). Ninguno está
##  sectorizado con seguridad; por eso NO entran en el streaming. Tampoco se
##  descargan las COLISIONES de la ciudad (fuera de alcance; su resolución es P9-D2).
##
##  COHERENCIA DEL MINIMAPA
##  -----------------------
##  El minimapa comparte el mundo y su cámara ve la capa 1 estática, así que si un
##  sector se descarga aparecería un hueco en el mapa. En modo NORMAL (radio ~70 m)
##  no hay huecos, porque lo que rodea al jugador siempre está cargado. En modo
##  AMPLIADO (isla completa, 1000 m) sí los habría; por eso, cuando `mantener_todo_
##  con_mapa` está activo y el mapa ampliado está abierto, se restauran TODOS los
##  sectores y se suspende el streaming hasta que se cierre el mapa.
##
##  RESTAURACIÓN DE EMERGENCIA: `restaurar_todo()` reconstruye todo lo descargado.
##
##  RETIRADA: ver `world/streaming/P10_RETIRADA.md`. Para no usarlo nunca basta con
##  NO activar este nodo (o borrarlo de la escena del mundo).
## =============================================================================

@export_group("Interruptor central")
## Interruptor maestro. APAGADO por defecto: el juego no cambia.
@export var activo: bool = false
## Si está activo, muestra/registra un diagnóstico de sectores por estado.
@export var modo_diagnostico: bool = false

@export_group("Presupuesto y ritmo")
## Máximo de cargas+descargas por fotograma que recibe cada subgestor.
@export var max_ops_por_fotograma: int = 4
## Cada cuántos segundos se refresca el diagnóstico.
@export var intervalo_diagnostico: float = 1.0

@export_group("Subsistemas")
@export var ciudad_activa: bool = true
@export var bosque_activo: bool = true

@export_group("Radios ciudad (m)")
@export var ciudad_r_activo: float = 120.0
@export var ciudad_r_precarga: float = 200.0
@export var ciudad_r_descarga: float = 280.0

@export_group("Radios bosque (m)")
@export var bosque_r_activo: float = 180.0
@export var bosque_r_precarga: float = 320.0
@export var bosque_r_descarga: float = 420.0

@export_group("Minimapa")
## Con el minimapa ampliado abierto se mantiene TODO cargado (evita huecos).
@export var mantener_todo_con_mapa: bool = true

# --- Estado interno -----------------------------------------------------------
var _ciudad: GestorStreamingCiudad = null
var _bosque: GestorStreamingBosque = null
var _minimapa: Node = null
var _activo_real := false
var _suspendido := false
var _acum := 0.0
var _etiqueta: Label = null
var _capa_diag: CanvasLayer = null


func _ready() -> void:
	set_process(false)
	if activo:
		_activar()


## Enciende/apaga el streaming en caliente (según acuerdo de configuración).
func set_activo(v: bool) -> void:
	activo = v
	if v:
		_activar()
	else:
		_desactivar()


func _activar() -> void:
	if _activo_real or not is_inside_tree():
		return
	if ciudad_activa:
		_ciudad = GestorStreamingCiudad.new()
		_ciudad.name = "StreamingCiudad"
		_ciudad.ruta_ciudad = NodePath("../../Ciudad")
		_ciudad.ruta_jugador = NodePath("../../Jugador")
		_ciudad.r_activo = ciudad_r_activo
		_ciudad.r_precarga = ciudad_r_precarga
		_ciudad.r_descarga = ciudad_r_descarga
		_ciudad.max_ops_por_fotograma = max_ops_por_fotograma
		_ciudad.diagnostico = false
		_ciudad.activo = true
		add_child(_ciudad)
	if bosque_activo:
		_bosque = GestorStreamingBosque.new()
		_bosque.name = "StreamingBosque"
		_bosque.ruta_bosque = NodePath("../../Bosque")
		_bosque.ruta_jugador = NodePath("../../Jugador")
		_bosque.r_activo = bosque_r_activo
		_bosque.r_precarga = bosque_r_precarga
		_bosque.r_descarga = bosque_r_descarga
		_bosque.max_ops_por_fotograma = max_ops_por_fotograma
		_bosque.diagnostico = false
		_bosque.activo = true
		add_child(_bosque)
	_activo_real = true
	_suspendido = false
	if modo_diagnostico:
		_crear_etiqueta()
		print("[StreamingMundo] ACTIVADO (ciudad=%s bosque=%s ops=%d)" % [
				str(ciudad_activa), str(bosque_activo), max_ops_por_fotograma])
	set_process(true)


func _desactivar() -> void:
	if not _activo_real:
		return
	restaurar_todo()
	if _ciudad != null and is_instance_valid(_ciudad):
		_ciudad.activo = false
	if _bosque != null and is_instance_valid(_bosque):
		_bosque.activo = false
	set_process(false)
	_quitar_etiqueta()
	_activo_real = false
	if modo_diagnostico:
		print("[StreamingMundo] DESACTIVADO; todo restaurado")


## Restauración de emergencia: reconstruye todo lo descargado en ambos subsistemas.
func restaurar_todo() -> void:
	if _ciudad != null and is_instance_valid(_ciudad):
		_ciudad.restaurar_todo()
	if _bosque != null and is_instance_valid(_bosque):
		_bosque.restaurar_todo()


## P10-B: empuja a los subgestores los radios actuales (por si se cambiaron en
## caliente desde los ajustes). Los subgestores los releen en cada comprobación,
## así que no hace falta recrearlos.
func aplicar_radios() -> void:
	if _ciudad != null and is_instance_valid(_ciudad):
		_ciudad.r_activo = ciudad_r_activo
		_ciudad.r_precarga = ciudad_r_precarga
		_ciudad.r_descarga = ciudad_r_descarga
	if _bosque != null and is_instance_valid(_bosque):
		_bosque.r_activo = bosque_r_activo
		_bosque.r_precarga = bosque_r_precarga
		_bosque.r_descarga = bosque_r_descarga


## P10-B: activa/desactiva la etiqueta de diagnóstico en caliente (si el gestor
## está encendido). Con el gestor apagado sólo guarda la preferencia.
func set_diagnostico(v: bool) -> void:
	modo_diagnostico = v
	if not _activo_real:
		return
	if v:
		_crear_etiqueta()
	else:
		_quitar_etiqueta()


func _process(delta: float) -> void:
	if not _activo_real:
		return
	_gestionar_minimapa()
	if modo_diagnostico:
		_acum += delta
		if _acum >= intervalo_diagnostico:
			_acum = 0.0
			_actualizar_diagnostico()


## Mantiene el minimapa sin huecos: si está ampliado, restaura y suspende.
func _gestionar_minimapa() -> void:
	if not mantener_todo_con_mapa:
		return
	if _minimapa == null or not is_instance_valid(_minimapa):
		_minimapa = _buscar_minimapa()
	if _minimapa == null:
		return
	var ampliado := false
	var v: Variant = _minimapa.get("_ampliado")
	if v != null:
		ampliado = bool(v)
	if ampliado and not _suspendido:
		restaurar_todo()
		if _ciudad != null and is_instance_valid(_ciudad):
			_ciudad.activo = false
		if _bosque != null and is_instance_valid(_bosque):
			_bosque.activo = false
		_suspendido = true
	elif not ampliado and _suspendido:
		if _ciudad != null and is_instance_valid(_ciudad):
			_ciudad.activo = true
		if _bosque != null and is_instance_valid(_bosque):
			_bosque.activo = true
		_suspendido = false


func _buscar_minimapa() -> Node:
	var r := get_tree().get_root() if is_inside_tree() else null
	if r == null:
		return null
	return _buscar_rec(r)


func _buscar_rec(n: Node) -> Node:
	if n is Minimapa:
		return n
	for c in n.get_children():
		var r := _buscar_rec(c)
		if r != null:
			return r
	return null


func resumen() -> Dictionary:
	var d := {"activo": _activo_real, "suspendido": _suspendido,
			"ciudad": {}, "bosque": {}}
	if _ciudad != null and is_instance_valid(_ciudad):
		d["ciudad"] = _ciudad.resumen()
	if _bosque != null and is_instance_valid(_bosque):
		d["bosque"] = _bosque.resumen()
	return d


func _crear_etiqueta() -> void:
	if _capa_diag != null:
		return
	_capa_diag = CanvasLayer.new()
	_capa_diag.name = "StreamingDiag"
	_capa_diag.layer = 128
	add_child(_capa_diag)
	_etiqueta = Label.new()
	_etiqueta.name = "Texto"
	_etiqueta.position = Vector2(12.0, 210.0)
	_etiqueta.add_theme_color_override("font_color", Color(1.0, 1.0, 0.55))
	_capa_diag.add_child(_etiqueta)


func _quitar_etiqueta() -> void:
	if _capa_diag != null and is_instance_valid(_capa_diag):
		_capa_diag.queue_free()
	_capa_diag = null
	_etiqueta = null


func _actualizar_diagnostico() -> void:
	var texto := "[StreamingMundo] activo=%s suspendido=%s" % [str(_activo_real), str(_suspendido)]
	if _ciudad != null and is_instance_valid(_ciudad):
		var rc := _ciudad.resumen()
		texto += "\nCiudad: %d/%d  (U=%d R=%d A=%d)" % [
				int(rc["nodos_presentes"]), int(rc["total"]),
				int(rc["unloaded"]), int(rc["ready"]), int(rc["active"])]
	if _bosque != null and is_instance_valid(_bosque):
		texto += "\nBosque: %s" % str(_bosque.resumen())
	if _etiqueta != null and is_instance_valid(_etiqueta):
		_etiqueta.text = texto
	print(texto)