extends Node
## SONDA TEMPORAL (vive en el dot-folder de respaldo, no en el juego).
##
## Mide sobre la ciudad REAL (semilla 20260707) todo lo que se ha tocado en esta pasada:
##
##   · FAROLES: cuántos hay de cada clase, a qué distancia quedan del bordillo, si el brazo
##     mira a la calzada, si alguno ha caído dentro de un árbol/cantero y si llevan colisión.
##   · PUERTAS: cuántas quedan usables, dónde se para el ciudadano frente a ellas, si el
##     punto de parada está en la acera, libre de mobiliario y con acceso en la red.
##   · COLISIONES DE VEGETACIÓN: cuántos cilindros hay y pruebas de FÍSICA reales (rayos con
##     la máscara del jugador, 17) contra troncos y postes.
##   · POBLACIÓN: cuántos ciudadanos, cómo se reparten por sectores y por zonas.
##   · ENTRADAS EN CASAS: secuencia completa (camino → parada → giro → espera → dentro),
##     cuántas ocurren, que nunca se solapen dos en la misma puerta y que la población se
##     mantenga (nacimientos escalonados).
##   · NAVEGACIÓN: nadie clavado corriendo en el sitio, nadie sobre el asfalto fuera del paso
##     y nadie dentro del mobiliario.
##
## No escribe nada del juego: sólo mide e informa.

const SEMILLA := 20260707
const SIMULADO := 80.0        ## segundos de juego que se simulan (a 6x)

var _juego: Node
var _ciudad: Node
var _far: Node
var _dir: Node
var _t_arranque := 0
var _listo := false
var _t_inicio := 0.0
var _entradas_vistas := 0
var _peor_clavado := 0.0
var _clavado_actual := 0.0
var _sitio_clavado := ""
var _mobiliario := 0
var _mobiliario_peor := 0.0
var _puertas_en_uso: Dictionary = {}      ## ref de puerta -> cuántos ciudadanos la usan ahora
var _solapes := 0
var _secuencias: Dictionary = {}          ## id de ciudadano -> {"fases": [], "t": float}
var _completadas := 0
var _abandonadas := 0
var _error_yaw: Array[float] = []
var _dist_pie: Array[float] = []
var _vel_min_en_puerta := 1e9
var _sondas_fisica := 0
var _sondas_fisica_ok := 0
var _terminado := false


