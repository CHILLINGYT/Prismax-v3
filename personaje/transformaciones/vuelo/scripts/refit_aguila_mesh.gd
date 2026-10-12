extends SceneTree
## =============================================================================
##  Reparación del cuerpo visible del personaje de VUELO (águila).
## =============================================================================
##  Situación de partida (medida, no supuesta):
##   * El "modelo" del águila es una ESTATUA de Tripo sin esqueleto ni skin
##     (28.805 vértices) que se escaló ×1.849 a la altura del maniquí
##     (`GeneralSkeleton`, 53 huesos tipo Godot) y se le calcularon pesos
##     automáticos por cercanía de segmentos de hueso.
##   * Esa asignación de pesos mezcló por distancia zonas que no se tocan en
##     reposo (la estatua tiene los brazos caídos ~53° y el rig está en T-pose):
##     2.021 vértices mezclan huesos de pierna y de brazo (p. ej. el vértice más
##     externo de la mano pesa 53% `RightUpperLeg` + 47% `RightThumbProximal`):
##     al animar, esas zonas se desgarran y se desplazan hasta 0.47 m.
##   * Además la malla está autorada en pose A mientras las animaciones (46
##     clips del maniquí + generadas) esperan el reposo T del rig: los deltas de
##     brazo se aplican DOS veces (caída + caída) y los brazos terminan dentro
##     del cuerpo.
##
##  Reparación (la que haría un rigger, sin Blender):
##   1. Detectar el clúster de cada brazo por GEOMETRÍA (eje por centroides
##      iterativo, radio del tubo por percentil) — no por los pesos rotos.
##   2. Re-posar esos vértices a la T-pose del rig girándolos alrededor del
##      hombro (miembro m suave en el hombro, 1 en el resto del brazo). La pose
##      autorada del brazo pasa a coincidir con el reposo del esqueleto.
##   3. Recalcular los pesos por distancia a SEGMENTOS de hueso con criterio
##      cinemático: los huesos candidatos deben estar a ≤2 pasos en el árbol
##      (padre/hijo/hermano) del más cercano; nada de mezclar brazo con pierna.
##   4. Reconstruir el Skin: un bind por hueso = inversa del reposo global.
##      (Los binds actuales ya eran eso: el problema nunca fue el bind.)
##   5. Guardar con respaldo previo en user://.
##  La escena (`vuelo_player.tscn`) no se toca: mismos nodos y rutas.
## =============================================================================

const MESH_PATH := "res://personaje/transformaciones/vuelo/models/aguila_skinned_mesh.res"
const SKIN_PATH := "res://personaje/transformaciones/vuelo/models/aguila_skin.res"
const MANIQUI_PATH := "res://personaje/transformaciones/vuelo/models/maniqui_godot_baked.tscn"
const BACKUP_DIR := "user://backup_aguila_refit/"

const RADIO_TUBO := 0.16
const MAX_INFLUENCIAS := 4
const PASOS_KINEMATICOS := 2
const RADIO_KINEMATICO := 1.75
const EPS_DISTANCIA := 0.02
const POTENCIA_PESO := 3.0


