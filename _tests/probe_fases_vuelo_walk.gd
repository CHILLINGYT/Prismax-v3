extends Node3D
## Sonda (temporal): mide las FASES DE CONTACTO del clip de locomoción terrestre
## del vuelo (`vuelo_walk`, retargeteado del `walk` del personaje de Combate) y
## deja al personaje en una pose de caminata para mirarla en la captura.

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const FPS_MEDICION := 240.0

var _jug: Node3D
var _ap: AnimationPlayer
var _skel: Skeleton3D

func _ready() -> void:
	var ps := load(JUGADOR) as PackedScene
	_jug = ps.instantiate() as Node3D
	_jug.position = Vector3.ZERO
	add_child(_jug)
	var vuelo: Node = _jug.get_node("Vuelo")
	_ap = vuelo.get_node("VisualRoot/AnimationLibrary_Godot_Standard/AnimationPlayer") as AnimationPlayer
	_skel = vuelo.get_node("VisualRoot/AnimationLibrary_Godot_Standard/Rig/GeneralSkeleton") as Skeleton3D
	# Transformar al águila: el cuerpo de VUELO queda activo (es el estado real).
	_jug.call("_on_transformacion_elegida", &"aguila")
	await get_tree().create_timer(2.0).timeout
	_medir()

func _medir() -> void:
	print("[probe] _skel = ", _skel, " válido=", is_instance_valid(_skel))
	if _skel != null:
		print("[probe] huesos=", _skel.get_bone_count(),
				" Hips=", _skel.find_bone(&"Hips"),
				" LeftToes=", _skel.find_bone(&"LeftToes"),
				" LeftFoot=", _skel.find_bone(&"LeftFoot"),
				" RightToes=", _skel.find_bone(&"RightToes"),
				" RightFoot=", _skel.find_bone(&"RightFoot"),
				" path=", _skel.get_path())
	var librerias := _ap.get_animation_library_list()
	print("[probe] librerías del reproductor = ", librerias)
	var tiene: bool = _ap.has_animation_library(&"vuelo_walk")
	print("[probe] ¿tiene librería vuelo_walk? ", tiene)
	var nombre := &"vuelo_walk/vuelo_walk" if tiene else &"vuelo_walk"
	if not _ap.has_animation(nombre):
		for cand in _ap.get_animation_list():
			if String(cand).contains("vuelo_walk"):
				nombre = cand
				break
	var clip := _ap.get_animation(nombre)
	if clip == null:
		push_error("[probe] NO se encontró el clip de locomoción del vuelo")
		get_tree().quit()
		return
	print("[probe] clip '%s': %.3f s, %d pistas, loop=%d" % [nombre, clip.length, clip.get_track_count(), clip.loop_mode])
	_ap.speed_scale = 0.0
	_ap.play(nombre)
	_ap.seek(0.0, true)
	# OJO: un PackedArray leído de un Dictionary se copia; hay que appendear sobre
	# referencias locales o los datos se pierden.
	var arr_izq := PackedFloat32Array()
	var arr_der := PackedFloat32Array()
	var arr_cad := PackedFloat32Array()
	var huesos := {
		"izq": ["LeftToes", "LeftFoot"],
		"der": ["RightToes", "RightFoot"],
	}
	var idx_cadera := _skel.find_bone(&"Hips")
	var n := int(clip.length * FPS_MEDICION)
	for k in n + 1:
		var t := clip.length * float(k) / float(n)
		_ap.seek(t, true)
		if _skel.has_method("force_update_all_bone_transforms"):
			_skel.call("force_update_all_bone_transforms")
		for pie in huesos:
			var y := INF
			for nombre_hueso in (huesos[pie] as Array):
				var i := _skel.find_bone(StringName(nombre_hueso))
				if i >= 0:
					y = minf(y, (_skel.global_transform * _skel.get_bone_global_pose(i).origin).y)
			if pie == "izq":
				arr_izq.append(y)
			else:
				arr_der.append(y)
		if idx_cadera >= 0:
			arr_cad.append((_skel.global_transform * _skel.get_bone_global_pose(idx_cadera).origin).y)
	print("[probe] muestras: izq=%d der=%d cadera=%d" % [arr_izq.size(), arr_der.size(), arr_cad.size()])
	for pie in ["izq", "der"]:
		var arr: PackedFloat32Array = arr_izq if pie == "izq" else arr_der
		var mn := INF
		var mx := -INF
		for k in arr.size():
			mn = minf(mn, arr[k])
			mx = maxf(mx, arr[k])
		var idx_min := -1
		var mejor := INF
		for k in range(1, arr.size() - 1):
			if arr[k] < arr[k - 1] and arr[k] <= arr[k + 1] and arr[k] < mejor:
				mejor = arr[k]
				idx_min = k
		var fase := float(idx_min) / float(arr.size() - 1) if idx_min >= 0 else -1.0
		print("[probe] pie %s: fase de contacto = %.4f (alturas %.4f a %.4f, rango %.3f)" % [pie, fase, mn, mx, mx - mn])
	var cad: PackedFloat32Array = arr_cad
	var cmn := INF
	var cmx := -INF
	for k in cad.size():
		cmn = minf(cmn, cad[k])
		cmx = maxf(cmx, cad[k])
	print("[probe] cadera y: %.4f a %.4f (rango %.3f)" % [cmn, cmx, cmx - cmn])
	# Pose de caminata en el contacto izquierdo y luego el ciclo suelto: la captura
	# final queda dentro de la caminata para poder mirarla.
	_ap.speed_scale = 0.0
	_ap.seek(clip.length * 0.3203, true)
	if _skel.has_method("force_update_all_bone_transforms"):
		_skel.call("force_update_all_bone_transforms")
	await get_tree().create_timer(1.0).timeout
	_ap.speed_scale = 1.0
	print("[probe] FIN")
	await get_tree().create_timer(6.0).timeout