class_name WaterZone
extends Area3D
## =============================================================================
##  ZONA DE AGUA
## =============================================================================
##  Es el "volumen" de agua de un lago o una piscina. Sabe tres cosas:
##
##    1. Donde esta la superficie (la Y de este nodo, mas la ola).
##    2. Cuanta agua hay en un punto (para saber si el personaje esta fuera,
##       medio sumergido o del todo debajo).
##    3. Si un punto cae dentro de la laguna (el rectangulo de "extent").
##
##  El Area3D sirve para que el Area3D que lleva el jugador (WaterDetection) la
##  detecte al entrar y al salir. Lo de la profundidad se consulta por codigo,
##  porque la forma de una caja no sabe nada de olas ni de niveles.
##
##  VARIAS LAGUNAS: se pueden poner tantas WaterZone como haga falta, a la altura
##  que sea. El jugador lleva una sola WaterDetection y elige la zona que de
##  verdad lo cubre.
##
##  LA OLA ES LA MISMA QUE LA DEL SHADER. Si se cambia water_surface.gdshader hay
##  que cambiar tambien esto, o el personaje flotara a una altura que no es la del
##  agua que se ve. Por eso las olas son cuatro senos con los mismos numeros.
## =============================================================================

## Capa de fisica reservada al agua. El jugador lleva su Area3D de deteccion con
## esta misma mascara, y asi el agua no se mezcla con el suelo ni con el jugador.
const WATER_LAYER := 8

@export_group("Volumen")
## Mitad del ancho y del fondo de la laguna (m), respecto a este nodo. Un lago de
## 24 x 20 m son extent = Vector2(12, 10).
@export var extent := Vector2(12.0, 10.0)
## Profundidad total (m) desde la superficie hasta el fondo.
@export var depth := 3.7
## radio (m) que se suma a "extent" para decidir si algo esta dentro. Sirve para
## que el personaje cuente como dentro del agua aunque su centro este justo en el
## borde (esta medio metido).
@export var edge_margin := 0.6

@export_group("Olas")
## Tienen que coincidir con los uniform del shader de la superficie.
@export var wave_height := 0.08
@export var wave_speed := 0.9

var _time := 0.0


func _ready() -> void:
	collision_layer = WATER_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true


func _process(delta: float) -> void:
	_time += delta


# -----------------------------------------------------------------------------
#  Consultas
# -----------------------------------------------------------------------------
## Altura (Y en el mundo) de la superficie del agua en ese punto, ola incluida.
func surface_height_at(world_point: Vector3) -> float:
	return global_position.y + wave_offset_at(world_point)


## Cuanto sube o baja la ola en ese punto (m). Misma formula que el shader.
func wave_offset_at(world_point: Vector3) -> float:
	var p := Vector2(world_point.x, world_point.z)
	var t := _time * wave_speed
	var h := sin(p.x * 0.62 + t * 1.15) * 0.50
	h += sin(p.y * 0.83 - t * 0.97) * 0.34
	h += sin((p.x + p.y) * 0.45 + t * 1.63) * 0.28
	h += sin((p.x - p.y) * 1.21 - t * 0.71) * 0.16
	h += sin(p.x * 1.9 + p.y * 0.7 + t * 2.30) * 0.11
	h += sin(p.x * -0.9 + p.y * 2.4 - t * 2.90) * 0.08
	return h * 0.5 * wave_height


## true si el punto (horizontalmente) cae dentro de la laguna.
func contains_horizontal(world_point: Vector3, margin := 0.0) -> bool:
	var local := to_local(world_point)
	return absf(local.x) <= extent.x + margin and absf(local.z) <= extent.y + margin


## Metros de agua por encima del punto (m). Mayor que 0 = el punto esta
## sumergido; menor que 0 = esta por encima de la superficie.
func submersion_at(world_point: Vector3) -> float:
	return surface_height_at(world_point) - world_point.y


## true si el punto esta dentro del agua (dentro y por debajo de la superficie).
func is_submerged(world_point: Vector3, margin := 0.0) -> bool:
	return contains_horizontal(world_point, margin) and submersion_at(world_point) > 0.0


## Fraccion sumergida (0..1) de un cuerpo vertical que apoya los pies en
## [param feet] y mide [param height] metros.
##
##   0.0 = seco (ni los pies mojados)
##   ~0.3 = por las rodillas   -> todavia se anda, no se nada
##   ~0.6 = por el pecho
##   1.0 = la cabeza debajo    -> sumergido del todo
func submerged_fraction(feet: Vector3, height: float) -> float:
	if not contains_horizontal(feet, edge_margin):
		return 0.0
	var surface := surface_height_at(feet)
	var water_depth := surface - feet.y
	if water_depth <= 0.0:
		return 0.0
	return clampf(water_depth / maxf(height, 0.01), 0.0, 1.0)


## Profundidad del fondo (m) por debajo de la superficie. Sirve para avisar de
## donde el agua es tan poco profunda que no se puede nadar.
func bottom_depth() -> float:
	return depth
