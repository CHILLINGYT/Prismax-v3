extends Node
## SONDA TEMPORAL v3 (dot-folder). Verifica en la ciudad REAL (semilla 20260707):
##   · faroles medidos por NODOS (la lectura de MultiMesh no es fiable: devuelve identidad;
##     las posiciones del poste se leen de FarolasColision y la cabeza/brazo de las luces),
##   · puertas usables y su punto de parada,
##   · colisiones de troncos y postes con rayos de la máscara del jugador (17),
##   · población y reparto por sectores,
##   · secuencia completa de entrada en una casa (fase forzada para poder verla),
##   · navegación (nadie clavado, nadie en la calzada) y noche (nadie tumbado).
## No escribe nada del juego.

const SEMILLA := 20260707

var _juego: Node
var _ciudad: Node
var _far: Node
var _dir: Node
var _ciclo: Node
var _listo := false
var _peor_clavado := 0.0
var _clavado_actual := 0.0
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
var _pen: Array[float] = []
var _fases_vistas: Dictionary = {}
var _fase_actual := "inicio"


func _ready() -> void:
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = SEMILLA
	_far = _juego.get_node_or_null("Farolas")
	_ciclo = _juego.get_node_or_null("CicloDiaNoche")
	add_child(_juego)
	get_tree().create_timer(250.0).timeout.connect(func() -> void:
		if _fase_actual == "fin":
			return
		print("[sonda] RESCATE (fase %s)" % _fase_actual)
		_informe_final()
		get_tree().quit())
	_run.call_deferred()


func _t_juego() -> float:
	return float(_dir.get("_t_ahora")) if _dir != null else 0.0


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
	await get_tree().create_timer(3.0).timeout
	_informe_estatico()
	Engine.time_scale = 6.0
	_listo = true

	# --- FASE A: comportamiento natural -------------------------------------------
	_fase_actual = "A natural"
	print("\n[sonda] --- FASE A: 30 s de juego con la entrada natural ---")
	var marca := _t_juego()
	while _t_juego() - marca < 30.0:
		await get_tree().create_timer(2.0).timeout
		_resumen("A")

	# --- FASE B: entrada FORZADA (para poder medir la secuencia completa) ---------
	_fase_actual = "B forzada"
	print("\n[sonda] --- FASE B: 60 s de juego con la entrada forzada (prob 1.0, máx 6) ---")
	if _dir != null:
		_dir.set("entrar_prob", 1.0)
		_dir.set("entrar_prob_tarde", 1.0)
		_dir.set("entrar_max", 6)
	marca = _t_juego()
	var paso := 0
	while _t_juego() - marca < 60.0:
		await get_tree().create_timer(2.0).timeout
		paso += 1
		if paso % 5 == 0:
			_resumen("B")

	# --- FASE C: noche, con la configuración normal ------------------------------
	_fase_actual = "C noche"
	print("\n[sonda] --- FASE C: se restaura la configuración y se hace de noche (fase 0.86) ---")
	if _dir != null:
		_dir.set("entrar_prob", 0.012)
		_dir.set("entrar_prob_tarde", 0.022)
		_dir.set("entrar_max", 3)
	if _ciclo != null:
		_ciclo.set("_fase", 0.86)
	marca = _t_juego()
	while _t_juego() - marca < 25.0:
		await get_tree().create_timer(2.0).timeout
	_resumen("C")
	Engine.time_scale = 1.0
	_listo = false
	_fase_actual = "fin"
	await get_tree().create_timer(1.0).timeout
	_informe_final()
	get_tree().quit()


func _resumen(etq: String) -> void:
	var r: Dictionary = _dir.call("resumen")
	var d: Dictionary = r.get("entrar_diag", {})
	print("   [%s] t=%.0f total=%d caminando=%d sentados=%d quietos=%d | entrando=%d entradas=%d pend=%d | puertas lib=%d/%d | yendo_a_puerta=%d | diag: llamadas=%d sorteo=%d sin_puerta=%d ok=%d | clavados=%d bloq=%d viol=%d noche=%s" % [
			etq, _t_juego(), r.get("total", 0), r.get("caminando", 0), r.get("sentados", 0),
			r.get("quietos", 0), r.get("entrando", 0), r.get("entradas", 0), r.get("pendientes", 0),
			r.get("puertas_libres", 0), r.get("puertas", 0), r.get("yendo_a_puerta", 0),
			d.get("llamadas", 0), d.get("sorteo", 0), d.get("sin_puerta", 0), d.get("ok", 0),
			r.get("clavados", 0), r.get("bloqueados", 0), r.get("violaciones", 0), str(r.get("noche"))])


