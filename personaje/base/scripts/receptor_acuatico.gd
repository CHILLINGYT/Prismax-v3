class_name ReceptorAcuatico
extends Node3D
## Reenvía al ControladorLeo las pistas de método de las animaciones acuáticas.
##
## Los clips ability_1..ability_4 del módulo acuático traen una pista de método que
## llama a notify_ability_release("ability_N") sobre la raíz del AnimationPlayer.
## El AnimationPlayer del modelo acuático cuelga de este nodo (Acuatico), así que la
## llamada llega aquí y se reenvía al controlador, que es quien crea la habilidad en
## el fotograma exacto en que la animación la suelta.
##
## Es el mismo mecanismo del módulo acuático (WaterAbilityManager), pero puenteado a
## la arquitectura de Leo sin duplicar el sistema de efectos.

func notify_ability_release(estado: String) -> void:
	var ctrl := get_parent()
	if ctrl != null and ctrl.has_method("_notificar_liberacion_agua"):
		ctrl.call("_notificar_liberacion_agua", estado)