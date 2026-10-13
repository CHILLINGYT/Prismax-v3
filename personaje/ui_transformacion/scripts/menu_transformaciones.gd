class_name MenuTransformaciones
extends CanvasLayer

## Menú radial de selección de transformaciones (inspirado en los menús de
## selección de forma estilo Ben 10).
##
## Este menú es SÓLO UNA NUEVA FORMA DE ELEGIR la transformación. No crea ni
## reemplaza ninguna transformación: cuando el jugador elige "Velocista", el
## menú emite `transformacion_elegida` y el ControladorLeo reutiliza el sistema
## de transformación que ya existía (el mismo que antes se activaba con una
## tecla).
##
## Añadir una transformación futura = añadir una entrada en TRANSFORMACIONES
## (con su icono y "desbloqueada" = true) y conectar su id en el
## ControladorLeo. La interfaz NO necesita cambios: se construye sola a partir
## de esta tabla.
##
## Tecla: F abre/cierra (acción de Input Map "menu_transformaciones").
## Mientras está abierto: el ratón se libera, la cámara y el personaje no se
## tocan (sólo se congela el control de movimiento), y al cerrar se restaura
## la captura del ratón.

## Emitida al elegir una transformación disponible (con su id).
signal transformacion_elegida(id: StringName)
## Emitida al abrir / cerrar el menú (para que el jugador congele el control).
signal menu_abierto
signal menu_cerrado

# ------------------------------------------------------------------ Datos
# Tabla de transformaciones. ÚNICA fuente de verdad del menú.
#   id         : identificador que se conecta con el sistema de transformación.
#   nombre     : texto que se muestra.
#   icono      : ruta del PNG (los originales del proyecto).
#   desbloqueada: true = seleccionable; false = bloqueada ("PRÓXIMAMENTE").
#   requiere_mision: true = ADEMÁS está bloqueada hasta completar la misión
#                      (el estado se deriva del gestor `Misiones`, no se fija aquí).
#   angulo     : posición en el anillo, en grados (-90 = arriba; sentido horario).
const TRANSFORMACIONES := [
	{"id": &"combate",   "nombre": "Combate",   "icono": "res://personaje/ui_transformacion/iconos/combate.png",   "desbloqueada": true,  "angulo": -90.0},
	{"id": &"velocista", "nombre": "Velocidad", "icono": "res://personaje/ui_transformacion/iconos/velocista.png", "desbloqueada": true,  "angulo": -18.0},
	{"id": &"pes",       "nombre": "Acuático",       "icono": "res://personaje/ui_transformacion/iconos/pes.png",       "desbloqueada": true,  "angulo": 54.0},
	{"id": &"tanque",    "nombre": "Fuerza",    "icono": "res://personaje/ui_transformacion/iconos/tanque.png",    "desbloqueada": true,  "angulo": 126.0},
	# Vuelo: seleccionable EN PRINCIPIO, pero BLOQUEADO mientras la misión de Iván
	# no esté completada (`requiere_mision`). Conserva la marca DEMO.
	{"id": &"aguila",    "nombre": "Vuelo",    "icono": "res://personaje/ui_transformacion/iconos/aguila.png",    "desbloqueada": true,  "angulo": 198.0, "demo": true, "requiere_mision": true},
]

# ------------------------------------------------------------------ Aspecto
const RADIO := 172.0                 # distancia de los iconos al centro (más compacta)
const TAM := 150.0                   # lado del área de cada icono (px)
const MARGEN_BORDE := 12.0           # margen mínimo para no salirse en pantallas pequeñas
const ALFA_FONDO := 0.68             # oscurecido de fondo al abrir
const COLOR_ACCENTO := Color(0.98, 0.76, 0.28, 1.0)  # dorado de la referencia
const DUR_HOVER := 0.12              # transición suave de hover
const ESCALA_HOVER := 1.15
# Tinte del icono bloqueado (desaturado/oscurecido).
const MOD_BLOQUEADA := Color(0.5, 0.5, 0.55, 0.85)
const MOD_BLOQUEADA_HOVER := Color(0.62, 0.62, 0.68, 0.95)

