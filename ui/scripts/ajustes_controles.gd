class_name AjustesControlesService
extends Node

## Ajustes de CONTROLES (autoload, nombre global `AjustesControles`).
##
## Es el UNICO punto donde se reasignan y se guardan los controles del juego, de
## modo que el panel de configuracion solo pide cambios y este nodo los ejecuta
## sobre el Input Map REAL.
##
## Que hace:
##   · Catalogo de acciones reasignables, con su contexto (en que formas se usan).
##   · Lectura/escritura de las asignaciones en el InputMap (no en project.godot:
##     el mapa se modifica en memoria y se persiste aparte).
##   · Deteccion de conflictos con criterio CONTEXTUAL: dos acciones solo chocan
##     si pueden estar activas a la vez (misma forma). Las teclas que comparten
##     dos formas distintas (p. ej. SHIFT = dash del Velocista y correr del
##     Humano) NO son un conflicto: se usan en contextos excluyentes.
##   · Persistencia propia en user://ajustes_controles.cfg (seccion "controles").
##     No toca los demas archivos de preferencias (graficos, jugabilidad, etc.).
##
## No modifica animaciones, estados, tiempos de carga, enfriamientos, colisiones
## ni la logica de combate: solo cambia QUE entrada dispara cada accion.

signal cambiado

const RUTA := "user://ajustes_controles.cfg"
const SECCION := "controles"

## Contextos (formas) en las que se usa una accion. Una accion "comun" se usa en
## todas las formas; las demas solo en la suya.
const HUMANO := &"humano"
const VELOCISTA := &"velocista"
const ACUATICO := &"acuatico"
const FUERZA := &"fuerza"
const COMBATE := &"combate"
const VUELO := &"vuelo"

## Acciones de INTERFAZ: no se reasignan desde CONTROLES (tienen su propio flujo:
## pausa, navegacion y aceptar). Se usan para avisar de posibles solapamientos.
const ACCIONES_INTERFAZ: Array[StringName] = [
	&"menu_up", &"menu_down", &"menu_accept", &"ui_cancel", &"ui_up", &"ui_down",
	&"ui_left", &"ui_right",
]

## Acciones de diagnostico que no se exponen en el panel.
const ACCIONES_OCULTAS: Array[StringName] = [&"dano_prueba"]

