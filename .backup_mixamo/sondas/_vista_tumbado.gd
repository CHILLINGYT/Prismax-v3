extends Node3D
## Captura temporal: vista cenital y oblicua de un ciudadano TUMBADO, sin tocarle la actividad
## (si se le fuerza "aviso" el ciudadano se levanta y la foto sale a medias). Mide además los
## brazos respecto al EJE DEL CUERPO: 0-35° = brazos a lo largo del cuerpo (correcto tumbado).

const DIR_CAP := "res://.backup_mixamo/capturas"

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null
var _cam: Camera3D = null
var _objetivo: Node = null
var _esperando := true
var _t0 := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR_CAP))
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = 20260707
	add_child(_juego)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.near = 0.05
	add_child(_cam)
	_cam.make_current()
	_t0 = Time.get_ticks_msec()
	Engine.time_scale = 4.0


func _process(_d: float) -> void:
	if _dir == null:
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
		return
	_cam.make_current()
	if _esperando:
		for c in _dir.peatones:
			if c.en_postura() and c.fase_postura() == "reposar" and c.postura_actual() == "recostarse":
				_objetivo = c
				break
		if _objetivo != null:
			_esperando = false
			Engine.time_scale = 1.0
			_lanzar()
		elif float(Time.get_ticks_msec() - _t0) > 90000.0:
			print("[VistaTumbado] nadie se tumbó a tiempo")
			get_tree().quit()


func _lanzar() -> void:
	await get_tree().create_timer(1.2).timeout
	var c := _objetivo as Node3D
	var p := c.global_position
	var yaw := c.rotation.y
	var eje := Vector3(sin(yaw), 0.0, cos(yaw))
	var lado := eje.cross(Vector3.UP).normalized()
	print("[VistaTumbado] objetivo %s modelo %s brazos(eje del cuerpo) %s" % [_objetivo.name,
			String(_objetivo.model_scene.resource_path).get_file(), str(_brazos(_objetivo))])
	_cam.global_position = p + Vector3.UP * 3.6 + lado * 0.35
	_cam.look_at(p + Vector3.UP * 0.15)
	await _capturar("tumb_cenital")
	_cam.global_position = p + lado * 2.6 + Vector3.UP * 1.9 - eje * 0.4
	_cam.look_at(p + Vector3.UP * 0.35)
	await _capturar("tumb_oblicua")
	print("[VistaTumbado] fin")
	get_tree().quit()


func _brazos(c: Node) -> Array:
	var sk: Skeleton3D = c.find_child("Skeleton3D", true, false)
	if sk == null:
		return ["sin esqueleto"]
	var out: Array[String] = []
	var xf := sk.global_transform
	var ic := _hueso(sk, ["mixamorig_Head", "Head"])
	var ip := _hueso(sk, ["mixamorig_LeftToeBase", "LeftToeBase"])
	var eje := Vector3.FORWARD
	if ic >= 0 and ip >= 0:
		eje = ((xf * sk.get_bone_global_pose(ic).origin) - (xf * sk.get_bone_global_pose(ip).origin)).normalized()
	for par: String in ["Left", "Right"]:
		var ia := _hueso(sk, ["mixamorig_%sArm" % par, "%sArm" % par])
		var ib := _hueso(sk, ["mixamorig_%sForeArm" % par, "%sForeArm" % par])
		if ia < 0 or ib < 0:
			continue
		var d := ((xf * sk.get_bone_global_pose(ib).origin) - (xf * sk.get_bone_global_pose(ia).origin)).normalized()
		var ang := rad_to_deg(d.angle_to(eje))
		out.append("%s %4.0f°" % [par, ang if ang <= 90.0 else 180.0 - ang])
	return out


func _hueso(sk: Skeleton3D, candidatos: Array) -> int:
	for n: String in candidatos:
		var i := sk.find_bone(n)
		if i >= 0:
			return i
	return -1


func _capturar(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [DIR_CAP, nombre])
	print("[VistaTumbado] captura %s -> %s" % [nombre, "OK" if err == OK else str(err)])