extends Node3D

# ARNÉS TEMPORAL DE INSPECCIÓN VISUAL de la muerte (se elimina al terminar la
# auditoría). Mata al jugador REAL en la forma pedida por el MISMO camino del
# juego (recibir_danio en Estadisticas) y deja una cámara fija mirando el cuerpo
# para capturar la pose del cadáver. No modifica la lógica de muerte.

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

@export var id_forma := "pes"
@export var cam_offset := Vector3(2.6, 2.3, 3.2)

var _jug: CharacterBody3D
var _cam: Camera3D


func _ready() -> void:
	call_deferred("_correr")


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _correr() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.25, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.9, 0.95)
	env.environment = e
	add_child(env)
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-50, -30, 0)
	add_child(luz)
	var cuerpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(60, 1, 60)
	forma.shape = caja
	forma.position = Vector3(0, -0.5, 0)
	cuerpo.add_child(forma)
	add_child(cuerpo)
	var piso := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	piso.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.5, 0.55)
	piso.material_override = mat
	add_child(piso)

	_jug = JUGADOR.instantiate() as CharacterBody3D
	add_child(_jug)
	_jug.global_position = Vector3(0, 0.4, 0)
	await _esperar(0.9)
	# Transformar por el MISMO camino del menú.
	_jug.menu_transf.transformacion_elegida.emit(StringName(id_forma))
	await _esperar(1.6)
	print("[MUERTE-VIS] forma=", _jug.forma, " id=", _jug.id_forma())
	var stats: EstadisticasJugador = _jug.get_node_or_null("Estadisticas")
	for _i in 12:
		if stats.muerto:
			break
		stats.recibir_danio(9999.0)
		await _esperar(0.12)
	print("[MUERTE-VIS] muerto=", stats.muerto)
	# Cámara fija (y apagar las del juego para que no peleen).
	for c in _jug.find_children("*", "Camera3D", true, false):
		(c as Camera3D).current = false
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.position = _jug.global_position + cam_offset
	_cam.look_at(_jug.global_position + Vector3(0, 0.3, 0))
	_cam.current = true
	while true:
		await _esperar(0.5)
		_informar()


func _informar() -> void:
	var nodo: Node3D = null
	match _jug.forma:
		2:
			nodo = _jug.get_node_or_null("Acuatico")
		3:
			nodo = _jug.get_node_or_null("Fuerza")
	var sk: Skeleton3D = null
	if nodo != null:
		for n in nodo.find_children("*", "Skeleton3D", true, false):
			sk = n
			break
	var estado := int(_jug._muerte_estado)
	var cadera := -1.0
	if sk != null and sk.find_bone("mixamorig_Hips") >= 0:
		cadera = (sk.global_transform * sk.get_bone_global_pose(
				sk.find_bone("mixamorig_Hips")).origin).y
	print("[MUERTE-VIS] estado=%d cadera=%.2f m | cam activa=%s" % [estado, cadera, str(_cam.current)])