## Catalogo de acciones reasignables del juego.
## Cada entrada: accion, contexto (formas donde aplica) y etiqueta legible.
## El ORDEN de esta lista es el orden en que aparecen las filas del panel.
const CATALOGO := [
	# --- Movimiento y acciones comunes a todas las formas ---------------------
	{"accion": &"mover_adelante", "formas": [], "etiqueta": "Moverse hacia delante"},
	{"accion": &"mover_atras", "formas": [], "etiqueta": "Moverse hacia atrás"},
	{"accion": &"mover_izquierda", "formas": [], "etiqueta": "Moverse hacia la izquierda"},
	{"accion": &"mover_derecha", "formas": [], "etiqueta": "Moverse hacia la derecha"},
	{"accion": &"saltar", "formas": [], "etiqueta": "Saltar"},
	{"accion": &"atacar", "formas": [VELOCISTA, ACUATICO, FUERZA, COMBATE], "etiqueta": "Atacar"},
	# --- Compartidas por varias formas ---------------------------------------
	{"accion": &"correr", "formas": [HUMANO, ACUATICO, FUERZA, VUELO], "etiqueta": "Correr"},
	{"accion": &"agacharse", "formas": [HUMANO, ACUATICO, FUERZA], "etiqueta": "Agacharse"},
	# --- Velocista ------------------------------------------------------------
	{"accion": &"dash", "formas": [VELOCISTA], "etiqueta": "Dash"},
	{"accion": &"emote", "formas": [VELOCISTA], "etiqueta": "Emote"},
	{"accion": &"cargar_poder", "formas": [VELOCISTA, FUERZA], "etiqueta": "Cargar poder"},
	# --- Acuatico -------------------------------------------------------------
	{"accion": &"agua_habilidad_1", "formas": [ACUATICO], "etiqueta": "Habilidad de agua 1"},
	{"accion": &"agua_habilidad_2", "formas": [ACUATICO], "etiqueta": "Habilidad de agua 2"},
	{"accion": &"agua_habilidad_3", "formas": [ACUATICO], "etiqueta": "Habilidad de agua 3"},
	{"accion": &"agua_habilidad_4", "formas": [ACUATICO], "etiqueta": "Habilidad de agua 4"},
	{"accion": &"agua_turbo", "formas": [ACUATICO], "etiqueta": "Turbo acuático"},
	# --- Fuerza ---------------------------------------------------------------
	{"accion": &"fuerza_embestida", "formas": [FUERZA], "etiqueta": "Embestida"},
	{"accion": &"fuerza_slam", "formas": [FUERZA], "etiqueta": "Pisotón"},
	{"accion": &"fuerza_roca", "formas": [FUERZA], "etiqueta": "Levantar roca"},
	# --- Vuelo (Águila) -------------------------------------------------------
	{"accion": &"fly_down", "formas": [VUELO], "etiqueta": "Picar / descender"},
	{"accion": &"toggle_flight", "formas": [VUELO], "etiqueta": "Despegar / aterrizar"},
	{"accion": &"aim", "formas": [VUELO], "etiqueta": "Apuntar (OTS)"},
	{"accion": &"feather_fire", "formas": [VUELO], "etiqueta": "Plumas de proyectil"},
	{"accion": &"melee_light", "formas": [VUELO], "etiqueta": "Golpe (combo)"},
	{"accion": &"guard", "formas": [VUELO], "etiqueta": "Guardia de alas"},
	{"accion": &"grab", "formas": [VUELO], "etiqueta": "Garras (agarre aéreo)"},
	{"accion": &"palmazo", "formas": [VUELO], "etiqueta": "Palmazo de viento"},
	# --- Globales (en cualquier forma) ---------------------------------------
	{"accion": &"menu_transformaciones", "formas": [], "etiqueta": "Menú de transformaciones"},
]

## Textos alternativos por forma: misma accion, significado distinto segun la
## forma (p. ej. SHIFT es "Correr" en el Humano y "Nadar rápido" en el Acuático).
## Los nombres se mantienen CORTOS: la columna de acción del panel es estrecha y
## el texto que no cabe se recorta. El matiz va en la NOTA (segunda línea).
const ETIQUETAS_POR_FORMA := {
	"correr": {
		HUMANO: "Correr",
		ACUATICO: "Nadar rápido",
		FUERZA: "Correr",
		VUELO: "Boost",
	},
	"agacharse": {
		HUMANO: "Agacharse",
		ACUATICO: "Bucear",
		FUERZA: "Agacharse",
	},
	"saltar": {
		ACUATICO: "Saltar / ascender",
		FUERZA: "Saltar / supersalto",
		COMBATE: "Saltar (doble salto)",
		VUELO: "Subir / ascender",
	},
	"atacar": {
		VELOCISTA: "Atacar (combo)",
		ACUATICO: "Atacar (tierra o agua)",
		FUERZA: "Puñetazo / lanzar",
		COMBATE: "Atacar (combo)",
	},
	"cargar_poder": {
		VELOCISTA: "Cargar poder",
		FUERZA: "Patada",
	},
}

