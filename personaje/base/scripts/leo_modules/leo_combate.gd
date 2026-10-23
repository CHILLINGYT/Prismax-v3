## leo_combate.gd - Fase 3 - Combate FreeFlow, Fuerza, Acuático
## Extraído y refactorizado de controlador_leo.gd
## Maneja la integración con combat_manager y los 3 sistemas de combate

class_name LeoCombate

## Configuración de combate acuático (2 golpes)
const COMBO_ACUATICO := [
	{"clip": "attack", "impact_u": 0.54, "danio": 20.0, "alcance": 1.1},
	{"clip": "attack_2", "impact_u": 0.55, "danio": 22.0, "alcance": 1.1},
]

## Configuración combate Fuerza (3 golpes)
const COMBO_FUERZA := [
	{"clip": "Punch_Left", "impact_u": 0.29, "danio": 30.0, "tipo": "punch"},
	{"clip": "Punch_Right", "impact_u": 0.32, "danio": 35.0, "tipo": "punch"},
	{"clip": "Kick", "impact_u": 0.35, "danio": 40.0, "tipo": "kick"},
]

static func punto_impacto(objetivo: Node3D) -> Vector3:
	if objetivo == null:
		return Vector3.ZERO
	if objetivo.has_method("get_hit_center"):
		return objetivo.call("get_hit_center")
	return objetivo.global_position + Vector3.UP * 1.0

static func pies_de(objetivo: Node3D) -> Vector3:
	if objetivo == null:
		return Vector3.ZERO
	return objetivo.global_position

static func aplicar_impacto_golpe_acuatico(leo: Node3D, centro: Vector3, radio: float, danio: float, empuje: float) -> Array:
	var mundo := leo.get_world_3d()
	if mundo == null:
		return []
	var espacio := mundo.direct_space_state
	# Buscar enemigos en esfera
	var params := PhysicsShapeQueryParameters3D.new()
	var esfera := SphereShape3D.new()
	esfera.radius = radio
	params.shape = esfera
	params.transform = Transform3D(Basis.IDENTITY, centro)
	params.collision_mask = 16 # capa enemigos
	params.exclude = [leo.get_rid()] if leo is CollisionObject3D else []
	
	var resultados := espacio.intersect_shape(params, 32)
	var golpeados: Array = []
	for r in resultados:
		var collider: Object = r.collider
		if collider == null:
			continue
		var nodo := collider as Node
		if nodo == null:
			continue
		# Buscar nodo con contrato de daño
		var target := nodo
		if not target.has_method("take_damage") and not target.has_method("apply_damage") and not target.has_method("take_hit"):
			# Subir en jerarquía
			if nodo is Node3D:
				target = (nodo as Node3D).get_parent()
		if target != null and (target.has_method("take_damage") or target.has_method("apply_damage") or target.has_method("take_hit")):
			if target.has_method("take_damage"):
				target.call("take_damage", danio, leo.global_position, Vector3(1,0,0) * empuje)
			elif target.has_method("take_hit"):
				var dir := (target.global_position - leo.global_position).normalized()
				dir.y = 0.0
				target.call("take_hit", danio, dir, empuje, 0.25)
			elif target.has_method("apply_damage"):
				target.call("apply_damage", danio, leo.global_position, &"melee")
			golpeados.append(target)
	return golpeados

static func aplicar_impacto_fuerza(leo: Node3D, centro: Vector3, radio: float, danio: float, empuje: float, altura: float) -> Array:
	var mundo := leo.get_world_3d()
	if mundo == null:
		return []
	var espacio := mundo.direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var esfera := SphereShape3D.new()
	esfera.radius = radio
	params.shape = esfera
	# Centro ajustado a altura de puño
	var centro_ajustado := centro + Vector3.UP * altura
	params.transform = Transform3D(Basis.IDENTITY, centro_ajustado)
	params.collision_mask = 16
	params.exclude = [leo.get_rid()] if leo is CollisionObject3D else []
	
	var resultados := espacio.intersect_shape(params, 32)
	var golpeados: Array = []
	for r in resultados:
		var collider: Object = r.collider
		if collider == null:
			continue
		var nodo := collider as Node
		if nodo == null:
			continue
		var target := nodo
		if target.has_method("take_damage"):
			var dir := (target.global_position - leo.global_position).normalized()
			dir.y = 0.3
			target.call("take_damage", danio, leo.global_position, dir * empuje)
			golpeados.append(target)
		elif target.has_method("take_hit"):
			var dir2 := (target.global_position - leo.global_position).normalized()
			dir2.y = 0.3
			target.call("take_hit", danio, dir2, empuje, 0.25)
			golpeados.append(target)
	return golpeados

## Afterimage pool para evade perfecto y velocista - Fase 3
class AfterimagePool:
	const POOL_SIZE := 12
	var _pool: Array[Node3D] = []
	var _parent: Node3D
	
	func _init(parent: Node3D) -> void:
		_parent = parent
	
	func get_afterimage(modelo: Node3D) -> Node3D:
		# Buscar uno libre
		for entry in _pool:
			if is_instance_valid(entry) and not entry.visible:
				return entry
		# Crear nuevo si pool no lleno
		if _pool.size() < POOL_SIZE and modelo != null:
			var fantasma := modelo.duplicate() as Node3D
			if fantasma != null:
				fantasma.visible = false
				if _parent != null:
					_parent.add_child(fantasma)
				_pool.append(fantasma)
				return fantasma
		# Reusar el más viejo
		if not _pool.is_empty():
			return _pool[0]
		return null
	
	func return_afterimage(node: Node3D, dur: float = 0.3) -> void:
		if node == null or not is_instance_valid(node):
			return
		node.visible = true
		var tween := node.create_tween()
		tween.tween_property(node, "transparency", 1.0, dur)
		tween.tween_callback(func(): node.visible = false)