func _ready() -> void:
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = SEMILLA
	_far = _juego.get_node_or_null("Farolas")
	add_child(_juego)
	_t_arranque = Time.get_ticks_msec()
	get_tree().create_timer(230.0).timeout.connect(func() -> void:
		if _terminado:
			return
		print("[sonda] RESCATE: se agotó el tiempo")
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
			print("[sonda] la ciudad no se cerró a tiempo (¿error?)")
			break
	_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
	print("[sonda] ciudad lista en %.1f s reales" % (float(Time.get_ticks_msec() - _t_arranque) / 1000.0))
	await _esperar(3.0)
	_informe_estatico()
	await _esperar(2.0)
	# --- Simulación acelerada ---
	if _dir != null:
		_dir.set("auditoria", true)
	Engine.time_scale = 6.0
	_listo = true
	_t_inicio = _ahora()
	print("[sonda] --- simulando %.0f s de juego a 6x ---" % SIMULADO)
	while _ahora() - _t_inicio < SIMULADO:
		await _esperar(4.0)
		if _dir != null:
			var r: Dictionary = _dir.call("resumen")
			print("   t=%.0fs total=%d caminando=%d sentados=%d tumbados=%d | entrando=%d entradas=%d nacidos=%d pendientes=%d | puertas libres=%d/%d | entrando_a_puerta=%d | clavados=%d bloqueados=%d viol=%d" % [
					_ahora() - _t_inicio, r.get("total", 0), r.get("caminando", 0), r.get("sentados", 0),
					r.get("tumbados", 0), r.get("entrando", 0), r.get("entradas", 0),
					r.get("nacimientos", 0), r.get("pendientes", 0), r.get("puertas_libres", 0),
					r.get("puertas", 0), r.get("yendo_a_puerta", 0), r.get("clavados", 0),
					r.get("bloqueados", 0), r.get("violaciones", 0)])
	Engine.time_scale = 1.0
	_listo = false
	await _esperar(1.0)
	_informe_dinamico()
	_terminado = true
	get_tree().quit()


func _ahora() -> float:
	return float(Time.get_ticks_msec() - _t_arranque) / 1000.0


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


# =====================================================================================
#  Informe estático (geometría y configuración)
# =====================================================================================
func _informe_estatico() -> void:
	print("\n===== 1) FAROLES =====")
	var est: Dictionary = _ciudad.get("_est")
	if _far == null:
		print("  (no hay nodo Farolas en la escena)")
	else:
		print("  colocadas: acera=%s esquina=%s parque/plaza=%s | movidas por mobiliario=%s descartadas=%s" % [
				_far.get("_n_acera"), _far.get("_n_esquina"), _far.get("_n_parque"),
				_far.get("_movidas"), _far.get("_descartadas")])
		var metal := _far.get_node_or_null("FarolasMetal") as MultiMeshInstance3D
		var col := _far.get_node_or_null("FarolasColision") as StaticBody3D
		print("  colisión propia: %s (%d formas, capa %s)" % [
				"OK" if col != null else "FALTA",
				col.get_child_count() if col != null else 0,
				col.collision_layer if col != null else "-"])
		if metal != null and metal.multimesh != null:
			var mm: MultiMesh = metal.multimesh
			var tra: Dictionary = _ciudad.get("_trazado")
			var x0: float = float(tra["off"].x)
			var z0: float = float(tra["off"].y)
			var paso: float = float(tra["paso"])
			var obs: Array = _ciudad.get("_obstaculos_peatones")
			var mal_brazo := 0
			var cerca := 0
			var d_min_obs := 1e9
			var por_clase := {"acera": 0, "esquina": 0, "otro": 0}
			var d_borde: Array[float] = []
			for i in mm.instance_count:
				var t: Transform3D = mm.get_instance_transform(i)
				var kx := roundf((t.origin.x - x0) / paso)
				var xl: float = x0 + kx * paso
				var kz := roundf((t.origin.z - z0) / paso)
				var zl: float = z0 + kz * paso
				var dx := absf(t.origin.x - xl)
				var dz := absf(t.origin.z - zl)
				var hacia: Vector3
				var d_calle := minf(dx, dz)
				if dx < dz:
					hacia = Vector3(signf(xl - t.origin.x), 0.0, 0.0)
				else:
					hacia = Vector3(0.0, 0.0, signf(zl - t.origin.z))
				var brazo := t.basis * Vector3(1.0, 0.0, 0.0)
				brazo.y = 0.0
				if brazo.length_squared() > 0.0001:
					brazo = brazo.normalized()
				if brazo.dot(hacia) < 0.9:
					mal_brazo += 1
				# Clase de la farola por su sitio
				if absf(d_calle - 6.45) < 0.06:
					por_clase["acera"] += 1
					d_borde.append(d_calle)
				elif absf(dx - 6.85) < 0.06 and absf(dz - 6.85) < 0.06:
					por_clase["esquina"] += 1
				else:
					por_clase["otro"] += 1
				# Distancia al mobiliario (círculos del generador)
				for o: Dictionary in obs:
					var d := Vector2(float(o["x"]) - t.origin.x, float(o["z"]) - t.origin.z).length()
					var libre := d - float(o["r"])
					d_min_obs = minf(d_min_obs, libre)
				if d_calle < 6.0:
					cerca += 1
			print("  instancias: %d | por clase: acera %d · esquina %d · otro %d" % [
					mm.instance_count, por_clase["acera"], por_clase["esquina"], por_clase["otro"]])
			print("  brazo que NO mira a la calzada: %d  (de %d)" % [mal_brazo, mm.instance_count])
			print("  sobre la calzada (a <6 m del eje): %d | holgura mínima al mobiliario: %.2f m" % [
					cerca, d_min_obs if d_min_obs < 1e8 else -1.0])
			if not d_borde.is_empty():
				d_borde.sort()
				print("  distancia de las farolas de acera al eje del vial: min=%.2f med=%.2f max=%.2f (bordillo a 6.00)" % [
						d_borde[0], d_borde[d_borde.size() / 2], d_borde[d_borde.size() - 1]])

	print("\n===== 2) PUERTAS =====")
	var portales: Array = _ciudad.get("prueba_portales")
	var frentes: Array = _ciudad.get("prueba_portales_frente")
	print("  portales del generador: %d | con frente medido: %d" % [portales.size(), frentes.size()])
	if not frentes.is_empty():
		var f := Array(frentes)
		f.sort()
		print("  frente del marco (m por delante del plano): min=%.2f med=%.2f max=%.2f" % [
				f[0], f[f.size() / 2], f[f.size() - 1]])
	if _dir != null:
		var ps: Array = _dir.get("_portales")
		print("  usables por el director: %d" % ps.size())
		var d_nodo: Array[float] = []
		var d_hueco: Array[float] = []
		var malas := 0
		for p: Dictionary in ps:
			var pie: Vector3 = p["pie"]
			var nodo := int(p["nodo"])
			d_nodo.append(Vector2(pie.x - (_dir.get("red").pos(nodo) as Vector3).x,
					pie.z - (_dir.get("red").pos(nodo) as Vector3).z).length())
			if (_dir.get("red") as RedPeatonal).es_calzada(pie):
				malas += 1
			var libre := 1e9
			for o: Dictionary in _ciudad.get("_obstaculos_peatones"):
				var d := Vector2(float(o["x"]) - pie.x, float(o["z"]) - pie.z).length() - float(o["r"])
				libre = minf(libre, d)
			d_hueco.append(libre)
		if not d_nodo.is_empty():
			d_nodo.sort()
			d_hueco.sort()
			print("  punto de parada -> nodo de la red: min=%.2f med=%.2f max=%.2f m" % [
					d_nodo[0], d_nodo[d_nodo.size() / 2], d_nodo[d_nodo.size() - 1]])
			print("  punto de parada -> mobiliario más cercano: min=%.2f med=%.2f m | sobre la calzada: %d" % [
					d_hueco[0], d_hueco[d_hueco.size() / 2], malas])

	print("\n===== 3) COLISIONES DE VEGETACIÓN =====")
	var veg := _juego.get_node_or_null("CiudadGenerada/Vegetacion")
	var cuerpo := veg.get_node_or_null("ColisionesVegetacion") as StaticBody3D if veg != null else null
	if cuerpo == null:
		print("  FALTA el cuerpo de colisiones de vegetación")
	else:
		print("  %d cilindros | capa %d | máscara %d" % [
				cuerpo.get_child_count(), cuerpo.collision_layer, cuerpo.collision_mask])
		print("  obstáculos para peatones (círculos): %d" % (_dir.get("_obstaculos") as Array).size() if _dir != null else "")


# =====================================================================================
#  Sondas de FÍSICA (con la máscara del jugador: capas 1 y 5)
# =====================================================================================
func _sondas_de_fisica() -> void:
	var veg := _juego.get_node_or_null("CiudadGenerada/Vegetacion")
	var cuerpo := veg.get_node_or_null("ColisionesVegetacion") as StaticBody3D if veg != null else null
	if cuerpo == null:
		return
	var espacio := get_viewport().world_3d.direct_space_state if get_viewport() != null else null
	if espacio == null:
		print("  (sin servidor de física: no se pueden hacer las sondas)")
		return
	var formas: Array = cuerpo.get_children()
	var paso: int = maxi(1, formas.size() / 30)
	var alturas := [1.2]
	for i in range(0, formas.size(), paso):
		var cs := formas[i] as CollisionShape3D
		if cs == null:
			continue
		var p: Vector3 = cuerpo.global_position + cs.position
		for h: float in alturas:
			var desde := p + Vector3(0.0, h, 0.0) + Vector3(3.0, 0.0, 0.0)
			var hasta := p + Vector3(0.0, h, 0.0)
			var q := PhysicsRayQueryParameters3D.create(desde, hasta)
			q.collision_mask = 17
			q.collide_with_bodies = true
			var hit := espacio.intersect_ray(q)
			_sondas_fisica += 1
			if not hit.is_empty():
				_sondas_fisica_ok += 1
	print("  sondas de física contra troncos/canteros (máscara 17): %d aciertos de %d" % [
			_sondas_fisica_ok, _sondas_fisica])


func _sondas_de_farolas() -> void:
	if _far == null:
		return
	var metal := _far.get_node_or_null("FarolasMetal") as MultiMeshInstance3D
	if metal == null or metal.multimesh == null:
		return
	var espacio := get_viewport().world_3d.direct_space_state if get_viewport() != null else null
	if espacio == null:
		return
	var mm: MultiMesh = metal.multimesh
	var paso: int = maxi(1, mm.instance_count / 20)
	var ok := 0
	var n := 0
	for i in range(0, mm.instance_count, paso):
		var p: Vector3 = _far.global_position + mm.get_instance_transform(i).origin
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(2.5, 1.5, 0.0), p + Vector3(0.0, 1.5, 0.0))
		q.collision_mask = 17
		var hit := espacio.intersect_ray(q)
		n += 1
		if not hit.is_empty():
			ok += 1
	print("  sondas de física contra postes de farola (máscara 17): %d aciertos de %d" % [ok, n])