## Comentario breve que acompaña a la accion en el panel (siempre el mismo).
const NOTAS := {
	"mover_adelante": "Mantener",
	"mover_atras": "Mantener",
	"mover_izquierda": "Mantener",
	"mover_derecha": "Mantener",
	"saltar": "Desde el suelo",
	"atacar": "Pulsación única",
	"correr": "Mantener",
	"agacharse": "Mantener",
	"dash": "Pulsación única",
	"emote": "Pulsación única",
	"cargar_poder": "Mantener y soltar",
	"agua_habilidad_1": "Pulsación única",
	"agua_habilidad_2": "Pulsación única",
	"agua_habilidad_3": "Pulsación única",
	"agua_habilidad_4": "Pulsación única",
	"agua_turbo": "Mantener para impulsar",
	"fuerza_embestida": "Desde el suelo",
	"fuerza_slam": "Sólo en el aire",
	"fuerza_roca": "Desde el suelo",
	"fly_down": "Picar (mantener)",
	"toggle_flight": "Iniciar / aterrizar vuelo",
	"aim": "Mantener",
	"feather_fire": "Clic izq. (apuntando)",
	"melee_light": "Clic izq. (sin apuntar)",
	"guard": "Mantener",
	"grab": "E o G, sólo volando",
	"palmazo": "Pulsación única",
	"menu_transformaciones": "Abre y cierra",
}

## Notas que cambian según la forma (la misma accion se comporta distinto).
const NOTAS_POR_FORMA := {
	"saltar": {
		ACUATICO: "Mantener para ascender",
		FUERZA: "Mantener y soltar = supersalto",
		COMBATE: "Doble salto en el aire",
		VUELO: "Mantener en vuelo = subir",
	},
	"atacar": {
		VELOCISTA: "Encadena combo",
		ACUATICO: "En tierra o nadando",
		FUERZA: "Con la roca lista, la lanza",
		COMBATE: "Encadena combo",
	},
	"cargar_poder": {
		VELOCISTA: "Mantener para trazar",
		FUERZA: "Pulsación única",
	},
	"fuerza_roca": {
		FUERZA: "Luego pulsa atacar para lanzar",
	},
}

## Estado: accion -> InputEvent (la asignacion ACTUAL).
var _eventos: Dictionary = {}
## Valores de fabrica: accion -> InputEvent, tal como venian en project.godot.
var _originales: Dictionary = {}
## Avistamientos del primer arranque (para el informe/depuracion).
var _ultimo_error: String = ""
## Reaplicacion ya pedida y aun no ejecutada (ver _on_node_added).
var _pendiente_reaplicar: bool = false

func _ready() -> void:
	# Acciones NUEVAS de la forma VUELO (Águila): se registran ANTES de capturar
	# los valores de fábrica, para que queden reasignables como las demás. El
	# movimiento, el salto y el boost del vuelo reutilizan los controles del juego.
	_registrar_acciones_vuelo()
	_capturar_originales()
	_cargar()
	_aplicar_todo()
	# Limpieza de configuraciones de versiones anteriores (acciones que ya no
	# existen, como la antigua "transformacion_velocidad").
	_purgar_entradas_obsoletas()
	get_tree().node_added.connect(_on_node_added)

# ---------------------------------------------------------------- arranque
## Guarda una copia de la asignacion de fabrica de cada accion del catalogo, tal
## como viene en project.godot. Es la base de "restablecer".
func _capturar_originales() -> void:
	for entrada in CATALOGO:
		var accion: StringName = entrada["accion"]
		if not InputMap.has_action(accion):
			continue
		var ev := _primer_evento(accion)
		if ev != null:
			_originales[accion] = ev

## Primer evento asignado a una accion (o null).
func _primer_evento(accion: StringName) -> InputEvent:
	var lista: Array[InputEvent] = InputMap.action_get_events(accion)
	return lista[0] if not lista.is_empty() else null

## Reaplica en el InputMap todas las asignaciones actuales. Se llama al arrancar
## y tambien cuando se anaden nodos: si una escena nueva vuelve a registrar el
## mapa por defecto, las preferencias del jugador se recuperan sin recargar nada.
##
## OJO (bug del dash): reescribir los eventos de una accion DESCARTA su estado
## pulsado en el Input. El jugador sigue con la tecla apretada, pero el juego la
## ve suelta y el personaje se queda parado (y el dash pierde la direccion) hasta
## que suelta y vuelve a pulsar. Por eso aqui se salta toda accion que se este
## pulsando en este instante: su reaplicacion puede esperar a que se suelte.
func _aplicar_todo() -> void:
	_pendiente_reaplicar = false
	for accion in _eventos.keys():
		if InputMap.has_action(accion) and Input.is_action_pressed(accion):
			continue
		_escribir_en_inputmap(accion, _eventos[accion])