# =============================================================================
#  Estático
# =============================================================================
func _informe_estatico() -> void:
	var tra: Dictionary = _ciudad.get("_trazado")
	var x0: float = float(tra["off"].x)
	var z0: float = float(tra["off"].y)
	var paso: float = float(tra["paso"])
	var obs: Array = _ciudad.get("_obstaculos_peatones")
	var parques: Array = _ciudad.get("_parques_datos")
	print("\n===== 1) FAROLES (medidos por nodos: poste = colisión, cabeza = luz) =====")
	print("  contadores del script: acera=%s esquina=%s parque=%s movidas=%s descartadas=%s" % [
			_far.get("_n_acera"), _far.get("_n_esquina"), _far.get("_n_parque"),
			_far.get("_movidas"), _far.get("_descartadas")])
	var col := _far.get_node_or_null("FarolasColision") as StaticBody3D
	var luces: Array = []
	for n in _far.get_children():
		if n is OmniLight3D:
			luces.append(n)
	var polos: Array = col.get_children()
	print("  postes con colisión: %d | luces: %d | capa de colisión: %d" % [
			polos.size(), luces.size(), col.collision_layer])
	var por_clase := {"acera": 0, "esquina": 0, "parque": 0, "otro": 0}
	var mal_brazo := 0
	var d_borde: Array[float] = []
	var d_obs_min := 1e9
	var d_obs_info := ""
	var sobre_calzada := 0
	var parque_ok := 0
	var cabeza_min := 1e9
	var cabeza_max := -1e9
	for i in polos.size():
		var polo: Vector3 = (polos[i] as CollisionShape3D).position
		var cabeza: Vector3 = (luces[i] as OmniLight3D).transform.origin if i < luces.size() else polo
		cabeza_min = minf(cabeza_min, cabeza.y)
		cabeza_max = maxf(cabeza_max, cabeza.y)
		var dx := absf(polo.x - (x0 + roundf((polo.x - x0) / paso) * paso))
		var dz := absf(polo.z - (z0 + roundf((polo.z - z0) / paso) * paso))
		var d_linea := minf(dx, dz)
		if d_linea < 6.0:
			sobre_calzada += 1
		var en_parque := false
		for rc: Rect2 in parques:
			if rc.grow(-0.5).has_point(Vector2(polo.x, polo.z)):
				en_parque = true
				break
		if en_parque:
			por_clase["parque"] += 1
			parque_ok += 1
		elif absf(d_linea - 6.45) < 0.06:
			por_clase["acera"] += 1
			d_borde.append(d_linea)
		elif absf(dx - 6.85) < 0.06 and absf(dz - 6.85) < 0.06:
			por_clase["esquina"] += 1
		else:
			por_clase["otro"] += 1
		# El brazo debe apuntar a la calzada: la cabeza está desplazada hacia el eje del vial.
		var hacia := Vector3.ZERO
		if dx < dz:
			hacia = Vector3(-signf(polo.x - (x0 + roundf((polo.x - x0) / paso) * paso)), 0.0, 0.0)
		else:
			hacia = Vector3(0.0, 0.0, -signf(polo.z - (z0 + roundf((polo.z - z0) / paso) * paso)))
		var brazo := Vector3(cabeza.x - polo.x, 0.0, cabeza.z - polo.z)
		if brazo.length() < 0.1:
			brazo = Vector3(signf(hacia.x) if absf(hacia.x) > 0.5 else 0.0, 0.0,
					signf(hacia.z) if absf(hacia.z) > 0.5 else 0.0)
		if brazo.length_squared() > 0.01:
			brazo = brazo.normalized()
		if hacia.length_squared() > 0.5 and brazo.dot(hacia) < 0.85 and not en_parque:
			mal_brazo += 1
		for o: Dictionary in obs:
			var d := Vector2(float(o["x"]) - polo.x, float(o["z"]) - polo.z).length() - float(o["r"])
			if d < d_obs_min:
				d_obs_min = d
				d_obs_info = "en (%.1f,%.1f) contra r=%.2f" % [polo.x, polo.z, float(o["r"])]
	print("  por clase: acera(mid-block)=%d esquina=%d parque/plaza=%d otro=%d" % [
			por_clase["acera"], por_clase["esquina"], por_clase["parque"], por_clase["otro"]])
	print("  brazos que NO miran a la calzada (fuera de parques): %d" % mal_brazo)
	print("  postes sobre la calzada (<6 m del eje): %d" % sobre_calzada)
	print("  holgura mínima al mobiliario: %.2f m %s" % [d_obs_min, d_obs_info])
	print("  farolas en parques/plazas reconocidas: %d (deben ser %d: 2 por parque)" % [
			parque_ok, parques.size() * 2])
	if not d_borde.is_empty():
		d_borde.sort()
		print("  distancia de las de acera al eje: min=%.2f med=%.2f max=%.2f (bordillo en 6.00)" % [
				d_borde[0], d_borde[d_borde.size() / 2], d_borde[d_borde.size() - 1]])
	print("  altura de la cabeza (luz): %.2f-%.2f m" % [cabeza_min, cabeza_max])

	print("\n===== 2) PUERTAS =====")
	var portales: Array = _ciudad.get("prueba_portales")
	var frentes: Array = _ciudad.get("prueba_portales_frente")
	var red: RedPeatonal = _dir.get("red")
	var usables: Array = _dir.get("_portales")
	print("  generador: %d portales | usables: %d | rechazados: %d" % [
			portales.size(), usables.size(), portales.size() - usables.size()])
	var d_nodo: Array[float] = []
	var d_hueco: Array[float] = []
	for p: Dictionary in usables:
		var pie: Vector3 = p["pie"]
		d_nodo.append(pie.distance_to(red.pos(int(p["nodo"]))))
		var libre := 1e9
		for o: Dictionary in obs:
			libre = minf(libre, Vector2(float(o["x"]) - pie.x, float(o["z"]) - pie.z).length() - float(o["r"]))
		d_hueco.append(libre)
	d_nodo.sort()
	d_hueco.sort()
	print("  pie->nodo de red: min=%.2f med=%.2f max=%.2f" % [
			d_nodo[0], d_nodo[d_nodo.size() / 2], d_nodo[d_nodo.size() - 1]])
	print("  pie->mobiliario más cercano: min=%.2f med=%.2f m" % [d_hueco[0], d_hueco[d_hueco.size() / 2]])
	print("  frente del marco: %s" % str(Array(frentes).size()))

	print("\n===== 3) COLISIONES =====")
	var veg := _ciudad.get_node_or_null("CiudadGenerada/Vegetacion")
	var cuerpo := veg.get_node_or_null("ColisionesVegetacion") as StaticBody3D if veg != null else null
	print("  vegetación: %s" % ("%d cilindros capa %d" % [cuerpo.get_child_count(), cuerpo.collision_layer]
			if cuerpo != null else "FALTA"))
	var espacio := get_viewport().world_3d.direct_space_state
	if cuerpo != null:
		var formas: Array = cuerpo.get_children()
		var salto: int = maxi(1, formas.size() / 30)
		var ok := 0
		var n := 0
		for i in range(0, formas.size(), salto):
			var cs := formas[i] as CollisionShape3D
			var q := PhysicsRayQueryParameters3D.create(cs.position + Vector3(3.0, 1.2, 0.0),
					cs.position + Vector3(0.0, 1.2, 0.0))
			q.collision_mask = 17
			var hit := espacio.intersect_ray(q)
			n += 1
			if not hit.is_empty() and (hit["collider"] as Node) == cuerpo:
				ok += 1
		print("  física vegetación (rayo con máscara 17 → tronco/cantero): %d de %d" % [ok, n])
	if col != null:
		var salto2: int = maxi(1, polos.size() / 20)
		var ok2 := 0
		var n2 := 0
		for i2 in range(0, polos.size(), salto2):
			var p2: Vector3 = (polos[i2] as CollisionShape3D).position
			var q2 := PhysicsRayQueryParameters3D.create(p2 + Vector3(2.5, 1.5, 0.0), p2 + Vector3(0.0, 1.5, 0.0))
			q2.collision_mask = 17
			var hit2 := espacio.intersect_ray(q2)
			n2 += 1
			if not hit2.is_empty() and (hit2["collider"] as Node) == col:
				ok2 += 1
		print("  física farolas (rayo con máscara 17 → poste): %d de %d" % [ok2, n2])


