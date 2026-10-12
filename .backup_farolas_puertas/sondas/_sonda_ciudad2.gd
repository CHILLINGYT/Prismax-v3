extends Node
## SONDA TEMPORAL v2 (dot-folder). Mide la ciudad REAL (semilla 20260707) después de los
## cambios de faroles, puertas, población y colisiones. Además de medir, imprime muestras
## crudas (posiciones de farola, puertas rechazadas) para poder diagnosticar sin adivinar.
## No escribe nada del juego.

const SEMILLA := 20260707
const NATURAL := 45.0        ## s de juego con la probabilidad normal de entrar
const FORZADO := 40.0        ## s de juego con la entrada forzada (para ver la secuencia)

var _juego: Node
var _ciudad: Node
var _far: Node
var _dir: Node
var _listo := false
var _t_inicio := 0.0
var _peor_clavado := 0.0
var _clavado_actual := 0.0
var _sitio_clavado := ""
var _mob := 0
var _mob_peor := 0.0
var _mob_info := ""
var _puertas_en_uso: Dictionary = {}
var _solapes := 0
var _sec: Dictionary = {}
var _completadas := 0
var _abandonadas := 0
var _yaw_err: Array[float] = []
var _pie_dist: Array[float] = []
var _fases_vistas: Dictionary = {}
var _borradas := 0
var _fase_actual := ""


func _ready() -> void:
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = SEMILLA
	_far = _juego.get_node_or_null("Farolas")
	add_child(_juego)
	get_tree().create_timer(260.0).timeout.connect(func() -> void:
		if _fase_actual == "fin":
			return
		print("[sonda] RESCATE (fase %s)" % _fase_actual)
		_informe_estatico()
		_informe_dinamico()
		get_tree().quit())
	_run.call_deferred()


func _run() -> void:
	var vueltas := 0
	while true:
		var est: Dictionary = _ciudad.get("_est")
		if int(est.get("ciudad_lista", 0)) == 1:
			break
		await get_tree().process_frame
		vueltas += 1
		if vueltas > 8000:
			print("[sonda] la ciudad no se cerró a tiempo")
			break
	_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
	await _esperar(3.0)
	_informe_estatico()
	_fase_actual = "natural"
	Engine.time_scale = 6.0
	_listo = true
	_t_inicio = _ahora()
	print("\n[sonda] --- FASE A: %.0f s de juego con la entrada natural (prob %.3f) ---" % [
			NATURAL, _dir.get("entrar_prob") if _dir != null else -1.0])
	while _ahora() - _t_inicio < NATURAL:
		await _esperar(15.0)
		_resumen_consola("A")
	print("\n[sonda] --- FASE B: %.0f s de juego con la entrada FORZADA (prob 1.0) ---" % FORZADO)
	if _dir != null:
		_dir.set("entrar_prob", 1.0)
		_dir.set("entrar_prob_tarde", 1.0)
		_dir.set("entrar_max", 6)
	_t_inicio = _ahora()
	_fase_actual = "forzada"
	while _ahora() - _t_inicio < FORZADO:
		await _esperar(10.0)
		_resumen_consola("B")
	print("\n[sonda] --- FASE C: se devuelve la configuración y se deja correr ---")
	if _dir != null:
		_dir.set("entrar_prob", 0.012)
		_dir.set("entrar_prob_tarde", 0.022)
		_dir.set("entrar_max", 3)
	_fase_actual = "natural2"
	_t_inicio = _ahora()
	while _ahora() - _t_inicio < 20.0:
		await _esperar(10.0)
		_resumen_consola("C")
	Engine.time_scale = 1.0
	_listo = false
	_fase_actual = "fin"
	await _esperar(1.0)
	_informe_dinamico()
	get_tree().quit()


