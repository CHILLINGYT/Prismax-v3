extends Node3D
## Verificación de los MODELOS DE MIXAMO y de las posturas (temporal, no forma parte del juego).
##
## Carga el juego real y guarda capturas con la cámara colocada en ESPACIO MUNDO a partir del
## banco y de la reposera (no del propio NPC): así se ve de verdad si el cuerpo está alineado con
## el mueble. Además imprime números de control: modelo de cada ciudadano, ángulo de los brazos
## respecto a la vertical (un brazo colgando ~0-30°; en T-pose ~90° sería un fallo) y el error de
## yaw al sentarse/tumbarse (debe ser ~0°).

const DIR_CAP := "res://.backup_mixamo/capturas"

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null
var _cam: Camera3D = null
var _t0 := 0
var _paso := 0
var _proxima := 0.0
var _limite := 0.0
var _objetivo: Node = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR_CAP))
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = 20260707
	add_child(_juego)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.08
	add_child(_cam)
	_cam.make_current()
	_t0 = Time.get_ticks_msec()
	Engine.time_scale = 6.0
	print("[MixVista] cargada; esperando a la ciudad...")


func _process(_d: float) -> void:
	if _dir == null:
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
		if _dir == null:
			return
	_cam.make_current()
	var real := float(Time.get_ticks_msec() - _t0) / 1000.0
	match _paso:
		0:
			if real > 7.0:
				Engine.time_scale = 1.0
				_resumen_modelos()
				_paso = 1
				_proxima = real + 0.5
		1:
			if real >= _proxima:
				_andando("perfil")
				_capturar("mix1_andando_perfil")
				_paso = 2
				_proxima = real + 0.5
		2:
			if real >= _proxima:
				_andando("frente")
				_capturar("mix2_andando_frente")
				_paso = 3
				_proxima = real + 0.5
		3:
			if real >= _proxima:
				_quieto()
				_capturar("mix3_quieto_frente")
				_paso = 4
				_proxima = real
				_limite = real + 6.0
		4:
			# Se espera (reloj acelerado) a que haya alguien sentado de verdad.
			if real >= _proxima:
				if _sentado("frente") or real > _limite:
					_capturar("mix4_sentado_frente")
					_paso = 5
					_proxima = real + 0.6
				else:
					_proxima = real + 0.6
		5:
			if real >= _proxima:
				_sentado("lado")
				_capturar("mix5_sentado_lado")
				_paso = 6
				_proxima = real
				_limite = real + 8.0
				Engine.time_scale = 3.0
		6:
			if real >= _proxima:
				if _tumbado("lado") or real > _limite:
					Engine.time_scale = 1.0
					_capturar("mix6_tumbado_lado")
					_paso = 7
					_proxima = real + 0.6
				else:
					_proxima = real + 0.6
		7:
			if real >= _proxima:
				if _tumbado("cabeza"):
					_capturar("mix7_tumbado_cabeza")
				_paso = 8
				_proxima = real + 0.6
		8:
			if real >= _proxima:
				_modelos_sueltos()
				_paso = 9
				_proxima = real + 0.6
		9:
			if real >= _proxima:
				print("[MixVista] fin")
				get_tree().quit()


## Un retrato por cada modelo distinto en uso: comprueba que los SIETE se dibujan bien
## (piel escamada a un lado, escala, ropa) y deja ver qué aspecto tiene cada uno.
func _modelos_sueltos() -> void:
	var vistos: Dictionary = {}
	for c in _dir.peatones:
		if c.model_scene == null:
			continue
		var n := String(c.model_scene.resource_path).get_file()
		if vistos.has(n):
			continue
		vistos[n] = true
		_preparar(c)
		var ry: float = (c as Node3D).rotation.y
		_cam.global_position = (c as Node3D).global_position + Vector3(sin(ry), 0.0, cos(ry)) * 3.2 + Vector3.UP * 1.45
		_cam.look_at((c as Node3D).global_position + Vector3.UP * 0.95)
		print("[MixVista] retrato %s: %s (andando=%s) brazos %s" % [n, c.name, str(c.is_walking()), _brazos(c)])
		await _capturar("mix8_%s" % n.replace(".fbx", ""))


