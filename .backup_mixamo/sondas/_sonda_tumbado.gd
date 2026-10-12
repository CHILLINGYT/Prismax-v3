extends Node
## Sonda temporal: vigila a un ciudadano TUMBADO durante varios segundos SIN tocarle la actividad,
## midiendo cada muestra los brazos (ángulo respecto a la vertical), la pista activa, la fase y la
## altura de la cadera. Sirve para saber si la pose de reposo se mantiene o se degrada (brazos
## abiertos tipo T, cuerpo hundido) mientras el ciudadano sigue tumbado.

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null


func _ready() -> void:
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = 20260707
	add_child(_juego)
	Engine.time_scale = 6.0
	_run.call_deferred()


func _run() -> void:
	while _dir == null:
		await get_tree().process_frame
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
	var objetivo: Node = null
	var sentado: Node = null
	var t0 := Time.get_ticks_msec()
	while (objetivo == null or sentado == null) and float(Time.get_ticks_msec() - t0) < 60000.0:
		await get_tree().process_frame
		for c in _dir.peatones:
			if not c.en_postura() or c.fase_postura() != "reposar":
				continue
			if c.postura_actual() == "recostarse" and objetivo == null:
				objetivo = c
			if c.postura_actual() == "sentarse" and sentado == null:
				sentado = c
	if objetivo == null and sentado == null:
		print("[SondaTumbado] nadie en postura")
		return
	if objetivo != null:
		print("[SondaTumbado] vigilando TUMBADO %s (modelo %s)" % [objetivo.name,
				String(objetivo.model_scene.resource_path).get_file()])
	if sentado != null:
		print("[SondaTumbado] vigilando SENTADO %s (modelo %s)" % [sentado.name,
				String(sentado.model_scene.resource_path).get_file()])
	for i in 12:
		await get_tree().create_timer(1.0).timeout
		for par: Array in [["TUM", objetivo], ["SEN", sentado]]:
			var c: Node = par[1]
			if c == null or not is_instance_valid(c):
				continue
			var m := _brazos(c)
			print("  %s t=%2ds fase=%-8s estado=%-10s árbol=%s brazos %s cadera y %+.2f" % [
					par[0], i + 1, str(c.get("_postura_fase")), _nodo_actual(c),
					str(c.get("_tree").active) if c.get("_tree") != null else "sin árbol",
					m[0], float(m[1])])
	print("[SondaTumbado] fin")


## Estado actual de la máquina de animación del ciudadano (el nombre real del nodo en uso).
func _nodo_actual(c: Node) -> String:
	var pb: Object = c.get("_playback")
	if pb == null:
		return "sin playback"
	return str(pb.call("get_current_node"))


func _brazos(c: Node) -> Array:
	var sk: Skeleton3D = c.find_child("Skeleton3D", true, false)
	if sk == null:
		return ["sin esqueleto", 0.0]
	var out: Array[String] = []
	var y_cadera := 0.0
	var xf := sk.global_transform
	# Eje del cuerpo (cabeza - pies): para un tumbado, un brazo "correcto" va a lo largo de ese
	# eje (~0-35°) y un brazo abierto a lo ancho queda cerca de 90°. Contra la vertical mundial
	# el ángulo no sirve, porque el cuerpo está horizontal.
	var i_cab := _hueso(sk, ["mixamorig_Head", "Head"])
	var i_pie := _hueso(sk, ["mixamorig_LeftToeBase", "LeftToeBase"])
	var eje := Vector3.FORWARD
	if i_cab >= 0 and i_pie >= 0:
		eje = ((xf * sk.get_bone_global_pose(i_cab).origin) - (xf * sk.get_bone_global_pose(i_pie).origin)).normalized()
	for par: String in ["Left", "Right"]:
		var ia := _hueso(sk, ["mixamorig_%sArm" % par, "%sArm" % par])
		var ib := _hueso(sk, ["mixamorig_%sForeArm" % par, "%sForeArm" % par])
		if ia < 0 or ib < 0:
			out.append("%s n/d" % par)
			continue
		var a := xf * sk.get_bone_global_pose(ia).origin
		var b := xf * sk.get_bone_global_pose(ib).origin
		var d := (b - a).normalized()
		var ang := rad_to_deg(d.angle_to(eje))
		if ang > 90.0:
			ang = 180.0 - ang
		out.append("%s %4.0f°" % [par, ang])
	var ic := _hueso(sk, ["mixamorig_Hips", "Hips"])
	if ic >= 0:
		y_cadera = (xf * sk.get_bone_global_pose(ic).origin).y
	return [str(out), y_cadera]


func _hueso(sk: Skeleton3D, candidatos: Array) -> int:
	for n: String in candidatos:
		var i := sk.find_bone(n)
		if i >= 0:
			return i
	return -1