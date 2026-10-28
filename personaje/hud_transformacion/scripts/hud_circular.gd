class_name HUDCircular
extends CanvasLayer

## HUD circular de vida, resistencia y transformación (esquina inferior derecha)
## más la BARRA DE ESTAMINA, VERTICAL y a la DERECHA del dial de vida, con el color
## del personaje activo (tabla central `CostosEstamina`).
##
## Es una CAPA VISUAL: no crea ni duplica sistemas de daño, ataque, movimiento
## o transformación. Se limita a:
##   - leer las estadísticas del hermano `Estadisticas` (EstadisticasJugador),
##   - leer la forma actual del jugador (ControladorLeo.id_forma()),
## y reflejarlas en los anillos y el icono central.
##
## Tabla de iconos: única fuente de verdad de qué imagen corresponde a cada
## forma. Añadir una transformación futura = añadir una entrada aquí (con su
## PNG); el resto del HUD no cambia.

## id de forma -> ruta del icono central.
const ICONOS := {
	&"humano": "res://personaje/hud_transformacion/iconos/leo_humano.png",
	&"velocista": "res://personaje/hud_transformacion/iconos/velocidad.png",
	&"combate": "res://personaje/hud_transformacion/iconos/combate.png",
	&"pes": "res://personaje/hud_transformacion/iconos/pes.png",
	&"tanque": "res://personaje/hud_transformacion/iconos/tanque.png",
	&"aguila": "res://personaje/hud_transformacion/iconos/aguila.png",
}

# Aspecto de los anillos (configurado aquí porque las propiedades de script no
# se leen bien desde el .tscn; así todo el diseño queda en un único lugar).
const VIDA_RADIO := 62.0
const VIDA_GROSOR := 16.0
const VIDA_COLOR := Color(0.9, 0.2, 0.24, 1.0)      # rojo = vida
const RESIST_RADIO := 62.0
const RESIST_GROSOR := 13.0
const RESIST_COLOR := Color(0.2, 0.78, 1.0, 1.0)    # cian = escudo/energía
const FONDO_ANILLO := Color(0.08, 0.09, 0.12, 0.7)

# Reparto HORIZONTAL alrededor del retrato: ESCUDO (izquierda) | retrato | VIDA (derecha).
# Cada barra pasa de anillo completo a una media luna (semicírculo) con un
# pequeño hueco arriba y abajo. ARCO_MEDIO = 90° (arranque "arriba").
const ARCO_MEDIO := PI * 0.5
const ARCO_HUECO := 0.14
const ARCO_BARRIDO := PI - ARCO_HUECO

# --- Viñeta de daño (bordes de pantalla) ---
## Color del borde mientras el escudo CONSERVA resistencia (rojo azulado: el
## escudo amortiguó el golpe).
const VINETA_COLOR_ESCUDO := Color(0.78, 0.2, 0.52, 1.0)
## Color del borde cuando el escudo está ROTO (rojo puro, sin componente azul).
const VINETA_COLOR_ROTO := Color(0.9, 0.12, 0.1, 1.0)
## Intensidad sostenida mientras el escudo sigue roto (se apaga al recuperarse).
const VINETA_BASE_ROTO := 0.42
## Ritmo (1/s) al que el pulso del golpe se desvanece (exponencial).
const VINETA_DECAIMIENTO := 3.0
## Ritmo (1/s) al que el estado sostenido sube o baja hacia su objetivo.
const VINETA_VEL_ESTADO := 3.0

@onready var _anillo_vida: IndicadorAnillo = $Raiz/Dial/AnilloVida
@onready var _anillo_resist: IndicadorAnillo = $Raiz/Dial/AnilloResistencia
@onready var _icono: TextureRect = $Raiz/Dial/Icono
@onready var _vineta: ColorRect = $Raiz/VinetaDano