# =============================================================================
#  Por fotograma
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
			_peor_clavado = maxf(_peor_clavado, _clavado_actual)
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
					_mob_info = "radio=%.2f tramo=%s" % [float(o2["r"]),
							String(t[2]) if t.size() >= 3 else "?"]
		if c.en_postura() and c.postura_actual() == "entrar":
			var id: int = c.get_instance_id()
			if not _sec.has(id):
				_sec[id] = {"fases": [], "pen0": Vector3.ZERO, "pen1": Vector3.ZERO}
			var s: Dictionary = _sec[id]
			var fases: Array = s["fases"]
			var fase := String(c.fase_postura())
			if fases.is_empty() or String(fases[fases.size() - 1]) != fase:
				fases.append(fase)
				_fases_vistas[fase] = int(_fases_vistas.get(fase, 0)) + 1
				if fase == "penetrar":
					s["pen0"] = c.global_position
			if fase == "penetrar":
				s["pen1"] = c.global_position
			if fase == "mirar" or fase == "penetrar":
				var ref := int(c.get("_postura_ref"))
				en_uso[ref] = int(en_uso.get(ref, 0)) + 1
				if fase == "mirar":
					_yaw_err.append(rad_to_deg(absf(wrapf(float(c.get("_postura_yaw")) - c.rotation.y, -PI, PI))))
					var obj: Vector3 = c.get("_postura_punto_ini")
					_pie_dist.append(Vector2(obj.x - c.global_position.x, obj.z - c.global_position.z).length())
	for ref2: int in en_uso.keys():
		if int(en_uso[ref2]) > 1:
			_solapes += 1
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
				var p0: Vector3 = (_sec[id2] as Dictionary)["pen0"]
				var p1: Vector3 = (_sec[id2] as Dictionary)["pen1"]
				_pen.append(Vector2(p1.x - p0.x, p1.z - p0.z).length())
			else:
				_abandonadas += 1
				print("   [aviso] entrada abandonada, fases=%s" % str(fas))
			_sec.erase(id2)


