class_name HUDCircular
extends CanvasLayer

## HUD circular de vida, resistencia y transformación (esquina inferior derecha).
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

@onready var _anillo_vida: IndicadorAnillo = $Raiz/Dial/AnilloVida
@onready var _anillo_resist: IndicadorAnillo = $Raiz/Dial/AnilloResistencia
@onready var _icono: TextureRect = $Raiz/Dial/Icono

var _stats: EstadisticasJugador
var _jugador: ControladorLeo

func _ready() -> void:
	_configurar_anillos()

	# El HUD viaja dentro de la escena del jugador, así que su padre es el
	# ControladorLeo y `Estadisticas` es su hermano.
	var raiz := get_parent()
	_jugador = raiz as ControladorLeo
	_stats = raiz.get_node_or_null("Estadisticas") as EstadisticasJugador

	if _stats != null:
		_stats.vida_cambiada.connect(_on_vida_cambiada)
		_stats.resistencia_cambiada.connect(_on_resistencia_cambiada)
		_stats.regenerando_cambiado.connect(_on_regenerando_cambiado)
		# Estado inicial inmediato (por si la señal diferida aún no llegó).
		_on_vida_cambiada(_stats.vida, _stats.vida_max)
		_on_resistencia_cambiada(_stats.resistencia, _stats.resistencia_max)

	if _jugador != null:
		_jugador.forma_cambiada.connect(_on_forma_cambiada)
		_actualizar_icono(_jugador.id_forma())
	else:
		_actualizar_icono(&"humano")

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

func _on_regenerando_cambiado(regenerando: bool) -> void:
	# Requisito: pequeña animación de "recuperándose" sólo mientras regenera.
	_anillo_resist.set_pulso(regenerando)

func _on_forma_cambiada(id: StringName) -> void:
	_actualizar_icono(id)

func _actualizar_icono(id: StringName) -> void:
	var ruta: String = ICONOS.get(id, ICONOS[&"humano"])
	if ResourceLoader.exists(ruta):
		_icono.texture = load(ruta)
