class_name EscaleraBarco
extends Node3D
## =============================================================================
##  ESCALERA DEL BARCO (punto de agarre para la forma acuática)
## =============================================================================
##  Este nodo NO es una escalera de colisión ni un ascensor: es el "anclaje" que
##  el controlador del personaje consulta cuando el jugador pulsa INTERACTUAR (E)
##  nadando junto al casco. El controlador es quien mueve el cuerpo peldaño a
##  peldaño (estado "subiendo escalera"); aquí sólo se describe DÓNDE está el pie
##  de la escalera (en el agua), DÓNDE se corona (en la cubierta) y hacia dónde
##  debe mirar el cuerpo mientras trepa.
##
##  Se coloca como hijo de `barco.gd` sobre el costado de babor, hundido por
##  debajo de la línea de flotación para que se pueda agarrar desde el agua.
## =============================================================================

## Radio (m, sólo horizontal) dentro del cual el cuerpo que nada puede agarrarse.
@export var radio_agarre: float = 2.4
## Punto LOCAL de agarre: el pie de la escalera, ya dentro del agua. Normalmente
## (0,0,0) porque el propio nodo se coloca ahí.
@export var pie_local: Vector3 = Vector3.ZERO
## Punto LOCAL de coronación: dónde aterriza el cuerpo al terminar de subir, sobre
## la cubierta y ya hacia dentro del barco.
@export var cima_local: Vector3 = Vector3(3.0, 5.2, 0.0)
## Dirección LOCAL (horizontal) hacia la que mira el cuerpo al trepar: hacia el
## casco (+X hacia dentro si la escalera está en babor/-X).
@export var mirada_local: Vector3 = Vector3(1.0, 0.0, 0.0)


func _ready() -> void:
	add_to_group("escalera_barco")


## Pie de la escalera en coordenadas GLOBALES (dentro del agua).
func pie() -> Vector3:
	return to_global(pie_local)


## Punto de coronación en coordenadas GLOBALES (sobre la cubierta).
func cima() -> Vector3:
	return to_global(cima_local)


## ¿Puede el cuerpo situado en `punto` (global) agarrarse a esta escalera? Debe
## estar a la altura del agua, no por encima de la cubierta ni demasiado hundido.
func puede_subir(punto: Vector3) -> bool:
	var p_pie := pie()
	var p_cima := cima()
	if punto.y > p_cima.y - 0.8:
		return false
	if punto.y < p_pie.y - 3.0:
		return false
	var plano := Vector2(punto.x - p_pie.x, punto.z - p_pie.z)
	return plano.length() <= radio_agarre


## Dirección horizontal (global) del casco, para orientar el cuerpo al trepar.
func direccion_mirada() -> Vector3:
	var d := to_global(mirada_local) - to_global(pi_local_vacio())
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD


func pi_local_vacio() -> Vector3:
	return Vector3.ZERO