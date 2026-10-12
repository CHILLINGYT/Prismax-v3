extends Node
## Sonda temporal: comprueba EN EL JUEGO REAL, con la librería nueva, lo que el usuario reportó:
##   1. al caminar, ¿el cuerpo mira hacia donde se desplaza? (dirección de avance vs frente del
##      cuerpo y de los pies, por modelo)
##   2. al sentarse, ¿la pelvis queda sobre el tablón del banco y el cuerpo mirando al frente del
##      banco?
##   3. al tumbarse, ¿el cuerpo apoya sobre la lona de la reposera y queda alineado con su eje?
## No toca nada: sólo mide e informa.

const SEMILLA := 20260707
const ALTO_ASIENTO := 0.465     # world/bancos.gd
const ALTO_RESBALDO := 0.89

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null


func _ready() -> void:
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = SEMILLA
	add_child(_juego)
	Engine.time_scale = 3.0
	_run.call_deferred()


func _run() -> void:
	while _dir == null:
		await get_tree().process_frame
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
	print("[Dir] ciudad lista")
	await get_tree().create_timer(6.0).timeout
	_caminando()
	await _esperar_posturas()
	_sentados()
	_tumbados()
	print("[Dir] fin")
	get_tree().quit()


## Espera (con el reloj acelerado) a que haya a la vez alguien sentado y alguien tumbado.
func _esperar_posturas() -> void:
	var t0 := Time.get_ticks_msec()
	Engine.time_scale = 4.0
	while float(Time.get_ticks_msec() - t0) < 45000.0:
		await get_tree().create_timer(0.5).timeout
		var sen := 0
		var tum := 0
		for c in _dir.peatones:
			if c.en_postura() and c.fase_postura() == "reposar":
				if c.postura_actual() == "sentarse":
					sen += 1
				else:
					tum += 1
		if sen > 0 and tum > 0:
			print("  hay %d sentados y %d tumbados" % [sen, tum])
			break
	Engine.time_scale = 1.0
	await get_tree().create_timer(1.0).timeout


# ---------------------------------------------------------------- 1. caminar
func _caminando() -> void:
	print("")
	print("================ CAMINANDO (frente del cuerpo vs dirección real de avance) ================")
	var por_modelo: Dictionary = {}
	var esperados: Array = []
	# Primera pasada: se eligen ciudadanos que estén andando en línea recta.
	for c in _dir.peatones:
		if not c.is_walking() or c.velocidad_real() < 0.7:
			continue
		var m := String(c.model_scene.resource_path).get_file() if c.model_scene != null else "?"
		if por_modelo.has(m) and por_modelo[m] >= 2:
			continue
		por_modelo[m] = int(por_modelo.get(m, 0)) + 1
		esperados.append(c)
	var muestras: Dictionary = {}
	for c in esperados:
		muestras[c] = []
	for k in 5:
		for c in esperados:
			if is_instance_valid(c):
				muestras[c].append((c as Node3D).global_position)
		await get_tree().create_timer(0.16).timeout
	for c in esperados:
		if not is_instance_valid(c):
			continue
		var pts: Array = muestras[c]
		if pts.size() < 3:
			continue
		var avance: Vector3 = (pts[-1] as Vector3) - (pts[1] as Vector3)
		avance.y = 0.0
		if avance.length() < 0.15:
			continue
		avance = avance.normalized()
		var m := _medir(c)
		var modelo := String(c.model_scene.resource_path).get_file() if c.model_scene != null else "?"
		print("  %-18s %s" % [modelo, m])
		print("      avance %+6.1f°  cuerpo %+6.1f° (diferencia %5.1f°)  pies %+6.1f° (diferencia %5.1f°)  yaw nodo %+6.1f° face_yaw %+5.1f°" % [
				rad_to_deg(atan2(avance.x, avance.z)),
				rad_to_deg(atan2(m["cuerpo"].x, m["cuerpo"].z)),
				rad_to_deg(absf(avance.angle_to(m["cuerpo"]))),
				rad_to_deg(atan2(m["pies"].x, m["pies"].z)),
				rad_to_deg(absf(avance.angle_to(m["pies"]))),
				rad_to_deg((c as Node3D).rotation.y), rad_to_deg(float(c.get("_face_yaw")))])


## Frente del cuerpo (eje entre caderas), de los pies (dedos − tobillo) y de los hombros.
func _medir(c: Object) -> Dictionary:
	var sk: Skeleton3D = c.find_child("Skeleton3D", true, false)
	var out := {"cuerpo": Vector3.FORWARD, "pies": Vector3.FORWARD, "hombros": Vector3.FORWARD}
	if sk == null:
		return out
	var xf := sk.global_transform
	out["cuerpo"] = _frente(xf, sk, "mixamorig_LeftUpLeg", "mixamorig_RightUpLeg")
	out["hombros"] = _frente(xf, sk, "mixamorig_LeftArm", "mixamorig_RightArm")
	var izq := _p(xf, sk, "mixamorig_LeftToeBase")
	var der := _p(xf, sk, "mixamorig_RightToeBase")
	var direccion := izq - _p(xf, sk, "mixamorig_LeftFoot") + der - _p(xf, sk, "mixamorig_RightFoot")
	direccion.y = 0.0
	if direccion.length_squared() > 0.000001:
		out["pies"] = direccion.normalized()
	return out


