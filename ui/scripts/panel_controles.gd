class_name PanelControles
extends Control

## Panel CONTROLES de CONFIGURACIÓN: amplía el panel existente del menú de pausa
## (mismo fondo, tipografía y panel derecho) con:
##
##   · Selector de transformación (flechas < > + icono + nombre).
##   · Lista de dos columnas: tecla/botón | acción, generada a partir de las
##     acciones REALES de la forma seleccionada.
##   · Reasignación real: pulsar una fila entra en modo captura ("PULSA UNA
##     TECLA...") y la entrada elegida se escribe en el InputMap a través del
##     autoload AjustesControles (que además la persiste).
##   · Detección de conflictos contextual: dos acciones que nunca pueden estar
##     activas a la vez (formas distintas) pueden compartir tecla.
##
## Sólo cambia CONTROLES: no toca animaciones, estados, colisiones ni combate.
##
## Los iconos son los MISMOS del HUD (res://personaje/hud_transformacion/iconos/):
## no se inventan recursos nuevos.

## Avisos de estado de la captura. El menú de pausa NO los necesita (consulta
## `esta_capturando()`), pero quedan disponibles para ampliaciones futuras
## (por ejemplo, silenciar un sonido de interfaz mientras se captura).
signal captura_iniciada
signal captura_terminada

## Formas jugables del controlador principal, en orden de recorrido.
## `id` conecta con el catálogo de AjustesControles y con el ID del HUD.
const FORMAS := [
	{"id": &"humano",    "nombre": "HUMANO",            "icono": "res://personaje/hud_transformacion/iconos/leo_humano.png"},
	{"id": &"velocista", "nombre": "VELOCISTA",         "icono": "res://personaje/hud_transformacion/iconos/velocidad.png"},
	{"id": &"acuatico",  "nombre": "ACUÁTICO (PES)",    "icono": "res://personaje/hud_transformacion/iconos/pes.png"},
	{"id": &"fuerza",    "nombre": "FUERZA (TANQUE)",   "icono": "res://personaje/hud_transformacion/iconos/tanque.png"},
	{"id": &"combate",   "nombre": "COMBATE",           "icono": "res://personaje/hud_transformacion/iconos/combate.png"},
]

## Colores coherentes con el resto del menú de pausa.
const COLOR_ACCION := Color(0.80, 0.82, 0.86, 1)
const COLOR_NOTA := Color(0.58, 0.60, 0.65, 1)
const COLOR_FONDO_FILA := Color(1, 1, 1, 0.035)
const COLOR_FONDO_HOVER := Color(1, 1, 1, 0.10)
const COLOR_FONDO_CAPTURA := Color(0.98, 0.76, 0.28, 0.18)
const COLOR_BORDE_CAPTURA := Color(0.98, 0.76, 0.28, 0.85)
const COLOR_HINT := Color(0.62, 0.64, 0.68, 1)
const COLOR_HINT_AVISO := Color(0.98, 0.78, 0.36, 1)
const COLOR_INFO := Color(0.55, 0.57, 0.62, 1)

const ALTO_FILA := 38.0
const ANCHO_TECLA := 136.0
## Pista por defecto del pie: se recupera cuando termina cualquier acción.
const PISTA_BASE := "Pulsa una fila para cambiar su tecla   ·   W / S eligen una fila"
## Pregunta de la confirmación de restablecimiento.
const PREGUNTA_RESET := "¿Quieres restablecer todas las teclas a sus valores predeterminados?"

@onready var _prev: Button = %ControlesPrev
@onready var _next: Button = %ControlesNext
@onready var _icono: TextureRect = %ControlesIcono
@onready var _nombre_forma: Label = %ControlesNombreForma
@onready var _rows: VBoxContainer = %ControlesRows
@onready var _scroll: ScrollContainer = %ControlesScroll
@onready var _hint: Label = %ControlesHint
## Botón RESTABLECER TECLAS y su confirmación en dos pasos.
@onready var _reset_btn: Button = %ControlesRestablecer
@onready var _confirmar_fila: Control = %ControlesConfirmarFila
@onready var _cancelar_btn: Button = %ControlesCancelar
@onready var _confirmar_btn: Button = %ControlesConfirmarBtn