func _resumen_consola(etq: String) -> void:
	if _dir == null:
		return
	var r: Dictionary = _dir.call("resumen")
	var d: Dictionary = r.get("entrar_diag", {})
	print("   [%s] total=%d caminando=%d sentados=%d tumbados=%d quietos=%d | entrando=%d entradas=%d nacidos=%d pend=%d | puertas lib=%d/%d | yendo_a_puerta=%d | diag entrar: llamadas=%d sorteo=%d sin_puerta=%d tope=%d ok=%d | clavados=%d bloqueados=%d viol=%d" % [
			etq, r.get("total", 0), r.get("caminando", 0), r.get("sentados", 0), r.get("tumbados", 0),
			r.get("quietos", 0), r.get("entrando", 0), r.get("entradas", 0), r.get("nacimientos", 0),
			r.get("pendientes", 0), r.get("puertas_libres", 0), r.get("puertas", 0),
			r.get("yendo_a_puerta", 0), d.get("llamadas", 0), d.get("sorteo", 0),
			d.get("sin_puerta", 0), d.get("tope", 0), d.get("ok", 0),
			r.get("clavados", 0), r.get("bloqueados", 0), r.get("violaciones", 0)])


func _ahora() -> float:
	return float(Time.get_ticks_msec()) / 1000.0 - _t_base


var _t_base := 0.0


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