var _stats: EstadisticasJugador
var _jugador: ControladorLeo
var _mat_vineta: ShaderMaterial
var _vineta_pulso: float = 0.0      # pico del último golpe (se desvanece solo)
var _vineta_estado: float = 0.0     # intensidad sostenida actual
var _vineta_estado_obj: float = 0.0 # objetivo del estado sostenido (escudo roto)

# --- Barra de ESTAMINA (vertical, a la derecha del dial de vida) ---
# Sólo LEE el sistema compartido (EstadisticasJugador + tabla de colores de
# CostosEstamina): no duplica estado ni lógica de juego.
var _est_raiz: Control
var _est_fondo: ColorRect
var _est_relleno: ColorRect
var _est_marco: Panel
var _est_estilo: StyleBoxFlat
var _est_objetivo: float = 1.0
var _est_mostrado: float = 1.0

# ---------------------------------------------------------------------------
# AVISO CONTEXTUAL ("Presioná E para subir al barco")
# ---------------------------------------------------------------------------
# No se duplica ningún sistema de interacción: el HUD sólo PREGUNTA al jugador
# qué texto toca mostrar (ControladorLeo.texto_interaccion(), que devuelve "" si
# no hay nada a mano). El aviso se construye aquí, en código, como el resto del
# diseño del HUD, y se funde con un Tween: mientras el texto no cambie no se
# toca nada, así que estando en la zona el mensaje queda fijo (sin parpadeos).
const AVISO_MARGEN_INFERIOR := 132.0
## Estilo nuevo (tema central + keycap, componente AvisoInteraccion). `false` =
## el panel anterior hecho a mano (para comparar).
const AVISO_ESTILO_NUEVO := true

var _aviso_nuevo: AvisoInteraccion
var _aviso: PanelContainer
var _aviso_etiqueta: Label
var _aviso_visible := false
var _aviso_tween: Tween
const AVISO_FUNDIDO := 0.18


func _ready() -> void:
	_configurar_anillos()
	_construir_aviso()
	_configurar_vineta()
	_construir_estamina()

	# El HUD viaja dentro de la escena del jugador, así que su padre es el
	# ControladorLeo y `Estadisticas` es su hermano.
	var raiz := get_parent()
	_jugador = raiz as ControladorLeo
	_stats = raiz.get_node_or_null("Estadisticas") as EstadisticasJugador

	if _stats != null:
		_stats.vida_cambiada.connect(_on_vida_cambiada)
		_stats.resistencia_cambiada.connect(_on_resistencia_cambiada)
		_stats.regenerando_cambiado.connect(_on_regenerando_cambiado)
		# La viñeta de daño se alimenta del estado REAL del escudo y del golpe.
		_stats.danio_recibido.connect(_on_danio_recibido)
		# Estamina: misma regla que vida/escudo (señal del personaje activo).
		_stats.stamina_cambiada.connect(_on_stamina_cambiada)
		# Estado inicial inmediato (por si la señal diferida aún no llegó).
		_on_vida_cambiada(_stats.vida, _stats.vida_max)
		_on_resistencia_cambiada(_stats.resistencia, _stats.resistencia_max)
		_on_stamina_cambiada(_stats.stamina, _stats.stamina_max)

	if _jugador != null:
		_jugador.forma_cambiada.connect(_on_forma_cambiada)
		_actualizar_icono(_jugador.id_forma())
		_actualizar_color_estamina(_jugador.id_forma())
	else:
		_actualizar_icono(&"humano")
		_actualizar_color_estamina(&"humano")