## Índice de la forma mostrada (índice en FORMAS).
var _forma_idx: int = 0
## Datos de cada fila mostrada, en orden.
var _filas: Array[Dictionary] = []
## Índice de la fila resaltada con el teclado/mando.
var _seleccion: int = 0
## Acción cuya nueva tecla estamos esperando (&"" = sin captura).
var _captura_accion: StringName = &""
## Conflicto pendiente de confirmar: acción con la que intercambiaríamos.
var _conflicto_accion: StringName = &""
## Evento que provocó el conflicto pendiente.
var _conflicto_evento: InputEvent = null
## ¿Está visible la confirmación de "restablecer todas las teclas"?
var _confirmando_reset: bool = false

func _ready() -> void:
	_prev.pressed.connect(func() -> void: cambiar_forma(-1))
	_next.pressed.connect(func() -> void: cambiar_forma(1))
	_reset_btn.pressed.connect(pedir_restablecer)
	_cancelar_btn.pressed.connect(cancelar_restablecer)
	_confirmar_btn.pressed.connect(_ejecutar_restablecer)
	_estilizar_boton(_reset_btn)
	_estilizar_boton(_cancelar_btn)
	_estilizar_boton(_confirmar_btn, true)
	_confirmar_fila.visible = false
	activar()

# ---------------------------------------------------------------- ciclo
## Prepara el panel para mostrarse: vuelve a Humano y reconstruye la lista.
## Este selector es SOLO de consulta: no transforma al personaje en partida.
func activar() -> void:
	_forma_idx = 0
	_seleccion = 0
	_cancelar_captura()
	_cerrar_confirmacion_reset()
	_reconstruir()

func desactivar() -> void:
	_cancelar_captura()
	_cerrar_confirmacion_reset()

func esta_capturando() -> bool:
	return _captura_accion != &""

## ¿Está el panel pidiendo confirmación para restablecer las teclas?
func esta_confirmando() -> bool:
	return _confirmando_reset

# ---------------------------------------------------------------- selector
## Cambia de transformación con recorrido circular (tras la última, la primera).
func cambiar_forma(paso: int) -> void:
	if FORMAS.is_empty():
		return
	# Con la confirmación abierta, las flechas no deben cambiar de forma.
	if _confirmando_reset:
		return
	_cancelar_captura()
	_forma_idx = wrapi(_forma_idx + paso, 0, FORMAS.size())
	_seleccion = 0
	_reconstruir()
	# Selector con flechas: sonido `siyno` una vez por cambio efectivo de forma.
	SonidoUI.reproducir_siyno()

func _forma_actual() -> Dictionary:
	return FORMAS[clampi(_forma_idx, 0, FORMAS.size() - 1)]

## Reconstruye icono, nombre y lista de filas de la forma actual.
func _reconstruir() -> void:
	var forma: Dictionary = _forma_actual()
	_nombre_forma.text = String(forma["nombre"])
	_cargar_icono(String(forma["icono"]))
	_construir_filas(forma["id"])
	_pista(PISTA_BASE)

## Carga el icono del HUD. Si el recurso no existiera, se deja el marco vacío sin
## inventar ninguna imagen sustituta.
func _cargar_icono(ruta: String) -> void:
	if ResourceLoader.exists(ruta):
		_icono.texture = load(ruta)
	else:
		_icono.texture = null

# ---------------------------------------------------------------- lista
## Crea las filas de una forma: primero sus acciones reasignables (según el
## catálogo real) y después los controles informativos (ratón, ESC...).
func _construir_filas(forma: StringName) -> void:
	for hijo in _rows.get_children():
		hijo.queue_free()
	_filas.clear()

	for accion in AjustesControles.acciones_para(forma):
		_crear_fila_accion(accion, forma)
	for extra in _extras_de(forma):
		_crear_fila_info(String(extra["tecla"]), String(extra["texto"]), String(extra["nota"]))

	_resaltar()