## Candado rojo que se superpone a la etiqueta "DEMO" de la transformación demo.
## Reutiliza la silueta (blanca, con transparencia) del candado del menú principal
## `lock_story.png`, teñida en rojo con `modulate`: no se crea ni se modifica el
## recurso original (el menú principal lo sigue usando igual, en gris).
const RUTA_CANDADO := "res://assets/generated/lock_story.png"
const COLOR_CANDADO := Color(0.93, 0.06, 0.06, 1.0)

## Forma que permanece BLOQUEADA hasta completar la misión de Iván (Vuelo/Águila).
## Su estado NO es fijo: se deriva en CADA momento del gestor de misiones `Misiones`,
## que es la ÚNICA fuente de verdad. El menú no lleva su propio contador.
const ID_VUELO := &"aguila"
## Texto EXACTO que se muestra en la zona central al pasar el cursor sobre Vuelo
## bloqueado (dos líneas). Sólo aparece mientras el cursor está encima del icono.
const TEXTO_BLOQUEO_VUELO := "requiere completar\nla mision"

@onready var _fondo: ColorRect = $Fondo
@onready var _centro: Control = $Centro
@onready var _iconos: Control = $Centro/Iconos
@onready var _detalle: Label = $Centro/Detalle

var _abierto: bool = false
var _seleccionando: bool = false
var _entradas: Dictionary = {}       # id -> { control, tex, marco, nombre, pronto, bloqueada, tween }
var _centro_px: Vector2 = Vector2.ZERO

# =============================================================== Ciclo de vida
func _ready() -> void:
	visible = false
	_construir_iconos()
	_iconos.resized.connect(_recolocar)
	# El desbloqueo de Vuelo es DINÁMICO: si la misión se completa con el menú
	# abierto (o cerrado), el candado y el estado se refrescan solos, sin tener que
	# cerrar ni reabrir el menú. Fuente única de verdad: el gestor `Misiones`.
	Misiones.mision_completada.connect(_on_mision_completada)

func _unhandled_input(event: InputEvent) -> void:
	# F: interruptor (abrir/cerrar). Igual que el patrón de PauseMenu.
	if event.is_action_pressed("menu_transformaciones"):
		alternar()
		get_viewport().set_input_as_handled()

func esta_abierto() -> bool:
	return _abierto

# =============================================================== Abrir / cerrar
func alternar() -> void:
	if _abierto:
		cerrar()
	else:
		abrir()

func abrir() -> void:
	if _abierto:
		return
	_abierto = true
	_seleccionando = false
	_refrescar_bloqueo()
	_restaurar_visual()
	_recolocar.call_deferred()
	visible = true
	# Fundido de entrada.
	_fondo.color = Color(_fondo.color, 0.0)
	_centro.modulate = Color(1, 1, 1, 0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_fondo, "color:a", ALFA_FONDO, 0.15)
	tw.tween_property(_centro, "modulate:a", 1.0, 0.15)
	# Ratón libre para poder pulsar los iconos. No se toca la cámara.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_abierto.emit()

func cerrar() -> void:
	if not _abierto:
		return
	_abierto = false
	_seleccionando = false
	visible = false
	# Restaura el comportamiento normal del ratón (cámara de nuevo controlable).
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	menu_cerrado.emit()

