class_name IndicadorAnillo
extends Control

## Anillo de progreso circular dibujado con _draw() (sin texturas).
##
## Dibuja una pista de fondo completa y, encima, un arco proporcional a `valor`
## (0..1) que empieza arriba (-90°) y avanza en sentido horario.
## Con `pulso = true` late suavemente (se usa mientras la resistencia se
## regenera), sin mover ni redimensionar nada.

@export var radio: float = 96.0
@export var grosor: float = 16.0
@export var color: Color = Color(0.9, 0.22, 0.26, 1.0)
@export var color_fondo: Color = Color(0.07, 0.08, 0.11, 0.65)
## Ángulo (rad) donde arranca la barra. Por defecto arriba (-90°).
## Permite dibujar medias lunas (escudo a la izquierda / vida a la derecha) en
## lugar del anillo completo, sin cambiar la lógica de valor.
@export var angulo_inicio: float = -PI * 0.5
## Cuánto abarca la barra (rad). TAU = anillo completo. Un valor negativo la
## hace recorrer el círculo en sentido antihorario.
@export var angulo_barrido: float = TAU
## Intensidad del latido cuando pulso = true.
@export var amplitud_pulso: float = 0.35
@export var frecuencia_pulso: float = 5.0

var _valor: float = 1.0
var _pulso: bool = false
var _fase: float = 0.0

func _ready() -> void:
	# El anillo no debe interceptar el ratón.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_valor(v: float) -> void:
	var nv := clampf(v, 0.0, 1.0)
	if not is_equal_approx(nv, _valor):
		_valor = nv
		queue_redraw()

func set_pulso(v: bool) -> void:
	if v == _pulso:
		return
	_pulso = v
	queue_redraw()

func _process(delta: float) -> void:
	if _pulso:
		_fase += delta
		queue_redraw()
	elif _fase != 0.0:
		_fase = 0.0
		queue_redraw()

func _draw() -> void:
	var centro := size * 0.5
	var span := absf(angulo_barrido)
	var segmentos := maxi(2, int(ceil(72.0 * span / TAU)))
	# Pista de fondo (tramo de la barra, tenue).
	draw_arc(centro, radio, angulo_inicio, angulo_inicio + angulo_barrido, segmentos, color_fondo, grosor, true)
	if _valor <= 0.0:
		return
	var fin := angulo_inicio + angulo_barrido * _valor
	var col := color
	if _pulso:
		var onda := 0.5 + 0.5 * sin(_fase * frecuencia_pulso)
		col = color.lightened(amplitud_pulso * onda)
		col.a = color.a
	draw_arc(centro, radio, angulo_inicio, fin, maxi(2, int(ceil(72.0 * span * _valor / TAU))), col, grosor, true)