# ---------------------------------------------------------------------------
# Aviso contextual: se construye en código y se coloca a mano (centrado abajo),
# porque el panel cambia de ancho según el texto y el presets de anclaje dejarían
# el borde descentrado.
# ---------------------------------------------------------------------------
func _construir_aviso() -> void:
	if AVISO_ESTILO_NUEVO:
		_aviso_nuevo = AvisoInteraccion.new()
		_aviso_nuevo.name = "Aviso"
		$Raiz.add_child(_aviso_nuevo)
		_aviso_nuevo.anclar_abajo_centro(AVISO_MARGEN_INFERIOR)
		return
	_aviso = PanelContainer.new()
	_aviso.name = "Aviso"
	_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aviso.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_aviso.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_aviso.visible = false
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.05, 0.07, 0.10, 0.78)
	estilo.border_color = Color(0.45, 0.82, 1.0, 0.9)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(10)
	estilo.content_margin_left = 18.0
	estilo.content_margin_right = 18.0
	estilo.content_margin_top = 10.0
	estilo.content_margin_bottom = 10.0
	_aviso.add_theme_stylebox_override("panel", estilo)
	_aviso_etiqueta = Label.new()
	_aviso_etiqueta.name = "Texto"
	_aviso_etiqueta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aviso_etiqueta.add_theme_font_size_override("font_size", 24)
	_aviso_etiqueta.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0, 1.0))
	_aviso_etiqueta.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_aviso_etiqueta.add_theme_constant_override("outline_size", 4)
	_aviso.add_child(_aviso_etiqueta)
	$Raiz.add_child(_aviso)


## Sondeo por fotograma: se le pregunta al jugador si hay algo interactuable a
## mano. Devolver el MISMO texto no hace nada (el aviso se queda tal cual), así
## que no hay parpadeo: sólo se funde al ENTRAR y al SALIR de la zona.
func _process(delta: float) -> void:
	# --- Viñeta de daño: pulso del golpe + estado sostenido del escudo roto ---
	if _mat_vineta != null:
		# Pulso exponencial: dura lo mismo a 30 que a 144 FPS y nunca se acumula.
		_vineta_pulso *= exp(-VINETA_DECAIMIENTO * delta)
		if _vineta_pulso < 0.002:
			_vineta_pulso = 0.0
		_vineta_estado = move_toward(_vineta_estado, _vineta_estado_obj, VINETA_VEL_ESTADO * delta)
		_mat_vineta.set_shader_parameter("intensidad",
				clampf(_vineta_estado + _vineta_pulso, 0.0, 1.0))
	# --- Barra de estamina (VERTICAL): transición suave hacia el valor real.
	# Crece de ABAJO hacia arriba, así que se ajustan la ALTURA y la posición Y. ---
	if _est_relleno != null:
		_est_mostrado = lerpf(_est_mostrado, _est_objetivo, 1.0 - exp(-CostosEstamina.EST_SUAVIZADO * delta))
		if absf(_est_mostrado - _est_objetivo) < 0.0005:
			_est_mostrado = _est_objetivo
		var largo := CostosEstamina.EST_ALTO - 2.0 * CostosEstamina.EST_BORDE
		var relleno := maxf(0.0, largo * _est_mostrado)
		_est_relleno.size.y = relleno
		_est_relleno.position.y = CostosEstamina.EST_BORDE + (largo - relleno)

	# --- Aviso contextual ---
	var texto: String = _jugador.texto_interaccion() if _jugador != null else ""
	if _aviso_nuevo != null:
		if texto.is_empty():
			_aviso_nuevo.ocultar()
		else:
			_aviso_nuevo.mostrar(texto)
		return
	if texto.is_empty():
		if _aviso_visible:
			_aviso_visible = false
			_fundir_aviso(false)
		return
	if _aviso_etiqueta.text != texto:
		_aviso_etiqueta.text = texto
	_colocar_aviso()
	if not _aviso_visible:
		_aviso_visible = true
		_fundir_aviso(true)


func _colocar_aviso() -> void:
	var vista := get_viewport().get_visible_rect().size
	_aviso.position = Vector2(
			(vista.x - _aviso.size.x) * 0.5,
			vista.y - AVISO_MARGEN_INFERIOR - _aviso.size.y)


func _fundir_aviso(mostrar: bool) -> void:
	if _aviso_tween != null and _aviso_tween.is_valid():
		_aviso_tween.kill()
	if mostrar:
		_aviso.visible = true
	_aviso_tween = create_tween()
	_aviso_tween.tween_property(_aviso, "modulate:a", 1.0 if mostrar else 0.0, AVISO_FUNDIDO)
	if not mostrar:
		_aviso_tween.tween_callback(_ocultar_aviso)