func _informe_final() -> void:
	print("\n===== 4) POBLACIÓN Y NAVEGACIÓN =====")
	var r: Dictionary = _dir.call("resumen")
	print("  vivos=%d (creados %d, pendientes %d) caminando=%d sentados=%d tumbados=%d" % [
			r.get("total", 0), r.get("nacimientos", 0), r.get("pendientes", 0), r.get("caminando", 0),
			r.get("sentados", 0), r.get("tumbados", 0)])
	var sect := {"n": 0, "con": 0, "vac": 0, "max": 0}
	for clave: String in (r.get("sectores", {}) as Dictionary).keys():
		sect["n"] = int(sect["n"]) + 1
		var k := int(r["sectores"][clave])
		if k > 0:
			sect["con"] = int(sect["con"]) + 1
		else:
			sect["vac"] = int(sect["vac"]) + 1
		sect["max"] = maxi(int(sect["max"]), k)
	print("  sectores=%d con gente=%d vacíos=%d máx/sector=%d" % [sect["n"], sect["con"], sect["vac"], sect["max"]])
	print("  violaciones de calzada fuera del paso: %d | peor 'caminando sin moverse': %.2f s" % [
			r.get("violaciones", 0), _peor_clavado])
	print("  dentro de mobiliario andando: %d fotogramas, peor holgura %.2f m (%s)" % [_mob, _mob_peor, _mob_info])
	print("  de noche quedan tumbados: %d (debe ser 0)" % r.get("tumbados", 0))
	print("\n===== 5) ENTRADAS EN CASAS =====")
	print("  secuencias completas=%d abandonadas=%d en curso=%d | solapes en una puerta=%d" % [
			_completadas, _abandonadas, _sec.size(), _solapes])
	print("  fases vistas: %s" % str(_fases_vistas))
	if not _yaw_err.is_empty():
		var e := _yaw_err.duplicate()
		e.sort()
		print("  error de giro frente a la puerta: med=%.1f° peor=%.1f° (n=%d)" % [
				e[e.size() / 2], e[e.size() - 1], e.size()])
	if not _pie_dist.is_empty():
		var d2 := _pie_dist.duplicate()
		d2.sort()
		print("  distancia al punto de parada al empezar a mirar: med=%.2f peor=%.2f m" % [
				d2[d2.size() / 2], d2[d2.size() - 1]])
	if not _pen.is_empty():
		var p3 := _pen.duplicate()
		p3.sort()
		print("  avance durante la desaparición (paso hacia el vano): med=%.2f peor=%.2f m" % [
				p3[p3.size() / 2], p3[p3.size() - 1]])
	print("  contadores: %s" % str(r.get("entrar_diag", {})))