func _on_node_added(n: Node) -> void:
	# Las acciones del InputMap son globales y persisten; esto solo cubre el caso
	# de que algo vuelva a registrar el mapa por defecto en tiempo de ejecucion.
	# Se agrupa en UNA sola reaplicacion por fotograma: la ciudad o un modelo que
	# se carga anaden miles de nodos y no necesitan una pasada cada uno.
	if _pendiente_reaplicar or not (n is Control or n is Node3D):
		return
	_pendiente_reaplicar = true
	call_deferred("_aplicar_todo")

## Escribe UNA accion en el InputMap real (borrando sus eventos anteriores para
## no acumular asignaciones viejas). Si el mapa YA tiene esa misma asignacion no
## se toca nada: reescribir por reescribir era justo lo que borraba el estado de
## las teclas que el jugador mantiene pulsadas.
func _escribir_en_inputmap(accion: StringName, ev: InputEvent) -> void:
	if not InputMap.has_action(accion):
		return
	if _ya_en_inputmap(accion, ev):
		return
	InputMap.action_erase_events(accion)
	if ev != null:
		InputMap.action_add_event(accion, ev)

## ¿El InputMap ya tiene exactamente esa asignacion para la accion?
func _ya_en_inputmap(accion: StringName, ev: InputEvent) -> bool:
	var actuales: Array[InputEvent] = InputMap.action_get_events(accion)
	if ev == null:
		return actuales.is_empty()
	return actuales.size() == 1 and _mismo_evento(actuales[0], ev)

# ---------------------------------------------------------------- consulta
## Asignacion actual de una accion (o null).
func evento_de(accion: StringName) -> InputEvent:
	return _eventos.get(accion, null)

## Texto legible de la tecla/boton de una accion ("W", "ESPACIO", "CLIC IZQ."...).
func texto_de(accion: StringName) -> String:
	return texto_de_evento(_eventos.get(accion, null))

## Texto legible de un evento cualquiera.
func texto_de_evento(ev: InputEvent) -> String:
	if ev == null:
		return "SIN ASIGNAR"
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code: Key = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return nombre_tecla(code)
	if ev is InputEventMouseButton:
		return nombre_boton_raton((ev as InputEventMouseButton).button_index)
	if ev is InputEventJoypadButton:
		return "MANDO %d" % (ev as InputEventJoypadButton).button_index
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		return "EJE %d%s" % [m.axis, "+" if m.axis_value > 0.0 else "-"]
	return "?"

func nombre_tecla(code: Key) -> String:
	# Nombres cortos en mayusculas para que quepan en la columna del panel.
	var nombre := OS.get_keycode_string(code)
	if nombre.is_empty():
		return "?"
	match nombre:
		"Escape": return "ESC"
		"Space": return "ESPACIO"
		"Shift": return "SHIFT"
		"Ctrl": return "CTRL"
		"Alt": return "ALT"
		"Tab": return "TAB"
		"Enter": return "ENTER"
		"Backspace": return "RETROCESO"
		"Left": return "IZQUIERDA"
		"Right": return "DERECHA"
		"Up": return "ARRIBA"
		"Down": return "ABAJO"
	return nombre.to_upper()

func nombre_boton_raton(boton: int) -> String:
	match boton:
		MOUSE_BUTTON_LEFT: return "CLIC IZQ."
		MOUSE_BUTTON_RIGHT: return "CLIC DER."
		MOUSE_BUTTON_MIDDLE: return "CLIC CENTRAL"
		MOUSE_BUTTON_WHEEL_UP: return "RUEDA ARRIBA"
		MOUSE_BUTTON_WHEEL_DOWN: return "RUEDA ABAJO"
	return "RATÓN %d" % boton

