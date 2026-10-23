## leo_agua.gd - Fase 3 - Sistema de agua y nado
## Extraído de controlador_leo.gd

class_name LeoAgua

## Profundidad de agua en un punto XZ usando Relieve si existe
static func profundidad_agua(leo: Node3D, x: float, z: float) -> float:
	# Intentar usar Relieve global si existe
	var relieve_node := leo.get_node_or_null("/root/Relieve") if leo.has_method("get_node_or_null") else null
	if relieve_node != null and relieve_node.has_method("profundidad_agua"):
		return relieve_node.call("profundidad_agua", x, z)
	# Fallback: usar constante de superficie
	return 0.0

static func agua_no_pisable(leo: Node3D, x: float, z: float) -> bool:
	var prof := profundidad_agua(leo, x, z)
	return prof > LeoConstants.PROFUNDIDAD_VADEO

static func en_agua_honda(leo: Node3D, punto: Vector3) -> bool:
	var prof := profundidad_agua(leo, punto.x, punto.z)
	return prof > LeoConstants.PROFUNDIDAD_NADO

static func cota_flotacion() -> float:
	return LeoConstants.SUPERFICIE_MAR + LeoConstants.A_CALADO_FLOTANDO

static func restringir_agua(leo: CharacterBody3D, antes: Vector3) -> void:
	# Si no es acuático y entra en agua honda, frenar en orilla
	if leo.has_method("forma_actual"):
		var forma: int = leo.call("forma_actual")
		if forma == LeoEnums.Forma.ACUATICO:
			return
	var prof := profundidad_agua(leo, leo.global_position.x, leo.global_position.z)
	if prof > LeoConstants.PROFUNDIDAD_VADEO:
		leo.global_position = antes
		leo.velocity.x = 0.0
		leo.velocity.z = 0.0

static func aplicar_vertical_acuatico(leo: CharacterBody3D, delta: float, nadando: bool, t_transicion: float) -> void:
	if not nadando:
		return
	var superficie := LeoConstants.SUPERFICIE_MAR
	var calado := LeoConstants.A_CALADO_FLOTANDO
	var objetivo_y := superficie + calado
	var actual_y := leo.global_position.y
	
	# Flotabilidad
	var dif := objetivo_y - actual_y
	var fuerza := dif * LeoConstants.A_FLOTABILIDAD
	
	# Amortiguación
	fuerza -= leo.velocity.y * LeoConstants.A_AMORTIGUA_VERTICAL
	
	leo.velocity.y += fuerza * delta
	
	# Control vertical con input si existe
	var sube := Input.is_action_pressed("jump") if InputMap.has_action("jump") else false
	var baja := Input.is_action_pressed("crouch") if InputMap.has_action("crouch") else false
	
	if sube:
		leo.velocity.y += LeoConstants.A_VEL_VERTICAL_NADO * delta * 5.0
	if baja:
		leo.velocity.y -= LeoConstants.A_VEL_VERTICAL_NADO * delta * 5.0

static func puede_golpear_acuatico(leo: Node3D) -> bool:
	# Verificar si está en estado que permite golpear
	if leo.has_method("forma_actual"):
		if leo.call("forma_actual") != LeoEnums.Forma.ACUATICO:
			return false
	return true
