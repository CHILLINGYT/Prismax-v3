class_name PanelHabilidadesHUD
extends CanvasLayer

## =============================================================================
##  GUÍA DE CONTROLES DE HABILIDADES (lado DERECHO del HUD, algo elevada)
## =============================================================================
##  Muestra, SÓLO del personaje equipado, la tecla y la acción de sus habilidades.
##  NO inventa ni duplica la información de controles: la lee del catálogo REAL
##  del juego (`AjustesControles`: acciones por forma, etiqueta, nota y TEXTO DE
##  LA TECLA YA ASIGNADA). Así, si el jugador reasigna una tecla desde los
##  ajustes, la guía se actualiza sola (escucha `cambiado`).
##
##  La forma actual la da el propio jugador (`ControladorLeo.forma_cambiada` /
##  `id_forma()`), la MISMA señal que usa el resto del HUD: al transformarse, la
##  guía se reconstruye y las habilidades del personaje anterior desaparecen.
##
##  Es una capa VISUAL pura: no toca controles, movimiento, combate ni estamina.
##  Todo su mouse_filter es IGNORE, así que nunca intercepta la entrada; con la
##  guía apagada (ajuste propio) tampoco ocupa espacio visible.
##
##  COLOCACIÓN: esquina inferior DERECHA con margen a la derecha y una separación
##  grande por abajo. Así queda por ENCIMA del bloque de vida/estamina (que vive
##  pegado a la esquina inferior derecha) y lejos del panel de misión (que está a
##  la izquierda, a media altura). La guía crece hacia ARRIBA y hacia la
##  IZQUIERDA desde ese punto, de modo que nunca se sale de la pantalla.
##
##  TAMAÑO: tres opciones (AjustesJugabilidad), con el tamaño de referencia como
##  GRANDE (100 %), MEDIANO al 75 % y CHICO al 50 %. La escala se aplica
##  proporcionalmente a TODO el panel — tipografías, recuadros de tecla, alturas
##  de fila, separaciones y márgenes —, así el texto se vuelve a dibujar nítido en
##  cada tamaño y no se recorta en ninguno.
## =============================================================================

## id de forma del CONTROLADOR (id_forma()) -> contexto del catálogo de
## `AjustesControles`. El controlador usa los ids internos del sistema de estamina
## (&"pes"/&"tanque"/&"aguila"); el catálogo, los nombres legibles de las formas.
const CONTEXTO := {
	&"humano": &"humano",
	&"velocista": &"velocista",
	&"pes": &"acuatico",
	&"tanque": &"fuerza",
	&"combate": &"combate",
	&"aguila": &"vuelo",
}

## Acciones que NO se listan en esta guía: el movimiento (las cuatro direcciones,
## las mismas en todas las formas y siempre a la vista en pantalla) y el botón de
## menús. Se OMITE su fila, pero la tecla sigue saliendo del catálogo para las que
## sí se muestran: aquí no se duplica ningún dato.
const OMITIDAS: Array[StringName] = [
	&"mover_adelante", &"mover_atras", &"mover_izquierda", &"mover_derecha",
	&"menu_transformaciones",
]

# --- Aspecto a tamaño de REFERENCIA (escala 1.0). Todo esto se multiplica por la
# escala elegida, así que no hay dos juegos de números que mantener. ------------
const COLOR_FONDO := Color(0.05, 0.06, 0.09, 0.72)
const COLOR_BORDE := Color(1.0, 1.0, 1.0, 0.14)
const COLOR_TITULO := Color(0.72, 0.76, 0.84, 1.0)
const COLOR_TECLA := Color(0.94, 0.96, 1.0, 1.0)
const COLOR_ACCION := Color(0.88, 0.90, 0.94, 1.0)
const COLOR_NOTA := Color(0.62, 0.66, 0.73, 1.0)
const COLOR_CHIP_FONDO := Color(1.0, 1.0, 1.0, 0.08)
const COLOR_CHIP_BORDE := Color(1.0, 1.0, 1.0, 0.24)

const ANCHO_CHIP := 74.0
const ALTO_FILA := 28.0
const FUENTE_TITULO := 11
const FUENTE_TECLA := 12
const FUENTE_ACCION := 13
const FUENTE_NOTA := 10
const MARGEN_MARCO_X := 10.0
const MARGEN_MARCO_Y := 8.0
const SEPARACION_COLUMNAS := 16.0
const SEPARACION_CHIP := 10.0

## Anclajes: esquina inferior derecha con margen a la derecha y separación por
## abajo (la guía crece hacia arriba y hacia la izquierda desde ahí).
const MARGEN_DERECHA := 24.0
## Por encima del bloque de vida/estamina (ocupa el fondo de la esquina inferior
## derecha) y con margen visible respecto del borde inferior.
const MARGEN_INFERIOR := 236.0
## A partir de esta cantidad de habilidades el contenido se reparte en DOS
## columnas: la guía se mantiene legible sin volverse una lista larguísima.
const FILAS_PARA_DOS_COLUMNAS := 8

var _caja: VBoxContainer
var _marco: PanelContainer
var _titulo: Label
var _columnas: HBoxContainer
var _jugador: ControladorLeo
var _contexto_actual: StringName = &"humano"
var _escala: float = 1.0

