class_name CityUtils
## Utilidades puras extraídas de generador_ciudad.gd

static func t(pos: Vector3, giro: float = 0.0, escala: float = 1.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0, giro, 0)).scaled(Vector3.ONE * escala), pos)

static func rot_para_dir(dir_modelo: Vector2i, dir_deseada: Vector2i) -> float:
	var ang_modelo := atan2(float(dir_modelo.y), float(dir_modelo.x))
	var ang_deseada := atan2(float(dir_deseada.y), float(dir_deseada.x))
	return ang_deseada - ang_modelo

static func elegir(rng: RandomNumberGenerator, lista: Array):
	if lista.is_empty(): return null
	return lista[rng.randi_range(0, lista.size() - 1)]

static func clave_sector(p: Vector3, lado_sector: float) -> String:
	var sx := int(floor(p.x / lado_sector))
	var sz := int(floor(p.z / lado_sector))
	return "%d_%d" % [sx, sz]

static func aabb_modelo_por_cajas(nodo: Node) -> AABB:
	var aabb := AABB()
	var primera := true
	var stack: Array[Node] = [nodo]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var mesh_aabb := mi.mesh.get_aabb()
				mesh_aabb = mi.transform * mesh_aabb
				if primera:
					aabb = mesh_aabb
					primera = false
				else:
					aabb = aabb.merge(mesh_aabb)
		for child in n.get_children():
			stack.append(child)
	return aabb