# =============================================================== Construcción UI
func _construir_iconos() -> void:
	for datos in TRANSFORMACIONES:
		var id: StringName = datos["id"]
		var por_mision: bool = bool(datos.get("requiere_mision", false))
		var bloqueada: bool = not bool(datos["desbloqueada"])
		# Vuelo: además depende del estado REAL de la misión (misma consulta que el
		# candado funcional del ControladorLeo).
		if por_mision and not _vuelo_desbloqueado():
			bloqueada = true

		var control := Control.new()
		control.name = String(id)
		control.custom_minimum_size = Vector2(TAM, TAM)
		control.size = Vector2(TAM, TAM)
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		control.pivot_offset = Vector2(TAM, TAM) * 0.5
		_iconos.add_child(control)

		# Marco (borde de selección/hover) dibujado como borde redondeado.
		var marco := Panel.new()
		marco.name = "Marco"
		marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var estilo := StyleBoxFlat.new()
		estilo.draw_center = false
		estilo.border_width_left = 3
		estilo.border_width_top = 3
		estilo.border_width_right = 3
		estilo.border_width_bottom = 3
		estilo.corner_radius_top_left = 16
		estilo.corner_radius_top_right = 16
		estilo.corner_radius_bottom_left = 16
		estilo.corner_radius_bottom_right = 16
		estilo.border_color = COLOR_ACCENTO
		marco.add_theme_stylebox_override("panel", estilo)
		marco.modulate = Color(1, 1, 1, 0)
		control.add_child(marco)
		marco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		# Icono.
		var tex := TextureRect.new()
		tex.name = "Icono"
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var ruta: String = datos["icono"]
		if ResourceLoader.exists(ruta):
			tex.texture = load(ruta)
		control.add_child(tex)
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		# Nodo del candado: SÓLO la tarjeta demo lo crea. Se guarda para poder
		# mostrarlo/ocultarlo cuando cambie el estado de la misión.
		var candado_nodo: TextureRect = null

		# Marca DEMO (SÓLO para esta transformación): el retrato se muestra en
		# escala de grises mediante un ShaderMaterial propio (no se toca el PNG
		# original ni se afecta a otras tarjetas) y se superponen un CANDADO rojo
		# y la etiqueta "DEMO" en rojo intenso, uno inmediatamente encima del otro.
		if bool(datos.get("demo", false)):
			var mat := ShaderMaterial.new()
			mat.shader = load("res://personaje/ui_transformacion/shaders/escala_grises.gdshader")
			tex.material = mat

			# Candado rojo JUSTO ENCIMA de "DEMO". Se ancla a la parte ancha de la
			# tarjeta (PRESET_TOP_WIDE) y se centra con KEEP_ASPECT_CENTERED, así
			# que queda centrado y con la misma proporción cambie la resolución que
			# cambie. Queda por DEBAJO de los ojos del emblema para no tapar el
			# símbolo principal de Vuelo.
			var candado := TextureRect.new()
			candado.name = "Candado"
			candado.mouse_filter = Control.MOUSE_FILTER_IGNORE
			candado.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			candado.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if ResourceLoader.exists(RUTA_CANDADO):
				candado.texture = load(RUTA_CANDADO)
			candado.modulate = COLOR_CANDADO
			control.add_child(candado)
			candado.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			candado.offset_top = TAM * 0.48
			candado.offset_bottom = TAM * 0.80
			# El candado representa el BLOQUEO: sólo se ve mientras lo esté.
			candado.visible = bloqueada
			candado_nodo = candado

			var demo := Label.new()
			demo.name = "Demo"
			demo.mouse_filter = Control.MOUSE_FILTER_IGNORE
			demo.text = "DEMO"
			demo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			demo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			var fuente := SystemFont.new()
			fuente.font_names = PackedStringArray(["Arial", "Verdana", "Helvetica", "sans-serif"])
			fuente.font_weight = 700  # negrita
			demo.add_theme_font_override("font", fuente)
			demo.add_theme_font_size_override("font_size", 30)
			demo.add_theme_color_override("font_color", Color(0.93, 0.06, 0.06, 1.0))
			demo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			demo.add_theme_constant_override("outline_size", 6)
			demo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
			demo.add_theme_constant_override("shadow_offset_x", 2)
			demo.add_theme_constant_override("shadow_offset_y", 3)
			control.add_child(demo)
			demo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			# Debajo del candado y dentro de la tarjeta (no se recorta).
			demo.offset_top = TAM * 0.80

		# Nombre bajo el icono.
		var nombre := Label.new()
		nombre.name = "Nombre"
		nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nombre.text = String(datos["nombre"])
		nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nombre.add_theme_font_size_override("font_size", 20)
		control.add_child(nombre)
		nombre.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		nombre.offset_top = TAM + 6.0
		nombre.offset_bottom = TAM + 32.0

		# Etiqueta "PRÓXIMAMENTE" (sólo iconos bloqueados de forma FIJA, al pasar el
		# ratón). Vuelo no la usa: su bloqueo es por misión y muestra su propio aviso
		# en la zona central (ver `TEXTO_BLOQUEO_VUELO`).
		var pronto := Label.new()
		pronto.name = "Pronto"
		pronto.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pronto.text = "PRÓXIMAMENTE"
		pronto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pronto.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pronto.add_theme_font_size_override("font_size", 16)
		pronto.add_theme_color_override("font_color", Color(0.95, 0.6, 0.55, 1))
		pronto.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		pronto.add_theme_constant_override("shadow_offset_y", 2)
		pronto.visible = false
		control.add_child(pronto)
		pronto.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		# Estado visual base según disponibilidad.
		if bloqueada:
			tex.modulate = MOD_BLOQUEADA
			nombre.modulate = Color(0.62, 0.62, 0.68, 1)
		else:
			tex.modulate = Color(1, 1, 1, 1)

		control.mouse_entered.connect(_on_icono_entra.bind(id))
		control.mouse_exited.connect(_on_icono_sale.bind(id))
		control.gui_input.connect(_on_icono_gui_input.bind(id))

		_entradas[id] = {
			"control": control, "tex": tex, "marco": marco,
			"nombre": nombre, "pronto": pronto,
			"bloqueada": bloqueada, "bloqueada_base": not bool(datos["desbloqueada"]),
			"por_mision": por_mision, "candado": candado_nodo, "tween": null,
		}