## Etiqueta de la accion para una forma concreta (usa el texto especifico si lo hay).
func etiqueta_de(accion: StringName, forma: StringName) -> String:
	var por_forma: Dictionary = ETIQUETAS_POR_FORMA.get(String(accion), {})
	if por_forma.has(forma):
		return por_forma[forma]
	for entrada in CATALOGO:
		if entrada["accion"] == accion:
			return entrada["etiqueta"]
	return String(accion)

func nota_de(accion: StringName, forma: StringName = &"") -> String:
	var por_forma: Dictionary = NOTAS_POR_FORMA.get(String(accion), {})
	if por_forma.has(forma):
		return por_forma[forma]
	return String(NOTAS.get(String(accion), ""))

## Formas en las que se usa una accion (vacio = todas).
func formas_de(accion: StringName) -> Array:
	for entrada in CATALOGO:
		if entrada["accion"] == accion:
			return entrada["formas"]
	return []

## Acciones del catalogo que se usan en la forma indicada, en el orden del catalogo.
func acciones_para(forma: StringName) -> Array:
	var salida: Array = []
	for entrada in CATALOGO:
		var formas: Array = entrada["formas"]
		if formas.is_empty() or formas.has(forma):
			salida.append(entrada["accion"])
	return salida

# ---------------------------------------------------------------- conflictos
## ¿Las dos acciones pueden estar activas a la vez? Comparten forma si una es
## comun (sin lista) o si sus listas se cruzan.
func _se_solapan(a: StringName, b: StringName) -> bool:
	var fa: Array = formas_de(a)
	var fb: Array = formas_de(b)
	if fa.is_empty() or fb.is_empty():
		return true
	for f in fa:
		if fb.has(f):
			return true
	return false

## Busca otra accion reasignable que ya use ese evento y pueda estar activa a la
## vez. Devuelve la accion en conflicto, o &"" si no hay ninguna.
## `excluir` permite ignorar la propia accion que se esta reasignando.
func conflicto_para(accion: StringName, ev: InputEvent, excluir: StringName = &"") -> StringName:
	for otra in _eventos.keys():
		if otra == accion or otra == excluir:
			continue
		if not _se_solapan(accion, otra):
			continue
		if _mismo_evento(_eventos[otra], ev):
			return otra
	return &""

## Accion de INTERFAZ que ya usa ese evento (informativo: no bloquea, porque los
## menus y el juego no estan activos a la vez).
func interfaz_que_usa(ev: InputEvent) -> StringName:
	for accion in ACCIONES_INTERFAZ:
		if not InputMap.has_action(accion):
			continue
		for e in InputMap.action_get_events(accion):
			if _mismo_evento(e, ev):
				return accion
	return &""

func etiqueta_interfaz(accion: StringName) -> String:
	match accion:
		&"menu_up": return "navegar hacia arriba"
		&"menu_down": return "navegar hacia abajo"
		&"menu_accept": return "aceptar en los menús"
		&"ui_cancel": return "pausa / cancelar"
		&"ui_up": return "navegar hacia arriba"
		&"ui_down": return "navegar hacia abajo"
		&"ui_left": return "navegar a la izquierda"
		&"ui_right": return "navegar a la derecha"
	return String(accion)

## ¿El evento esta reservado (Escape, que es pausa/cancelar)? No se puede asignar.
## Se comprueban las dos codificaciones: un evento sintético puede traer sólo una.
func esta_reservado(ev: InputEvent) -> bool:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE
	return false

## ¿Es un evento aceptable como control? (tecla, boton de raton o mando).
func es_aceptable(ev: InputEvent) -> bool:
	return ev is InputEventKey or ev is InputEventMouseButton \
			or ev is InputEventJoypadButton or ev is InputEventJoypadMotion