## Controles reales que NO se reasignan (y por qué), para que el jugador los vea.
func _extras_de(forma: StringName) -> Array:
	var extras: Array = [
		{"tecla": "RATÓN", "texto": "Mirar alrededor", "nota": "Fijo (se ajusta en JUGABILIDAD)"},
	]
	if forma == AjustesControlesService.FUERZA:
		extras.append({"tecla": "ESC", "texto": "Cancelar habilidad", "nota": "Fijo (pausa/cancelar)"})
	return extras

## Fila reasignable: [ tecla ]  Acción  + nota corta.
func _crear_fila_accion(accion: StringName, forma: StringName) -> void:
	var fila := _base_fila()
	var tecla := _crear_etiqueta_tecla()
	var texto := _crear_etiqueta_accion(AjustesControles.etiqueta_de(accion, forma),
			AjustesControles.nota_de(accion, forma))
	_rellenar(fila, tecla, texto)

	var datos := {
		"accion": accion,
		"editable": true,
		"fondo": fila.get_node("Fondo"),
		"etiqueta_tecla": tecla,
		"etiqueta_accion": texto.get_node("Nombre"),
		"nota": texto.get_node("Nota"),
	}
	_filas.append(datos)
	_actualizar_fila(datos)
	_conectar_fila(fila, datos)

## Fila informativa (no editable): se muestra atenuada.
func _crear_fila_info(tecla_texto: String, texto: String, nota: String) -> void:
	var fila := _base_fila()
	var tecla := _crear_etiqueta_tecla()
	tecla.text = tecla_texto
	tecla.add_theme_color_override("font_color", COLOR_INFO)
	var accion := _crear_etiqueta_accion(texto, nota)
	_rellenar(fila, tecla, accion)

	var datos := {
		"accion": &"",
		"editable": false,
		"fondo": fila.get_node("Fondo"),
		"etiqueta_tecla": tecla,
		"etiqueta_accion": accion.get_node("Nombre"),
		"nota": accion.get_node("Nota"),
	}
	_filas.append(datos)
	_conectar_fila(fila, datos)

# ---------------------------------------------------------------- construcción
func _base_fila() -> Control:
	var fila := Control.new()
	fila.custom_minimum_size = Vector2(0, ALTO_FILA)
	fila.mouse_filter = Control.MOUSE_FILTER_STOP

	var fondo := ColorRect.new()
	fondo.name = "Fondo"
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fondo.color = COLOR_FONDO_FILA
	fila.add_child(fondo)
	return fila

## Recuadro de la tecla (aspecto de "botón") con su etiqueta centrada.
func _crear_etiqueta_tecla() -> Label:
	var marco := PanelContainer.new()
	marco.name = "MarcoTecla"
	marco.custom_minimum_size = Vector2(ANCHO_TECLA, 0)
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fondo_tecla(marco, false)

	var etiqueta := Label.new()
	etiqueta.name = "Tecla"
	etiqueta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	etiqueta.clip_text = true
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiqueta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	etiqueta.add_theme_color_override("font_color", COLOR_ACCION)
	etiqueta.add_theme_font_size_override("font_size", 14)
	marco.add_child(etiqueta)
	return etiqueta

