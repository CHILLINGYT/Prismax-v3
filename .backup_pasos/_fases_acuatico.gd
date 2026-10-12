extends Node
## VARIANTE de la sonda de fases de contacto para el ACUÁTICO.
## Instancia leo_jugador.tscn y mide, para walk/run, la altura del tobillo
## (mixamorig_LeftFoot / mixamorig_RightFoot) a 240 Hz, e imprime el % del ciclo
## en el contacto MÁS BAJO (el "u" que usa la TABLA de PasosJugador).
## Basado en res://.backup_pasos/_fases_contacto.gd (mismo método; sólo lectura).

const PASO := 1.0 / 240.0
const VENTANA := 0.02  # 2 cm por encima del mínimo = pie apoyado

var _jug: Node = null
var _tareas: Array = []
var _i: int = 0
var _frames: int = 0

func _ready() -> void:
	var esc: PackedScene = load("res://personaje/base/escenas/leo_jugador.tscn")
	_jug = esc.instantiate()
	add_child(_jug)
	_jug.set_process(false)
	_jug.set_physics_process(false)
	_tareas = [
		["acuatico   ", "Acuatico/AnimadorAcuatico", "walk"],
		["acuatico   ", "Acuatico/AnimadorAcuatico", "run"],
	]

func _process(_d: float) -> void:
	_frames += 1
	if _frames < 2:
		return
	while _i < _tareas.size():
		var t: Array = _tareas[_i]
		_i += 1
		_medir(String(t[0]), String(t[1]), String(t[2]))
	print("[fases] FIN")
	get_tree().quit()

func _medir(etiqueta: String, ruta: String, buscado: String) -> void:
	var ap := _jug.get_node_or_null(ruta) as AnimationPlayer
	if ap == null:
		print("%s | %s | AnimationPlayer NO encontrado" % [etiqueta, buscado]); return
	var nombre := ""
	for n in ap.get_animation_list():
		var s := String(n)
		if s == buscado or s.begins_with(buscado + "/"):
			nombre = s; break
	if nombre.is_empty():
		print("%s | %s | clip NO existe (hay: %s)" % [etiqueta, buscado, str(ap.get_animation_list())]); return
	var sk := _esqueleto_de(ap)
	if sk == null:
		print("%s | %s | sin Skeleton3D" % [etiqueta, buscado]); return
	var izq := _hueso(sk, "LeftFoot")
	var der := _hueso(sk, "RightFoot")
	if izq < 0 or der < 0:
		print("%s | %s | sin huesos de pie (izq %d, der %d)" % [etiqueta, buscado, izq, der]); return
	ap.play(nombre)
	ap.speed_scale = 1.0
	var largo := ap.get_animation(nombre).length
	var n := int(ceil(largo / PASO))
	var yi := PackedFloat32Array(); var yd := PackedFloat32Array()
	yi.resize(n); yd.resize(n)
	# ToeBase (si existe) para precisar el contacto
	var izq_t := _hueso(sk, "LeftToeBase"); var der_t := _hueso(sk, "RightToeBase")
	var yit := PackedFloat32Array(); var ydt := PackedFloat32Array()
	yit.resize(n); ydt.resize(n)
	for k in n:
		ap.seek(float(k) * PASO, true)
		yi[k] = sk.get_bone_global_pose(izq).origin.y
		yd[k] = sk.get_bone_global_pose(der).origin.y
		if izq_t >= 0: yit[k] = sk.get_bone_global_pose(izq_t).origin.y
		if der_t >= 0: ydt[k] = sk.get_bone_global_pose(der_t).origin.y
	print("%s | %-24s | dura %.4f s | muestras %d" % [etiqueta, buscado, largo, n])
	_detalle("  Foot izq", yi, largo)
	_detalle("  Foot der", yd, largo)
	if izq_t >= 0: _detalle("  Toe  izq", yit, largo)
	if der_t >= 0: _detalle("  Toe  der", ydt, largo)

func _detalle(cual: String, ys: PackedFloat32Array, largo: float) -> void:
	var min_y := 1e9
	var idx_min := 0
	for k in ys.size():
		if ys[k] < min_y:
			min_y = ys[k]; idx_min = k
	var idx_apo := idx_min
	for k in range(idx_min, -1, -1):
		if ys[k] > min_y + VENTANA:
			idx_apo = k + 1; break
		else:
			idx_apo = k
	var pmin := float(idx_min) * PASO / largo
	print("%s | min y=%.4f en t=%.4f | u_contacto=%.4f (%.2f%%) | u_apoyo=%.4f" % [
			cual, min_y, float(idx_min) * PASO, pmin, pmin * 100.0, float(idx_apo) * PASO / largo])

func _esqueleto_de(ap: AnimationPlayer) -> Skeleton3D:
	var raiz := ap.get_node_or_null(ap.root_node)
	if raiz == null:
		raiz = ap.get_parent()
	var cola: Array = [raiz]
	while not cola.is_empty():
		var n: Node = cola.pop_front()
		if n is Skeleton3D:
			return n as Skeleton3D
		for h in n.get_children():
			cola.append(h)
	return null

func _hueso(sk: Skeleton3D, sufijo: String) -> int:
	for i in sk.get_bone_count():
		if String(sk.get_bone_name(i)).ends_with(sufijo):
			return i
	return -1