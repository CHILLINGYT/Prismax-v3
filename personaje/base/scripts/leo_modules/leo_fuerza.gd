## leo_fuerza.gd - Fase 3 - Lógica de Fuerza
## Extraído de controlador_leo.gd - embestida, slam, roca, combo

class_name LeoFuerza

static func procesar_embestida(leo: CharacterBody3D, delta: float, dir: Vector3, t: float, golpeados: Array) -> Dictionary:
	var dur := LeoConstants.F_EMBESTIDA_DUR
	var vel := LeoConstants.F_EMBESTIDA_VEL
	
	leo.velocity.x = dir.x * vel
	leo.velocity.z = dir.z * vel
	
	# Detectar impacto con enemigos
	var mundo := leo.get_world_3d()
	if mundo != null:
		var espacio := mundo.direct_space_state
		var params := PhysicsShapeQueryParameters3D.new()
		var esfera := SphereShape3D.new()
		esfera.radius = LeoConstants.F_EMBESTIDA_RADIO
		params.shape = esfera
		params.transform = Transform3D(Basis.IDENTITY, leo.global_position + Vector3.UP * 1.0)
		params.collision_mask = 16
		params.exclude = [leo.get_rid()] if leo is CollisionObject3D else []
		var resultados := espacio.intersect_shape(params, 8)
		for r in resultados:
			var col: Object = r.collider
			if col == null or golpeados.has(col):
				continue
			if col is Node and (col as Node).has_method("take_damage"):
				(col as Node).call("take_damage", LeoConstants.F_EMBESTIDA_DANIO, leo.global_position, dir * 6.0)
				golpeados.append(col)
	
	var nuevo_t := t - delta
	if nuevo_t <= 0.0:
		return {"terminado": true, "t": 0.0, "golpeados": golpeados, "recuperacion": LeoConstants.F_EMBESTIDA_RECUP}
	return {"terminado": false, "t": nuevo_t, "golpeados": golpeados}

static func procesar_slam(leo: CharacterBody3D, delta: float) -> Dictionary:
	# Caída rápida
	leo.velocity.y -= LeoConstants.F_SLAM_VEL * delta
	
	if leo.is_on_floor():
		# Impacto
		var mundo := leo.get_world_3d()
		var golpeados: Array = []
		if mundo != null:
			var espacio := mundo.direct_space_state
			var params := PhysicsShapeQueryParameters3D.new()
			var esfera := SphereShape3D.new()
			esfera.radius = LeoConstants.F_SLAM_RADIO
			params.shape = esfera
			params.transform = Transform3D(Basis.IDENTITY, leo.global_position)
			params.collision_mask = 17
			params.exclude = [leo.get_rid()] if leo is CollisionObject3D else []
			var resultados := espacio.intersect_shape(params, 16)
			for r in resultados:
				var col: Object = r.collider
				if col is Node and (col as Node).has_method("take_damage"):
					var dir := ((col as Node3D).global_position - leo.global_position).normalized()
					dir.y = 0.5
					(col as Node).call("take_damage", LeoConstants.F_SLAM_DANIO, leo.global_position, dir * 5.0)
					golpeados.append(col)
		return {"impacto": true, "golpeados": golpeados}
	return {"impacto": false}

static func actualizar_carga_super(carga: float, delta: float, cargando: bool) -> float:
	if cargando:
		return minf(carga + delta, LeoConstants.F_SUPER_CARGA_MAX)
	else:
		return maxf(carga - delta * 2.0, 0.0)

static func calcular_velocidad_super(carga: float) -> float:
	var t := clampf((carga - LeoConstants.F_SUPER_CARGA_MIN) / (LeoConstants.F_SUPER_CARGA_MAX - LeoConstants.F_SUPER_CARGA_MIN), 0.0, 1.0)
	return lerpf(LeoConstants.F_SUPER_VEL_MIN, LeoConstants.F_SUPER_VEL_MAX, t)
