class_name PanelHabilidadesHUD
extends CanvasLayer

## =============================================================================
##  GUÍA DE ASIGNACIONES DE TECLAS (cuadrante inferior IZQUIERDO, SIN fondo)
## =============================================================================
##  Muestra, SÓLO del personaje equipado, la tecla y la habilidad a la que está
##  asignada. NO inventa ni duplica la información de controles: la lee del
##  catálogo REAL del juego (`AjustesControles`: acciones por forma, etiqueta,
##  nota y TEXTO DE LA TECLA YA ASIGNADA). Si el jugador reasigna una tecla desde
##  los ajustes, la guía se actualiza sola (escucha `cambiado`).
##
##  La forma actual la da el propio jugador (`ControladorLeo.forma_cambiada` /
##  `id_forma()`), la MISMA señal que usa el resto del HUD: al transformarse, la
##  guía se reconstruye y las habilidades del personaje anterior desaparecen.
##
##  Es una capa VISUAL pura: no toca controles, movimiento, combate ni estamina.
##  Todo su mouse_filter es IGNORE, así que nunca intercepta la entrada.
##
##  ---------------------------------------------------------------------------
##  DISTRIBUCIÓN: UNA SOLA COLUMNA, SIEMPRE. Cada habilidad ocupa su propia fila y
##  las filas van una DEBAJO de la otra, de arriba hacia abajo:
##      Q        —  Levantar roca (desde el suelo)
##      ESPACIO  —  Saltar / supersalto (mantener y soltar = supersalto)
##      E        —  Pisotón (en el aire)
##  No se reparte en dos columnas aunque sobre ancho horizontal: el ancho de la
##  guía lo decide únicamente la fila más larga (y el texto de cada descripción se
##  adapta a su longitud, sin superponerse ni desbordar).
##
##  ASPECTO: SIN fondo, tarjeta, rectángulo ni panel alguno. Sólo texto:
##  · La TECLA va en blanco puro, en su propia columna, para distinguirse de un
##    vistazo de la descripción (un punto más apagada).
##  · El guion que las separa es tenue.
##  · La nota de la habilidad va entre paréntesis, en gris, al final.
##  · Para que se lea tanto sobre el cielo como sobre una pared o el asfalto,
##    cada rótulo lleva un CONTORNO oscuro sutil (nada de fondos opacos ni
##    semitransparentes detrás del texto).
##  · La escala (GRANDE / MEDIANO / CHICO) se aplica a las MEDIDAS — tipografías,
##    columnas, alturas, separaciones y grosor del contorno —, así el texto se
##    vuelve a dibujar nítido en cada tamaño y no se recorta en ninguno.
##  ---------------------------------------------------------------------------
##  COLOCACIÓN: cuadrante inferior IZQUIERDO con margen respecto de los dos
##  bordes y sin pegarse al fondo. Anclada a la esquina, la separación es la misma
##  en cualquier resolución o proporción, y crece hacia ARRIBA y hacia la DERECHA
##  desde ese punto, de modo que nunca se sale de la pantalla.
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
const COLOR_TECLA := Color(1.0, 1.0, 1.0, 1.0)          # blanco puro
const COLOR_GUION := Color(1.0, 1.0, 1.0, 0.42)         # separador tenue
const COLOR_ACCION := Color(0.90, 0.93, 0.97, 1.0)      # descripción
const COLOR_NOTA := Color(0.70, 0.75, 0.82, 1.0)        # matiz, más apagado
## Contorno oscuro sutil: es lo que hace legible el texto sobre cielo, pared o
## asfalto sin colocar ningún fondo detrás.
const COLOR_CONTORNO := Color(0.0, 0.0, 0.0, 0.72)

const ANCHO_TECLA := 96.0
const ALTO_FILA := 25.0
const FUENTE_TECLA := 13
const FUENTE_ACCION := 13
const FUENTE_NOTA := 12
const SEPARACION_GUION := 9.0
## Separación VERTICAL entre filas: pequeña, pero suficiente para que cada
## habilidad se distinga de la de arriba (la lista es una sola columna).
const SEPARACION_FILAS := 3.0
const CONTORNO_PX := 4

## Margen respecto del borde izquierdo y separación del borde inferior (nada de
## pegarla al fondo: queda claramente dentro del cuadrante inferior izquierdo).
const MARGEN_IZQUIERDA := 24.0
const MARGEN_INFERIOR := 56.0