func _ready() -> void:
	# Capa propia, por encima del cartel de objetivo y por debajo de los avisos
	# contextuales del HUD: no tapa la mira ni los indicadores de juego.
	layer = 75
	_construir()
	_reconstruir()
	_aplicar_ajustes()
	# El jugador puede no existir todavía en el primer fotograma del mundo: se
	# busca en diferido, sin bloquear la carga.
	_conectar.call_deferred()

# ------------------------------------------------------------------ montaje
## Construye el panel entero en código (como el resto del HUD): un título corto y
## una o dos columnas de filas [ tecla ] acción + nota.
func _construir() -> void:
	_caja = VBoxContainer.new()
	_caja.name = "Caja"
	_caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Esquina inferior DERECHA: el rect nace en el punto (margen derecho, margen
	# inferior) medido desde esa esquina y crece hacia arriba y a la izquierda, así
	# que nunca se sale de la pantalla por mucho contenido que tenga.
	_caja.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_caja.anchor_left = 1.0
	_caja.anchor_top = 1.0
	_caja.anchor_right = 1.0
	_caja.anchor_bottom = 1.0
	_caja.offset_left = -MARGEN_DERECHA
	_caja.offset_right = -MARGEN_DERECHA
	_caja.offset_top = -MARGEN_INFERIOR
	_caja.offset_bottom = -MARGEN_INFERIOR
	_caja.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # crece a la IZQUIERDA
	_caja.grow_vertical = Control.GROW_DIRECTION_BEGIN     # crece hacia ARRIBA
	_caja.add_theme_constant_override("separation", 0)
	add_child(_caja)

	_marco = PanelContainer.new()
	_marco.name = "Marco"
	_marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marco.add_theme_stylebox_override("panel", _estilo_marco())
	_caja.add_child(_marco)

	var contenido := VBoxContainer.new()
	contenido.name = "Contenido"
	contenido.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contenido.add_theme_constant_override("separation", roundi(2.0 * _escala))
	_marco.add_child(contenido)

	_titulo = Label.new()
	_titulo.name = "Titulo"
	_titulo.text = "CONTROLES"
	_titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_titulo.add_theme_color_override("font_color", COLOR_TITULO)
	_titulo.add_theme_font_size_override("font_size", _fuente(FUENTE_TITULO))
	contenido.add_child(_titulo)

	_columnas = HBoxContainer.new()
	_columnas.name = "Columnas"
	_columnas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_columnas.add_theme_constant_override("separation", roundi(SEPARACION_COLUMNAS * _escala))
	contenido.add_child(_columnas)

func _estilo_marco() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = COLOR_FONDO
	estilo.border_color = COLOR_BORDE
	estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(roundi(8.0 * _escala))
	estilo.content_margin_left = roundf(MARGEN_MARCO_X * _escala)
	estilo.content_margin_right = roundf((MARGEN_MARCO_X + 2.0) * _escala)
	estilo.content_margin_top = roundf(MARGEN_MARCO_Y * _escala)
	estilo.content_margin_bottom = roundf((MARGEN_MARCO_Y + 1.0) * _escala)
	return estilo

## Tamaño de fuente ya escalado (nunca por debajo de 1 px).
func _fuente(base: int) -> int:
	return maxi(1, roundi(float(base) * _escala))

# ------------------------------------------------------------------ jugador
## Busca al jugador (ControladorLeo) del mundo actual y se engancha a su señal de
## transformación. Reintenta unos fotogramas porque la guía puede entrar en el
## árbol antes que el jugador.
func _conectar() -> void:
	var intentos := 0
	while _jugador == null and intentos < 120:
		_jugador = _buscar_jugador(get_tree().root)
		if _jugador == null:
			intentos += 1
			await get_tree().process_frame
	if _jugador == null:
		return
	if not _jugador.forma_cambiada.is_connected(_on_forma_cambiada):
		_jugador.forma_cambiada.connect(_on_forma_cambiada)
	if not AjustesControles.cambiado.is_connected(_reconstruir):
		AjustesControles.cambiado.connect(_reconstruir)
	if not AjustesJugabilidad.cambiado.is_connected(_aplicar_ajustes):
		AjustesJugabilidad.cambiado.connect(_aplicar_ajustes)
	_contexto_actual = _contexto_de(_jugador.id_forma())
	_reconstruir()

## Primer nodo del árbol con la interfaz del controlador (id_forma + la señal de
## transformación). Se busca por CAPACIDAD, no por nombre de nodo.
func _buscar_jugador(raiz: Node) -> ControladorLeo:
	var pila: Array[Node] = [raiz]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is ControladorLeo:
			var j := n as ControladorLeo
			if j.forma_cambiada != null:
				return j
		for c in n.get_children():
			pila.append(c)
	return null

func _contexto_de(id_forma: StringName) -> StringName:
	return CONTEXTO.get(id_forma, &"humano")

func _on_forma_cambiada(id: StringName) -> void:
	_contexto_actual = _contexto_de(id)
	if AjustesJugabilidad.hud_controles_visible:
		_reconstruir()

# ------------------------------------------------------------------ ajustes
## Visibilidad y tamaño: los DOS ajustes propios de la guía. Al cambiar el tamaño
## se reconstruye el panel entero para que cada medida se vuelva a calcular con la
## escala nueva (texto nítido, sin reescalados que emborronen).
func _aplicar_ajustes() -> void:
	visible = AjustesJugabilidad.hud_controles_visible
	if not visible:
		return
	var nueva := AjustesJugabilidad.factor_hud_controles()
	if not is_equal_approx(nueva, _escala):
		_escala = nueva
		_montaje_escala()
	_reconstruir()

## Rearma título y marco con la escala vigente (las filas las rehace
## `_reconstruir`).
func _montaje_escala() -> void:
	if _titulo != null:
		_titulo.add_theme_font_size_override("font_size", _fuente(FUENTE_TITULO))
	if _marco != null:
		_marco.add_theme_stylebox_override("panel", _estilo_marco())
	if _columnas != null:
		_columnas.add_theme_constant_override("separation", roundi(SEPARACION_COLUMNAS * _escala))

# ------------------------------------------------------------------ contenido
## Reconstruye las filas con las habilidades del personaje equipado. Las teclas
## salen SIEMPRE del catálogo real (`AjustesControles.texto_de`), así que reflejan
## lo que el jugador tenga asignado en ese momento.
func _reconstruir() -> void:
	if _columnas == null or not AjustesJugabilidad.hud_controles_visible:
		return
	for hijo in _columnas.get_children():
		# Se QUITA del contenedor antes de liberarlo: así no conviven las columnas
		# viejas y las nuevas durante el fotograma del recambio.
		_columnas.remove_child(hijo)
		hijo.queue_free()

	var acciones: Array[StringName] = []
	for accion_v in AjustesControles.acciones_para(_contexto_actual):
		var accion: StringName = accion_v
		if not OMITIDAS.has(accion):
			acciones.append(accion)
	if acciones.is_empty():
		return

	# Muchas habilidades -> dos columnas (más ancho y menos alto); pocas -> una.
	var n_columnas := 2 if acciones.size() >= FILAS_PARA_DOS_COLUMNAS else 1
	var columnas: Array[VBoxContainer] = []
	for _c in n_columnas:
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 0)
		_columnas.add_child(col)
		columnas.append(col)

	# Reparto por mitades, en orden: primero la mitad de arriba, luego la otra.
	var por_columna := int(ceil(float(acciones.size()) / float(n_columnas)))
	for i in acciones.size():
		@warning_ignore("integer_division")
		var col := columnas[mini(i / por_columna, n_columnas - 1)]
		_crear_fila(col, acciones[i])

