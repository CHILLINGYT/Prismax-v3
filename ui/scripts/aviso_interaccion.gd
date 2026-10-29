class_name AvisoInteraccion
extends PanelContainer
## =============================================================================
##  AVISO DE INTERACCIÓN ("Presiona [E] para entrar a la casa de Leo")
## =============================================================================
##  Componente ÚNICO para todos los avisos contextuales del juego (HUD y NPC):
##  antes había dos copias del mismo panel con estilo puesto a mano.
##
##  SÓLO es presentación: quien lo usa decide CUÁNDO se muestra y QUÉ dice
##  (`mostrar(texto)` / `ocultar()`); el texto llega tal cual y se conserva entero
##  en el hijo oculto `Texto` (lo leen las pruebas y sirve de fuente de verdad).
##
##  La tecla se dibuja como un KEYCAP en lugar de la letra suelta:
##   · se busca en el texto la letra de la tecla como palabra suelta ("E");
##   · el keycap muestra la tecla REALMENTE asignada a `accion` en el InputMap
##     (si el jugador la reasigna en Ajustes, el aviso dice la tecla correcta);
##   · ícono de Kenney Input Prompts (CC0) si existe; si no, un keycap del tema.
##  Si el texto no nombra ninguna tecla (p. ej. el aviso del agua), se muestra
##  sólo el texto.
##
##  Estilo: el del tema central `res://ui/tema/tema_juego.tres` (velo oscuro sin
##  caja, Barlow con contorno y sombra). Entrada: fundido + subida corta; salida:
##  fundido.

const TEMA := preload("res://ui/tema/tema_juego.tres")
const DIR_ICONOS := "res://assets/ui/kenney_input_prompts/"
## Letra que los textos del juego usan para nombrar la tecla de interacción.
const LETRA_EN_TEXTO := "E"
const DURACION_ENTRADA := 0.2
const DURACION_SALIDA := 0.16
const SUBIDA := 12.0

## Acción del InputMap cuya tecla se dibuja.
@export var accion: StringName = &"interactuar"
## Tamaño (px) del keycap.
@export var tam_tecla := 46.0

var _fila: HBoxContainer
var _antes: Label
var _despues: Label
var _tecla: Control
var _texto: Label            ## texto completo, oculto (fuente de verdad)
var _tween: Tween
var _mostrado := false
var _base_y := 0.0


func _init() -> void:
	theme = TEMA
	theme_type_variation = &"HudVelo"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texto = Label.new()
	_texto.name = "Texto"
	_texto.visible = false
	add_child(_texto)
	_fila = HBoxContainer.new()
	_fila.name = "Fila"
	_fila.alignment = BoxContainer.ALIGNMENT_CENTER
	_fila.add_theme_constant_override("separation", 10)
	_fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fila)
	_antes = _etiqueta("Antes")
	_fila.add_child(_antes)
	_despues = _etiqueta("Despues")
	_fila.add_child(_despues)
	modulate.a = 0.0
	visible = false


func _etiqueta(nombre: String) -> Label:
	var l := Label.new()
	l.name = nombre
	l.theme_type_variation = &"HudAviso"
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Texto completo que muestra ahora (el de origen, sin tocar).
func texto() -> String:
	return _texto.text


## Muestra (o actualiza) el aviso. Mismo texto = no hace nada (sin parpadeo).
func mostrar(nuevo: String) -> void:
	if nuevo != _texto.text:
		_componer(nuevo)
	if not _mostrado:
		_mostrado = true
		_animar(true)


func ocultar() -> void:
	if not _mostrado:
		return
	_mostrado = false
	_animar(false)


func esta_mostrado() -> bool:
	return _mostrado


