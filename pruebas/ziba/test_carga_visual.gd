extends Node3D

# Diagnostico visual cercano: fuerza la carga, coloca una camara lateral
# cercana y una marca roja en el nivel del suelo (origen del jugador).

func _medir(j: Node3D, etiqueta: String) -> void:
	var skel: Skeleton3D = j.get_node("Visual/Pose/Volteo/Modelo/Skeleton3D")
	var base_y: float = j.global_position.y
	var min_y: float = INF
	var detalle: Array = []
	for n in ["mixamorig_Hips", "mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_LeftToeBase", "mixamorig_RightToeBase"]:
		var idx := skel.find_bone(n)
		var y := skel.to_global(skel.get_bone_global_pose(idx).origin).y
		detalle.append("%s=%+.3f" % [n.replace("mixamorig_", ""), y - base_y])
		min_y = minf(min_y, y - base_y)
	print("[VIS] ", etiqueta, " origin.y=", snappedf(base_y, 0.001), " relSuelo: ", " ".join(detalle), "  MIN=%+.3f" % min_y)

func _ready() -> void:
	for i in 80:
		await get_tree().physics_frame
	var j: Node3D = $ZibaPrototipo.get_node("Jugador")
	_medir(j, "inactivo")
	j._iniciar_carga()
	for i in 45:
		await get_tree().physics_frame
	_medir(j, "carga (con offset codigo)")

	# Aislar SOLO el offset vertical del codigo, sin tocar fisica ni animacion.
	j.set_physics_process(false)
	j.get_node("Visual/Pose").position.y = 0.0
	for i in 4:
		await get_tree().physics_frame
	_medir(j, "carga (sin offset codigo)")

	var base_y: float = j.global_position.y
	# Marca roja fina en el nivel del suelo (origen del jugador).
	var marca := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 0.012, 2.4)
	marca.mesh = bm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1, 0, 0, 1)
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marca.material_override = mm
	add_child(marca)
	marca.global_position = Vector3(j.global_position.x, base_y - 0.006, j.global_position.z)

	# Camara lateral apuntando a los pies.
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	var objetivo := Vector3(j.global_position.x, base_y + 0.35, j.global_position.z)
	cam.global_position = objetivo + Vector3(2.6, 0.9, 2.0)
	cam.look_at(objetivo, Vector3.UP)
	cam.current = true