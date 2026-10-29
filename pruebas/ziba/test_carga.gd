extends Node3D

# Diagnostico: mide la altura (Y mundo) de la cadera y los pies durante
# 'inactivo' y 'cargar poder click derecho', con y sin el offset de _actualizar_pose.

var prototipo: Node3D
var jugador: Node3D
var skel: Skeleton3D
var huesos: Dictionary = {}

func _esperar(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _y_mundo(idx: int) -> float:
	if idx < 0:
		return 0.0
	return skel.to_global(skel.get_bone_global_pose(idx).origin).y

func _medir(etiqueta: String) -> void:
	var filas: Array = []
	var minimo: float = INF
	for nombre in huesos:
		var y: float = _y_mundo(huesos[nombre])
		filas.append("%s=%.3f" % [nombre, y])
		minimo = minf(minimo, y)
	print("[MEDIR] ", etiqueta, "  ", " ".join(filas), "  MIN=%.3f" % minimo)

func _ready() -> void:
	prototipo = $ZibaPrototipo
	await _esperar(12)
	jugador = prototipo.get_node("Jugador")
	skel = jugador.get_node("Visual/Pose/Volteo/Modelo/Skeleton3D")
	print("[INFO] skel.global_origin.y=", snappedf(skel.global_position.y, 0.001), " modelo_index=", skel.get_parent().get_index())
	for n in ["mixamorig_Hips", "mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_LeftToeBase", "mixamorig_RightToeBase"]:
		huesos[n] = skel.find_bone(n)

	var space := jugador.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(jugador.global_position + Vector3.UP * 3.0, jugador.global_position + Vector3.DOWN * 6.0)
	var hit := space.intersect_ray(q)
	print("[INFO] jugador.origin.y=", snappedf(jugador.global_position.y, 0.001),
		"  piso.y=", (snappedf(hit.position.y, 0.001) if hit else "none"))

	_medir("inactivo (referencia)")

	Input.action_press("cargar_poder")
	await _esperar(40)
	_medir("carga CON offset de pose (-0.22)")

	# Anular en memoria SOLO el offset del codigo para aislar la animacion.
	jugador.set_physics_process(false)
	jugador.get_node("Visual/Pose").position.y = 0.0
	await _esperar(4)
	_medir("carga SIN offset de pose (solo animacion)")

	# Restaurar
	jugador.get_node("Visual/Pose").position.y = -0.22
	jugador.set_physics_process(true)
	Input.action_release("cargar_poder")
	await _esperar(30)
	_medir("post-carga")

	print("[TEST] FIN")
	get_tree().quit()