func _ocultar_aviso() -> void:
	_aviso.visible = false


func _configurar_anillos() -> void:
	# VIDA: media luna DERECHA. Arranca arriba y avanza en sentido horario.
	_anillo_vida.radio = VIDA_RADIO
	_anillo_vida.grosor = VIDA_GROSOR
	_anillo_vida.color = VIDA_COLOR
	_anillo_vida.color_fondo = FONDO_ANILLO
	_anillo_vida.angulo_inicio = -ARCO_MEDIO + ARCO_HUECO * 0.5
	_anillo_vida.angulo_barrido = ARCO_BARRIDO

	# ESCUDO: media luna IZQUIERDA. Arranca arriba y avanza en sentido antihorario.
	_anillo_resist.radio = RESIST_RADIO
	_anillo_resist.grosor = RESIST_GROSOR
	_anillo_resist.color = RESIST_COLOR
	_anillo_resist.color_fondo = FONDO_ANILLO
	_anillo_resist.angulo_inicio = -ARCO_MEDIO - ARCO_HUECO * 0.5
	_anillo_resist.angulo_barrido = -ARCO_BARRIDO

func _on_vida_cambiada(actual: float, maxima: float) -> void:
	_anillo_vida.set_valor(actual / maxima if maxima > 0.0 else 0.0)

func _on_resistencia_cambiada(actual: float, maxima: float) -> void:
	_anillo_resist.set_valor(actual / maxima if maxima > 0.0 else 0.0)
	# El estado de la viñeta (rojo azulado vs rojo roto) sigue SIEMPRE a la
	# resistencia real: al romperse y al recuperarse se actualiza sola.
	_actualizar_vineta_estado()

func _on_regenerando_cambiado(regenerando: bool) -> void:
	# Requisito: pequeña animación de "recuperándose" sólo mientras regenera.
	_anillo_resist.set_pulso(regenerando)

func _on_forma_cambiada(id: StringName) -> void:
	_actualizar_icono(id)
	# Cambiar de personaje cambia el COLOR de la barra de estamina; nada más del
	# HUD se toca.
	_actualizar_color_estamina(id)

func _actualizar_icono(id: StringName) -> void:
	var ruta: String = ICONOS.get(id, ICONOS[&"humano"])
	if ResourceLoader.exists(ruta):
		_icono.texture = load(ruta)


# =============================================================== Barra de estamina
## Se construye en código (como el resto del diseño del HUD), VERTICAL y a la
## DERECHA del dial de vida, y sólo refleja el sistema compartido: ni estado
## propio ni lógica de juego.
func _construir_estamina() -> void:
	_est_raiz = Control.new()
	_est_raiz.name = "BarraEstamina"
	_est_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_est_raiz.set_anchors_preset(Control.PRESET_TOP_LEFT)

	_est_fondo = ColorRect.new()
	_est_fondo.name = "Fondo"
	_est_fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_est_fondo.color = CostosEstamina.EST_COLOR_FONDO
	_est_fondo.position = Vector2.ZERO
	_est_fondo.size = Vector2(CostosEstamina.EST_ANCHO, CostosEstamina.EST_ALTO)
	_est_raiz.add_child(_est_fondo)

	_est_relleno = ColorRect.new()
	_est_relleno.name = "Relleno"
	_est_relleno.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_est_relleno.position = Vector2(CostosEstamina.EST_BORDE, CostosEstamina.EST_BORDE)
	_est_relleno.size = Vector2(
			CostosEstamina.EST_ANCHO - 2.0 * CostosEstamina.EST_BORDE,
			CostosEstamina.EST_ALTO - 2.0 * CostosEstamina.EST_BORDE)
	_est_raiz.add_child(_est_relleno)

	_est_estilo = StyleBoxFlat.new()
	_est_estilo.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_est_estilo.set_border_width_all(int(CostosEstamina.EST_BORDE))
	_est_estilo.set_corner_radius_all(4)
	_est_marco = Panel.new()
	_est_marco.name = "Marco"
	_est_marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_est_marco.add_theme_stylebox_override("panel", _est_estilo)
	_est_marco.position = Vector2.ZERO
	_est_marco.size = Vector2(CostosEstamina.EST_ANCHO, CostosEstamina.EST_ALTO)
	_est_raiz.add_child(_est_marco)

	$Raiz.add_child(_est_raiz)
	_colocar_estamina()
	if not get_viewport().size_changed.is_connected(_colocar_estamina):
		get_viewport().size_changed.connect(_colocar_estamina)
	# El dial puede no estar maquetado todavía en _ready: se recoloca en diferido.
	_colocar_estamina.call_deferred()