## Resumen: qué modelos usan los ciudadanos vivos y de qué tamaño son.
func _resumen_modelos() -> void:
	var cuenta: Dictionary = {}
	var activos := 0
	for c in _dir.peatones:
		if c.model_scene == null:
			continue
		activos += 1
		var n := String(c.model_scene.resource_path).get_file()
		cuenta[n] = int(cuenta.get(n, 0)) + 1
	print("[MixVista] ciudadanos con modelo: %d | reparto: %s" % [activos, str(cuenta)])
	var c0: Object = _dir.peatones[0]
	var sk: Skeleton3D = c0.find_child("Skeleton3D", true, false)
	if sk != null:
		print("[MixVista] huesos del primero: %s ... (total %d)" % [String(sk.get_bone_name(0)), sk.get_bone_count()])
		print("[MixVista] pista de animación viva: %s" % str(c0.get("_active_clip")))


func _andando(tipo: String) -> void:
	var c: Object = _mejor_para("andando")
	if c == null:
		print("[MixVista] nadie andando (vista %s)" % tipo)
		return
	_preparar(c)
	var p: Vector3 = c.global_position
	var ry: float = c.rotation.y
	if tipo == "frente":
		_cam.global_position = p + Vector3(sin(ry), 0.0, cos(ry)) * 3.4 + Vector3.UP * 1.5
	else:
		var lado := Vector3(sin(ry), 0.0, cos(ry)).cross(Vector3.UP).normalized()
		_cam.global_position = p + lado * 3.4 + Vector3.UP * 1.4
	_cam.look_at(p + Vector3.UP * 0.95)
	print("[MixVista] andando (%s): %s modelo %s vel %.2f | brazos: %s" % [tipo, _objetivo.name,
			String(c.model_scene.resource_path).get_file(), c.velocidad_real(), _brazos(c)])


func _quieto() -> void:
	var c: Object = _mejor_para("quieto")
	if c == null:
		return
	_preparar(c)
	var ry: float = c.rotation.y
	_cam.global_position = c.global_position + Vector3(sin(ry), 0.0, cos(ry)) * 3.2 + Vector3.UP * 1.5
	_cam.look_at(c.global_position + Vector3.UP * 1.0)
	print("[MixVista] quieto: %s modelo %s | brazos: %s" % [c.name,
			String(c.model_scene.resource_path).get_file(), _brazos(c)])


## Captura desde el FRENTE del banco (espacio mundo, no del NPC) y desde su LADO.
func _sentado(tipo: String) -> bool:
	var c: Object = null
	for p in _dir.peatones:
		if p.en_postura() and p.fase_postura() == "reposar" and p.postura_actual() == "sentarse":
			c = p
			break
	if c == null:
		print("[MixVista] nadie sentado todavía")
		return false
	_preparar(c)
	var asiento: Dictionary = _dir._asientos[int(c.get("_postura_ref"))] if int(c.get("_postura_ref")) >= 0 else {}
	var punto: Vector3 = asiento.get("pos", c.global_position)
	var giro := _giro_banco(punto)
	var frente := Basis(Vector3.UP, giro) * Vector3(0.0, 0.0, -1.0)
	var lado := frente.cross(Vector3.UP).normalized()
	if tipo == "frente":
		_cam.global_position = punto + frente * 3.3 + Vector3.UP * 1.6
	else:
		_cam.global_position = punto + lado * 3.0 + Vector3.UP * 1.25
	_cam.look_at(punto + Vector3.UP * 0.8)
	var yaw_c := (c as Node3D).rotation.y
	var deseado := float(c.get("_postura_yaw"))
	print("[MixVista] SENTADO (%s): %s modelo %s | yaw %.1f° deseado %.1f° → error %.1f° | brazos %s" % [
			tipo, c.name, String(c.model_scene.resource_path).get_file(), rad_to_deg(yaw_c),
			rad_to_deg(deseado), rad_to_deg(absf(wrapf(yaw_c - deseado, -PI, PI))), _brazos(c)])
	return true