## Compara dos eventos por su identidad funcional (tecla fisica / boton / eje).
func _mismo_evento(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		var ca: int = ka.physical_keycode if ka.physical_keycode != 0 else ka.keycode
		var cb: int = kb.physical_keycode if kb.physical_keycode != 0 else kb.keycode
		return ca == cb and ca != 0
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ma := a as InputEventJoypadMotion
		var mb := b as InputEventJoypadMotion
		return ma.axis == mb.axis and signf(ma.axis_value) == signf(mb.axis_value)
	return false

## Copia de un evento normalizada (tecla fisica, sin modificadores ni estado).
func duplicar_evento(ev: InputEvent) -> InputEvent:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var nk := InputEventKey.new()
		var code: Key = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		nk.physical_keycode = code
		return nk
	if ev is InputEventMouseButton:
		var m := ev as InputEventMouseButton
		var nm := InputEventMouseButton.new()
		nm.button_index = m.button_index
		return nm
	if ev is InputEventJoypadButton:
		var j := ev as InputEventJoypadButton
		var nj := InputEventJoypadButton.new()
		nj.button_index = j.button_index
		return nj
	if ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		var njm := InputEventJoypadMotion.new()
		njm.axis = jm.axis
		njm.axis_value = signf(jm.axis_value)
		return njm
	return null

# ---------------------------------------------------------------- asignacion
## Asigna `ev` a `accion`. Devuelve un Dictionary:
##   ok        : true si se aplico (o se intercambio)
##   conflicto : accion en conflicto (o "")
##   texto     : asignacion resultante
##   mensaje   : texto para la interfaz (vacio si todo fue bien)
func asignar(accion: StringName, ev: InputEvent) -> Dictionary:
	if not InputMap.has_action(accion):
		return _respuesta(false, &"", "Esa acción ya no existe.")
	if not es_aceptable(ev):
		return _respuesta(false, &"", "Entrada no válida.")
	if esta_reservado(ev):
		return _respuesta(false, &"", "ESC está reservado para pausar y cancelar.")

	var otro := conflicto_para(accion, ev)
	if otro != &"":
		# No se toca nada: el panel pedira confirmacion para intercambiar.
		return _respuesta(false, otro,
				"«%s» ya está asignada a «%s»." % [texto_de_evento(ev), etiqueta_de(otro, &"")])

	_eventos[accion] = duplicar_evento(ev)
	_escribir_en_inputmap(accion, _eventos[accion])
	_guardar()
	cambiado.emit()
	var aviso := ""
	var ui := interfaz_que_usa(_eventos[accion])
	if ui != &"":
		aviso = "Aviso: también se usa para %s." % etiqueta_interfaz(ui)
	return _respuesta(true, &"", texto_de(accion), aviso)

## Intercambia las asignaciones de dos acciones. Ninguna asignacion se pierde.
func intercambiar(a: StringName, b: StringName) -> Dictionary:
	if not (_eventos.has(a) and _eventos.has(b)):
		return _respuesta(false, &"", "No se pudo intercambiar.")
	var ea: InputEvent = _eventos[a]
	var eb: InputEvent = _eventos[b]
	_eventos[a] = eb
	_eventos[b] = ea
	_escribir_en_inputmap(a, _eventos[a])
	_escribir_en_inputmap(b, _eventos[b])
	_guardar()
	cambiado.emit()
	return _respuesta(true, &"", texto_de(a),
			"Intercambiadas: «%s» ↔ «%s»." % [etiqueta_de(a, &""), etiqueta_de(b, &"")])

## Devuelve una accion a su valor de fabrica.
func restablecer(accion: StringName) -> void:
	if not _originales.has(accion):
		return
	_eventos[accion] = duplicar_evento(_originales[accion])
	_escribir_en_inputmap(accion, _eventos[accion])
	_guardar()
	cambiado.emit()

## Devuelve TODAS las acciones reasignables a su valor de fabrica.
##
## Se recorre el catalogo COMPLETO, no solo la forma que el jugador este viendo:
## el restablecimiento es global. Los valores de fabrica NO salen del archivo
## guardado (que contiene las personalizaciones del jugador), sino de la copia
## que `_capturar_originales()` tomó del InputMap al arrancar, antes de aplicar
## ninguna preferencia.
##
## El resultado se guarda explicitamente en disco, de modo que los valores
## restablecidos siguen vigentes al cerrar y volver a abrir el juego. No se borra
## el archivo: asi no se pierde ninguna otra seccion que pudiera vivir en el.
func restablecer_todo() -> void:
	for accion in _originales.keys():
		_eventos[accion] = duplicar_evento(_originales[accion])
		_escribir_en_inputmap(accion, _eventos[accion])
	_guardar()
	cambiado.emit()

## ¿Hay alguna asignacion distinta de la de fabrica? (Para el informe/depuracion.)
func hay_personalizaciones() -> bool:
	for accion in _eventos.keys():
		if not _originales.has(accion):
			continue
		if not _mismo_evento(_eventos[accion], _originales[accion]):
			return true
	return false

func _respuesta(ok: bool, conflicto: StringName, texto: String, mensaje: String = "") -> Dictionary:
	return {"ok": ok, "conflicto": conflicto, "texto": texto, "mensaje": mensaje}

# ---------------------------------------------------------------- persistencia
## Serializa un evento a un Dictionary explicito (nada de texto de teclas: se
## guarda lo necesario para reconstruir la asignacion real).
func _serializar(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return {"tipo": "tecla",
				"codigo": int(k.physical_keycode if k.physical_keycode != 0 else k.keycode)}
	if ev is InputEventMouseButton:
		return {"tipo": "raton", "boton": int((ev as InputEventMouseButton).button_index)}
	if ev is InputEventJoypadButton:
		return {"tipo": "mando", "boton": int((ev as InputEventJoypadButton).button_index)}
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		return {"tipo": "eje", "eje": int(m.axis), "valor": signf(m.axis_value)}
	return {}

func _deserializar(d: Variant) -> InputEvent:
	if not (d is Dictionary):
		return null
	var tipo := String(d.get("tipo", ""))
	match tipo:
		"tecla":
			var nk := InputEventKey.new()
			nk.physical_keycode = int(d.get("codigo", 0)) as Key
			return nk if nk.physical_keycode != 0 else null
		"raton":
			var nm := InputEventMouseButton.new()
			nm.button_index = int(d.get("boton", 0)) as MouseButton
			return nm
		"mando":
			var nj := InputEventJoypadButton.new()
			nj.button_index = int(d.get("boton", 0)) as JoyButton
			return nj
		"eje":
			var njm := InputEventJoypadMotion.new()
			njm.axis = int(d.get("eje", 0)) as JoyAxis
			njm.axis_value = float(d.get("valor", 1.0))
			return njm
	return null

func _guardar() -> void:
	var cf := ConfigFile.new()
	# Se carga primero para no borrar nada ajeno que viviera en el archivo
	# (cualquier otra sección se conserva tal cual).
	cf.load(RUTA)
	# Se retiran las entradas de acciones que ya no se reasignan: si el jugador
	# guardo su configuracion con una version anterior que todavia tenia esa
	# accion, su referencia obsoleta desaparece sin provocar ningun error.
	if cf.has_section(SECCION):
		for clave in cf.get_section_keys(SECCION):
			if not _eventos.has(StringName(clave)):
				cf.erase_section_key(SECCION, clave)
	for accion in _eventos.keys():
		cf.set_value(SECCION, String(accion), _serializar(_eventos[accion]))
	var err := cf.save(RUTA)
	if err != OK:
		_ultimo_error = "No se pudo guardar %s (error %d)" % [RUTA, err]

## Retira del archivo guardado las acciones que ya no se reasignan (por ejemplo la
## antigua "transformacion_velocidad"). Una configuracion de una version anterior
## no deja asi referencias muertas ni provoca errores: simplemente se limpia.
## Las acciones desconocidas se ignoraban al cargar; esto ademas las borra.
func _purgar_entradas_obsoletas() -> void:
	var cf := ConfigFile.new()
	if cf.load(RUTA) != OK or not cf.has_section(SECCION):
		return
	var sobran: Array[String] = []
	for clave in cf.get_section_keys(SECCION):
		if not _eventos.has(StringName(clave)):
			sobran.append(String(clave))
	if sobran.is_empty():
		return
	for clave in sobran:
		cf.erase_section_key(SECCION, clave)
	cf.save(RUTA)

## Carga las preferencias. Empieza SIEMPRE por los valores de fabrica: si no hay
## archivo, o una entrada es ilegible, o la accion ya no existe, se queda con el
## valor de fabrica sin fallar.
func _cargar() -> void:
	for accion in _originales.keys():
		_eventos[accion] = duplicar_evento(_originales[accion])

	var cf := ConfigFile.new()
	if cf.load(RUTA) != OK:
		return
	if not cf.has_section(SECCION):
		return
	for accion in cf.get_section_keys(SECCION):
		var clave := StringName(accion)
		if not _eventos.has(clave):
			continue
		var ev := _deserializar(cf.get_value(SECCION, accion, null))
		if ev != null:
			_eventos[clave] = ev

# ---------------------------------------------------------------- acciones de VUELO
## Acciones cuyo nombre NO existe todavía en el proyecto y que usa la forma VUELO
## (Águila). Se registran aquí (autoridad del Input Map) con sus bindings de
## fábrica; si el proyecto ya tuviera una, NO se toca. El movimiento/salto/boost
## del vuelo se sirven de las acciones comunes (mover_*, saltar, correr).
##
## NOTA: feather_fire y melee_light comparten el clic izquierdo a propósito (el
## héroe decide por contexto: apuntando = pluma, si no = golpe; con presa en las
## garras = lanzamiento). La detección de conflictos los marca como "contextual",
## igual que SHIFT entre formas distintas.
const ACCIONES_VUELO := {
	&"fly_down": {"teclas": [KEY_X], "raton": []},
	&"toggle_flight": {"teclas": [KEY_C], "raton": []},
	&"aim": {"teclas": [], "raton": [MOUSE_BUTTON_RIGHT]},
	&"feather_fire": {"teclas": [], "raton": [MOUSE_BUTTON_LEFT]},
	&"melee_light": {"teclas": [], "raton": [MOUSE_BUTTON_LEFT]},
	&"guard": {"teclas": [KEY_Q], "raton": []},
	&"grab": {"teclas": [KEY_E, KEY_G], "raton": []},
	&"palmazo": {"teclas": [KEY_V], "raton": []},
	# Mirada con el stick derecho (mando). Se registran vacías para que el
	# personaje volador pueda consultarlas sin errores; el ratón sigue siendo
	# el control de cámara del proyecto.
	&"look_left": {"teclas": [], "raton": []},
	&"look_right": {"teclas": [], "raton": []},
	&"look_up": {"teclas": [], "raton": []},
	&"look_down": {"teclas": [], "raton": []},
	&"respawn": {"teclas": [], "raton": []},
}

func _registrar_acciones_vuelo() -> void:
	for accion: StringName in ACCIONES_VUELO.keys():
		if InputMap.has_action(accion):
			continue
		InputMap.add_action(accion, 0.2)
		var datos: Dictionary = ACCIONES_VUELO[accion]
		for t: Key in datos["teclas"]:
			var ek := InputEventKey.new()
			ek.physical_keycode = t
			InputMap.action_add_event(accion, ek)
		for b: MouseButton in datos["raton"]:
			var em := InputEventMouseButton.new()
			em.button_index = b
			InputMap.action_add_event(accion, em)