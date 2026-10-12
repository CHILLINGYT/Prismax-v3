class_name VueloInputDefaults
extends Object
## Registro OPCIONAL de las acciones de entrada que necesita el personaje volador.
##
## NO es un autoload y NO se ejecuta solo. El proyecto de destino lo invoca
## explícitamente si le faltan acciones. Solo AGREGA las acciones ausentes:
## nunca reemplaza ni modifica acciones que ya existan (así no rompe los
## controles de otros personajes del proyecto de destino).
##
## Uso (una vez, por ejemplo en el _ready() de la escena que instancia al héroe):
##     VueloInputDefaults.registrar_acciones_faltantes()
##
## Las teclas/botones replican EXACTAMENTE las del proyecto HARPY original
## (ver INPUT_MAP.md). Si querés otras, cambiá las entradas antes de llamar.

const ACCIONES := {
	"move_forward": {
		"keys": [KEY_W], "pad_buttons": [], "axis": [JOY_AXIS_LEFT_Y, -1.0],
		"mouse": [], "deadzone": 0.2,
	},
	"move_back": {
		"keys": [KEY_S], "pad_buttons": [], "axis": [JOY_AXIS_LEFT_Y, 1.0],
		"mouse": [], "deadzone": 0.2,
	},
	"move_left": {
		"keys": [KEY_A], "pad_buttons": [], "axis": [JOY_AXIS_LEFT_X, -1.0],
		"mouse": [], "deadzone": 0.2,
	},
	"move_right": {
		"keys": [KEY_D], "pad_buttons": [], "axis": [JOY_AXIS_LEFT_X, 1.0],
		"mouse": [], "deadzone": 0.2,
	},
	"jump": {
		"keys": [KEY_SPACE], "pad_buttons": [JOY_BUTTON_A], "axis": [],
		"mouse": [], "deadzone": 0.2,
	},
	"sprint": {
		"keys": [KEY_SHIFT], "pad_buttons": [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_LEFT_STICK],
		"axis": [], "mouse": [], "deadzone": 0.2,
	},
	# PRISMAX: C activa el vuelo (F abre el menú de transformaciones) y la picada
	# se separa a X para que una sola tecla no haga dos cosas.
	"toggle_flight": {
		"keys": [KEY_C], "pad_buttons": [JOY_BUTTON_Y], "axis": [],
		"mouse": [], "deadzone": 0.2,
	},
	"fly_down": {
		"keys": [KEY_X], "pad_buttons": [JOY_BUTTON_B], "axis": [],
		"mouse": [], "deadzone": 0.2,
	},
	"feather_fire": {
		"keys": [], "pad_buttons": [], "axis": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
		"mouse": [MOUSE_BUTTON_LEFT], "deadzone": 0.2,
	},
	"aim": {
		"keys": [], "pad_buttons": [], "axis": [JOY_AXIS_TRIGGER_LEFT, 1.0],
		"mouse": [MOUSE_BUTTON_RIGHT], "deadzone": 0.2,
	},
	"melee_light": {
		"keys": [], "pad_buttons": [JOY_BUTTON_X], "axis": [],
		"mouse": [MOUSE_BUTTON_LEFT], "deadzone": 0.2,
	},
	"guard": {
		"keys": [KEY_Q], "pad_buttons": [JOY_BUTTON_RIGHT_SHOULDER], "axis": [],
		"mouse": [], "deadzone": 0.2,
	},
	"grab": {
		"keys": [KEY_E, KEY_G], "pad_buttons": [JOY_BUTTON_X], "axis": [],
		"mouse": [], "deadzone": 0.2,
	},
	"palmazo": {
		"keys": [KEY_V], "pad_buttons": [], "axis": [],
		"mouse": [], "deadzone": 0.2,
	},
	"respawn": {
		"keys": [KEY_R], "pad_buttons": [JOY_BUTTON_BACK], "axis": [],
		"mouse": [], "deadzone": 0.2,
	},
	"look_left": {
		"keys": [], "pad_buttons": [], "axis": [JOY_AXIS_RIGHT_X, -1.0],
		"mouse": [], "deadzone": 0.2,
	},
	"look_right": {
		"keys": [], "pad_buttons": [], "axis": [JOY_AXIS_RIGHT_X, 1.0],
		"mouse": [], "deadzone": 0.2,
	},
	"look_up": {
		"keys": [], "pad_buttons": [], "axis": [JOY_AXIS_RIGHT_Y, -1.0],
		"mouse": [], "deadzone": 0.2,
	},
	"look_down": {
		"keys": [], "pad_buttons": [], "axis": [JOY_AXIS_RIGHT_Y, 1.0],
		"mouse": [], "deadzone": 0.2,
	},
}


## Acciones que habilitan habilidades concretas: el personaje arranca y vuela
## sin ellas, pero las habilidades asociadas quedan inertes. Input opcional.
const OPCIONALES := ["grab", "palmazo"]


## Devuelve los nombres de las acciones que FALTAN en el Input Map actual,
## sin modificar nada. Ideal para auditar antes de registrar.
static func acciones_faltantes() -> PackedStringArray:
	var faltan := PackedStringArray()
	for nombre: String in ACCIONES.keys():
		if not InputMap.has_action(nombre):
			faltan.append(nombre)
	return faltan


## Devuelve las acciones OPCIONALES que faltan (subconjunto de las anteriores).
static func opcionales_faltantes() -> PackedStringArray:
	var faltan := PackedStringArray()
	for nombre: String in OPCIONALES:
		if not InputMap.has_action(nombre):
			faltan.append(nombre)
	return faltan


## Agrega SOLO las acciones ausentes. Devuelve la lista de las agregadas.
static func registrar_acciones_faltantes() -> PackedStringArray:
	var agregadas := PackedStringArray()
	for nombre: String in ACCIONES.keys():
		if InputMap.has_action(nombre):
			continue
		var datos: Dictionary = ACCIONES[nombre]
		InputMap.add_action(nombre, datos["deadzone"])
		for tecla: Key in datos["keys"]:
			var ev := InputEventKey.new()
			ev.physical_keycode = tecla
			InputMap.action_add_event(nombre, ev)
		for boton: JoyButton in datos["pad_buttons"]:
			var ev_btn := InputEventJoypadButton.new()
			ev_btn.button_index = boton
			InputMap.action_add_event(nombre, ev_btn)
		for boton_raton: MouseButton in datos["mouse"]:
			var ev_mouse := InputEventMouseButton.new()
			ev_mouse.button_index = boton_raton
			InputMap.action_add_event(nombre, ev_mouse)
		var eje: Array = datos["axis"]
		if eje.size() == 2:
			var ev_eje := InputEventJoypadMotion.new()
			ev_eje.axis = eje[0]
			ev_eje.axis_value = eje[1]
			InputMap.action_add_event(nombre, ev_eje)
		agregadas.append(nombre)
	return agregadas