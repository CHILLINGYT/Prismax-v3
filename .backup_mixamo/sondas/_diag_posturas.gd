extends Node
## Diagnóstico de POSTURAS (temporal, no forma parte del juego).
##
## Mide en el juego real, con huesos y transformadas:
##   - hacia dónde mira de verdad el cuerpo de quien está SENTADO (dirección de los pies),
##   - hacia dónde debería mirar (el frente del banco: el banco mira a −Z local),
##   - el yaw que el ciudadano tiene puesto y el que le puso el director,
##   - lo mismo para quien está TUMBADO: eje del cuerpo (cabeza→pies) frente al eje de la reposera.
## Separa dos causas distintas: yaw mal aplicado al ciudadano (error del sistema) y pose del clip
## girada respecto a ese yaw (error de la animación/horneado).

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null
var _gen: Node = null


func _ready() -> void:
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_gen = _ciudad
	_ciudad.semilla = 20260707
	add_child(_juego)
	Engine.time_scale = 6.0
	print("[DiagPos] cargando...")
	_run.call_deferred()


func _run() -> void:
	while _dir == null:
		await get_tree().process_frame
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) < 40000.0:
		await get_tree().process_frame
		if _cuantos("sentarse") > 0 and _cuantos("recostarse") > 0:
			break
	print("[DiagPos] sentados ahora: %d | tumbados: %d" % [_cuantos("sentarse"), _cuantos("recostarse")])
	_sentados()
	_tumbados()
	print("[DiagPos] fin")
	get_tree().quit()


func _cuantos(postura: String) -> int:
	var n := 0
	for c in _dir.peatones:
		if c.en_postura() and c.fase_postura() == "reposar" and c.postura_actual() == postura:
			n += 1
	return n


func _sentados() -> void:
	print("[DiagPos] ---------------- SENTADOS ----------------")
	var n := 0
	for c in _dir.peatones:
		if not (c.en_postura() and c.fase_postura() == "reposar" and c.postura_actual() == "sentarse"):
			continue
		if n >= 4:
			break
		n += 1
		var ref := int(c.get("_postura_ref"))
		var asiento: Dictionary = _dir._asientos[ref] if ref >= 0 and ref < _dir._asientos.size() else {}
		var giro_banco := _giro_del_banco(asiento.get("pos", Vector3.ZERO))
		var frente_banco := Basis(Vector3.UP, giro_banco) * Vector3(0.0, 0.0, -1.0)
		var yaw_ciudadano := (c as Node3D).rotation.y
		var fwd_ciudadano := Basis(Vector3.UP, yaw_ciudadano) * Vector3(0.0, 0.0, 1.0)
		var m := _cuerpo(c)
		print(c.name)
		print("   yaw ciudadano %.1f° (face_yaw %.1f°, postura_yaw %.1f°) | asiento ref %d en %s yaw %.1f°" % [
				rad_to_deg(yaw_ciudadano), rad_to_deg(float(c.get("_face_yaw"))),
				rad_to_deg(float(c.get("_postura_yaw"))), ref, str(asiento.get("pos", Vector3.ZERO)),
				rad_to_deg(float(asiento.get("yaw", 0.0)))])
		print("   banco: giro %.1f° (frente %s) | asiento a %s del banco" % [
				rad_to_deg(giro_banco), str(frente_banco),
				str((asiento.get("pos", Vector3.ZERO) - _pos_banco(asiento.get("pos", Vector3.ZERO))))])
		print("   pies del ciudadano (dirección %s) → ángulo con el frente del banco %.1f°" % [
				str(m["pies"]), rad_to_deg(fwd_ciudadano.signed_angle_to(frente_banco, Vector3.UP))])
		print("   cuerpo: dirección de los pies %s vs frente %s → error de POSE %.1f°" % [
				str(m["pies"]), str(frente_banco),
				rad_to_deg(_aplanar(m["pies"]).signed_angle_to(frente_banco, Vector3.UP))])
		print("   cadera %s | cabeza %s | tobillo %s | dedo %s" % [
				str(m["cadera"]), str(m["cabeza"]), str(m["tobillo"]), str(m["dedo"])])


