class_name TuboEvento
extends Node3D

## =============================================================================
##  TUBO DE EVENTO (representación ligera + área de activación por proximidad)
## =============================================================================
##  Deliberadamente NO sabe nada de enemigos ni de combate: cuando el JUGADOR
##  entra en su zona emite `activado` UNA sola vez y deja de detectar. El
##  DirectorEventos decide qué enemigos crear y libera este nodo.
##
##  El cuerpo se comprueba por GRUPO ("player") y, si no está, por el tipo del
##  controlador: nunca por una ruta de nodo rígida.

## Emitida la primera vez que el jugador entra en la zona de activación.
signal activado(tubo: TuboEvento)

var _activado: bool = false


## Cuerpo entró en la zona de activación. Sólo el jugador cuenta.
func _on_cuerpo_entra(body: Node3D) -> void:
	if _activado or not _es_jugador(body):
		return
	_activado = true
	var zona := get_node_or_null("Zona") as Area3D
	if zona != null:
		zona.set_deferred("monitoring", false)
	activado.emit(self)


## ¿Es el cuerpo del jugador? Grupo primero, tipo después.
func _es_jugador(body: Node3D) -> bool:
	if body == null:
		return false
	if body.is_in_group("player"):
		return true
	return body is ControladorLeo