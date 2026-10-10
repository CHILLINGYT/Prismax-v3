extends SceneTree

# ============================================================================
#  HORNEADO de los clips de la roca (RockLift / RockCarry / RockCarryWalk /
#  RockThrow) en la librería viva.
#
#  Ejecutar EN HEADLESS (extends SceneTree; se puede pegar en la herramienta de
#  scripts de Ziva tal cual). Es idempotente: siempre parte de la fuente
#  original respaldada, así que se puede repetir sin miedo.
#
#  IMPORTANTE: las constantes de abajo y las del controlador
#  (res://personaje/base/scripts/controlador_leo.gd, bloque F_ROCA_* y las
#  funciones _centro_roca_sk / _peso_ik_roca) DEBEN llevar los mismos números:
#  el horneado y el IK en tiempo real convierten los mismos valores a poses.
# ============================================================================
const RUTA_FUENTE := "res://personaje/transformaciones/fuerza/.backup_anim_piedra/FuerzaUniversal_original.tres"
const RUTA_DESTINO := "res://personaje/transformaciones/fuerza/animations (1)/libraries/FuerzaUniversal.tres"
const RUTA_FBX := "res://personaje/transformaciones/fuerza/model (1)/tripo_convert_69413d1d-9e71-458a-9b8b-ac8ba6650d4c (1).fbx"

const R_SK := 0.404          # radio de la roca en espacio del esqueleto
const Z0 := 0.62             # adelante (sk) donde nace/apoya la roca
const DUR_LIFT := 2.0
const DUR_CARRY := 1.2
const DUR_THROW := 0.62
const THROW_MEZCLA := 0.12   # tramo inicial del tiro mezclado desde la pose de carga
const U_LEAN_INICIo := 0.08
const U_SQUAT := 0.42
const U_GRAB_FIN := 0.46
const U_ESTIRON_INI := 0.46
const U_ESTIRON_FIN := 0.52
const U_RISE_FIN := 0.90
const B_CARRY := 0.10
const L_CARRY := -0.05
const B_GRAB := 1.05
const L_GRAB := 0.20
const PIERNA_WALK := ["mixamorig_Hips", "mixamorig_LeftUpLeg", "mixamorig_LeftLeg",
	"mixamorig_LeftFoot", "mixamorig_LeftToeBase", "mixamorig_RightUpLeg",
	"mixamorig_RightLeg", "mixamorig_RightFoot", "mixamorig_RightToeBase"]

var sk: Skeleton3D
var ik: FuerzaBrazosIK
var pistas: Array = []           # [tipo, nombre_hueso, idx] de las 23 pistas
var p_idle: Dictionary
var p_crouch: Dictionary

func _init() -> void:
	_bake.call_deferred()