func _init() -> void:
	# ------------------------------------------------------------ cargar todo
	var mesh := load(MESH_PATH) as ArrayMesh
	var skin := load(SKIN_PATH) as Skin
	var manq := (load(MANIQUI_PATH) as PackedScene).instantiate()
	var sk: Skeleton3D = null
	for n in manq.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	if mesh == null or skin == null or sk == null:
		push_error("[refit] faltan dependencias")
		quit(1)
		return

	var arr: Array = mesh.surface_get_arrays(0)
	var prim := mesh.surface_get_primitive_type(0)
	var mat := mesh.surface_get_material(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normales: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var tangentes: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
	print("[refit] malla: %d vértices | normal=%s tangente=%s" % [verts.size(),
			not normales.is_empty(), not tangentes.is_empty()])

	# Respaldos (bytes tal cual). El respaldo se escribe SÓLO la primera vez:
# re-ejecutar el generador nunca pisa la copia original.
	DirAccess.make_dir_recursive_absolute(BACKUP_DIR)
	if not FileAccess.file_exists(BACKUP_DIR + "aguila_skinned_mesh.res.bak"):
		_copiar(MESH_PATH, BACKUP_DIR + "aguila_skinned_mesh.res.bak")
	if not FileAccess.file_exists(BACKUP_DIR + "aguila_skin.res.bak"):
		_copiar(SKIN_PATH, BACKUP_DIR + "aguila_skin.res.bak")
	print("[refit] respaldos en ", BACKUP_DIR)

	# Reposo global (espacio modelo) por hueso + cabeza/cola de cada segmento.
	var n_huesos := sk.get_bone_count()
	var glob: Array[Transform3D] = []
	for i in n_huesos:
		var t: Transform3D = sk.get_bone_rest(i)
		var p := sk.get_bone_parent(i)
		if p >= 0:
			t = glob[p] * t
		glob.append(t)
	var cabeza: Array[Vector3] = []
	var cola: Array[Vector3] = []
	for i in n_huesos:
		cabeza.append(glob[i].origin)
		var hijos := sk.get_bone_children(i)
		if hijos.is_empty():
			cola.append(glob[i].origin + (glob[i].basis.y).normalized() * 0.05)
		else:
			var c := Vector3.ZERO
			for h in hijos:
				c += glob[h].origin
			cola.append(c / float(hijos.size()))

	# -------------------------------------------- 1+2) re-posar los brazos a T
	for lado in [1.0, -1.0]:  # +X = Left en este rig; -X = Right
		var hueso_hombro := "LeftUpperArm" if lado > 0.0 else "RightUpperArm"
		var i_h := sk.find_bone(hueso_hombro)
		var hombro := glob[i_h].origin
		var dir := _ajustar_eje_brazo(verts, hombro, lado)
		if dir == Vector3.ZERO:
			print("[refit] lado %+.0f: sin clúster de brazo" % lado)
			continue
		var objetivo := Vector3(lado, 0.0, 0.0)
		var q := Quaternion(dir, objetivo)
		print("[refit] brazo %s: eje %s -> T-pose (giro %.1f°)" % [hueso_hombro, str(dir.snappedf(0.001)),
				rad_to_deg(dir.angle_to(objetivo))])
		# Ya en T-pose (re-ejecución): no hay nada que reposar.
		if rad_to_deg(dir.angle_to(objetivo)) < 3.0:
			print("[refit] lado %+.0f: ya está en T-pose; sin cambios de vértices" % lado)
			continue
		var movidos := 0
		var max_mov := 0.0
		var d95 := _percentil_distancia(verts, hombro, dir, RADIO_TUBO)
		for v in verts.size():
			var m := _membresia(verts[v], hombro, dir, d95, lado)
			if m <= 0.0:
				continue
			var qm := Quaternion.IDENTITY.slerp(q, m)
			var nuevo := hombro + qm * (verts[v] - hombro)
			max_mov = maxf(max_mov, verts[v].distance_to(nuevo))
			if verts[v].distance_to(nuevo) > 0.0005:
				movidos += 1
			verts[v] = nuevo
			if v < normales.size():
				normales[v] = (qm * normales[v]).normalized()
			if not tangentes.is_empty():
				var k := v * 4
				var t3 := Vector3(tangentes[k], tangentes[k + 1], tangentes[k + 2])
				t3 = (qm * t3).normalized()
				tangentes[k] = t3.x
				tangentes[k + 1] = t3.y
				tangentes[k + 2] = t3.z
		print("[refit] lado %+.0f: %d vértices reposados (máx %.2f m)" % [lado, movidos, max_mov])

	arr[Mesh.ARRAY_VERTEX] = verts
	if not normales.is_empty():
		arr[Mesh.ARRAY_NORMAL] = normales
	if not tangentes.is_empty():
		arr[Mesh.ARRAY_TANGENT] = tangentes

	# ------------------------------------- 3) recalcular pesos (distancias+near)
	var padres := PackedInt32Array()
	for i in n_huesos:
		padres.append(sk.get_bone_parent(i))
	var arbol := {}
	for i in n_huesos:
		arbol[sk.get_bone_name(i)] = i
	var nuevos_b := PackedInt32Array()
	var nuevos_w := PackedFloat32Array()
	nuevos_b.resize(verts.size() * MAX_INFLUENCIAS)
	nuevos_w.resize(verts.size() * MAX_INFLUENCIAS)
	var sin_peso := 0
	var mezclas_prohibidas := 0
	var d0_acc := 0.0
	for v in verts.size():
		var p := verts[v]
		var dist: PackedFloat32Array = PackedFloat32Array()
		dist.resize(n_huesos)
		var i_min := 0
		var d_min := INF
		for i in n_huesos:
			var d := _distancia_segmento(p, cabeza[i], cola[i])
			dist[i] = d
			if d < d_min:
				d_min = d
				i_min = i
		# candidatos: cerca del hueso más próximo Y emparentados con él
		var cand: Array[int] = []
		for i in n_huesos:
			if dist[i] <= d_min * RADIO_KINEMATICO \
					and _pasos_arbol(i, i_min, padres) <= PASOS_KINEMATICOS:
				cand.append(i)
		if cand.is_empty():
			cand = [i_min]
		# pesos por falloff, mejores MAX_INFLUENCIAS
		var pesos: Array = []
		var suma := 0.0
		for i in cand:
			var w := pow(1.0 / (dist[i] + EPS_DISTANCIA), POTENCIA_PESO)
			pesos.append([i, w])
			suma += w
		pesos.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
		if pesos.size() > MAX_INFLUENCIAS:
			pesos.resize(MAX_INFLUENCIAS)
		var suma_final := 0.0
		for par in pesos:
			suma_final += float(par[1])
		if suma_final <= 0.0:
			sin_peso += 1
			nuevos_b[v * MAX_INFLUENCIAS] = i_min
			nuevos_w[v * MAX_INFLUENCIAS] = 1.0
			continue
		d0_acc += d_min
		for k in MAX_INFLUENCIAS:
			var b := 0
			var w := 0.0
			if k < pesos.size():
				b = int(pesos[k][0])
				w = float(pesos[k][1]) / suma_final
			nuevos_b[v * MAX_INFLUENCIAS + k] = b
			nuevos_w[v * MAX_INFLUENCIAS + k] = w
		# control: ¿hay mezcla brazo/pierna con peso relevante?
		var toca_brazo := false
		var toca_pierna := false
		for k in MAX_INFLUENCIAS:
			var bn := String(sk.get_bone_name(nuevos_b[v * MAX_INFLUENCIAS + k]))
			if nuevos_w[v * MAX_INFLUENCIAS + k] > 0.05:
				if "Arm" in bn or "Hand" in bn or "Shoulder" in bn:
					toca_brazo = true
				if "Leg" in bn or "Foot" in bn:
					toca_pierna = true
		if toca_brazo and toca_pierna:
			mezclas_prohibidas += 1
	print("[refit] pesos: vértices sin peso=%d | mezclas brazo+pierna>5%%: %d | dist. media al hueso=%.3f m" % [
			sin_peso, mezclas_prohibidas, d0_acc / maxf(1.0, float(verts.size()))])
	arr[Mesh.ARRAY_BONES] = nuevos_b
	arr[Mesh.ARRAY_WEIGHTS] = nuevos_w

	# -------------------------------------------------- 4) guardar malla + skin
	var nueva := ArrayMesh.new()
	nueva.add_surface_from_arrays(prim, arr)
	if mat != null:
		nueva.surface_set_material(0, mat)
	var err := ResourceSaver.save(nueva, MESH_PATH)
	if err != OK:
		push_error("[refit] no se pudo guardar la malla: %s" % error_string(err))
		quit(1)
		return

	var nueva_piel := Skin.new()
	for i in n_huesos:
		nueva_piel.add_bind(i, glob[i].affine_inverse())
		nueva_piel.set_bind_name(i, sk.get_bone_name(i))
	err = ResourceSaver.save(nueva_piel, SKIN_PATH)
	if err != OK:
		push_error("[refit] no se pudo guardar el skin: %s" % error_string(err))
		quit(1)
		return

	# ------------------------------------------------------- 5) verificación
	var recargada := load(MESH_PATH) as ArrayMesh
	var a2: Array = recargada.surface_get_arrays(0)
	var v2: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for v in v2:
		mn = mn.min(v)
		mx = mx.max(v)
	print("[refit] OK. bbox nueva: %s -> %s" % [str(mn.snappedf(0.01)), str(mx.snappedf(0.01))])
	print("[refit] brazos T esperados: xs ±0.6..0.8 a y≈1.44")
	manq.free()
	quit()


func _copiar(origen: String, destino: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(origen)
	var f := FileAccess.open(destino, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()


## Eje del brazo por centroides iterativos sobre el tubo (desde el hombro).
func _ajustar_eje_brazo(verts: PackedVector3Array, hombro: Vector3, lado: float) -> Vector3:
	var semilla := Vector3.ZERO
	var n_semilla := 0
	for v in verts:
		if lado * v.x > 0.42 and v.y > 0.5 and v.y < 1.7:
			semilla += v
			n_semilla += 1
	if n_semilla == 0:
		return Vector3.ZERO
	var dir := (semilla / float(n_semilla) - hombro).normalized()
	for _it in 5:
		var c := Vector3.ZERO
		var n := 0
		for v in verts:
			if lado * v.x <= 0.16:
				continue
			var rel := v - hombro
			var t := rel.dot(dir)
			if t < -0.02:
				continue
			var d := (rel - dir * t).length()
			if d < RADIO_TUBO:
				c += v
				n += 1
		if n == 0:
			break
		dir = (c / float(n) - hombro).normalized()
	return dir


## Percentil 95 de la distancia al eje dentro del tubo (radio real del brazo).
func _percentil_distancia(verts: PackedVector3Array, hombro: Vector3, dir: Vector3, radio_inicial: float) -> float:
	var ds: Array[float] = []
	for v in verts:
		var rel := v - hombro
		var t := rel.dot(dir)
		if t < 0.0:
			continue
		var d := (rel - dir * t).length()
		if d < radio_inicial:
			ds.append(d)
	ds.sort()
	if ds.is_empty():
		return radio_inicial
	return ds[int(float(ds.size() - 1) * 0.95)]


## Membresía 0..1 del vértice al brazo (1 = gira completo a la T-pose).
func _membresia(p: Vector3, hombro: Vector3, dir: Vector3, d95: float, lado: float) -> float:
	if lado * p.x <= 0.16:
		return 0.0
	var rel := p - hombro
	var t := rel.dot(dir)
	if t < -0.04 or t > 1.2:
		return 0.0
	var d := (rel - dir * t).length()
	var m_t := clampf((t + 0.04) / 0.20, 0.0, 1.0)  # transición suave en el hombro
	var m_d := clampf(1.0 - (d - d95 * 0.9) / maxf(0.02, d95 * 0.6), 0.0, 1.0)
	return m_t * m_d


## Distancia de un punto al segmento cabeza→cola.
func _distancia_segmento(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return p.distance_to(a)
	var u := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * u)


## Pasos en el árbol entre dos huesos (padre/hijo), sin pasar por la raíz dos veces.
func _pasos_arbol(a: int, b: int, padres: PackedInt32Array) -> int:
	var asc_a: Array[int] = []
	var x := a
	while x >= 0:
		asc_a.append(x)
		x = padres[x]
	var pasos_b := 0
	var y := b
	while y >= 0:
		var idx := asc_a.find(y)
		if idx >= 0:
			return pasos_b + idx
		y = padres[y]
		pasos_b += 1
	return 999