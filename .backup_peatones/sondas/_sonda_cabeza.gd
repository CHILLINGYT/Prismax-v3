extends Node3D
## Sonda de CABEZA/TORSO en juego (temporal): mide, para cada ciudadano vivo, cuánto tiene
## girada la cabeza respecto al pecho, primero con el modificador de mirada activo y después
## con él apagado. Separa dos causas muy distintas:
##   - giro que SIGUE con la mirada apagada  -> viene del clip horneado (animación).
##   - giro que DESAPARECE al apagarla        -> es la mirada al jugador (NPCLookAt).

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null
var _t0 := 0
var _paso := 0
var _proxima := 0.0


func _ready() -> void:
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = 20260707
	add_child(_juego)
	_t0 = Time.get_ticks_msec()
	Engine.time_scale = 6.0
	print("[SondaCabeza] cargada")


func _process(_d: float) -> void:
	if _dir == null:
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
		if _dir == null:
			return
	var real := float(Time.get_ticks_msec() - _t0) / 1000.0
	match _paso:
		0:
			if real > 9.0:
				Engine.time_scale = 1.0
				_paso = 1
				_medir("CON MIRADA", true)
				_paso = 2
				_proxima = real + 0.4
		2:
			if real >= _proxima:
				for c in _dir.peatones:
					var look: Object = c.get_node_or_null("LookAt")
					if look != null:
						look.active = false
					c.set("_watch", 0.0)
				_paso = 3
				_proxima = real + 0.4
		3:
			if real >= _proxima:
				_medir("SIN MIRADA", false)
				_aislar()
				_paso = 4
				_proxima = real + 0.4
		4:
			if real > _proxima + 0.3:
				print("[SondaCabeza] fin")
				get_tree().quit()


## Para los ciudadanos con la cabeza girada: congela su pose y mide qué pasa al devolver a su
## reposo, primero el hueso de la cabeza y después el del cuello. Eso dice de dónde viene el giro.
func _aislar() -> void:
	print("[SondaCabeza] --- aislando el hueso culpable ---")
	for c in _dir.peatones:
		var sk: Skeleton3D = c.find_child("Skeleton3D", true, false) as Skeleton3D
		if sk == null:
			continue
		var m0 := _angulos(sk)
		if m0["vacio"] or absf(m0["cara"]) <= 20.0:
			continue
		var arboles: Array = c.find_children("*", "AnimationTree", true, false)
		if arboles.is_empty():
			continue
		var arbol: AnimationTree = arboles[0]
		arbol.active = false                     # se congela la pose del fotograma
		var i_cab := _hueso(sk, ["mixamorig_Head", "head.x", "B_Head"])
		var i_cuello := _hueso(sk, ["mixamorig_Neck", "neck.x", "B_Neck"])
		var q_cab := sk.get_bone_pose_rotation(i_cab)
		var q_cuello := sk.get_bone_pose_rotation(i_cuello) if i_cuello >= 0 else Quaternion.IDENTITY
		sk.set_bone_pose_rotation(i_cab, Quaternion.IDENTITY)
		var m1 := _angulos(sk)                   # sólo con la cabeza a reposo
		if i_cuello >= 0:
			sk.set_bone_pose_rotation(i_cuello, Quaternion.IDENTITY)
		var m2 := _angulos(sk)                   # cabeza y cuello a reposo
		sk.set_bone_pose_rotation(i_cab, q_cab)
		if i_cuello >= 0:
			sk.set_bone_pose_rotation(i_cuello, q_cuello)
		arbol.active = true
		print("  %-22s clip=%-9s actual %6.1f° | cabeza a reposo %6.1f° (+cuello a reposo %6.1f°) | reposo crudo del modelo: cara %6.1f°" % [
				c.name, String(c.get("_active_clip")), m0["cara"], m1["cara"], m2["cara"],
				_reposo(sk)])