func _bake() -> void:
	var fbx: PackedScene = load(RUTA_FBX)
	var raiz := Node3D.new(); raiz.name = "Raiz"; root.add_child(raiz)
	var modelo := Node3D.new(); modelo.name = "Model"; raiz.add_child(modelo)
	var cm := Node3D.new(); cm.name = "CharacterModel"; modelo.add_child(cm)
	var inst: Node3D = fbx.instantiate(); inst.name = "FuerzaModel"; cm.add_child(inst)
	await process_frame
	sk = _buscar_sk(inst)
	if sk == null:
		print("FALLO: sin esqueleto"); quit(); return
	for i in sk.get_bone_count():
		sk.reset_bone_pose(i)

	var lib: AnimationLibrary = load(RUTA_FUENTE)
	if lib == null:
		print("FALLO: no carga la librería fuente"); quit(); return

	ik = FuerzaBrazosIK.new()
	var tl := Node3D.new(); tl.name = "LeftHandTarget"; ik.add_child(tl)
	var tr := Node3D.new(); tr.name = "RightHandTarget"; ik.add_child(tr)
	ik.polo_salida = 2.2
	ik.polo_abajo = 0.0
	ik.polo_atras = 0.2
	sk.add_child(ik)
	await process_frame

	# Referencia de mano: se mide de la pose original de RockCarry.
	_posar(_evaluar(lib.get_animation("RockCarry"), 0.0))
	ik.resolver(sk, sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftHand")).origin,
		sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand")).origin, Vector3(0, 1.42, 0.02))

	p_idle = _evaluar(lib.get_animation("Idle"), 0.0)
	p_crouch = _crouch_mas_bajo(lib)

	# Pistas: se copian EXACTAMENTE las del clip original RockLift (23).
	var mod: Animation = lib.get_animation("RockLift")
	for i in mod.get_track_count():
		var camino := String(mod.track_get_path(i))
		var hueso := camino.substr(camino.find(":") + 1)
		pistas.append([mod.track_get_type(i), hueso, sk.find_bone(hueso)])

	# --- RockLift (2.0 s) ---
	var lift := _crear_anim(mod, DUR_LIFT, false)
	var n_lift := 60
	for i in n_lift + 1:
		var u := float(i) / float(n_lift)
		_cuerpo_mezcla(p_idle, p_crouch, _b(u), _lam(u))
		_brazos(_path(u, _cabeza_top()), _sigma(u))
		_insertar(lift, u * DUR_LIFT)

	# --- RockCarry (bucle 1.2 s) ---
	var carry := _crear_anim(mod, DUR_CARRY, true)
	var n_carry := 36
	for i in n_carry + 1:
		var u := float(i) / float(n_carry)
		_cuerpo_mezcla(p_idle, p_crouch,
			B_CARRY + 0.012 * sin(u * TAU), L_CARRY + 0.006 * sin(u * TAU + 0.7))
		_brazos(_C1(_cabeza_top()), 1.0)
		_insertar(carry, u * DUR_CARRY)

	# --- RockCarryWalk (bucle, piernas del Walk original) ---
	var walk: Animation = lib.get_animation("Walk")
	var dur_walk: float = walk.length
	var cw_anim := _crear_anim(mod, dur_walk, true)
	var n_walk := maxi(roundi(dur_walk * 30.0), 8)
	var frame0 := _evaluar(walk, 0.0)
	for i in n_walk + 1:
		var t := dur_walk * float(i) / float(n_walk)
		_cuerpo_mezcla(p_idle, p_crouch, B_CARRY, L_CARRY)
		_aplicar_piernas(frame0 if i == n_walk else _evaluar(walk, t))
		var c := _C1(_cabeza_top())
		if i != n_walk:
			c.x += 0.008 * sin(t / dur_walk * TAU)
		_brazos(c, 1.0)
		_insertar(cw_anim, t)

	# --- RockThrow (0.62 s): primeros 0.12 s desde la pose de carga ---
	var thr: Animation = lib.get_animation("RockThrow")
	var throw_n := _crear_anim(mod, DUR_THROW, false)
	_cuerpo_mezcla(p_idle, p_crouch, B_CARRY, L_CARRY)
	_brazos(_C1(_cabeza_top()), 1.0)
	var r_carga := _leer_rotaciones()
	var p_carga := sk.get_bone_pose_position(sk.find_bone("mixamorig_Hips"))
	var n_throw := 18
	for i in n_throw + 1:
		var t := DUR_THROW * float(i) / float(n_throw)
		var pt := _evaluar(thr, t)
		var alfa: float = _smooth(t / THROW_MEZCLA) if t < THROW_MEZCLA else 1.0
		var pose := {"r": {}, "p": p_carga.lerp(pt.p, alfa)}
		for idx: int in pt.r:
			var q_base: Quaternion = r_carga[idx] if r_carga.has(idx) else pt.r[idx]
			pose.r[idx] = pt.r[idx] if alfa >= 1.0 else _ext(q_base, pt.r[idx], alfa)
		_posar(pose)
		_insertar(throw_n, t)

	# --- Guardar ---
	lib.remove_animation("RockLift")
	lib.add_animation("RockLift", lift)
	lib.remove_animation("RockCarry")
	lib.add_animation("RockCarry", carry)
	lib.remove_animation("RockCarryWalk")
	lib.add_animation("RockCarryWalk", cw_anim)
	lib.remove_animation("RockThrow")
	lib.add_animation("RockThrow", throw_n)
	var err := ResourceSaver.save(lib, RUTA_DESTINO)
	print("guardado: ", err, " (0 = OK)")
	quit()

func _buscar_sk(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _buscar_sk(c)
		if r != null: return r
	return null

func _crear_anim(modelo: Animation, dur: float, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = dur
	a.step = 1.0 / 30.0
	if loop:
		a.loop_mode = Animation.LOOP_LINEAR
	for p: Array in pistas:
		var j := a.add_track(p[0] as int)
		a.track_set_path(j, String(modelo.track_get_path(_buscar_track(modelo, p[1] as String))))
		a.track_set_interpolation_type(j, Animation.INTERPOLATION_LINEAR)
	return a

func _buscar_track(modelo: Animation, hueso: String) -> int:
	for i in modelo.get_track_count():
		if String(modelo.track_get_path(i)).ends_with(":" + hueso):
			return i
	return 0

func _insertar(a: Animation, t: float) -> void:
	var p_hips := sk.get_bone_pose_position(sk.find_bone("mixamorig_Hips"))
	for j in a.get_track_count():
		var p: Array = pistas[j]
		if (p[0] as int) == Animation.TYPE_ROTATION_3D:
			a.track_insert_key(j, t, sk.get_bone_pose_rotation(p[2] as int))
		else:
			a.track_insert_key(j, t, p_hips)

func _leer_rotaciones() -> Dictionary:
	var salida: Dictionary = {}
	for i in sk.get_bone_count():
		salida[i] = sk.get_bone_pose_rotation(i)
	return salida

func _evaluar(anim: Animation, t: float) -> Dictionary:
	var pose := {"r": {}, "p": Vector3.ZERO}
	for i in anim.get_track_count():
		var camino := String(anim.track_get_path(i))
		var hueso := camino.substr(camino.find(":") + 1)
		var idx := sk.find_bone(hueso)
		if idx < 0: continue
		var tipo := anim.track_get_type(i)
		var n := anim.track_get_key_count(i)
		if n == 0: continue
		var tN: float = anim.track_get_key_time(i, n - 1)
		var tc: float = clampf(t, anim.track_get_key_time(i, 0), tN)
		var k0 := 0
		for k in n - 1:
			if anim.track_get_key_time(i, k) <= tc:
				k0 = k
		var k1: int = mini(k0 + 1, n - 1)
		var ta: float = anim.track_get_key_time(i, k0)
		var tb: float = anim.track_get_key_time(i, k1)
		var al: float = 0.0 if tb <= ta else clampf((tc - ta) / (tb - ta), 0.0, 1.0)
		if tipo == Animation.TYPE_ROTATION_3D:
			pose.r[idx] = (anim.track_get_key_value(i, k0) as Quaternion).slerp(anim.track_get_key_value(i, k1), al)
		elif tipo == Animation.TYPE_POSITION_3D and hueso == "mixamorig_Hips":
			pose.p = (anim.track_get_key_value(i, k0) as Vector3).lerp(anim.track_get_key_value(i, k1), al)
	return pose

func _crouch_mas_bajo(lib: AnimationLibrary) -> Dictionary:
	var a: Animation = lib.get_animation("Crouch")
	var mejor: Dictionary = {}
	var mejor_y := 999.0
	for i in 31:
		var p := _evaluar(a, a.length * float(i) / 30.0)
		if p.p.y < mejor_y:
			mejor_y = p.p.y
			mejor = p
	return mejor

func _posar(pose: Dictionary) -> void:
	for idx: int in pose.r:
		sk.set_bone_pose_rotation(idx, pose.r[idx])
	sk.set_bone_pose_position(sk.find_bone("mixamorig_Hips"), pose.p)
	sk.force_update_all_bone_transforms()

func _ext(qa: Quaternion, qb: Quaternion, t: float) -> Quaternion:
	var rel: Quaternion = qa.inverse() * qb
	if rel.w < 0.0:
		rel = Quaternion(-rel.x, -rel.y, -rel.z, -rel.w)
	var ang: float = 2.0 * acos(clampf(rel.w, -1.0, 1.0))
	var s: float = sqrt(maxf(1.0 - rel.w * rel.w, 0.0))
	var eje := Vector3(1, 0, 0)
	if s > 0.0001:
		var e2 := Vector3(rel.x, rel.y, rel.z) / s
		if e2.length_squared() > 0.0001:
			eje = e2.normalized()
	return (qa * Quaternion(eje, ang * t)).normalized()

func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _b(u: float) -> float:
	if u < U_LEAN_INICIo: return 0.0
	if u < U_SQUAT: return _smooth((u - U_LEAN_INICIo) / (U_SQUAT - U_LEAN_INICIo))
	if u < U_ESTIRON_INI: return 1.0
	if u < U_ESTIRON_FIN:
		return 1.0 + 0.05 * sin((u - U_ESTIRON_INI) / (U_ESTIRON_FIN - U_ESTIRON_INI) * PI)
	if u < U_RISE_FIN: return B_GRAB - (B_GRAB - B_CARRY) * _smooth((u - U_ESTIRON_FIN) / (U_RISE_FIN - U_ESTIRON_FIN))
	return B_CARRY - 0.045 * sin((u - U_RISE_FIN) / (1.0 - U_RISE_FIN) * PI)

func _lam(u: float) -> float:
	if u < U_LEAN_INICIo: return 0.0
	if u < U_SQUAT: return L_GRAB * _smooth((u - U_LEAN_INICIo) / (U_SQUAT - U_LEAN_INICIo))
	if u < U_ESTIRON_FIN: return L_GRAB
	if u < U_RISE_FIN: return L_GRAB + (L_CARRY - L_GRAB) * _smooth((u - U_ESTIRON_FIN) / (U_RISE_FIN - U_ESTIRON_FIN))
	return L_CARRY

func _sigma(u: float) -> float:
	if u < 0.12: return 0.0
	if u < U_GRAB_FIN: return _smooth((u - 0.12) / (U_GRAB_FIN - 0.12))
	return 1.0

func _C1(head_top: Vector3) -> Vector3:
	return Vector3(0.0, head_top.y + R_SK * 1.13 + 0.005, 0.02)

func _C0() -> Vector3:
	return Vector3(0.0, R_SK * 0.94, Z0)

func _cabeza_top() -> Vector3:
	var i := sk.find_bone("mixamorig_HeadTop_End")
	if i < 0: i = sk.find_bone("mixamorig_Head")
	return sk.get_bone_global_pose(i).origin

func _cabeza_centro() -> Vector3:
	var i_h := sk.find_bone("mixamorig_Head")
	var i_t := sk.find_bone("mixamorig_HeadTop_End")
	return (sk.get_bone_global_pose(i_h).origin + sk.get_bone_global_pose(i_t).origin) * 0.5

## Trayectoria de la roca: sube por delante mientras el cuerpo se yergue y una
## guarda la aparta de la cabeza en el tramo final. Termina justo encima.
func _path(u: float, ht: Vector3) -> Vector3:
	var c0 := _C0()
	var c1 := _C1(ht)
	var fy := _smooth((u - 0.55) / (U_RISE_FIN - 0.55))
	var c := Vector3(0.0, lerp(c0.y, c1.y, fy), lerp(c0.z, c1.z, fy))
	var hc := _cabeza_centro()
	var min_dist := R_SK + 0.10
	var d := c - hc
	if d.length() < min_dist and d.length_squared() > 0.000001:
		var cg := hc + d.normalized() * min_dist
		var w_g := _smooth((u - 0.58) / 0.10) * (1.0 - _smooth((u - 0.86) / 0.14))
		c = c.lerp(cg, w_g)
	return c

func _cuerpo_mezcla(pi: Dictionary, pc: Dictionary, b: float, lam: float) -> void:
	var pose := {"r": {}, "p": pi.p.lerp(pc.p, clampf(b, -0.5, 1.5))}
	for idx: int in pi.r:
		var q: Quaternion = _ext(pi.r[idx], pc.r[idx], b)
		if ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"].has(sk.get_bone_name(idx)):
			q = _ext(q, pc.r[idx], lam)
		pose.r[idx] = q
	_posar(pose)

func _brazos(centro: Vector3, sigma: float) -> Dictionary:
	var i_li := sk.find_bone("mixamorig_LeftArm")
	var i_ri := sk.find_bone("mixamorig_RightArm")
	var sl: Vector3 = sk.get_bone_global_pose(i_li).origin
	var sr: Vector3 = sk.get_bone_global_pose(i_ri).origin
	var gl := ik.punto_agarre(sk, i_li, centro, R_SK)
	var gr := ik.punto_agarre(sk, i_ri, centro, R_SK)
	if sigma < 1.0:
		gl = (sl + Vector3(0.015, -0.19, 0.075)).lerp(gl, sigma)
		gr = (sr + Vector3(-0.015, -0.19, 0.075)).lerp(gr, sigma)
	return ik.resolver(sk, gl, gr, centro)

func _aplicar_piernas(frame: Dictionary) -> void:
	for nombre: String in PIERNA_WALK:
		var idx := sk.find_bone(nombre)
		if frame.r.has(idx):
			sk.set_bone_pose_rotation(idx, frame.r[idx])
	sk.set_bone_pose_position(sk.find_bone("mixamorig_Hips"), frame.p)
	sk.force_update_all_bone_transforms()