# =============================================================================
#  Informe estático
# =============================================================================
func _informe_estatico() -> void:
	_t_base = float(Time.get_ticks_msec()) / 1000.0
	var tra: Dictionary = _ciudad.get("_trazado")
	var x0: float = float(tra["off"].x)
	var z0: float = float(tra["off"].y)
	var paso: float = float(tra["paso"])
	print("\n===== 1) FAROLES =====")
	print("  contadores: acera=%s esquina=%s parque=%s | movidas=%s descartadas=%s" % [
			_far.get("_n_acera"), _far.get("_n_esquina"), _far.get("_n_parque"),
			_far.get("_movidas"), _far.get("_descartadas")])
	var metal := _far.get_node_or_null("FarolasMetal") as MultiMeshInstance3D
	var col := _far.get_node_or_null("FarolasColision") as StaticBody3D
	print("  colisión: %s · %d formas · capa %d" % [
			"OK" if col != null else "FALTA", col.get_child_count() if col != null else 0,
			col.collision_layer if col != null else -1])
	var mm: MultiMesh = metal.multimesh
	print("  transform del nodo Farolas: %s" % str(_far.transform))
	var mal := 0
	var por_clase := {"acera": 0, "esquina": 0, "otro": 0}
	var d_borde: Array[float] = []
	var d_obs_min := 1e9
	var obs: Array = _ciudad.get("_obstaculos_peatones")
	for i in mm.instance_count:
		var t: Transform3D = mm.get_instance_transform(i)
		var dx := absf(t.origin.x - (x0 + roundf((t.origin.x - x0) / paso) * paso))
		var dz := absf(t.origin.z - (z0 + roundf((t.origin.z - z0) / paso) * paso))
		var d_calle := minf(dx, dz)
		var hacia: Vector3
		if dx < dz:
			hacia = Vector3(-signf(t.origin.x - (x0 + roundf((t.origin.x - x0) / paso) * paso)), 0.0, 0.0)
		else:
			hacia = Vector3(0.0, 0.0, -signf(t.origin.z - (z0 + roundf((t.origin.z - z0) / paso) * paso)))
		var brazo := t.basis * Vector3(1.0, 0.0, 0.0)
		brazo.y = 0.0
		if brazo.length_squared() > 0.0001:
			brazo = brazo.normalized()
		if hacia.length_squared() > 0.5 and brazo.dot(hacia) < 0.9:
			mal += 1
		if absf(d_calle - 6.45) < 0.06:
			por_clase["acera"] += 1
			d_borde.append(d_calle)
		elif absf(dx - 6.85) < 0.06 and absf(dz - 6.85) < 0.06:
			por_clase["esquina"] += 1
		else:
			por_clase["otro"] += 1
		for o: Dictionary in obs:
			var d := Vector2(float(o["x"]) - t.origin.x, float(o["z"]) - t.origin.z).length() - float(o["r"])
			d_obs_min = minf(d_obs_min, d)
	print("  instancias=%d · por clase: acera=%d esquina=%d otro=%d · brazo NO hacia la calzada=%d" % [
			mm.instance_count, por_clase["acera"], por_clase["esquina"], por_clase["otro"], mal])
	if not d_borde.is_empty():
		d_borde.sort()
		print("  farolas de acera: distancia al eje min=%.2f med=%.2f max=%.2f (bordillo a 6.0)" % [
				d_borde[0], d_borde[d_borde.size() / 2], d_borde[d_borde.size() - 1]])
	print("  holgura mínima al mobiliario (círculos del generador): %.2f m" % d_obs_min)
	print("  --- muestras crudas de farola (origen, dx, dz, brazo) ---")
	var salto: int = maxi(1, mm.instance_count / 6)
	for i2 in range(0, mm.instance_count, salto):
		var t2: Transform3D = mm.get_instance_transform(i2)
		var b2 := (t2.basis * Vector3(1.0, 0.0, 0.0))
		print("     %.2f,%.2f,%.2f  dx=%.2f dz=%.2f  brazo=(%.2f,%.2f)" % [
				t2.origin.x, t2.origin.y, t2.origin.z,
				absf(t2.origin.x - (x0 + roundf((t2.origin.x - x0) / paso) * paso)),
				absf(t2.origin.z - (z0 + roundf((t2.origin.z - z0) / paso) * paso)), b2.x, b2.z])

	print("\n===== 2) PUERTAS =====")
	var portales: Array = _ciudad.get("prueba_portales")
	var dirs: Array = _ciudad.get("prueba_portales_dir")
	var frentes: Array = _ciudad.get("prueba_portales_frente")
	var red: RedPeatonal = _dir.get("red")
	print("  del generador: %d | usables: %d" % [portales.size(), (_dir.get("_portales") as Array).size()])
	var pie_ok: Array[float] = []
	for i3 in portales.size():
		var pos: Vector3 = portales[i3]
		var dir: Vector3 = dirs[i3]
		var pie := pos + dir * (float(frentes[i3]) + 0.85)
		var nodo := red.nodo_mas_cercano(pie, ["acera", "plaza", "parque", "paseo", "acceso"])
		var d := 99.0 if nodo < 0 else pie.distance_to(red.pos(nodo))
		if d > 7.0:
			print("     [rechazada] portal %d en (%.1f,%.1f) dir=(%.2f,%.2f) → nodo más cercano a %.2f m | es_calzada=%s" % [
					i3, pos.x, pos.z, dir.x, dir.z, d, str(red.es_calzada(pie))])
		else:
			pie_ok.append(d)
	if not pie_ok.is_empty():
		pie_ok.sort()
		print("  distancia del punto de parada al nodo de la red: min=%.2f med=%.2f max=%.2f" % [
				pie_ok[0], pie_ok[pie_ok.size() / 2], pie_ok[pie_ok.size() - 1]])

	print("\n===== 3) COLISIONES =====")
	var veg := _ciudad.get_node_or_null("CiudadGenerada/Vegetacion")
	var cuerpo := veg.get_node_or_null("ColisionesVegetacion") as StaticBody3D if veg != null else null
	if cuerpo == null:
		print("  FALTA ColisionesVegetacion (buscado en CiudadGenerada/Vegetacion)")
	else:
		print("  vegetación: %d cilindros, capa %d" % [cuerpo.get_child_count(), cuerpo.collision_layer])
	if col != null:
		print("  farolas: %d cilindros, capa %d" % [col.get_child_count(), col.collision_layer])
	var n_post := 0
	var n_post_max := 0
	if _dir != null:
		for c in _dir.get("peatones"):
			if is_instance_valid(c):
				n_post_max += 1
				if c.tiene_posturas():
					n_post += 1
	print("  ciudadanos con clips de postura: %d de %d | obstáculos del director: %d" % [
			n_post, n_post_max, (_dir.get("_obstaculos") as Array).size()])


