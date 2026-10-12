extends Node

## Sonda de fases de contacto (SOLO LECTURA sobre la escena del jugador).
## Instancia res://personaje/base/escenas/leo_jugador.tscn, busca los
## AnimationPlayer reales y, para cada clip, muestrea a 240 Hz la altura del
## tobillo (hueso del pie) en el espacio del modelo. Imprime:
##   - instante (y % del ciclo) del tobillo MÁS BAJO  -> "min"
##   - inicio de la ventana de apoyo (y <= min + 2 cm) -> "apo"
## El % del mínimo es el que usa el sistema de pisadas.

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
		["humano    ", "Humano/Animador", "walk"],
		["humano    ", "Humano/Animador", "fast_run"],
		["humano    ", "Humano/Animador", "crouch_walk"],
		["combate   ", "Ataque/AnimadorAtaque", "walk"],
		["fuerza    ", "Fuerza/AnimadorFuerza", "Walk"],
		["fuerza    ", "Fuerza/AnimadorFuerza", "Run"],
		["fuerza    ", "Fuerza/AnimadorFuerza", "CrouchWalk"],
		["fuerza    ", "Fuerza/AnimadorFuerza", "RockCarryWalk"],
		["velocista ", "Visual/Pose/Volteo/Modelo/AnimadorVelocista", "caminar_hacia_adelante"],
		["velocista ", "Visual/Pose/Volteo/Modelo/AnimadorVelocista", "caminar_hacia_atras"],
		["velocista ", "Visual/Pose/Volteo/Modelo/AnimadorVelocista", "superduper_velocidad"],
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
		print("%s | %s | AnimationPlayer NO encontrado" % [etiqueta, buscado])
		return
	var nombre := ""
	for n in ap.get_animation_list():
		var s := String(n)
		if s == buscado or s.begins_with(buscado + "/"):
			nombre = s
			break
	if nombre.is_empty():
		print("%s | %s | clip NO existe (hay: %s)" % [etiqueta, buscado, str(ap.get_animation_list())])
		return
	var sk := _esqueleto_de(ap)
	if sk == null:
		print("%s | %s | sin Skeleton3D" % [etiqueta, buscado])
		return
	var izq := _hueso(sk, "LeftFoot")
	var der := _hueso(sk, "RightFoot")
	if izq < 0 or der < 0:
		print("%s | %s | sin huesos de pie (izq %d, der %d)" % [etiqueta, buscado, izq, der])
		return
	ap.play(nombre)
	ap.speed_scale = 1.0
	var largo := ap.get_animation(nombre).length
	var n := int(ceil(largo / PASO))
	var yi := PackedFloat32Array()
	var yd := PackedFloat32Array()
	yi.resize(n)
	yd.resize(n)
	var xi := PackedFloat32Array()
	var zi := PackedFloat32Array()
	var xd := PackedFloat32Array()
	var zd := PackedFloat32Array()
	xi.resize(n)
	zi.resize(n)
	xd.resize(n)
	zd.resize(n)
	for k in n:
		ap.seek(float(k) * PASO, true)
		yi[k] = sk.get_bone_global_pose(izq).origin.y
		yd[k] = sk.get_bone_global_pose(der).origin.y
		xi[k] = sk.get_bone_global_pose(izq).origin.x
		zi[k] = sk.get_bone_global_pose(izq).origin.z
		xd[k] = sk.get_bone_global_pose(der).origin.x
		zd[k] = sk.get_bone_global_pose(der).origin.z
	print("%s | %-28s | dura %.4f s | muestras %d" % [etiqueta, buscado, largo, n])
	_detalle("  izq", yi, largo)
	_detalle("  der", yd, largo)
	# PASO DEL CLIP: recorrido horizontal del tobillo en un ciclo (espacio del modelo).
	# Se compara con lo que el personaje avanza de verdad por paso = velocidad * T/2.
	print("   paso del clip (m, recorrido horizontal del tobillo en un ciclo): izq %.3f | der %.3f" % [
			_paso(xi, zi), _paso(xd, zd)])

func _paso(xs: PackedFloat32Array, zs: PackedFloat32Array) -> float:
	var x_min := 1e9
	var x_max := -1e9
	var z_min := 1e9
	var z_max := -1e9
	for k in xs.size():
		x_min = minf(x_min, xs[k])
		x_max = maxf(x_max, xs[k])
		z_min = minf(z_min, zs[k])
		z_max = maxf(z_max, zs[k])
	return maxf(x_max - x_min, z_max - z_min)

func _detalle(cual: String, ys: PackedFloat32Array, largo: float) -> void:
	var min_y := 1e9
	var idx_min := 0
	for k in ys.size():
		if ys[k] < min_y:
			min_y = ys[k]
			idx_min = k
	# inicio de la ventana de apoyo (último cruce hacia abajo antes del mínimo)
	var idx_apo := idx_min
	for k in range(idx_min, -1, -1):
		if ys[k] > min_y + VENTANA:
			idx_apo = k + 1
			break
		else:
			idx_apo = k
	var apa := float(idx_apo) * PASO / largo * 100.0
	var pmin := float(idx_min) * PASO / largo * 100.0
	print("%s | min y=%.4f en t=%.4f (u=%.2f%%) | apoyo u=%.2f%% | fin apoyo u=%.2f%%" % [
			cual, min_y, float(idx_min) * PASO, pmin, apa,
			_fin_apoyo(ys, min_y, idx_min) * PASO / largo * 100.0])

func _fin_apoyo(ys: PackedFloat32Array, min_y: float, idx_min: int) -> float:
	var k := idx_min
	while k < ys.size() and ys[k] <= min_y + VENTANA:
		k += 1
	return float(k)

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