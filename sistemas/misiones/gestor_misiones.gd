class_name GestorMisiones
extends Node

## GESTOR DE MISIONES (autoload `Misiones`). Mínimo y centralizado.
##
## Guarda el estado de las misiones EN MEMORIA durante la partida (sin persistencia
## entre sesiones: el proyecto todavía no tiene guardado de progreso) y avisa por
## señales a quien quiera pintarlo. NO conoce el HUD, ni el diálogo, ni los enemigos:
## es la lógica pura; las vistas (el panel) se conectan a sus señales y los sistemas
## que producen hechos (el NPC al terminar de hablar, el enemigo al morir) llaman a
## sus métodos.
##
## Está pensado para crecer: cada misión es una entrada con su objetivo y progreso,
## y las señales son genéricas (llevan el `id` de la misión).

## La misión se ha activado por primera vez (arranca el seguimiento).
signal mision_activada(id: StringName)
## El progreso de una misión ha cambiado (y también se emite al activarse).
signal progreso_cambiado(id: StringName, actual: int, objetivo: int)
## La misión ha alcanzado su objetivo (se emite UNA sola vez).
signal mision_completada(id: StringName)

## Misión de Iván: derrotar a 20 "criminales prófugos".
const MISION_PROFUGOS := &"derrotar_profugos"
const OBJETIVO_PROFUGOS := 20
const TITULO_PROFUGOS := "Derrota a los criminales profugos"

## Metadato que marca un enemigo ya contabilizado: evita el doble conteo aunque
## distintas rutas notifiquen la misma muerte.
const META_CONTADO := &"_mision_baja_contada"

## id -> {titulo: String, objetivo: int, progreso: int, activa: bool,
##        completada: bool, ancla: Variant (Vector3 o null)}
var _misiones: Dictionary = {}

func _ready() -> void:
	_definir(MISION_PROFUGOS, TITULO_PROFUGOS, OBJETIVO_PROFUGOS)

# ------------------------------------------------------------------ definición
func _definir(id: StringName, titulo: String, objetivo: int) -> void:
	_misiones[id] = {
		"titulo": titulo,
		"objetivo": maxi(objetivo, 0),
		"progreso": 0,
		"activa": false,
		"completada": false,
		# Ancla OPCIONAL: dónde está el objetivo en el mundo. La usa el mapa para
		# poner su marcador; una misión sin ancla (p. ej. la de los prófugos, que
		# aparecen por todo el mapa) simplemente no dibuja marcador.
		"ancla": null,
	}

# ------------------------------------------------------------------ consulta
func mision_activa(id: StringName) -> bool:
	var m: Dictionary = _misiones.get(id, {})
	return not m.is_empty() and bool(m["activa"])

func esta_completada(id: StringName) -> bool:
	var m: Dictionary = _misiones.get(id, {})
	return not m.is_empty() and bool(m["completada"])

## Copia de sólo lectura del estado de una misión (no expone el diccionario interno).
func progreso_de(id: StringName) -> Dictionary:
	var m: Dictionary = _misiones.get(id, {})
	return m.duplicate() if not m.is_empty() else {}

# ------------------------------------------------------------------ activación
## Activa una misión. Idempotente: NO reinicia el progreso ni reactiva una misión
## ya activa o completada (volver a hablar con Iván no cambia nada). Devuelve true
## SÓLO la primera vez que se activa.
## `ancla` (opcional) es la posición en el mundo del objetivo: el mapa la usa para
## señalar la misión con un marcador.
func activar_mision(id: StringName, ancla: Variant = null) -> bool:
	var m: Dictionary = _misiones.get(id, {})
	if m.is_empty() or bool(m["activa"]) or bool(m["completada"]):
		return false
	m["activa"] = true
	if ancla is Vector3:
		m["ancla"] = ancla
	mision_activada.emit(id)
	progreso_cambiado.emit(id, int(m["progreso"]), int(m["objetivo"]))
	return true


# ------------------------------------------------------------------ anclas (mapa)
## Anclas de las misiones ACTIVAS y sin completar, para los marcadores del mapa:
## [{id, titulo, posicion, actual, objetivo}]. Sólo entran las misiones con ancla
## (las que no tienen un punto fijo en el mundo no dibujan marcador). Es una copia
## de sólo lectura: no expone el diccionario interno.
func anclas_activas() -> Array:
	var salida: Array = []
	for id in _misiones.keys():
		var m: Dictionary = _misiones[id]
		if not bool(m["activa"]) or bool(m["completada"]):
			continue
		var a: Variant = m.get("ancla")
		if not (a is Vector3):
			continue
		salida.append({
			"id": id,
			"titulo": String(m["titulo"]),
			"posicion": a,
			"actual": int(m["progreso"]),
			"objetivo": int(m["objetivo"]),
		})
	return salida

# ------------------------------------------------------------------ progreso
## Registra UNA baja REAL de enemigo. Sólo cuenta si hay alguna misión ACTIVA y sin
## completar; nunca supera el objetivo; la transición a completada ocurre una sola
## vez. El mismo enemigo sólo cuenta una vez (marca en el propio nodo).
func registrar_baja_de_enemigo(enemigo: Node) -> void:
	if not _hay_activas():
		return
	if enemigo != null:
		if enemigo.has_meta(META_CONTADO):
			return
		enemigo.set_meta(META_CONTADO, true)
	for id in _misiones.keys():
		var m: Dictionary = _misiones[id]
		if not bool(m["activa"]) or bool(m["completada"]):
			continue
		var objetivo := int(m["objetivo"])
		var nuevo := mini(int(m["progreso"]) + 1, objetivo)
		m["progreso"] = nuevo
		progreso_cambiado.emit(id, nuevo, objetivo)
		if nuevo >= objetivo:
			m["completada"] = true
			mision_completada.emit(id)

## Fuerza el estado completado (para misiones que se cierren por otra vía que las
## bajas de enemigos). No hace nada si ya estaba completada.
func marcar_completada(id: StringName) -> void:
	var m: Dictionary = _misiones.get(id, {})
	if m.is_empty() or bool(m["completada"]):
		return
	m["progreso"] = int(m["objetivo"])
	m["completada"] = true
	mision_completada.emit(id)

func _hay_activas() -> bool:
	for id in _misiones.keys():
		var m: Dictionary = _misiones[id]
		if bool(m["activa"]) and not bool(m["completada"]):
			return true
	return false