var _caja: VBoxContainer
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
## Construye la guía entera en código (como el resto del HUD): una lista de filas
## `TECLA — Habilidad`, sin ningún elemento de fondo.
func _construir() -> void:
	_caja = VBoxContainer.new()
	_caja.name = "Caja"
	_caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Cuadrante inferior IZQUIERDO: el rect nace en el punto (margen izquierdo,
	# margen inferior) medido desde esa esquina y crece hacia arriba y a la
	# derecha, así que nunca se sale de la pantalla por mucho contenido que tenga.
	_caja.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_caja.anchor_left = 0.0
	_caja.anchor_top = 1.0
	_caja.anchor_right = 0.0
	_caja.anchor_bottom = 1.0
	_caja.offset_left = MARGEN_IZQUIERDA
	_caja.offset_right = MARGEN_IZQUIERDA
	_caja.offset_top = -MARGEN_INFERIOR
	_caja.offset_bottom = -MARGEN_INFERIOR
	_caja.grow_horizontal = Control.GROW_DIRECTION_END     # crece a la DERECHA
	_caja.grow_vertical = Control.GROW_DIRECTION_BEGIN     # crece hacia ARRIBA
	_caja.add_theme_constant_override("separation", 0)
	add_child(_caja)

	# Envoltorio de la lista. Tiene EXACTAMENTE un hijo (la columna única) y su
	# nombre se mantiene porque las sondas de prueba lo buscan por nombre.
	_columnas = HBoxContainer.new()
	_columnas.name = "Columnas"
	_columnas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_columnas.add_theme_constant_override("separation", 0)
	_caja.add_child(_columnas)

## Tamaño de fuente ya escalado (nunca por debajo de 1 px).
func _fuente(base: int) -> int:
	return maxi(1, roundi(float(base) * _escala))

## Rótulo sin fondo con contorno oscuro sutil (lo que da contraste en cualquier
## escenario). Devuelve el Label ya configurado.
func _rotulo(texto: String, color: Color, fuente: int) -> Label:
	var l := Label.new()
	l.text = texto
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", _fuente(fuente))
	l.add_theme_constant_override("outline_size", maxi(0, roundi(float(CONTORNO_PX) * _escala)))
	l.add_theme_color_override("font_outline_color", COLOR_CONTORNO)
	return l

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
## Visibilidad y tamaño: los DOS ajustes propios de la guía (siguen igual que
## antes: el panel NO está en el grupo `hud_juego`, así que `ocultar_hud` no lo
## toca). Al cambiar el tamaño se reconstruye con la escala nueva, porque todas
## las medidas se aplican al crear cada rótulo.
func _aplicar_ajustes() -> void:
	visible = AjustesJugabilidad.hud_controles_visible
	if not visible:
		return
	_escala = AjustesJugabilidad.factor_hud_controles()
	_reconstruir()

# ------------------------------------------------------------------ contenido
## Reconstruye la lista con las habilidades del personaje equipado: una fila por
## habilidad, en UNA SOLA COLUMNA. Las teclas salen SIEMPRE del catálogo real
## (`AjustesControles.texto_de`), así que reflejan lo que el jugador tenga
## asignado en ese momento.
func _reconstruir() -> void:
	if _columnas == null or not AjustesJugabilidad.hud_controles_visible:
		return
	for hijo in _columnas.get_children():
		# Se QUITA del contenedor antes de liberarlo: así no conviven la lista
		# vieja y la nueva durante el fotograma del recambio.
		_columnas.remove_child(hijo)
		hijo.queue_free()

	var acciones: Array[StringName] = []
	for accion_v in AjustesControles.acciones_para(_contexto_actual):
		var accion: StringName = accion_v
		if not OMITIDAS.has(accion):
			acciones.append(accion)
	if acciones.is_empty():
		return

	# UNA SOLA COLUMNA, SIEMPRE: cada habilidad en su propia fila, una debajo de
	# la otra de arriba hacia abajo. No se reparte en dos columnas aunque sobre
	# ancho horizontal: el ancho lo decide sólo la fila más larga.
	var lista := VBoxContainer.new()
	lista.name = "Lista"
	lista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lista.add_theme_constant_override("separation", roundi(SEPARACION_FILAS * _escala))
	_columnas.add_child(lista)
	for accion in acciones:
		_crear_fila(lista, accion)

## Una habilidad:  `TECLA   —   Descripción (nota)`  en una sola línea, sin fondo.
func _crear_fila(padre: VBoxContainer, accion: StringName) -> void:
	var fila := HBoxContainer.new()
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.custom_minimum_size = Vector2(0.0, roundf(ALTO_FILA * _escala))
	fila.add_theme_constant_override("separation", roundi(SEPARACION_GUION * _escala))
	padre.add_child(fila)

	# Columna de la TECLA: ancho fijo (escala mediante) para que los guiones de
	# todas las filas queden alineados. Blanco puro: se distingue de la descripción.
	var tecla := _rotulo(AjustesControles.texto_de(accion), COLOR_TECLA, FUENTE_TECLA)
	tecla.custom_minimum_size = Vector2(roundf(ANCHO_TECLA * _escala), 0.0)
	fila.add_child(tecla)

	# Guion tenue de separación.
	fila.add_child(_rotulo("—", COLOR_GUION, FUENTE_ACCION))

	# Descripción de la habilidad (una línea, se adapta a su propia longitud).
	fila.add_child(_rotulo(AjustesControles.etiqueta_de(accion, _contexto_actual),
			COLOR_ACCION, FUENTE_ACCION))

	# Matiz de "mantener", "en el aire", "sólo volando"… Sale del propio catálogo,
	# no de aquí, y va entre paréntesis y más apagado.
	var nota_texto := AjustesControles.nota_de(accion, _contexto_actual)
	if nota_texto != "":
		fila.add_child(_rotulo("(%s)" % nota_texto.to_lower(), COLOR_NOTA, FUENTE_NOTA))