## Para avisos cuya VISIBILIDAD la decide otra lógica encendiendo y apagando una
## CanvasLayer (p. ej. el NPC): el aviso queda fijo con `texto` y repite la
## animación de entrada cada vez que la capa se hace visible. No decide nada.
func seguir_capa(capa: CanvasLayer, texto_fijo: String) -> void:
	_componer(texto_fijo)
	_mostrado = true
	visible = true
	modulate.a = 1.0
	capa.visibility_changed.connect(func() -> void:
		if capa.visible:
			visible = false
			_mostrado = false
			mostrar(texto_fijo))


## Parte el texto alrededor de la letra de la tecla y pone el keycap en medio.
func _componer(nuevo: String) -> void:
	_texto.text = nuevo
	if _tecla != null:
		_tecla.queue_free()
		_tecla = null
	var corte := _buscar_letra(nuevo)
	if corte < 0:
		_antes.text = nuevo
		_antes.visible = true
		_despues.visible = false
		return
	_antes.text = nuevo.substr(0, corte).strip_edges()
	_despues.text = nuevo.substr(corte + LETRA_EN_TEXTO.length()).strip_edges()
	_antes.visible = not _antes.text.is_empty()
	_despues.visible = not _despues.text.is_empty()
	_tecla = _crear_tecla()
	_fila.add_child(_tecla)
	_fila.move_child(_tecla, _antes.get_index() + 1)


## Índice de la letra de la tecla como PALABRA SUELTA (no la "E" de "Entrar").
func _buscar_letra(t: String) -> int:
	var desde := 0
	while true:
		var i := t.find(LETRA_EN_TEXTO, desde)
		if i < 0:
			return -1
		var izq := i == 0 or t[i - 1] == " "
		var fin := i + LETRA_EN_TEXTO.length()
		var der := fin >= t.length() or t[fin] == " "
		if izq and der:
			return i
		desde = i + 1
	return -1


## Nombre de la tecla asignada a la acción ("E", "F", "Space"...).
func _tecla_real() -> String:
	if not InputMap.has_action(accion):
		return LETRA_EN_TEXTO
	for ev in InputMap.action_get_events(accion):
		var k := ev as InputEventKey
		if k == null:
			continue
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		if code == KEY_NONE:
			continue
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code) if k.physical_keycode != KEY_NONE else code)
	return LETRA_EN_TEXTO


func _crear_tecla() -> Control:
	var nombre := _tecla_real()
	var ruta := DIR_ICONOS + "keyboard_%s.png" % nombre.to_lower()
	if ResourceLoader.exists(ruta):
		var icono := TextureRect.new()
		icono.name = "Tecla"
		icono.texture = load(ruta) as Texture2D
		icono.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icono.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icono.custom_minimum_size = Vector2(tam_tecla, tam_tecla)
		icono.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icono.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icono.tooltip_text = nombre
		return icono
	# Sin ícono para esa tecla: keycap dibujado con el tema.
	var caja := PanelContainer.new()
	caja.name = "Tecla"
	caja.theme_type_variation = &"HudTecla"
	caja.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caja.custom_minimum_size = Vector2(tam_tecla * 0.8, 0.0)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = nombre.to_upper()
	l.theme_type_variation = &"HudTeclaTexto"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(l)
	return caja


func _animar(entrar: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	if entrar:
		# La posición de reposo sólo se toma con el aviso oculto del todo: si se
		# interrumpe una salida a medias no se arrastra un desplazamiento.
		if not visible:
			_base_y = position.y
		visible = true
		position.y = _base_y + SUBIDA
		_tween.tween_property(self, "modulate:a", 1.0, DURACION_ENTRADA)
		_tween.tween_property(self, "position:y", _base_y, DURACION_ENTRADA) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(self, "modulate:a", 0.0, DURACION_SALIDA)
		_tween.chain().tween_callback(func() -> void: visible = false)


## Anclado abajo al centro, crece hacia los dos lados (no hay que recolocarlo a
## mano cuando cambia el ancho del texto). `margen` = px desde el borde inferior.
func anclar_abajo_centro(margen: float) -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = 0.0
	offset_right = 0.0
	offset_top = -margen
	offset_bottom = -margen
