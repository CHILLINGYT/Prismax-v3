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

## Tamaño de la GUÍA DE CONTROLES: TRES opciones. El tamaño de REFERENCIA es la
## guía tal como está definida (Grande = 100 %); Mediano = 75 % y Chico = 50 %.
## Se guarda el ÍNDICE de la opción elegida. Es un ajuste SÓLO de esa guía.
const HUD_TAM_GRANDE := 0
const HUD_TAM_MEDIANO := 1
const HUD_TAM_CHICO := 2
const HUD_TAM_TEXTO := ["GRANDE", "MEDIANO", "CHICO"]
## Escala de cada opción sobre el tamaño de referencia (4/4, 3/4 y 2/4).
const HUD_TAM_FACTOR := [1.0, 0.75, 0.5]

var sensibilidad: int = SENS_DEFECTO
var invertir_eje_vertical: bool = false
## Pendiente de implementación: por ahora solo se guarda y se muestra.
var mostrar_ayudas: bool = false
var ocultar_hud: bool = false
## PANEL DE CONTROLES DE HABILIDADES (inferior izquierda, durante la partida):
##   · `hud_controles_visible`: lo enciende/apaga ENTERO. Apagado no ocupa nada ni
##     intercepta entrada (el nodo se oculta y todo su mouse_filter es IGNORE).
##   · `hud_controles_tamano`: índice de HUD_TAM_FACTOR (GRANDE/MEDIANO/CHICO).
## Los dos son INDEPENDIENTES del resto del HUD: `ocultar_hud` no los toca (el
## panel no está en el grupo `hud_juego`) y cambiar este panel no cambia ningún
## otro elemento de la interfaz, ni al revés.
var hud_controles_visible: bool = true
var hud_controles_tamano: int = HUD_TAM_GRANDE

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

# ------------------------------------------ Panel de controles de habilidades
## Enciende/apaga el panel de controles de habilidades de la partida.
func poner_hud_controles_visible(v: bool) -> void:
	if v == hud_controles_visible:
		return
	hud_controles_visible = v
	_guardar()
	cambiado.emit()

func alternar_hud_controles_visible() -> void:
	poner_hud_controles_visible(not hud_controles_visible)

## Cambia el TAMAÑO de la guía (GRANDE / MEDIANO / CHICO): afecta sólo a la guía.
func poner_hud_controles_tamano(indice: int) -> void:
	indice = clampi(indice, 0, HUD_TAM_FACTOR.size() - 1)
	if indice == hud_controles_tamano:
		return
	hud_controles_tamano = indice
	_guardar()
	cambiado.emit()

## Recorre las TRES opciones en círculo (las flechas < > del menú).
func pasar_hud_controles_tamano(paso: int) -> void:
	poner_hud_controles_tamano(wrapi(hud_controles_tamano + paso, 0, HUD_TAM_FACTOR.size()))

## Factor de escala de la guía: 1.0 = tamaño de REFERENCIA (GRANDE), 0.75
## (MEDIANO) o 0.5 (CHICO). Nunca es 0 ni negativo, así que no puede dejar la guía
## invisible ni provocar una división por cero.
func factor_hud_controles() -> float:
	return float(HUD_TAM_FACTOR[clampi(hud_controles_tamano, 0, HUD_TAM_FACTOR.size() - 1)])

## Texto legible del tamaño elegido ("GRANDE" / "MEDIANO" / "CHICO").
func texto_hud_controles_tamano() -> String:
	return String(HUD_TAM_TEXTO[clampi(hud_controles_tamano, 0, HUD_TAM_TEXTO.size() - 1)])

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
	cf.set_value(SECCION, "hud_controles_visible", hud_controles_visible)
	cf.set_value(SECCION, "hud_controles_tamano", hud_controles_tamano)
	# La clave de la versión anterior (nivel 6..16) se retira si existía: ya se
	# tradujo al leerla y no debe quedar una opción duplicada en el archivo.
	if cf.has_section_key(SECCION, "hud_controles_escala"):
		cf.erase_section_key(SECCION, "hud_controles_escala")
	cf.save(RUTA)

func _cargar() -> void:
	var cf := ConfigFile.new()
	if cf.load(RUTA) != OK:
		return
	sensibilidad = clampi(int(cf.get_value(SECCION, "sensibilidad", SENS_DEFECTO)), SENS_MIN, SENS_MAX)
	invertir_eje_vertical = bool(cf.get_value(SECCION, "invertir_eje_vertical", false))
	mostrar_ayudas = bool(cf.get_value(SECCION, "mostrar_ayudas", false))
	ocultar_hud = bool(cf.get_value(SECCION, "ocultar_hud", false))
	hud_controles_visible = bool(cf.get_value(SECCION, "hud_controles_visible", true))
	hud_controles_tamano = _tamano_guardado(cf)

## Lee el tamaño guardado de la guía. Si el archivo viene de la versión anterior
## (guardaba un nivel 6..16, con 10 = 100 %), se traduce a la opción más parecida
## — 10 pasa a GRANDE (que ES el 100 % de referencia) — para que la preferencia
## del jugador no se pierda al actualizar.
func _tamano_guardado(cf: ConfigFile) -> int:
	if cf.has_section_key(SECCION, "hud_controles_tamano"):
		return clampi(int(cf.get_value(SECCION, "hud_controles_tamano", HUD_TAM_GRANDE)),
				0, HUD_TAM_FACTOR.size() - 1)
	if cf.has_section_key(SECCION, "hud_controles_escala"):
		var nivel := clampi(int(cf.get_value(SECCION, "hud_controles_escala", 10)), 6, 16)
		if nivel <= 7:
			return HUD_TAM_CHICO
		if nivel <= 12:
			return HUD_TAM_MEDIANO
		return HUD_TAM_GRANDE
	return HUD_TAM_GRANDE