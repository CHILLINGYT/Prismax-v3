class_name WaterDetection
extends Area3D
## =============================================================================
##  DETECCIÓN DE AGUA
## =============================================================================
##  Es un Area3D que viaja montada en el jugador y contesta a tres preguntas:
##
##      1. ¿Estoy dentro del agua?             -> is_in_water()
##      2. ¿Cuánta agua tengo por encima?      -> get_depth() / get_submersion()
##      3. ¿Es bastante honda para nadar?      -> is_deep_enough_to_swim()
##
##  POR QUÉ UN Area3D Y NO UN RAYO O UNA COMPARACIÓN DE ALTURAS
##    El Area3D sirve para saber EN QUÉ laguna estás (puede haber varias, a
##    alturas distintas) y para no contar como agua el aire que hay fuera. Su
##    máscara mira SOLO la capa del agua (WaterZone.WATER_LAYER), así que
##    cualquier otra Area del juego (un trigger, una meta) no cuenta.
##
##    La PROFUNDIDAD no se saca de la forma del Area: una caja daría siempre el
##    mismo grosor. Se le pregunta a la zona a qué altura está SU superficie, y
##    de ahí sale una fracción 0..1 en vez de un simple sí/no. Así el personaje
##    puede estar fuera, con el agua por las rodillas, por el pecho o con la
##    cabeza debajo, y el jugador decide qué hacer en cada caso.
##
##  El jugador llama a refresh() al principio de su _physics_process, para que el
##  agua y la física se lean en el mismo fotograma (si esto tuviera su propio
##  _physics_process, el orden dependería de la prioridad de proceso).
##
##  VARIAS LAGUNAS: funciona igual con una sola laguna que con varias a alturas
##  distintas. De las zonas que solapen se elige la que tiene la superficie más
##  alta en ese punto, que es la que de verdad cubre al personaje.
## =============================================================================

## El script de la zona de agua, cargado por RUTA. Es lo mismo que usar su
## class_name "WaterZone", pero por ruta funciona siempre: Godot registra los
## class_name al IMPORTAR los scripts, y un script recien anadido a una carpeta
## nueva tarda un ciclo de escaneo del editor en entrar en esa lista. Con
## preload no hay que esperar a nada.
const WaterZoneScript := preload("res://personaje/transformaciones/acuatica/water/water_zone.gd")

## Se emite la primera vez que los pies se mojan (y una sola vez por entrada).
signal water_entered(zone: WaterZoneScript)
## Se emite cuando los pies vuelven a estar por encima de la superficie.
signal water_exited(zone: WaterZoneScript)

## Fracción del cuerpo (0..1) que tiene que quedar bajo el agua para dejar de
## vadear y ponerse a nadar. 0.45 de 1.72 m son 0.77 m: más o menos la cintura.
## Por debajo de eso el personaje anda por el fondo, que es lo que pide el punto
## de "no nadar estando en el suelo".
@export var swim_threshold := 0.45
## Fracción a partir de la cual se considera que está del todo sumergido (la
## cabeza bajo el agua). Solo informa: no cambia el movimiento.
@export var submerged_threshold := 0.92
## Altura (m) del personaje. Solo se usa para pasar la profundidad a fracción.
@export var body_height := 1.72

## Zona de agua en la que está metido ahora mismo (null si está en tierra).
var _zone: WaterZoneScript = null
## Cuántas zonas de agua solapan ahora (normalmente 0 o 1).
var _overlaps := 0
## Metros de agua por encima de los pies. Negativo si están al aire.
var _depth := 0.0
## true desde que los pies se mojan hasta que salen del agua.
var _wet := false


func _ready() -> void:
	# Solo mira el agua. Así este Area no se entera de nada más.
	collision_layer = 0
	collision_mask = WaterZoneScript.WATER_LAYER
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _on_area_entered(area: Area3D) -> void:
	if area is WaterZoneScript:
		_overlaps += 1
		_refresh_zone()


func _on_area_exited(area: Area3D) -> void:
	if area is WaterZoneScript:
		_overlaps = maxi(_overlaps - 1, 0)
		_refresh_zone()


# -----------------------------------------------------------------------------
#  Consultas (lo que usa el jugador)
# -----------------------------------------------------------------------------
## Recalcula el estado del agua. La llama Player cada frame.
func refresh() -> void:
	_refresh_zone()


## true si los pies están por debajo de la superficie del agua.
func is_in_water() -> bool:
	return _wet


## Metros de agua por encima de los pies. 0 o menos = seco.
func get_depth() -> float:
	return _depth


## Fracción del cuerpo (0..1) que queda bajo el agua.
func get_submersion() -> float:
	if _depth <= 0.0:
		return 0.0
	return clampf(_depth / maxf(body_height, 0.01), 0.0, 1.0)


## true si hay agua suficiente para nadar. Por debajo del umbral el personaje
## todavía hace pie: vadea, no nada.
func is_deep_enough_to_swim() -> bool:
	return _wet and get_submersion() >= swim_threshold


## true si la cabeza está debajo del agua.
func is_fully_submerged() -> bool:
	return _wet and get_submersion() >= submerged_threshold


## Altura (Y en el mundo) de la superficie del agua donde está el jugador.
func get_surface_height() -> float:
	if _zone == null:
		return global_position.y
	return _zone.surface_height_at(global_position)


## La zona de agua en la que está (null en tierra).
func get_zone() -> WaterZoneScript:
	return _zone


# -----------------------------------------------------------------------------
#  Interno
# -----------------------------------------------------------------------------
## Elige la zona y recalcula la profundidad, avisando si se entra o se sale.
func _refresh_zone() -> void:
	_zone = _pick_zone()
	if _zone == null:
		_depth = 0.0
	else:
		_depth = _zone.surface_height_at(global_position) - global_position.y
	var wet := _zone != null and _depth > -0.06
	if wet and not _wet:
		_wet = true
		water_entered.emit(_zone)
	elif not wet and _wet:
		_wet = false
		water_exited.emit(_zone)


## De las zonas que solapan, la que tiene la superficie más alta en este punto:
## es la que de verdad está cubriendo al personaje si hay dos lagos solapados.
func _pick_zone() -> WaterZoneScript:
	if _overlaps <= 0:
		return null
	var best: WaterZoneScript = null
	var best_surface := -INF
	for area in get_overlapping_areas():
		if area is not WaterZoneScript:
			continue
		var zone := area as WaterZoneScript
		if not zone.contains_horizontal(global_position, zone.edge_margin):
			continue
		var surface := zone.surface_height_at(global_position)
		if surface > best_surface:
			best_surface = surface
			best = zone
	return best