# =============================================================== Colocación radial
func _recolocar() -> void:
	_centro_px = _iconos.size * 0.5
	# Radio efectivo: el compacto por defecto, recortado sólo si la ventana es
	# tan pequeña que los iconos se saldrían (el resto de resoluciones ya escalan
	# con el modo de estiramiento "canvas_items" del proyecto).
	var limite: float = min(_iconos.size.x, _iconos.size.y) * 0.5 - TAM * 0.5 - MARGEN_BORDE
	var radio: float = min(RADIO, max(limite, TAM * 0.5))
	for datos in TRANSFORMACIONES:
		var id: StringName = datos["id"]
		if not _entradas.has(id):
			continue
		var e: Dictionary = _entradas[id]
		var rad := deg_to_rad(float(datos["angulo"]))
		var punto := _centro_px + Vector2(cos(rad), sin(rad)) * radio
		e["control"].position = punto - Vector2(TAM, TAM) * 0.5

# =============================================================== Interacción
func _on_icono_entra(id: StringName) -> void:
	if _seleccionando:
		return
	var e: Dictionary = _entradas[id]
	if e["bloqueada"]:
		_animar_icono(id, 1.0, MOD_BLOQUEADA_HOVER, 0.0)
		# Vuelo bloqueado: aviso propio en la ZONA CENTRAL (dos líneas, blanco). Los
		# iconos bloqueados de forma fija conservan su "PRÓXIMAMENTE".
		if bool(e.get("por_mision", false)):
			_fijar_detalle(TEXTO_BLOQUEO_VUELO, Color(1, 1, 1, 1))
		else:
			e["pronto"].visible = true
	else:
		_animar_icono(id, ESCALA_HOVER, Color(1.18, 1.18, 1.18, 1.0), 1.0)

func _on_icono_sale(id: StringName) -> void:
	if _seleccionando:
		return
	var e: Dictionary = _entradas[id]
	if e["bloqueada"]:
		e["pronto"].visible = false
		_animar_icono(id, 1.0, MOD_BLOQUEADA, 0.0)
	else:
		_animar_icono(id, 1.0, Color(1, 1, 1, 1), 0.0)
	# La zona central vuelve a quedar limpia al retirar el cursor.
	_detalle.text = ""

func _on_icono_gui_input(event: InputEvent, id: StringName) -> void:
	if not _abierto or _seleccionando:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var e: Dictionary = _entradas[id]
		if e["bloqueada"]:
			_rechazar(id)
		else:
			_seleccionar(id)
		get_viewport().set_input_as_handled()

# Icono bloqueado: pequeño gesto de "no disponible" (no selecciona).
func _rechazar(id: StringName) -> void:
	var e: Dictionary = _entradas[id]
	var base: float = e["control"].position.x
	var tw := create_tween()
	for i in 3:
		tw.tween_property(e["control"], "position:x", base - 8.0, 0.04)
		tw.tween_property(e["control"], "position:x", base + 8.0, 0.04)
	tw.tween_property(e["control"], "position:x", base, 0.04)

