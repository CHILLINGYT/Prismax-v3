## leo_velocista.gd - Fase 3 - Lógica del velocista
## Extraído de controlador_leo.gd

class_name LeoVelocista

static func procesar_normal(leo: CharacterBody3D, delta: float, dir: Vector3) -> int:
	# Retorna nuevo estado si cambia, sino Estado.NORMAL
	var vel_max := LeoConstants.VEL_MAX
	var acel := LeoConstants.VEL_ACEL
	var desacel := LeoConstants.VEL_DESACEL
	
	var target_vel := dir * vel_max
	var current_vel := Vector3(leo.velocity.x, 0, leo.velocity.z)
	
	if dir.length_squared() > 0.001:
		current_vel = current_vel.move_toward(target_vel, acel * delta)
	else:
		current_vel = current_vel.move_toward(Vector3.ZERO, desacel * delta)
	
	leo.velocity.x = current_vel.x
	leo.velocity.z = current_vel.z
	
	if not leo.is_on_floor():
		leo.velocity.y -= LeoConstants.VEL_GRAVEDAD * delta
	elif leo.velocity.y < 0.0:
		leo.velocity.y = -0.1
	
	# Input dash
	if Input.is_action_just_pressed("esprintar") or Input.is_action_just_pressed("dash"):
		return LeoEnums.Estado.DASH
	
	if Input.is_action_pressed("carga_poder"):
		return LeoEnums.Estado.CARGA
	
	return LeoEnums.Estado.NORMAL

static func procesar_dash(leo: CharacterBody3D, delta: float, dir_dash: Vector3, t_dash: float) -> Dictionary:
	# Retorna {"estado": Estado, "t": float restante, "pos": Vector3}
	var dur := LeoConstants.DASH_DUR
	var dist := LeoConstants.DASH_DIST
	
	var progreso := 1.0 - (t_dash / dur)
	var pos_inicio: Vector3 = leo.get_meta("dash_inicio", leo.global_position) if leo.has_meta("dash_inicio") else leo.global_position
	
	leo.global_position = pos_inicio.lerp(pos_inicio + dir_dash * dist, progreso)
	
	var nuevo_t := t_dash - delta
	if nuevo_t <= 0.0:
		return {"estado": LeoEnums.Estado.NORMAL, "t": 0.0}
	return {"estado": LeoEnums.Estado.DASH, "t": nuevo_t}

static func procesar_carga(leo: CharacterBody3D, delta: float, t_carga: float) -> Dictionary:
	var nuevo_t := t_carga + delta
	# Si suelta carga, va a PREPARADO
	if not Input.is_action_pressed("carga_poder"):
		if nuevo_t > 0.3:
			return {"estado": LeoEnums.Estado.PREPARADO, "t": nuevo_t}
		else:
			return {"estado": LeoEnums.Estado.NORMAL, "t": 0.0}
	return {"estado": LeoEnums.Estado.CARGA, "t": nuevo_t}

static func actualizar_animaciones(leo: CharacterBody3D, estado: int, dir: Vector3, vel: float) -> String:
	# Retorna nombre de animación a reproducir
	match estado:
		LeoEnums.Estado.NORMAL:
			if vel < 0.15:
				return LeoConstants.ANIM_INACTIVO
			elif vel < 3.5:
				if dir.dot(-leo.global_transform.basis.z) < -0.5:
					return LeoConstants.ANIM_ATRAS
				return LeoConstants.ANIM_ADELANTE
			else:
				return LeoConstants.ANIM_ADELANTE
		LeoEnums.Estado.DASH:
			return LeoConstants.ANIM_DASH
		LeoEnums.Estado.CARGA:
			return LeoConstants.ANIM_CARGA
		LeoEnums.Estado.EJECUCION:
			return LeoConstants.ANIM_SUPERVELOCIDAD
		_:
			return LeoConstants.ANIM_INACTIVO