func _frente(xf: Transform3D, sk: Skeleton3D, a: String, b: String) -> Vector3:
	var v := _p(xf, sk, a) - _p(xf, sk, b)
	v.y = 0.0
	if v.length_squared() < 0.000001:
		return Vector3.FORWARD
	return v.normalized().cross(Vector3.UP)


func _p(xf: Transform3D, sk: Skeleton3D, h: String) -> Vector3:
	var i := sk.find_bone(h)
	return (xf * sk.get_bone_global_pose(i).origin) if i >= 0 else Vector3.ZERO


# ---------------------------------------------------------------- 2. sentados
func _sentados() -> void:
	print("")
	print("================ SENTADOS (pelvis vs tablón del banco) ================")
	var n := 0
	for c in _dir.peatones:
		if not (c.en_postura() and c.fase_postura() == "reposar" and c.postura_actual() == "sentarse"):
			continue
		var ref := int(c.get("_postura_ref"))
		if ref < 0 or ref >= _dir._asientos.size():
			continue
		var asiento: Dictionary = _dir._asientos[ref]
		var ancla: Vector3 = asiento["pos"]
		var superficie := ancla.y + 0.045 + ALTO_ASIENTO      # base del banco + altura del asiento
		var m := _medir(c)
		var cadera := _p((c as Node3D).get_node("Model").find_child("Skeleton3D", true, false).global_transform,
				(c as Node3D).get_node("Model").find_child("Skeleton3D", true, false), "mixamorig_Hips")
		var giro := 0.0
		for bb in _ciudad.find_children("Banco*", "StaticBody3D", true, false):
			if (bb as Node3D).global_position.distance_to(ancla) < 2.0:
				giro = (bb as Node3D).rotation.y
				break
		var frente_banco: Vector3 = Basis(Vector3.UP, giro) * Vector3(0, 0, -1)
		print("  %-18s cadera y %+.3f | superficie del asiento %+.3f → pelvis %+.3f sobre la tabla | frente del cuerpo vs frente del banco %.1f°" % [
				String(c.model_scene.resource_path).get_file(), cadera.y, superficie,
				cadera.y - superficie, rad_to_deg(absf(frente_banco.angle_to(m["cuerpo"])))])
		n += 1
	if n == 0:
		print("  (nadie sentado todavía)")


# ---------------------------------------------------------------- 3. tumbados
func _tumbados() -> void:
	print("")
	print("================ TUMBADOS (cuerpo vs lona de la reposera) ================")
	var n := 0
	for c in _dir.peatones:
		if not (c.en_postura() and c.fase_postura() == "reposar" and c.postura_actual() == "recostarse"):
			continue
		var ref := int(c.get("_postura_ref"))
		if ref < 0 or ref >= _dir._reposeras.size():
			continue
		var lug: Dictionary = _dir._reposeras[ref]     # "pos" = fin (ancla), no el origen de la malla
		var yaw := float(lug["yaw"])
		var base := Basis(Vector3.UP, yaw)
		var origen_malla: Vector3 = (lug["pos"] as Vector3) - base * Vector3(0.0, 0.377, 0.119)
		var sk: Skeleton3D = c.find_child("Skeleton3D", true, false)
		var xf := sk.global_transform
		var inv := Basis(Vector3.UP, -yaw)
		var cadera := inv * (_p(xf, sk, "mixamorig_Hips") - origen_malla)
		var cabeza := inv * (_p(xf, sk, "mixamorig_Head") - origen_malla)
		var pies := inv * (_p(xf, sk, "mixamorig_LeftToeBase") - origen_malla)
		var eje_cuerpo := (cabeza - pies)
		eje_cuerpo.y = 0.0
		print("  %-18s cadera(y %+.3f z %+.3f) cabeza(y %+.3f z %+.3f) pies(y %+.3f z %+.3f)" % [
				String(c.model_scene.resource_path).get_file(), cadera.y, cadera.z,
				cabeza.y, cabeza.z, pies.y, pies.z])
		print("      lecho: lona llana y=0,363 de z −0,05 a +1,02 · cabezal sube en −Z | cuerpo vs eje de la reposera %.1f°" % [
				rad_to_deg(absf(eje_cuerpo.normalized().angle_to(Vector3(0, 0, -1))))])
		n += 1
	if n == 0:
		print("  (nadie tumbado todavía)")