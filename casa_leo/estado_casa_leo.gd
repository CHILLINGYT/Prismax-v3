class_name EstadoCasaLeo
extends RefCounted
## =============================================================================
##  ESTADO COMPARTIDO DE LA CASA DE LEO (entre la ciudad y el interior)
## =============================================================================
##  Entrar y salir de la casa son dos CAMBIOS DE ESCENA de verdad, con la pantalla
##  de carga que ya usa el juego (res://ui/scenes/LoadingScreen.tscn, con progreso
##  real de ResourceLoader en segundo plano). Entre una escena y otra no queda nada
##  vivo, así que lo poco que hay que pasar viaja aquí, en variables estáticas:
##
##   · el PUNTO DE VUELTA (dónde reaparece Leo al salir: delante de su puerta) y
##     hacia dónde mira;
##   · un BLOQUEO breve tras volver, para que la misma pulsación de E que sale de
##     la casa no lo meta otra vez (nada de bucles);
##   · quién inicia la carga (la puerta o la salida), con la ruta de cada escena en
##     un solo sitio.
##
##  No hay ningún sistema nuevo: es el mismo `LoadingScreen` que usan el menú y la
##  pantalla de muerte.
##
##  También guarda a qué HORA (fase del ciclo de día y noche) se entró en la casa:
##  así el interior arranca con la misma luz que había en la calle y, al volver, la
##  calle recupera la hora que dejó el interior. Es UNA sola cifra que viaja; el
##  reloj sigue siendo el de siempre (`CicloDiaNoche`), no hay un segundo reloj.

const CASA := "res://casa_leo/casa_leo.tscn"
const MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"
const CARGA := "res://ui/scenes/LoadingScreen.tscn"
## Tiempo (ms) que la puerta ignora la E justo después de volver de la casa.
const BLOQUEO_MS := 900
## Fase del ciclo cuando no hay ninguna guardada (el ciclo decide la suya).
const SIN_FASE := -1.0

static var _hay_vuelta := false
static var _punto := Vector3.ZERO
static var _mira := Vector3.FORWARD
static var _bloqueo_hasta := 0
static var _fase := SIN_FASE
## Portal de la ciudad elegido como puerta de Leo (-1 = todavía sin elegir). Se
## elige UNA vez (la puerta más a mano al empezar) y se recuerda: así la casa tiene
## siempre la misma puerta, entre y salga las veces que salga.
static var _portal := -1


## La salida interior apunta dónde y cómo reaparecerá Leo en la ciudad.
static func marcar_vuelta(punto: Vector3, mirada: Vector3) -> void:
	_punto = punto
	_mira = mirada.normalized() if mirada.length() > 0.001 else Vector3.FORWARD
	_hay_vuelta = true
	_bloqueo_hasta = Time.get_ticks_msec() + BLOQUEO_MS


## ¿Queda una vuelta pendiente por colocar? (la consulta la puerta al arrancar el mundo)
static func hay_vuelta() -> bool:
	return _hay_vuelta


## La consume: sólo la primera consulta dice que sí (no se puede colocar dos veces).
static func tomar_vuelta() -> bool:
	if not _hay_vuelta:
		return false
	_hay_vuelta = false
	return true


static func punto_de_vuelta() -> Vector3:
	return _punto


static func mirada_de_vuelta() -> Vector3:
	return _mira


## La puerta no acepta la E durante unos instantes tras volver de la casa.
static func bloqueado() -> bool:
	return Time.get_ticks_msec() < _bloqueo_hasta


static func bloquear(ms: int = BLOQUEO_MS) -> void:
	_bloqueo_hasta = Time.get_ticks_msec() + ms


## Guarda la hora del ciclo (fase en [0, 1)) para el otro lado del cambio de escena.
static func guardar_fase(f: float) -> void:
	_fase = fposmod(f, 1.0)


## Fase guardada, o `SIN_FASE` (< 0) si no hay ninguna: quien la lea debe dejar que
## su ciclo arranque como siempre en ese caso.
static func fase_guardada() -> float:
	return _fase


## Lee la fase del ciclo VIVO (el de la escena que se está abandonando), si lo hay.
static func fase_del_ciclo(desde: Node) -> float:
	if desde == null or not desde.is_inside_tree():
		return SIN_FASE
	var ciclo := desde.get_tree().get_first_node_in_group("ciclo_dia_noche")
	if ciclo == null or not ciclo.has_method("fase_actual"):
		return SIN_FASE
	return float(ciclo.call("fase_actual"))


## Guarda el portal de la ciudad que hace de puerta de la casa (sólo la primera vez:
## la puerta elegida no cambia nunca).
static func guardar_portal(indice: int) -> void:
	if _portal < 0:
		_portal = indice


## Índice del portal guardado, o -1 si todavía no se eligió ninguno.
static func portal_guardado() -> int:
	return _portal


## Olvida el portal elegido (sólo para pruebas: deja la casa como recién empezada).
static func olvidar_portal() -> void:
	_portal = -1


## Arranca la carga del INTERIOR de la casa (con la pantalla de carga del juego).
static func entrar(desde: Node) -> void:
	_cargar(desde, CASA)


## Arranca la carga de la CIUDAD (al salir de la casa).
static func salir(desde: Node) -> void:
	_cargar(desde, MUNDO)


static func _cargar(desde: Node, destino: String) -> void:
	if desde == null or not desde.is_inside_tree():
		return
	LoadingScreen.destino = destino
	desde.get_tree().change_scene_to_file(CARGA)