class_name AvisosMinimapa
extends Control

## CAPA DE AVISOS del minimapa y del mapa ampliado (Tarea 6).
##
## Dibuja los marcadores de aviso POR ENCIMA de la imagen del mapa: misiones
## activas (objetivo en el mundo), eventos de enemigos (tubo disponible o combate
## en curso) y enemigos relevantes (los que están atacando ahora mismo, con un
## latido de advertencia, y el resto como punto).
##
## El minimapa (`minimapa.gd`) es quien reúne las fuentes, las proyecta a píxeles
## con la MISMA cámara cenital que renderiza el mapa y rellena `marcadores`; aquí
## sólo se pinta. Un objetivo que cae FUERA del mapa se pega al borde y se pinta
## atenuado: así el aviso sigue indicando hacia dónde está en vez de desaparecer.
##
## Cada marcador es un Dictionary:
##   punto:  Vector2 (píxeles, dentro de este Control)
##   tipo:   int (ver las constantes T_*)
##   dentro: bool (false = pegado al borde, fuera del encuadre)
##   pulso:  float 0..1 (latido ya calculado por el minimapa)

const T_MISION := 0
const T_EVENTO := 1
const T_EVENTO_COMBATE := 2
const T_ENEMIGO := 3
const T_AMENAZA := 4

@export var color_mision: Color = Color(1.0, 0.82, 0.22, 1.0)
@export var color_evento: Color = Color(1.0, 0.55, 0.16, 1.0)
@export var color_evento_combate: Color = Color(1.0, 0.36, 0.12, 1.0)
@export var color_enemigo: Color = Color(0.74, 0.22, 0.22, 1.0)
@export var color_amenaza: Color = Color(1.0, 0.26, 0.20, 1.0)
## Contorno oscuro común: los avisos se leen sobre terreno claro y oscuro.
@export var color_borde: Color = Color(0.06, 0.05, 0.05, 0.9)

@export_group("Forma y tamaño")
## Lado base (px) del marcador más pequeño; cada tipo lo escala con `_escala_de`.
@export var tamano_px: float = 8.0
@export var grosor_borde: float = 1.5
## Opacidad de los avisos que quedan fuera del encuadre (pegados al borde).
@export_range(0.1, 1.0, 0.05) var alfa_fuera: float = 0.55

## Lista de marcadores ya proyectados (la rellena el minimapa).
var marcadores: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = false


func _draw() -> void:
	for m in marcadores:
		var punto: Vector2 = m.get("punto", Vector2.ZERO)
		var tipo := int(m.get("tipo", T_ENEMIGO))
		var color := _color_de(tipo)
		if not bool(m.get("dentro", true)):
			color.a *= alfa_fuera
		var escala := _escala_de(tipo)
		var r := tamano_px * 0.5 * escala
		# Latido: sólo los avisos "vivos" (misión, evento y amenaza) laten.
		r *= 1.0 + 0.30 * _pulso_de(tipo) * float(m.get("pulso", 0.0))
		match tipo:
			T_ENEMIGO:
				draw_circle(punto, r, color)
				draw_arc(punto, r, 0.0, TAU, 16, color_borde, grosor_borde * 0.6, true)
			T_MISION:
				_forma(punto, r, color, _rombo(r))
			T_EVENTO, T_EVENTO_COMBATE:
				_forma(punto, r, color, _cuadrado(r))
			T_AMENAZA:
				_forma(punto, r, color, _triangulo(r))
			_:
				draw_circle(punto, r, color)


## Polígono relleno + contorno (cerrado) para las formas no circulares.
func _forma(punto: Vector2, r: float, color: Color, forma: PackedVector2Array) -> void:
	var pol := PackedVector2Array()
	for p in forma:
		pol.append(punto + p)
	draw_colored_polygon(pol, color)
	if grosor_borde > 0.0:
		var borde := pol.duplicate()
		borde.append(pol[0])
		draw_polyline(borde, color_borde, grosor_borde, true)
	if r > 4.0:
		draw_circle(punto, maxf(1.0, r * 0.16), color_borde)


func _rombo(r: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -r), Vector2(r, 0.0), Vector2(0.0, r), Vector2(-r, 0.0),
	])


func _cuadrado(r: float) -> PackedVector2Array:
	var r2 := r * 0.82
	return PackedVector2Array([
		Vector2(-r2, -r2), Vector2(r2, -r2), Vector2(r2, r2), Vector2(-r2, r2),
	])


func _triangulo(r: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -r * 1.25), Vector2(r, r * 0.9), Vector2(-r, r * 0.9),
	])


func _color_de(tipo: int) -> Color:
	match tipo:
		T_MISION:
			return color_mision
		T_EVENTO:
			return color_evento
		T_EVENTO_COMBATE:
			return color_evento_combate
		T_AMENAZA:
			return color_amenaza
		_:
			return color_enemigo


func _escala_de(tipo: int) -> float:
	match tipo:
		T_ENEMIGO:
			return 0.62
		T_MISION:
			return 1.05
		T_EVENTO:
			return 0.95
		T_EVENTO_COMBATE:
			return 1.05
		T_AMENAZA:
			return 1.30
		_:
			return 1.0


## Cuánto late cada tipo (0 = quieto).
func _pulso_de(tipo: int) -> float:
	match tipo:
		T_ENEMIGO:
			return 0.0
		T_MISION:
			return 0.35
		T_EVENTO:
			return 0.5
		T_EVENTO_COMBATE:
			return 0.7
		T_AMENAZA:
			return 1.0
		_:
			return 0.0