# =============================================================================
#  Vigilancia por fotograma
# =============================================================================
func _process(delta: float) -> void:
	if not _listo or _dir == null or delta <= 0.0:
		return
	var peatones: Array = _dir.get("peatones")
	var obs: Array = _dir.get("_obstaculos")
	var en_uso := {}
	for c in peatones:
		if not is_instance_valid(c):
			continue
		if c.is_walking() and c.velocidad_real() < c.walk_speed * 0.2:
			_clavado_actual += delta
			if _clavado_actual > _peor_clavado:
				_peor_clavado = _clavado_actual
				_sitio_clavado = "%.1f,%.1f" % [c.global_position.x, c.global_position.z]
		else:
			_clavado_actual = 0.0
		if c.is_walking():
			var p: Vector3 = c.global_position
			var peor := 1e9
			var peor_i := -1
			for k in obs.size():
				var o: Dictionary = obs[k]
				var dd := Vector2(float(o["x"]) - p.x, float(o["z"]) - p.z).length() - float(o["r"]) - 0.35
				if dd < peor:
					peor = dd
					peor_i = k
			if peor < 0.0:
				_mob += 1
				if peor < _mob_peor:
					_mob_peor = peor
					var o2: Dictionary = obs[peor_i]
					var t: Array = c.tramo_red()
					_mob_info = "radio=%.2f tramo=%s veh=%.2f" % [float(o2["r"]),
							String(t[2]) if t.size() >= 3 else "?", c.velocidad_real()]
		if c.en_postura() and c.postura_actual() == "entrar":
			if not _sec.has(c.get_instance_id()):
				_sec[c.get_instance_id()] = {"fases": []}
			var fases: Array = (_sec[c.get_instance_id()] as Dictionary)["fases"]
			var fase := String(c.fase_postura())
			if fases.is_empty() or String(fases[fases.size() - 1]) != fase:
				fases.append(fase)
				_fases_vistas[fase] = int(_fases_vistas.get(fase, 0)) + 1
			if fase == "mirar" or fase == "penetrar":
				var ref := int(c.get("_postura_ref"))
				en_uso[ref] = int(en_uso.get(ref, 0)) + 1
				if fase == "mirar":
					var err := rad_to_deg(absf(wrapf(float(c.get("_postura_yaw")) - c.rotation.y, -PI, PI)))
					_yaw_err.append(err)
					var obj: Vector3 = c.get("_postura_punto_ini")
					_pie_dist.append(Vector2(obj.x - c.global_position.x, obj.z - c.global_position.z).length())
	# Solapes y secuencias terminadas
	for ref2: int in en_uso.keys():
		if int(en_uso[ref2]) > 1:
			_solapes += 1
			print("   [AVISO] dos ciudadanos en la puerta %d a la vez" % ref2)
	for id2 in _sec.keys():
		var vive := false
		for c2 in peatones:
			if is_instance_valid(c2) and c2.get_instance_id() == id2:
				vive = true
				break
		if not vive:
			var fas: Array = (_sec[id2] as Dictionary)["fases"]
			if fas.has("penetrar"):
				_completadas += 1
			else:
				_abandonadas += 1
				print("   [aviso] entrada abandonada con fases %s" % str(fas))
			_borradas += 1
			_sec.erase(id2)