## Captura de la reposera: desde el costado del cuerpo y desde el extremo de la cabeza.
func _tumbado(tipo: String) -> bool:
	var c: Object = null
	for p in _dir.peatones:
		if p.en_postura() and p.fase_postura() == "reposar" and p.postura_actual() == "recostarse":
			c = p
			break
	if c == null:
		print("[MixVista] nadie tumbado todavía")
		return false
	_preparar(c)
	var ref := int(c.get("_postura_ref"))
	var lug: Dictionary = _dir._reposeras[ref] if ref >= 0 and ref < _dir._reposeras.size() else {}
	var base: Vector3 = lug.get("pos", c.global_position)
	var yaw := float(lug.get("yaw", 0.0))
	var eje := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 1.0)     # eje largo de la reposera
	var lado := eje.cross(Vector3.UP).normalized()
	if tipo == "lado":
		_cam.global_position = base + lado * 3.2 + Vector3.UP * 1.7
		_cam.look_at(base + Vector3.UP * 0.35)
	else:
		_cam.global_position = base - eje * 3.0 + Vector3.UP * 1.5
		_cam.look_at(base + Vector3.UP * 0.3)
	var yaw_c := (c as Node3D).rotation.y
	var deseado := float(c.get("_postura_yaw"))
	var m := _huesos(c)
	var eje_cuerpo := Vector3(m["cabeza"].x - m["pies"].x, 0.0, m["cabeza"].z - m["pies"].z).normalized()
	print("[MixVista] TUMBADO (%s): %s modelo %s | yaw %.1f° deseado %.1f° error %.1f° | cuerpo vs reposera %.1f° (0/180 = alineado)" % [
			tipo, c.name, String(c.model_scene.resource_path).get_file(), rad_to_deg(yaw_c),
			rad_to_deg(deseado), rad_to_deg(absf(wrapf(yaw_c - deseado, -PI, PI))),
			rad_to_deg(absf(eje_cuerpo.angle_to(eje)))])
	print("      alturas: cadera %.2f cabeza %.2f tobillo %.2f | reposera y %.2f" % [
			m["cadera"].y, m["cabeza"].y, m["pies"].y, base.y])
	return true


func _mejor_para(que: String) -> Object:
	for c in _dir.peatones:
		if que == "andando" and c.is_walking() and c.velocidad_real() > 0.5:
			return c
		if que == "quieto" and not c.en_postura() and c.state == NPCCitizen.State.IDLE:
			return c
	return null


## Ángulo (grados) del brazo izquierdo respecto a la vertical: 0 = colgando, 90 = en cruz.
func _brazos(c: Object) -> String:
	var out: Array[String] = []
	for par: String in ["Left", "Right"]:
		var d: Variant = _brazo_dir(c, par)
		if d == null:
			out.append("%s n/d" % par)
			continue
		out.append("%s %5.1f°" % [par, rad_to_deg((d as Vector3).angle_to(Vector3.DOWN))])
	return str(out)


func _brazo_dir(c: Object, lado: String) -> Variant:
	var sk: Skeleton3D = c.find_child("Skeleton3D", true, false)
	if sk == null:
		return null
	var i_a := _hueso(sk, ["mixamorig_%sArm" % lado, "%sArm" % lado])
	var i_b := _hueso(sk, ["mixamorig_%sForeArm" % lado, "%sForeArm" % lado])
	if i_a < 0 or i_b < 0:
		return null
	var xf := sk.global_transform
	var a := xf * sk.get_bone_global_pose(i_a).origin
	var b := xf * sk.get_bone_global_pose(i_b).origin
	return (b - a).normalized()


func _huesos(c: Object) -> Dictionary:
	var sk: Skeleton3D = c.find_child("Skeleton3D", true, false)
	var out := {"cadera": Vector3.ZERO, "cabeza": Vector3.ZERO, "pies": Vector3.ZERO}
	if sk == null:
		return out
	var xf := sk.global_transform
	var i_cad := _hueso(sk, ["mixamorig_Hips", "Hips"])
	var i_cab := _hueso(sk, ["mixamorig_Head", "Head"])
	var i_ded := _hueso(sk, ["mixamorig_LeftToeBase", "LeftToeBase"])
	out["cadera"] = xf * sk.get_bone_global_pose(i_cad).origin if i_cad >= 0 else Vector3.ZERO
	out["cabeza"] = xf * sk.get_bone_global_pose(i_cab).origin if i_cab >= 0 else Vector3.ZERO
	out["pies"] = xf * sk.get_bone_global_pose(i_ded).origin if i_ded >= 0 else Vector3.ZERO
	return out


func _hueso(sk: Skeleton3D, candidatos: Array) -> int:
	for c: String in candidatos:
		var i := sk.find_bone(c)
		if i >= 0:
			return i
	return -1


func _giro_banco(p: Vector3) -> float:
	var mejor := 9999.0
	var giro := 0.0
	for n in _ciudad.find_children("Banco*", "StaticBody3D", true, false):
		var d := (n as Node3D).global_position.distance_to(p)
		if d < mejor:
			mejor = d
			giro = (n as Node3D).rotation.y
	return giro


func _preparar(c: Object) -> void:
	_objetivo = c as Node
	c.set_activity(NPCCitizen.Activity.NEAR)


func _capturar(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [DIR_CAP, nombre])
	print("[MixVista] captura %s -> %s" % [nombre, "OK" if err == OK else str(err)])