# Icono disponible: resaltado -> animación -> desaparece el menú -> señal.
func _seleccionar(id: StringName) -> void:
	if _seleccionando:
		return
	_seleccionando = true
	var e: Dictionary = _entradas[id]

	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(e["control"], "scale", Vector2(1.5, 1.5), 0.22)
	tw.tween_property(e["tex"], "modulate", Color(1.6, 1.6, 1.6, 1.0), 0.18)
	tw.tween_property(e["marco"], "modulate:a", 1.0, 0.18)
	for otra in _entradas.keys():
		if otra == id:
			continue
		var o: Dictionary = _entradas[otra]
		tw.tween_property(o["control"], "modulate", Color(1, 1, 1, 0.0), 0.22)
	await tw.finished

	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(_centro, "modulate:a", 0.0, 0.22)
	tw2.tween_property(_fondo, "color:a", 0.0, 0.22)
	await tw2.finished

	_restaurar_visual()
	cerrar()
	transformacion_elegida.emit(id)

# =============================================================== Bloqueo por misión
## Vuelo sólo se puede elegir cuando la misión de Iván está COMPLETADA. La respuesta
## sale SIEMPRE del gestor `Misiones` (única fuente de verdad), la misma que usa el
## candado funcional del ControladorLeo.
func _vuelo_desbloqueado() -> bool:
	return Misiones.esta_completada(Misiones.MISION_PROFUGOS)

func _on_mision_completada(_id: StringName) -> void:
	_refrescar_bloqueo()

## Recalcula el estado de bloqueo dependiente de la misión y lo vuelca en la tarjeta
## (candado visible/oculto, tinte y color del nombre). No toca las transformaciones
## cuyo bloqueo es fijo.
func _refrescar_bloqueo() -> void:
	for id in _entradas.keys():
		var e: Dictionary = _entradas[id]
		if not bool(e.get("por_mision", false)):
			continue
		var bloqueada: bool = bool(e["bloqueada_base"]) or not _vuelo_desbloqueado()
		e["bloqueada"] = bloqueada
		var candado: CanvasItem = e.get("candado", null)
		if candado != null:
			candado.visible = bloqueada
		e["pronto"].visible = false
		if bloqueada:
			e["tex"].modulate = MOD_BLOQUEADA
			e["nombre"].modulate = Color(0.62, 0.62, 0.68, 1)
		else:
			e["tex"].modulate = Color(1, 1, 1, 1)
			e["nombre"].modulate = Color(1, 1, 1, 1)
	_detalle.text = ""

# =============================================================== Utilidades
func _animar_icono(id: StringName, escala: float, mod_tex: Color, borde_a: float) -> void:
	var e: Dictionary = _entradas[id]
	var tw: Tween = e["tween"]
	if tw != null and tw.is_valid():
		tw.kill()
	tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(e["control"], "scale", Vector2(escala, escala), DUR_HOVER)
	tw.tween_property(e["tex"], "modulate", mod_tex, DUR_HOVER)
	tw.tween_property(e["marco"], "modulate:a", borde_a, DUR_HOVER)
	e["tween"] = tw

func _fijar_detalle(texto: String, color: Color) -> void:
	_detalle.text = texto
	_detalle.modulate = color

func _nombre_de(id: StringName) -> String:
	for datos in TRANSFORMACIONES:
		if datos["id"] == id:
			return String(datos["nombre"])
	return String(id)

func _restaurar_visual() -> void:
	for id in _entradas.keys():
		var e: Dictionary = _entradas[id]
		var tw: Tween = e["tween"]
		if tw != null and tw.is_valid():
			tw.kill()
			e["tween"] = null
		e["control"].modulate = Color(1, 1, 1, 1)
		e["control"].scale = Vector2.ONE
		e["marco"].modulate = Color(1, 1, 1, 0)
		e["pronto"].visible = false
		e["tex"].modulate = MOD_BLOQUEADA if e["bloqueada"] else Color(1, 1, 1, 1)
	_detalle.text = ""