# =====================================================================================
#  Vigilancia por fotograma durante la simulación
# =====================================================================================
func _process(delta: float) -> void:
	if not _listo or _dir == null or delta <= 0.0:
		return
	var peatones: Array = _dir.get("peatones")
	var obs: Array = _dir.get("_obstaculos")
	var en_uso := {}
	var clavados_ahora := 0
	for c in peatones:
		if not is_instance_valid(c):
			continue
		# --- Clavado andando: acumula tiempo con la animación de caminar y sin moverse ---
		if c.is_walking() and c.velocidad_real() < c.walk_speed * 0.2:
			clavados_ahora += 1
			_clavado_actual += delta
			if _clavado_actual > _peor_clavado:
				_peor_clavado = _clavado_actual
				_sitio_clavado = "%.1f,%.1f (bloqueos=%d)" % [c.global_position.x, c.global_position.z, 1]
		else:
			_clavado_actual = 0.0
		# --- Dentro de mobiliario andando (sin estar sentado/tumbado/entrando) ---
		if c.is_walking():
			var p: Vector3 = c.global_position
			var peor := 1e9
			for o: Dictionary in obs:
				var d := Vector2(float(o["x"]) - p.x, float(o["z"]) - p.z).length() - float(o["r"]) - 0.35
				peor = minf(peor, d)
			if peor < 0.0:
				_mobiliario += 1
				_mobiliario_peor = minf(_mobiliario_peor, peor)
		# --- Secuencia de entrada en una casa ---
		if c.en_postura() and c.postura_actual() == "entrar":
			var id: int = c.get_instance_id()
			if not _secuencias.has(id):
				_secuencias[id] = {"fases": [], "t": 0.0}
			var s: Dictionary = _secuencias[id]
			var fase := String(c.fase_postura())
			var fases: Array = s["fases"]
			if fases.is_empty() or String(fases[fases.size() - 1]) != fase:
				fases.append(fase)
			s["t"] = float(s["t"]) + delta
			# Comprobaciones de la fase frente a la puerta
			if fase == "mirar" or fase == "penetrar":
				var ref := int(c.get("_postura_ref"))
				en_uso[ref] = int(en_uso.get(ref, 0)) + 1
				if fase == "mirar":
					var yaw_obj: float = float(c.get("_postura_yaw"))
					var err := rad_to_deg(absf(wrapf(yaw_obj - c.rotation.y, -PI, PI)))
					_error_yaw.append(err)
					var objetivo: Vector3 = c.get("_postura_punto_ini")
					var d := Vector2(objetivo.x - c.global_position.x, objetivo.z - c.global_position.z).length()
					_dist_pie.append(d) if d < 1.0 else _dist_pie.append(d)
	# Solapes de puerta + secuencias cerradas
	for ref: int in en_uso.keys():
		if int(en_uso[ref]) > 1:
			_solapes += 1
			print("   [AVISO] dos ciudadanos usando la puerta %d a la vez" % ref)
	for id2 in _secuencias.keys():
		var vive := false
		for c2 in peatones:
			if is_instance_valid(c2) and c2.get_instance_id() == id2:
				vive = true
				break
		if not vive:
			var s2: Dictionary = _secuencias[id2]
			var fas: Array = s2["fases"]
			if fas.has("penetrar"):
				_completadas += 1
			else:
				_abandonadas += 1
			_secuencias.erase(id2)


