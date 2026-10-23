## leo_transformation.gd - Fase 3 - Transformaciones
## Maneja cambio de formas y efectos visuales

class_name LeoTransformation

static func id_forma(forma: int) -> StringName:
	match forma:
		LeoEnums.Forma.HUMANO:
			return &"humano"
		LeoEnums.Forma.VELOCISTA:
			return &"velocista"
		LeoEnums.Forma.ACUATICO:
			return &"acuatico"
		LeoEnums.Forma.FUERZA:
			return &"fuerza"
		LeoEnums.Forma.COMBATE:
			return &"combate"
		LeoEnums.Forma.VUELO:
			return &"vuelo"
		_:
			return &"humano"

static func cambiar_forma_con_efecto(leo: Node3D, destino: int) -> void:
	# Efecto visual de transformación
	var efecto := leo.get_node_or_null("EfectoTransformacion") as Node3D
	if efecto != null and efecto.has_method("disparar"):
		efecto.call("disparar", id_forma(destino))
	
	var audio := leo.get_node_or_null("AudioTransformacion") as AudioStreamPlayer
	if audio != null:
		audio.play()
	
	# Llamar métodos de entrada/salida si existen
	var forma_actual: int = 0
	if leo.has_method("forma_actual"):
		forma_actual = leo.call("forma_actual")
	
	# Detener forma actual
	match forma_actual:
		LeoEnums.Forma.VELOCISTA:
			if leo.has_method("_detener_velocista"):
				leo.call("_detener_velocista")
		LeoEnums.Forma.ACUATICO:
			if leo.has_method("_detener_acuatico"):
				leo.call("_detener_acuatico")
		LeoEnums.Forma.FUERZA:
			if leo.has_method("_detener_fuerza"):
				leo.call("_detener_fuerza")
		LeoEnums.Forma.COMBATE:
			if leo.has_method("_detener_combate"):
				leo.call("_detener_combate")
		LeoEnums.Forma.VUELO:
			if leo.has_method("_detener_vuelo"):
				leo.call("_detener_vuelo")
	
	# Entrar nueva forma
	match destino:
		LeoEnums.Forma.HUMANO:
			if leo.has_method("_entrar_humano"):
				leo.call("_entrar_humano")
		LeoEnums.Forma.VELOCISTA:
			if leo.has_method("_entrar_velocista"):
				leo.call("_entrar_velocista")
		LeoEnums.Forma.ACUATICO:
			if leo.has_method("_entrar_acuatico"):
				leo.call("_entrar_acuatico")
		LeoEnums.Forma.FUERZA:
			if leo.has_method("_entrar_fuerza"):
				leo.call("_entrar_fuerza")
		LeoEnums.Forma.COMBATE:
			if leo.has_method("_entrar_combate"):
				leo.call("_entrar_combate")
		LeoEnums.Forma.VUELO:
			if leo.has_method("_entrar_vuelo"):
				leo.call("_entrar_vuelo")
	
	# Emitir señal
	if leo.has_signal("forma_cambiada"):
		leo.emit_signal("forma_cambiada", id_forma(destino))

static func cuerpo_activo(leo: Node3D) -> Node3D:
	# En VUELO, el cuerpo activo es el hijo Vuelo
	if leo.has_method("forma_actual"):
		var forma: int = leo.call("forma_actual")
		if forma == LeoEnums.Forma.VUELO:
			var vuelo := leo.get_node_or_null("Vuelo") as Node3D
			if vuelo != null:
				return vuelo
	return leo as Node3D

static func vuelo_desbloqueado(leo: Node3D) -> bool:
	# Verificar si vuelo está desbloqueado (ej: por misión)
	var misiones := leo.get_node_or_null("/root/Misiones") if leo.has_method("get_node_or_null") else null
	if misiones != null and misiones.has_method("vuelo_desbloqueado"):
		return misiones.call("vuelo_desbloqueado")
	return true # por defecto desbloqueado para pruebas