func _medir(etiqueta: String, informar_todos: bool) -> void:
	var torcidos := 0
	var n := 0
	var peor := 0.0
	var lineas: Array[String] = []
	for c in _dir.peatones:
		var sk: Skeleton3D = c.find_child("Skeleton3D", true, false) as Skeleton3D
		if sk == null:
			continue
		var m := _angulos(sk)
		if m["vacio"]:
			continue
		n += 1
		var yaw: float = m["cara"]
		if absf(yaw) > 20.0:
			torcidos += 1
		peor = maxf(peor, absf(yaw))
		if informar_todos and (absf(yaw) > 20.0 or absf(m["espalda"]) > 20.0):
			var watch: float = c.get("_watch")
			lineas.append("  %-22s est=%d %-9s mirando=%.2f | cabeza %6.1f° (espalda %4.1f°) %s" % [
					c.name, int(c.state), m["estado"], watch, yaw, m["espalda"],
					"clip=" + String(c.get("_active_clip"))])
	print("[SondaCabeza] %s: %d ciudadanos | con cabeza >20° = %d | peor = %.1f°" % [
			etiqueta, n, torcidos, peor])
	for l in lineas:
		print(l)


## Ángulos (grados) de la pose actual: cara de la cabeza respecto al pecho, y espalda vs vertical.
func _angulos(sk: Skeleton3D) -> Dictionary:
	var out := {"cara": 0.0, "espalda": 0.0, "estado": "-", "vacio": true}
	var i_cab := _hueso(sk, ["mixamorig_Head", "head.x", "B_Head"])
	var i_izq := _hueso(sk, ["mixamorig_LeftArm", "arm_stretch.l", "B_L_UpperArm"])
	var i_der := _hueso(sk, ["mixamorig_RightArm", "arm_stretch.r", "B_R_UpperArm"])
	var i_cad := _hueso(sk, ["mixamorig_Hips", "root.x", "B_Pelvis"])
	if i_cab < 0 or i_izq < 0 or i_der < 0 or i_cad < 0:
		return out
	var arriba := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var cab := sk.get_bone_global_pose(i_cab).origin
	var cad := sk.get_bone_global_pose(i_cad).origin
	var izq := sk.get_bone_global_pose(i_izq).origin
	var der := sk.get_bone_global_pose(i_der).origin
	# Pecho: de hombro derecho a izquierdo, girado 90° respecto a "arriba" = hacia donde da el pecho.
	var hombros := (izq - der)
	hombros -= arriba * hombros.dot(arriba)
	if hombros.length_squared() < 0.000001:
		return out
	hombros = hombros.normalized()
	var pecho := hombros.cross(arriba).normalized()
	# Cara de la cabeza: el eje local que más apunta "hacia delante" (el +X en los rigs Mixamo).
	var cb: Basis = sk.get_bone_global_pose(i_cab).basis
	var cara := Vector3.ZERO
	var mejor := -2.0
	for eje: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var d := (cb * eje).normalized()
		var plano := d - arriba * d.dot(arriba)
		if plano.length_squared() < 0.000001:
			continue
		var val := plano.normalized().dot(pecho)
		if val > mejor:
			mejor = val
			cara = plano.normalized()
	out["cara"] = rad_to_deg(pecho.signed_angle_to(cara, arriba))
	out["espalda"] = rad_to_deg((cab - cad).normalized().angle_to(arriba))
	out["vacio"] = false
	return out


func _hueso(sk: Skeleton3D, candidatos: Array) -> int:
	for c: String in candidatos:
		var i := sk.find_bone(c)
		if i >= 0:
			return i
	return -1


## Giro de la cara respecto al pecho EN REPOSO (sin animación): la "postura base" del modelo.
func _reposo(sk: Skeleton3D) -> float:
	var i_cab := _hueso(sk, ["mixamorig_Head", "head.x", "B_Head"])
	var i_izq := _hueso(sk, ["mixamorig_LeftArm", "arm_stretch.l", "B_L_UpperArm"])
	var i_der := _hueso(sk, ["mixamorig_RightArm", "arm_stretch.r", "B_R_UpperArm"])
	if i_cab < 0 or i_izq < 0 or i_der < 0:
		return 0.0
	var arriba := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var hombros := sk.get_bone_global_rest(i_izq).origin - sk.get_bone_global_rest(i_der).origin
	hombros -= arriba * hombros.dot(arriba)
	if hombros.length_squared() < 0.000001:
		return 0.0
	var pecho := hombros.normalized().cross(arriba).normalized()
	var cb: Basis = sk.get_bone_global_rest(i_cab).basis
	var cara := Vector3.ZERO
	var mejor := -2.0
	for eje: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var d := (cb * eje).normalized()
		var plano := d - arriba * d.dot(arriba)
		if plano.length_squared() < 0.000001:
			continue
		var val := plano.normalized().dot(pecho)
		if val > mejor:
			mejor = val
			cara = plano.normalized()
	return rad_to_deg(pecho.signed_angle_to(cara, arriba))