func _informe_dinamico() -> void:
	print("\n===== 4) POBLACIÓN Y NAVEGACIÓN (tras %.0f s de juego) =====" % SIMULADO)
	if _dir != null:
		var r: Dictionary = _dir.call("resumen")
		print("  ciudadanos vivos: %d (creados %d, pendientes %d)" % [
				r.get("total", 0), r.get("nacimientos", 0), r.get("pendientes", 0)])
		print("  caminando %d · sentados %d · tumbados %d · yendo a postura %d · yendo a puerta %d" % [
				r.get("caminando", 0), r.get("sentados", 0), r.get("tumbados", 0),
				r.get("yendo_a_postura", 0), r.get("yendo_a_puerta", 0)])
		var censo: Dictionary = _sector_censo(_dir.get("_sector_censo"))
		print("  sectores con gente: %s" % str(censo))
		print("  violaciones de calzada (auditoría): %d" % r.get("violaciones", 0))
	print("  peor tiempo 'caminando sin moverse': %.2f s (%s)" % [_peor_clavado, _sitio_clavado])
	print("  ciudadanos dentro de mobiliario andando: %d fotogramas (peor holgura %.2f m)" % [
			_mobiliario, _mobiliario_peor if _mobiliario > 0 else 0.0])
	print("\n===== 5) ENTRADAS EN CASAS =====")
	print("  secuencias completas (llegaron a 'penetrar'): %d | abandonadas: %d | en curso: %d" % [
			_completadas, _abandonadas, _secuencias.size()])
	print("  solapes de dos ciudadanos en la misma puerta: %d" % _solapes)
	if not _error_yaw.is_empty():
		var e := _error_yaw.duplicate()
		e.sort()
		print("  error de giro frente a la puerta: med=%.1f° peor=%.1f° (n=%d)" % [
				e[e.size() / 2], e[e.size() - 1], e.size()])
	if not _dist_pie.is_empty():
		var d2 := _dist_pie.duplicate()
		d2.sort()
		print("  distancia al punto de parada al llegar: med=%.2f m peor=%.2f m" % [
				d2[d2.size() / 2], d2[d2.size() - 1]])
	_sondas_de_fisica()
	_sondas_de_farolas()


func _sector_censo(censo: Dictionary) -> Dictionary:
	var con_gente := 0
	var vacios := 0
	var minimo := 1e9
	var maximo := 0
	for clave: String in censo.keys():
		var n := int(censo[clave])
		if n > 0:
			con_gente += 1
		else:
			vacios += 1
		minimo = minf(minimo, n)
		maximo = maxi(maximo, n)
	return {"sectores": censo.size(), "con_gente": con_gente, "vacios": vacios,
			"min": minimo if minimo < 1e8 else 0, "max": maximo}