func fondo_tecla(marco: PanelContainer, capturando: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_FONDO_CAPTURA if capturando else Color(1, 1, 1, 0.07)
	sb.border_color = COLOR_BORDE_CAPTURA if capturando else Color(1, 1, 1, 0.22)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	marco.add_theme_stylebox_override("panel", sb)

## Nombre de la acción (grande) + nota corta (pequeña) en la columna derecha.
func _crear_etiqueta_accion(texto: String, nota: String) -> VBoxContainer:
	var caja := VBoxContainer.new()
	caja.name = "Accion"
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caja.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caja.add_theme_constant_override("separation", 0)

	var nombre := Label.new()
	nombre.name = "Nombre"
	nombre.text = texto
	nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nombre.add_theme_color_override("font_color", COLOR_ACCION)
	nombre.add_theme_font_size_override("font_size", 15)
	caja.add_child(nombre)

	var nota_lbl := Label.new()
	nota_lbl.name = "Nota"
	nota_lbl.text = nota
	nota_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nota_lbl.add_theme_color_override("font_color", COLOR_NOTA)
	nota_lbl.add_theme_font_size_override("font_size", 11)
	caja.add_child(nota_lbl)
	return caja

func _rellenar(fila: Control, tecla: Label, accion: Control) -> void:
	var caja := HBoxContainer.new()
	caja.name = "Contenido"
	caja.set_anchors_preset(Control.PRESET_FULL_RECT)
	caja.offset_left = 6
	caja.offset_right = -6
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_theme_constant_override("separation", 12)
	caja.add_child(tecla.get_parent())
	caja.add_child(accion)
	fila.add_child(caja)
	_rows.add_child(fila)

func _conectar_fila(fila: Control, _datos: Dictionary) -> void:
	var indice := _filas.size() - 1
	fila.mouse_entered.connect(_on_fila_hover.bind(indice))
	fila.gui_input.connect(_on_fila_input.bind(indice))

# ---------------------------------------------------------------- estado visual
## Refleja la asignación real de la acción en la fila correspondiente.
func _actualizar_fila(datos: Dictionary) -> void:
	var accion: StringName = datos["accion"]
	var etiqueta: Label = datos["etiqueta_tecla"]
	var marco: PanelContainer = etiqueta.get_parent()
	if _captura_accion == accion:
		etiqueta.text = "PULSA UNA TECLA…"
		etiqueta.add_theme_color_override("font_color", COLOR_HINT_AVISO)
		etiqueta.add_theme_font_size_override("font_size", 12)
		fondo_tecla(marco, true)
	else:
		etiqueta.text = AjustesControles.texto_de(accion)
		etiqueta.add_theme_color_override("font_color", COLOR_ACCION)
		etiqueta.add_theme_font_size_override("font_size", 14)
		fondo_tecla(marco, false)

## Pinta el resaltado de selección/hover de todas las filas.
func _resaltar() -> void:
	for i in _filas.size():
		var datos: Dictionary = _filas[i]
		var fondo: ColorRect = datos["fondo"]
		var es_sel: bool = i == _seleccion
		if _captura_accion != &"" and datos["accion"] == _captura_accion:
			fondo.color = COLOR_FONDO_CAPTURA
		elif es_sel:
			# Las filas fijas se resaltan menos: se ven, pero no invitan a pulsarlas.
			fondo.color = COLOR_FONDO_HOVER if datos["editable"] else Color(1, 1, 1, 0.055)
		else:
			fondo.color = COLOR_FONDO_FILA

## Deja visible la fila seleccionada dentro del ScrollContainer.
func _asegurar_visible() -> void:
	if _seleccion < 0 or _seleccion >= _filas.size():
		return
	var nodo: Control = _filas[_seleccion]["fondo"].get_parent()
	_scroll.ensure_control_visible(nodo)

func _pista(texto: String, aviso: bool = false) -> void:
	_hint.text = texto
	_hint.add_theme_color_override("font_color", COLOR_HINT_AVISO if aviso else COLOR_HINT)

# ---------------------------------------------------------------- navegación
## Mueve la selección con el teclado/mando (lo llama el menú de pausa).
func mover_seleccion(paso: int) -> void:
	if _filas.is_empty() or _confirmando_reset:
		return
	# Navegación entre filas: sonido `cursor` solo si cambia de fila.
	if _filas.size() > 1:
		SonidoUI.reproducir_cursor()
	_seleccion = wrapi(_seleccion + paso, 0, _filas.size())
	_resaltar()
	_asegurar_visible()

## Activa la fila seleccionada: entra en modo captura si es reasignable.
## Con la confirmación de restablecer abierta, ACEPTAR equivale a RESTABLECER.
func confirmar() -> void:
	if _confirmando_reset:
		_ejecutar_restablecer()
		return
	if _seleccion < 0 or _seleccion >= _filas.size():
		return
	var datos: Dictionary = _filas[_seleccion]
	if not datos["editable"]:
		_pista("Ese control es fijo y no se puede reasignar.")
		return
	SonidoUI.reproducir_click()
	_iniciar_captura(datos["accion"])

func _on_fila_hover(indice: int) -> void:
	if _seleccion == indice:
		return
	# El cursor entró en OTRA fila: un único sonido de navegación.
	SonidoUI.reproducir_cursor()
	_seleccion = indice
	_resaltar()

func _on_fila_input(event: InputEvent, indice: int) -> void:
	if esta_capturando() or _confirmando_reset:
		return
	if not (event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		return
	SonidoUI.reproducir_click()
	_seleccion = indice
	_resaltar()
	var datos: Dictionary = _filas[indice]
	if not datos["editable"]:
		_pista("Ese control es fijo y no se puede reasignar.")
	else:
		_iniciar_captura(datos["accion"])
	# La pulsación que ABRE la captura no debe capturarse a sí misma.
	accept_event()

# ---------------------------------------------------------------- captura
func _iniciar_captura(accion: StringName) -> void:
	_captura_accion = accion
	_conflicto_accion = &""
	_conflicto_evento = null
	for datos in _filas:
		_actualizar_fila(datos)
	_resaltar()
	_pista("Pulsa la tecla o el botón que quieras asignar. ESC cancela.")
	captura_iniciada.emit()

func _cancelar_captura() -> void:
	if _captura_accion == &"":
		return
	var anterior := _captura_accion
	_captura_accion = &""
	_conflicto_accion = &""
	_conflicto_evento = null
	for datos in _filas:
		_actualizar_fila(datos)
	_resaltar()
	if anterior != &"":
		_pista("Asignación sin cambios.")
	captura_terminada.emit()

## Fin correcto de la captura, con la nueva asignación ya aplicada.
func _cerrar_captura_con(mensaje: String) -> void:
	_captura_accion = &""
	_conflicto_accion = &""
	_conflicto_evento = null
	for datos in _filas:
		_actualizar_fila(datos)
	_resaltar()
	_pista(mensaje)
	captura_terminada.emit()

## Captura de entrada: se ejecuta en _input, ANTES del gui del menú y de
## _unhandled_input, de modo que la pulsación que elige la nueva tecla no abre ni
## cierra menús ni dispara ninguna habilidad.
func _input(event: InputEvent) -> void:
	if _captura_accion == &"":
		# La confirmación de restablecer también se cancela con ESC, y ese ESC se
		# consume: no debe cerrar además el panel de configuración.
		if _confirmando_reset and _es_escape(event):
			cancelar_restablecer()
			get_viewport().set_input_as_handled()
			accept_event()
		return
	if _es_escape(event):
		_cancelar_captura()
	elif event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		_intentar_asignar(event)
	elif event is InputEventMouseButton and event.pressed:
		_intentar_asignar(event)
	elif event is InputEventJoypadButton and event.pressed:
		_intentar_asignar(event)
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6:
		_intentar_asignar(event)
	# Mientras se captura, la entrada no llega a nada más (ni al juego ni al menú).
	get_viewport().set_input_as_handled()
	accept_event()

## ¿El evento es la tecla ESC? Se comprueban las dos codificaciones (lógica y
## física) porque un evento sintético puede traer sólo una de las dos, y ESC debe
## cancelar SIEMPRE la captura en lugar de convertirse en la nueva asignación.
func _es_escape(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return false
	var k := event as InputEventKey
	return k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE

## Aplica la entrada elegida, resolviendo antes los conflictos.
func _intentar_asignar(event: InputEvent) -> void:
	var accion := _captura_accion
	var evento := AjustesControles.duplicar_evento(event)
	if evento == null:
		return
	var resultado: Dictionary = AjustesControles.asignar(accion, evento)

	if bool(resultado["ok"]):
		var texto := String(resultado["texto"])
		var etiqueta := AjustesControles.etiqueta_de(accion, _forma_actual()["id"])
		var mensaje := "«%s» ahora es «%s»." % [etiqueta, texto]
		if String(resultado["mensaje"]) != "":
			mensaje += " " + String(resultado["mensaje"])
		_cerrar_captura_con(mensaje)
		return

	var conflicto: StringName = resultado["conflicto"]
	if conflicto == &"":
		# Entrada no válida o reservada: no se cierra la captura, sólo se avisa.
		_pista(String(resultado["mensaje"]), true)
		return

	# Conflicto real: hay que confirmar el intercambio. La segunda pulsación de la
	# MISMA tecla intercambia las dos asignaciones (no se pierde ninguna).
	var etiqueta_conflicto := AjustesControles.etiqueta_de(conflicto, _forma_actual()["id"])
	if _conflicto_accion == conflicto and AjustesControles.texto_de_evento(_conflicto_evento) \
			== AjustesControles.texto_de_evento(evento):
		var res: Dictionary = AjustesControles.intercambiar(accion, conflicto)
		_cerrar_captura_con(String(res["mensaje"]))
		return

	_conflicto_accion = conflicto
	_conflicto_evento = evento
	_pista("«%s» ya está asignada a «%s». Pulsa otra vez para intercambiar, o ESC para cancelar."
			% [AjustesControles.texto_de_evento(evento), etiqueta_conflicto], true)

# ---------------------------------------------------------------- restablecer
## Pide confirmación. El restablecimiento afecta a TODAS las teclas reasignables
## del juego (no sólo a la forma que se está viendo), así que nunca se aplica de
## un solo clic.
func pedir_restablecer() -> void:
	if _confirmando_reset:
		return
	SonidoUI.reproducir_click()
	_cancelar_captura()
	_confirmando_reset = true
	_reset_btn.visible = false
	_confirmar_fila.visible = true
	_pista(PREGUNTA_RESET, true)

## Cancela la confirmación sin tocar ninguna asignación.
func cancelar_restablecer() -> void:
	if not _confirmando_reset:
		return
	SonidoUI.reproducir_click()
	_cerrar_confirmacion_reset()
	_pista("Restablecimiento cancelado: no se cambió ninguna tecla.")

## Aplica el restablecimiento global y refresca la lista al instante, de modo que
## las teclas mostradas en TODAS las formas son ya las de fábrica.
func _ejecutar_restablecer() -> void:
	SonidoUI.reproducir_click()
	AjustesControles.restablecer_todo()
	_cancelar_captura()
	_cerrar_confirmacion_reset()
	_reconstruir()
	_pista("Controles restablecidos correctamente")

## Cierra la confirmación y devuelve el pie a su estado normal.
func _cerrar_confirmacion_reset() -> void:
	_confirmando_reset = false
	_confirmar_fila.visible = false
	_reset_btn.visible = true

# ---------------------------------------------------------------- estilo
## Da a un Button el mismo aspecto que el resto del menú: recuadro redondeado
## tenue (como los recuadros de tecla), tipografía del panel y resaltado al
## pasar por encima. `acento` lo tiñe con el dorado que el menú usa para lo
## importante (aquí, la acción que sí aplica el cambio).
func _estilizar_boton(boton: Button, acento: bool = false) -> void:
	boton.flat = false
	boton.focus_mode = Control.FOCUS_NONE
	boton.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	boton.add_theme_font_size_override("font_size", 13)
	var tinte := Color(0.98, 0.76, 0.28) if acento else Color(1, 1, 1)
	boton.add_theme_stylebox_override("normal", _estilo_boton(tinte, 0.07, 0.22))
	boton.add_theme_stylebox_override("hover", _estilo_boton(tinte, 0.16, 0.42))
	boton.add_theme_stylebox_override("pressed", _estilo_boton(tinte, 0.26, 0.72))
	boton.add_theme_stylebox_override("disabled", _estilo_boton(tinte, 0.03, 0.10))
	boton.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94, 1))
	boton.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	boton.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))

func _estilo_boton(tinte: Color, alfa_fondo: float, alfa_borde: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tinte.r, tinte.g, tinte.b, alfa_fondo)
	sb.border_color = Color(tinte.r, tinte.g, tinte.b, alfa_borde)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb