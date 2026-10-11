class_name LucesVentanas
extends Node
## =============================================================================
##  VENTANAS ENCENDIDAS DE NOCHE (en fase con el ciclo de día y noche)
## =============================================================================
##  El generador de ciudad crea este nodo junto al MultiMesh de las ventanas y
##  le pasa el material compartido (`material`) y su MultiMeshInstance3D (`mmi`).
##
##  El encendido NO usa ningún temporizador propio: lee la fase del
##  `CicloDiaNoche` de la escena y reutiliza `Farolas.factor_noche()`, que es
##  exactamente la misma curva que enciende las farolas de la calle. Así las
##  ventanas se encienden poco a poco al atardecer (minuto 13 a 15 de juego),
##  quedan encendidas toda la noche y se apagan al amanecer, siempre en fase
##  con el resto de la iluminación del mapa.
##
##  Si la escena no tiene ciclo horario (por ejemplo una escena de prueba con
##  sólo la ciudad), las ventanas se quedan apagadas: el mismo aspecto diurno.
## =============================================================================

## Material compartido de TODAS las ventanas encendidas.
@export var material: ShaderMaterial
## MultiMeshInstance3D con las ventanas (se oculta durante el día: ni siquiera
## se dibuja).
@export var mmi: MultiMeshInstance3D

var _ciclo: Node = null
var _factor := -1.0
var _t_espera := 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _ciclo != null and not is_instance_valid(_ciclo):
		_ciclo = null
	if _ciclo == null:
		# Se busca el ciclo unas cuantas veces por segundo mientras la escena
		# (que puede generarse por etapas) no lo tenga: sin coste por fotograma.
		_t_espera += delta
		if _t_espera > 0.25:
			_t_espera = 0.0
			_ciclo = _buscar_ciclo()
	var objetivo := _factor_actual()
	if is_equal_approx(objetivo, _factor):
		return
	_factor = objetivo
	if material != null:
		material.set_shader_parameter("noche", objetivo)
	if mmi != null:
		mmi.visible = objetivo > 0.001


## Busca el CicloDiaNoche de la escena (la ciudad se genera en escenas
## distintas, así que no se guarda una ruta fija).
func _buscar_ciclo() -> Node:
	var arbol := get_tree()
	if arbol == null:
		return null
	return _buscar_en(arbol.root)


func _buscar_en(nodo: Node) -> Node:
	if nodo is CicloDiaNoche:
		return nodo
	for c in nodo.get_children():
		var hallado := _buscar_en(c)
		if hallado != null:
			return hallado
	return null


## Factor de encendido (0..1): la misma curva que las farolas de la calle.
func _factor_actual() -> float:
	if _ciclo == null:
		return 0.0
	return Farolas.factor_para(_ciclo, float(_ciclo.get("_fase")))


## Resumen del estado, para las comprobaciones en el juego.
func resumen() -> String:
	return "ventanas: factor=%.2f visibles=%s ciclo=%s" % [_factor,
			str(_factor > 0.001), "n/d" if _ciclo == null else "sí"]