func _crear_fila(padre: VBoxContainer, accion: StringName) -> void:
	var fila := HBoxContainer.new()
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.custom_minimum_size = Vector2(0.0, roundf(ALTO_FILA * _escala))
	fila.add_theme_constant_override("separation", roundi(SEPARACION_CHIP * _escala))
	padre.add_child(fila)

	# Recuadro de la TECLA (mismo aspecto de "botón" que el panel de ajustes).
	var marco := PanelContainer.new()
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.custom_minimum_size = Vector2(roundf(ANCHO_CHIP * _escala), 0.0)
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = COLOR_CHIP_FONDO
	estilo.border_color = COLOR_CHIP_BORDE
	estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(roundi(4.0 * _escala))
	estilo.content_margin_left = roundf(6.0 * _escala)
	estilo.content_margin_right = roundf(6.0 * _escala)
	estilo.content_margin_top = roundf(2.0 * _escala)
	estilo.content_margin_bottom = roundf(2.0 * _escala)
	marco.add_theme_stylebox_override("panel", estilo)
	fila.add_child(marco)

	var tecla := Label.new()
	tecla.text = AjustesControles.texto_de(accion)
	tecla.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tecla.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tecla.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tecla.clip_text = true
	tecla.add_theme_color_override("font_color", COLOR_TECLA)
	tecla.add_theme_font_size_override("font_size", _fuente(FUENTE_TECLA))
	marco.add_child(tecla)

	# Acción (una línea) + nota corta (segunda línea): el matiz de "mantener",
	# "en el aire", "sólo volando"… sale del propio catálogo, no de aquí.
	var caja := VBoxContainer.new()
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caja.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caja.add_theme_constant_override("separation", 0)
	fila.add_child(caja)

	var nombre := Label.new()
	nombre.text = AjustesControles.etiqueta_de(accion, _contexto_actual)
	nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nombre.add_theme_color_override("font_color", COLOR_ACCION)
	nombre.add_theme_font_size_override("font_size", _fuente(FUENTE_ACCION))
	caja.add_child(nombre)

	var nota_texto := AjustesControles.nota_de(accion, _contexto_actual)
	if nota_texto != "":
		var nota := Label.new()
		nota.text = nota_texto
		nota.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nota.add_theme_color_override("font_color", COLOR_NOTA)
		nota.add_theme_font_size_override("font_size", _fuente(FUENTE_NOTA))
		caja.add_child(nota)