func _tumbados() -> void:
	print("[DiagPos] ---------------- TUMBADOS ----------------")
	var n := 0
	for c in _dir.peatones:
		if not (c.en_postura() and c.fase_postura() == "reposar" and c.postura_actual() == "recostarse"):
			continue
		if n >= 4:
			break
		n += 1
		var ref := int(c.get("_postura_ref"))
		var lug: Dictionary = _dir._reposeras[ref] if ref >= 0 and ref < _dir._reposeras.size() else {}
		var m := _cuerpo(c)
		var eje_cuerpo := _aplanar(m["cabeza"] - m["pies"])
		var yaw_lug := float(lug.get("yaw", 0.0))
		var eje_lug := _aplanar(Basis(Vector3.UP, yaw_lug) * Vector3(0.0, 0.0, 1.0))
		print(c.name)
		print("   fase=%s t=%.2f dur_entrar=%.2f espera=%.1f" % [String(c.get("_postura_fase")),
				float(c.get("_postura_t")), float(c.get("_dur_entrar")), float(c.get("_postura_espera"))])
		print("   nodo en %s" % str((c as Node3D).global_position))
		print("   _postura_punto    %s" % str(c.get("_postura_punto")))
		print("   _postura_punto_ini %s" % str(c.get("_postura_punto_ini")))
		print("   yaw ciudadano %.1f° | reposera ref %d yaw %.1f° | pos de la reposera %s" % [
				rad_to_deg((c as Node3D).rotation.y), ref, rad_to_deg(yaw_lug), str(lug.get("pos", Vector3.ZERO))])
		print("   eje del cuerpo (cabeza→pies) %s vs eje de la reposera %s → %.1f° (0/180 = alineado)" % [
				str(eje_cuerpo), str(eje_lug), rad_to_deg(absf(eje_cuerpo.angle_to(eje_lug)))])
		print("   cadera %s | cabeza %s | tobillo %s" % [str(m["cadera"]), str(m["cabeza"]), str(m["tobillo"])])


## Frente/giro real del banco más cercano a un punto, leyendo la transformada del nodo "Banco".
func _giro_del_banco(p: Vector3) -> float:
	var mejor := 9999.0
	var giro := 0.0
	for n in _ciudad.find_children("Banco*", "StaticBody3D", true, false):
		var d := (n as Node3D).global_position.distance_to(p)
		if d < mejor:
			mejor = d
			giro = (n as Node3D).rotation.y
	print("      [banco más cercano a %.1f m]" % mejor)
	return giro


func _pos_banco(p: Vector3) -> Vector3:
	var mejor := 9999.0
	var pos := p
	for n in _ciudad.find_children("Banco*", "StaticBody3D", true, false):
		var d := (n as Node3D).global_position.distance_to(p)
		if d < mejor:
			mejor = d
			pos = (n as Node3D).global_position
	return pos


## Posiciones world de los huesos clave y la dirección de los pies.
func _cuerpo(c: Object) -> Dictionary:
	var sk: Skeleton3D = c.find_child("Skeleton3D", true, false)
	var out := {"cadera": Vector3.ZERO, "cabeza": Vector3.ZERO, "tobillo": Vector3.ZERO,
			"dedo": Vector3.ZERO, "pies": Vector3.FORWARD}
	if sk == null:
		return out
	var i_cad := _hueso(sk, ["mixamorig_Hips", "root.x", "B_Pelvis"])
	var i_cab := _hueso(sk, ["mixamorig_Head", "head.x", "B_Head"])
	var i_tob := _hueso(sk, ["mixamorig_LeftFoot", "foot.l", "B_L_Foot"])
	var i_ded := _hueso(sk, ["mixamorig_LeftToeBase", "toes_01.l", "B_L_Toe0"])
	var xf := sk.global_transform
	var a := func(i: int) -> Vector3: return xf * sk.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO
	out["cadera"] = a.call(i_cad)
	out["cabeza"] = a.call(i_cab)
	out["tobillo"] = a.call(i_tob)
	out["dedo"] = a.call(i_ded)
	var pies := _aplanar(out["dedo"] - out["tobillo"])
	out["pies"] = pies if pies.length_squared() > 0.0001 else Vector3.FORWARD
	return out


func _aplanar(v: Vector3) -> Vector3:
	var r := Vector3(v.x, 0.0, v.z)
	return r.normalized() if r.length_squared() > 0.000001 else Vector3.ZERO


func _hueso(sk: Skeleton3D, candidatos: Array) -> int:
	for c: String in candidatos:
		var i := sk.find_bone(c)
		if i >= 0:
			return i
	return -1