func _informe_dinamico() -> void:
	print("\n===== 4) POBLACIÓN Y NAVEGACIÓN =====")
	var r: Dictionary = _dir.call("resumen")
	print("  vivos=%d (creados %d, pendientes %d) | caminando=%d sentados=%d tumbados=%d quietos=%d" % [
			r.get("total", 0), r.get("nacimientos", 0), r.get("pendientes", 0), r.get("caminando", 0),
			r.get("sentados", 0), r.get("tumbados", 0), r.get("quietos", 0)])
	var censo := {"sectores": 0, "con_gente": 0, "vacios": 0, "max": 0}
	for clave: String in (r.get("sectores", {}) as Dictionary).keys():
		censo["sectores"] = int(censo["sectores"]) + 1
		var n := int(r["sectores"][clave])
		if n > 0:
			censo["con_gente"] = int(censo["con_gente"]) + 1
		else:
			censo["vacios"] = int(censo["vacios"]) + 1
		censo["max"] = maxi(int(censo["max"]), n)
	print("  sectores=%d con gente=%d vacíos=%d (máx por sector=%d)" % [
			censo["sectores"], censo["con_gente"], censo["vacios"], censo["max"]])
	print("  violaciones de calzada fuera del paso (auditoría): %d" % r.get("violaciones", 0))
	print("  peor 'caminando sin moverse': %.2f s (%s)" % [_peor_clavado, _sitio_clavado])
	print("  dentro de mobiliario andando: %d fotogramas · peor holgura %.2f m (%s)" % [
			_mob, _mob_peor, _mob_info])
	print("\n===== 5) ENTRADAS EN CASAS =====")
	print("  secuencias completas=%d abandonadas=%d en curso=%d" % [_completadas, _abandonadas, _sec.size()])
	print("  solapes en la misma puerta: %d" % _solapes)
	print("  fases vistas (cuántas veces): %s" % str(_fases_vistas))
	if not _yaw_err.is_empty():
		var e := _yaw_err.duplicate()
		e.sort()
		print("  error de giro frente a la puerta: med=%.1f° peor=%.1f° (n=%d)" % [
				e[e.size() / 2], e[e.size() - 1], e.size()])
	if not _pie_dist.is_empty():
		var d2 := _pie_dist.duplicate()
		d2.sort()
		print("  distancia al punto de parada: med=%.2f m peor=%.2f m" % [d2[d2.size() / 2], d2[d2.size() - 1]])
	print("  contadores de entrada: %s" % str(r.get("entrar_diag", {})))
	_sondas_fisica()


func _sondas_fisica() -> void:
	var espacio := get_viewport().world_3d.direct_space_state
	# --- Troncos y canteros ---
	var veg := _ciudad.get_node_or_null("CiudadGenerada/Vegetacion")
	var cuerpo := veg.get_node_or_null("ColisionesVegetacion") as StaticBody3D if veg != null else null
	if cuerpo != null:
		var formas: Array = cuerpo.get_children()
		var salto: int = maxi(1, formas.size() / 30)
		var ok := 0
		var n := 0
		for i in range(0, formas.size(), salto):
			var cs := formas[i] as CollisionShape3D
			var p := cs.position
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(3.0, 1.2, 0.0), p + Vector3(0.0, 1.2, 0.0))
			q.collision_mask = 17
			var hit := espacio.intersect_ray(q)
			n += 1
			if not hit.is_empty() and (hit["collider"] as Node) == cuerpo:
				ok += 1
		print("  física vegetación (rayos con máscara 17 → tronco): %d aciertos de %d" % [ok, n])
	# --- Postes de farola ---
	var col := _far.get_node_or_null("FarolasColision") as StaticBody3D
	if col != null:
		var formas2: Array = col.get_children()
		var salto2: int = maxi(1, formas2.size() / 20)
		var ok2 := 0
		var n2 := 0
		for i2 in range(0, formas2.size(), salto2):
			var cs2 := formas2[i2] as CollisionShape3D
			var p2 := cs2.position
			var q2 := PhysicsRayQueryParameters3D.create(p2 + Vector3(2.5, 1.5, 0.0), p2 + Vector3(0.0, 1.5, 0.0))
			q2.collision_mask = 17
			var hit2 := espacio.intersect_ray(q2)
			n2 += 1
			if not hit2.is_empty() and (hit2["collider"] as Node) == col:
				ok2 += 1
		print("  física farolas (rayos con máscara 17 → poste): %d aciertos de %d" % [ok2, n2])