class_name AjustesJugabilidadService
extends Node

## Ajustes de JUGABILIDAD (autoload, nombre global `AjustesJugabilidad`).
##
## Es el ÚNICO punto donde se guardan y se aplican los ajustes de la categoría
## JUGABILIDAD, de modo que el menú de configuración solo pide cambios y este
## nodo los ejecuta:
##   · Sensibilidad del ratón (nivel 0..10): la lee la cámara del jugador.
##   · Invertir eje vertical: la lee la cámara del jugador.
##   · Mostrar ayudas: PENDIENTE (solo se guarda el valor, sin efecto real aún).
##   · Ocultar interfaz (HUD): cambia la visibilidad de los nodos del grupo
##     `hud_juego`, nunca los destruye.
##
## Persistencia: un ConfigFile propio (user://ajustes_jugabilidad.cfg) con solo
## la sección "jugabilidad". No toca otros guardados del proyecto.
##
## No modifica la física, la velocidad del personaje ni las transformaciones.

signal cambiado

const RUTA := "user://ajustes_jugabilidad.cfg"
const SECCION := "jugabilidad"

## Sensibilidad: nivel 0..10. El nivel 5 equivale a la sensibilidad que ya tenía
## la cámara (0.0025). factor = (nivel + 1) / 6  ->  0 = 0.17x, 5 = 1.0x, 10 = 1.83x.
## Se usa una multiplicación (nunca una división), así el nivel 0 no puede
## provocar división por cero: como mínimo deja la cámara muy lenta, no rota.
const SENS_MIN := 0
const SENS_MAX := 10
const SENS_DEFECTO := 5
const SENS_DIVISOR := 6.0

## Grupo al que pertenecen los nodos visuales del HUD de partida. Ocultar la
## interfaz solo alterna su visibilidad; el menú de pausa NO está en el grupo.
const GRUPO_HUD := &"hud_juego"

var sensibilidad: int = SENS_DEFECTO
var invertir_eje_vertical: bool = false
## Pendiente de implementación: por ahora solo se guarda y se muestra.
var mostrar_ayudas: bool = false
var ocultar_hud: bool = false

func _ready() -> void:
	_cargar()
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_aplicar_hud")

# ---------------------------------------------------------------- API cámara
## Multiplicador de sensibilidad que aplica la cámara al movimiento del ratón.
func factor_sensibilidad() -> float:
	return float(sensibilidad + 1) / SENS_DIVISOR

## Signo del eje vertical de la cámara: -1 lo invierte, +1 lo deja igual.
func signo_eje_vertical() -> float:
	return -1.0 if invertir_eje_vertical else 1.0

# ---------------------------------------------------------------- API (menú)
func poner_sensibilidad(nivel: int) -> void:
	nivel = clampi(nivel, SENS_MIN, SENS_MAX)
	if nivel == sensibilidad:
		return
	sensibilidad = nivel
	_guardar()
	cambiado.emit()

func alternar_sensibilidad(paso: int) -> void:
	poner_sensibilidad(sensibilidad + paso)

func poner_invertir_eje_vertical(v: bool) -> void:
	if v == invertir_eje_vertical:
		return
	invertir_eje_vertical = v
	_guardar()
	cambiado.emit()

func alternar_invertir_eje_vertical() -> void:
	poner_invertir_eje_vertical(not invertir_eje_vertical)

func poner_mostrar_ayudas(v: bool) -> void:
	if v == mostrar_ayudas:
		return
	mostrar_ayudas = v
	_guardar()
	cambiado.emit()

func alternar_mostrar_ayudas() -> void:
	poner_mostrar_ayudas(not mostrar_ayudas)

func poner_ocultar_hud(v: bool) -> void:
	if v == ocultar_hud:
		return
	ocultar_hud = v
	_aplicar_hud()
	_guardar()
	cambiado.emit()

func alternar_ocultar_hud() -> void:
	poner_ocultar_hud(not ocultar_hud)

# ---------------------------------------------------------------- HUD
## Alterna la visibilidad (reversible) de todos los nodos del grupo `hud_juego`.
func _aplicar_hud() -> void:
	var arbol := get_tree()
	if arbol == null:
		return
	for nodo in arbol.get_nodes_in_group(GRUPO_HUD):
		# OJO: CanvasLayer NO deriva de CanvasItem, así que se cubren ambos (y
		# Node3D por si algún HUD futuro es 3D). Solo se toca la visibilidad.
		if nodo is CanvasItem or nodo is CanvasLayer or nodo is Node3D:
			nodo.set("visible", not ocultar_hud)

func _on_node_added(nodo: Node) -> void:
	# Al cargar/reiniciar el mundo el HUD se vuelve a crear: reaplica el ajuste.
	if nodo.is_in_group(GRUPO_HUD):
		call_deferred("_aplicar_hud")

# ---------------------------------------------------------------- persistencia
func _guardar() -> void:
	var cf := ConfigFile.new()
	# Se carga antes de escribir para no borrar claves ajenas del mismo archivo.
	cf.load(RUTA)
	cf.set_value(SECCION, "sensibilidad", sensibilidad)
	cf.set_value(SECCION, "invertir_eje_vertical", invertir_eje_vertical)
	cf.set_value(SECCION, "mostrar_ayudas", mostrar_ayudas)
	cf.set_value(SECCION, "ocultar_hud", ocultar_hud)
	cf.save(RUTA)

func _cargar() -> void:
	var cf := ConfigFile.new()
	if cf.load(RUTA) != OK:
		return
	sensibilidad = clampi(int(cf.get_value(SECCION, "sensibilidad", SENS_DEFECTO)), SENS_MIN, SENS_MAX)
	invertir_eje_vertical = bool(cf.get_value(SECCION, "invertir_eje_vertical", false))
	mostrar_ayudas = bool(cf.get_value(SECCION, "mostrar_ayudas", false))
	ocultar_hud = bool(cf.get_value(SECCION, "ocultar_hud", false))