## Barra VERTICAL inmediatamente a la DERECHA del dial de vida (el HUD circular
## vive abajo a la derecha). Se recoloca al cambiar el tamaño de la pantalla.
func _colocar_estamina() -> void:
	if _est_raiz == null:
		return
	var dial := get_node_or_null("Raiz/Dial") as Control
	if dial == null:
		return
	var r := dial.get_rect()
	if r.size.x <= 0.0:
		return
	_est_raiz.position = Vector2(
			r.end.x + CostosEstamina.EST_SEPARACION,
			r.get_center().y - CostosEstamina.EST_ALTO * 0.5)


func _on_stamina_cambiada(actual: float, maxima: float) -> void:
	_est_objetivo = clampf(actual / maxima, 0.0, 1.0) if maxima > 0.0 else 0.0


## El color es del PERSONAJE: relleno por forma y borde de contraste cuando el
## relleno es oscuro (combate → borde claro; águila → borde oscuro general).
func _actualizar_color_estamina(id: StringName) -> void:
	if _est_relleno == null:
		return
	_est_relleno.color = CostosEstamina.color_de(id)
	if _est_estilo != null:
		_est_estilo.border_color = CostosEstamina.borde_de(id)


# =============================================================== Viñeta de daño
## El estado visual de la viñeta sale SIEMPRE del estado real del escudo
## (EstadisticasJugador.resistencia), nunca de la forma actual ni del número de
## golpes. El pulso es un pico que se desvanece; no se acumula.
func _on_danio_recibido(cantidad: float) -> void:
	if _stats == null:
		return
	var roto: bool = _stats.resistencia <= 0.001
	_actualizar_vineta_color(roto)
	# Pulso del impacto: más fuerte cuanto menos escudo queda (y máximo ya roto).
	var fuerza := 0.9
	if not roto:
		var fraccion := clampf(_stats.resistencia / maxf(_stats.resistencia_max, 0.01), 0.0, 1.0)
		fuerza = 0.5 + 0.3 * (1.0 - fraccion) + clampf(cantidad / 250.0, 0.0, 0.15)
	_vineta_pulso = maxf(_vineta_pulso, clampf(fuerza, 0.25, 1.0))

## Fija color e intensidad sostenida según el escudo: rojo azulado con carga,
## rojo puro persistente mientras esté roto, y vuelta atrás al recuperarse.
func _actualizar_vineta_estado() -> void:
	if _stats == null:
		return
	var roto: bool = _stats.resistencia <= 0.001
	_actualizar_vineta_color(roto)
	_vineta_estado_obj = VINETA_BASE_ROTO if roto else 0.0

func _actualizar_vineta_color(roto: bool) -> void:
	if _mat_vineta == null:
		return
	_mat_vineta.set_shader_parameter("color",
			VINETA_COLOR_ROTO if roto else VINETA_COLOR_ESCUDO)

func _configurar_vineta() -> void:
	_mat_vineta = (_vineta.material as ShaderMaterial) if _vineta != null else null
	if _mat_vineta != null:
		_mat_vineta.set_shader_parameter("intensidad", 0.0)
