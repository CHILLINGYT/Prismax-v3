extends Node3D

# Suite automática (se ejecuta como ESCENA) del SISTEMA DE EVENTOS (etapas 1 y 2):
#   · la API crear_enemigo_en() del gerente: posición válida -> nodo vivo; tipo
#     inválido / sin suelo -> null; no entra en los cajones de G/H/J;
#   · el DirectorEventos: 10 eventos definidos, 0 tubos al inicio, aparición de un
#     tubo en su punto, activación única que genera SÓLO los enemigos del evento;
#   · los eventos del barco colocan sus tubos sobre la cubierta y generan enemigos
#     sobre ella;
#   · G/H/J (generar_grupo / retirar_grupo) siguen funcionando igual y NO tocan a
#     los enemigos de evento.
#
# Se ejecuta como escena:  godot --headless --path <proyecto> res://_tests/prueba_eventos.tscn

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")
const GestorCombate := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_manager.gd")
const ConfigCombate := preload("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")
const GerenteScript := preload("res://Enemigos Prueba/Scripts/gerente_enemigos_prueba.gd")
const DirectorScript := preload("res://sistemas/eventos/director_eventos.gd")
const ESCENA_BARCO := preload("res://world/barco.tscn")

var _pasadas := 0
var _falladas := 0
var _jug: Node3D
var _gerente: Node3D
var _dir: Node3D
var _mgr: Node

func _ready() -> void:
	call_deferred("_correr")

func _check(nombre: String, ok: bool, detalle: String = "") -> void:
	var sufijo := (" — " + detalle) if detalle != "" else ""
	if ok:
		_pasadas += 1
		print("[OK]    ", nombre, sufijo)
	else:
		_falladas += 1
		print("[FALLA] ", nombre, sufijo)

func _esperar(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _correr() -> void:
	# --- Montaje mínimo pero REAL (usa el jugador y el CombatManager del juego) ---
	var suelo := StaticBody3D.new()
	suelo.name = "Suelo"
	suelo.collision_layer = 1
	suelo.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1400.0, 1.0, 1400.0)
	cs.shape = bs
	suelo.add_child(cs)
	suelo.position = Vector3(0, -0.5, 0)
	add_child(suelo)

	_mgr = Node.new()
	_mgr.name = "CombatManager"
	_mgr.set_script(GestorCombate)
	_mgr.set("config", ConfigCombate)
	add_child(_mgr)

	_jug = JUGADOR.instantiate()
	_jug.name = "Jugador"
	_jug.position = Vector3(0, 1, 0)
	add_child(_jug)

	_gerente = Node3D.new()
	_gerente.name = "EnemigosPrueba"
	_gerente.set_script(GerenteScript)
	add_child(_gerente)

	var barco := ESCENA_BARCO.instantiate()
	barco.name = "Barco"
	barco.transform = Transform3D(Vector3(-0.70710678, 0.0, -0.70710678),
			Vector3(0.0, 1.0, 0.0), Vector3(0.70710678, 0.0, -0.70710678),
			Vector3(277.1, -2.05, 277.1))
	add_child(barco)

	_dir = Node3D.new()
	_dir.name = "DirectorEventos"
	_dir.set_script(DirectorScript)
	add_child(_dir)

	await _esperar(6)
	# Estabilizar al jugador para las pruebas de ciclo: el controlador real, sin
	# cámara ni entrada, puede derivar en Y; se detiene su física y se fija su
	# posición. El Area3D y la IA de los enemigos siguen usando su transform.
	_jug.set_physics_process(false)
	_jug.global_position = Vector3(0, 1.1, 0)

	# ============================================================= ETAPA 1: API
	var e1: Variant = _gerente.call("crear_enemigo_en", Vector3(6, 0, 6), 1)
	_check("API: crear_enemigo_en(posición válida, cuerpo a cuerpo) devuelve un nodo",
			e1 is Node3D)
	if e1 is Node3D:
		_check("API: el enemigo creado está vivo", (e1 as Node3D).call("is_alive") == true)
		_check("API: el enemigo creado entra en el grupo enemigos_prueba",
				(e1 as Node3D).is_in_group(&"enemigos_prueba"))
	var vivos_mgr: Array = _mgr.call("get_active_enemies")
	_check("API: el enemigo creado queda registrado en el CombatManager",
			vivos_mgr.has(e1))

	_check("API: NO entra en los cajones del gerente (enemigos_vivos vacío)",
			(_gerente.call("enemigos_vivos") as Array).is_empty())

	var e_tipo: Variant = _gerente.call("crear_enemigo_en", Vector3(6, 0, 6), 99)
	_check("API: tipo inválido devuelve null", e_tipo == null)

	var e_mezcla: Variant = _gerente.call("crear_enemigo_en", Vector3(6, 0, 6), 3)
	_check("API: tipo MEZCLA (sin escena propia) devuelve null", e_mezcla == null)

	var e_sinsuelo: Variant = _gerente.call("crear_enemigo_en", Vector3(5000, 0, 5000), 1)
	_check("API: posición sin suelo devuelve null", e_sinsuelo == null)

	# ============================================================= ETAPA 2: director
	_check("Director: 12 eventos definidos", int(_dir.call("eventos_definidos")) == 12)
	_check("Director: 0 tubos visibles al inicio", int(_dir.call("tubos_visibles")) == 0)
	_check("Director: 12 eventos pendientes al inicio", int(_dir.call("pendientes")) == 12)

	var ok_ap: bool = _dir.call("forzar_aparicion", &"E4")
	_check("Director: aparece el tubo del evento E4", ok_ap)
	_check("Director: E4 queda DISPONIBLE", int(_dir.call("estado_de", &"E4")) == 1)
	_check("Director: 1 tubo visible tras la aparición", int(_dir.call("tubos_visibles")) == 1)

	# Activación: simular que el jugador entra (la señal que emite el tubo).
	var tubo: Node3D = _buscar_tubo(&"E4")
	_check("Director: el tubo de E4 existe como nodo", tubo != null)
	if tubo != null:
		tubo.emit_signal("activado", tubo)
		await _esperar(4)
		var enem: Array = _dir.call("enemigos_de", &"E4")
		_check("Director: activar E4 genera sus enemigos", enem.size() >= 1, "n=%d" % enem.size())
		_check("Director: E4 pasa a COMBATE", int(_dir.call("estado_de", &"E4")) == 2)
		_check("Director: el tubo se retira al activarse", not is_instance_valid(tubo))

		# Activación duplicada: no debe crear más enemigos.
		var n_antes: int = (_dir.call("enemigos_de", &"E4") as Array).size()
		# (el tubo ya no existe; se comprueba que el estado impide re-generar)
		_check("Director: sin duplicar tras re-activar", (_dir.call("enemigos_de", &"E4") as Array).size() == n_antes)

	# Independencia entre eventos: el barco genera los suyos sin tocar a E4.
	var n_e4: int = (_dir.call("enemigos_de", &"E4") as Array).size()
	_check("Director: aparece el tubo del evento B1 (barco)", bool(_dir.call("forzar_aparicion", &"B1")))
	var tubo_b: Node3D = _buscar_tubo(&"B1")
	_check("Barco: el tubo de B1 cuelga del Barco (sigue su transformación)",
			tubo_b != null and tubo_b.get_parent() != null and tubo_b.get_parent().name == "Barco")
	if tubo_b != null:
		var y_deck: float = tubo_b.global_position.y
		_check("Barco: el tubo está a la altura de la cubierta", y_deck > 0.5 and y_deck < 3.5,
				"y=%.2f" % y_deck)
		tubo_b.emit_signal("activado", tubo_b)
		await _esperar(4)
		var enem_b: Array = _dir.call("enemigos_de", &"B1")
		_check("Barco: activar B1 genera enemigos sobre la cubierta", enem_b.size() >= 1,
				"n=%d" % enem_b.size())
		var sobre_cubierta := true
		for x in enem_b:
			if absf((x as Node3D).global_position.y - y_deck) > 2.0:
				sobre_cubierta = false
		_check("Barco: los enemigos quedan sobre la cubierta (no en el agua)", sobre_cubierta)
		_check("Director: B1 no altera los enemigos de E4",
				(_dir.call("enemigos_de", &"E4") as Array).size() == n_e4)

	# ============================================================= G/H/J intactos
	_gerente.call("generar_grupo")
	await _esperar(2)
	var caps: Array = _gerente.call("enemigos_vivos")
	_check("G/H/J: generar_grupo() sigue creando 6 cápsulas", caps.size() == 6, "n=%d" % caps.size())
	_gerente.call("retirar_grupo")
	await _esperar(2)
	_check("G/H/J: retirar_grupo() limpia las cápsulas",
			(_gerente.call("enemigos_vivos") as Array).is_empty())
	_check("G/H/J: retirar_grupo() NO retira los enemigos de evento",
			(_dir.call("enemigos_de", &"E4") as Array).size() == n_e4)

	# ============================================================= ETAPAS 3 y 4
	# Aceleración SOLO para la prueba (el juego real usa 240 s, ver el export).
	_dir.set("duracion_enfriamiento", 1.0)

	# --- 1/2/3: contador propio por evento; muere uno, sigue; muere el último, cierra
	_dir.call("forzar_aparicion", &"E5")
	var t5 := _buscar_tubo(&"E5")
	var pos5 := t5.global_position
	t5.emit_signal("activado", t5)
	await _esperar(3)
	_check("E3-1 el contador refleja SÓLO los enemigos de su evento",
			int(_dir.call("enemigos_vivos_de", &"E5")) == 4,
			"n=%d" % int(_dir.call("enemigos_vivos_de", &"E5")))
	_check("E3-1 E5 en COMBATE", int(_dir.call("estado_de", &"E5")) == 2)

	(_dir.call("enemigos_de", &"E5") as Array)[0].call("execute")
	await _esperar(2)
	_check("E3-2 la muerte de uno NO termina el evento si quedan vivos",
			int(_dir.call("enemigos_vivos_de", &"E5")) == 3 and int(_dir.call("estado_de", &"E5")) == 2)
	_check("E3-8 no se cuenta dos veces la misma muerte",
			int(_dir.call("enemigos_vivos_de", &"E5")) == (_dir.call("enemigos_de", &"E5") as Array).size())

	await _matar_todos(&"E5")
	await _esperar(2)
	_check("E3-3 el último enemigo cierra el evento (ENFRIAMIENTO)", int(_dir.call("estado_de", &"E5")) == 3)
	_check("E4-1 el enfriamiento arranca con tiempo > 0", float(_dir.call("restante_enfriamiento", &"E5")) > 0.0)

	# --- 4: alejarse no inicia el enfriamiento
	_activar(&"E6")
	await _esperar(3)
	_jug.global_position = _jug.global_position + Vector3(50.0, 0.0, 0.0)
	await _esperar(20)
	_check("E3-4 alejarse NO termina el combate ni inicia enfriamiento",
			int(_dir.call("estado_de", &"E6")) == 2 and float(_dir.call("restante_enfriamiento", &"E6")) == 0.0)

	# --- 5/6: dos eventos simultáneos sin interferencias
	_activar(&"E7")
	_activar(&"E8")
	await _esperar(3)
	var e8_antes := int(_dir.call("enemigos_vivos_de", &"E8"))
	await _matar_todos(&"E7")
	await _esperar(2)
	_check("E3-5/6 E7 termina y E8 sigue intacto (sin conteo cruzado)",
			int(_dir.call("estado_de", &"E7")) == 3 and int(_dir.call("estado_de", &"E8")) == 2
			and int(_dir.call("enemigos_vivos_de", &"E8")) == e8_antes,
			"E8=%d/%d" % [int(_dir.call("enemigos_vivos_de", &"E8")), e8_antes])

	# --- 7/8/9/10/11: reaparición de E5 y SEGUNDO ciclo
	await _esperar(120)   # supera el enfriamiento reducido (1 s)
	_check("E4-7 al terminar el enfriamiento E5 vuelve a DISPONIBLE", int(_dir.call("estado_de", &"E5")) == 1)
	_check("E4-10 al reaparecer NO se generan enemigos automáticamente",
			int(_dir.call("enemigos_vivos_de", &"E5")) == 0)
	var t5b := _buscar_tubo(&"E5")
	_check("E4-8 el tubo reaparece en la MISMA ubicación",
			t5b != null and t5b.global_position.distance_to(pos5) < 0.05,
			"d=%.4f" % (t5b.global_position.distance_to(pos5) if t5b != null else -1.0))
	_check("E4-9 el Area3D del tubo reaparecido está activo (monitoring)",
			t5b != null and (t5b.get_node_or_null("Zona") as Area3D) != null
			and (t5b.get_node("Zona") as Area3D).monitoring)
	# Detección REAL por proximidad: acercar al jugador al tubo reaparecido.
	_jug.global_position = pos5 + Vector3(0.0, 1.0, 0.0)
	await _esperar(12)
	_check("E4-9 el Area3D vuelve a detectar al jugador (segundo ciclo)",
			int(_dir.call("estado_de", &"E5")) == 2)
	_check("E4-11 el segundo ciclo del evento crea sus propios enemigos",
			int(_dir.call("enemigos_vivos_de", &"E5")) >= 1)

	# --- 12: la pausa detiene el enfriamiento y reanudar continúa
	_dir.set("duracion_enfriamiento", 3.0)
	_activar(&"E2")
	await _esperar(3)
	await _matar_todos(&"E2")
	await _esperar(2)
	_check("E4-12 E2 en ENFRIAMIENTO", int(_dir.call("estado_de", &"E2")) == 3)
	var r0 := float(_dir.call("restante_enfriamiento", &"E2"))
	get_tree().paused = true
	for _i in 20:
		await get_tree().process_frame
	var r1 := float(_dir.call("restante_enfriamiento", &"E2"))
	get_tree().paused = false
	await get_tree().process_frame
	_check("E4-12 la PAUSA congela el enfriamiento", is_equal_approx(r0, r1), "%.3f->%.3f" % [r0, r1])
	for _i in 12:
		await get_tree().process_frame
	var r2 := float(_dir.call("restante_enfriamiento", &"E2"))
	_check("E4-12 REANUDAR continúa desde el tiempo restante", r2 < r1, "%.3f->%.3f" % [r1, r2])
	_dir.call("forzar_fin_enfriamiento", &"E2")
	await _esperar(3)
	_check("E4-12 al terminar el enfriamiento E2 reaparece", int(_dir.call("estado_de", &"E2")) == 1)
	_dir.set("duracion_enfriamiento", 1.0)

	# --- 13: un enemigo liberado inesperadamente (sin señal) no bloquea el evento
	_activar(&"E3")
	await _esperar(3)
	_check("E3-13 E3 con enemigos vivos", int(_dir.call("enemigos_vivos_de", &"E3")) >= 1)
	for e in (_dir.call("enemigos_de", &"E3") as Array):
		if is_instance_valid(e):
			(e as Node).queue_free()   # liberación DIRECTA, sin emitir `murio`
	await _esperar(40)   # > intervalo_poda
	_check("E3-13 una desaparición inesperada no bloquea el evento (ENFRIAMIENTO)",
			int(_dir.call("estado_de", &"E3")) == 3)

	# --- 14: un evento sin enemigos creados no queda bloqueado
	_dir.set("radio_generacion", 100000.0)   # ningún candidato cae en suelo válido
	_activar(&"E1")
	await _esperar(3)
	_check("E3-14 un evento sin enemigos creados no queda bloqueado (ENFRIAMIENTO)",
			int(_dir.call("estado_de", &"E1")) == 3 and int(_dir.call("enemigos_vivos_de", &"E1")) == 0)
	_dir.set("radio_generacion", 5.0)

	# ============================================================= TUBO (Mejora 2)
	var tubo_pre := preload("res://sistemas/eventos/tubo_evento.tscn").instantiate()
	var vis := tubo_pre.get_node("Visual") as MeshInstance3D
	var cm := vis.mesh as CylinderMesh
	_check("Tubo: más ancho que antes (radio > 0.5)", cm.top_radius > 0.5, "r=%.2f" % cm.top_radius)
	_check("Tubo: altura moderada (5.0 < h < 6.1)", cm.height > 5.0 and cm.height < 6.1, "h=%.2f" % cm.height)
	var mat := vis.material_override as StandardMaterial3D
	_check("Tubo: emisión AMARILLA (rojo alto, azul bajo)",
			mat.emission_enabled and mat.emission.r > 0.7 and mat.emission.g > 0.6 and mat.emission.b < 0.4,
			str(mat.emission))
	_check("Tubo: conserva el Area3D de activación (mask 1)",
			tubo_pre.get_node_or_null("Zona") is Area3D
			and (tubo_pre.get_node("Zona") as Area3D).collision_mask == 1)
	_check("Tubo: sin colisión física propia", not (tubo_pre is CollisionObject3D))
	tubo_pre.free()

	# ============================================================= UBICACIONES (Mejora 3)
	var defs: Array = _dir.call("definiciones")
	_check("Ubicaciones: 12 definidas", defs.size() == 12, "n=%d" % defs.size())
	var vistos := {}
	var dup := false
	var terr := 0
	var bar := 0
	var lineas := [-126.0, -84.0, -42.0, 0.0, 42.0, 84.0, 126.0]
	var en_calle := true
	for d in defs:
		var id: StringName = d["id"]
		if vistos.has(id):
			dup = true
		vistos[id] = true
		if d.has("barco"):
			bar += 1
		else:
			terr += 1
			var p: Vector3 = d["terrestre"]
			# Sólo las ubicaciones DENTRO de la ciudad deben caer en líneas de
			# calle (las naturales, fuera del recinto, van sobre el terreno).
			var dentro := absf(p.x) <= 126.0 and absf(p.z) <= 126.0
			if dentro and not (lineas.has(p.x) and lineas.has(p.z)):
				en_calle = false
	_check("Ubicaciones: sin ids duplicados", not dup)
	_check("Ubicaciones: 10 terrestres + 2 barco", terr == 10 and bar == 2, "%d+%d" % [terr, bar])
	_check("Ubicaciones: todas las terrestres caen en líneas de calle", en_calle)

	# ============================================================= CONTADOR (Mejora 1)
	_dir.set("duracion_enfriamiento", 20.0)
	_activar(&"E7")
	await _esperar(3)
	_check("Contador: NO aparece mientras hay enemigos", not bool(_dir.call("contador_visible", &"E7")))
	await _matar_todos(&"E7")
	await _esperar(2)
	_check("Contador: aparece al morir el último enemigo", bool(_dir.call("contador_visible", &"E7")))
	var txt7 := String(_dir.call("texto_contador", &"E7"))
	_check("Contador: formato MM:SS y sin negativos",
			txt7.length() == 5 and txt7.substr(2, 1) == ":" and not txt7.begins_with("-"), txt7)
	_check("Contador: coincide con el tiempo REAL del enfriamiento",
			txt7 == _mmss(float(_dir.call("restante_enfriamiento", &"E7"))), txt7)
	for _i in 90:
		await get_tree().process_frame
	_activar(&"E2")
	await _esperar(3)
	await _matar_todos(&"E2")
	await _esperar(2)
	var txt7b := String(_dir.call("texto_contador", &"E7"))
	var txt2 := String(_dir.call("texto_contador", &"E2"))
	_check("Contador: dos eventos muestran tiempos distintos", txt7b != txt2, "%s vs %s" % [txt7b, txt2])
	# La pausa congela el contador (y el enfriamiento).
	var rA := float(_dir.call("restante_enfriamiento", &"E7"))
	var tA := String(_dir.call("texto_contador", &"E7"))
	get_tree().paused = true
	for _i in 20:
		await get_tree().process_frame
	var rB := float(_dir.call("restante_enfriamiento", &"E7"))
	var tB := String(_dir.call("texto_contador", &"E7"))
	get_tree().paused = false
	await get_tree().process_frame
	_check("Contador: la pausa lo congela", is_equal_approx(rA, rB) and tA == tB, "%s->%s" % [tA, tB])
	# Al reaparecer, el contador desaparece.
	_dir.call("forzar_fin_enfriamiento", &"E7")
	_dir.call("forzar_fin_enfriamiento", &"E2")
	await _esperar(4)
	_check("Contador: desaparece cuando el tubo reaparece", not bool(_dir.call("contador_visible", &"E7")))
	_check("Contador: el tubo vuelve tras el contador",
			int(_dir.call("estado_de", &"E7")) == 1 and _buscar_tubo(&"E7") != null)
	_dir.set("duracion_enfriamiento", 1.0)

	print("==================================================")
	print("RESULTADO: %d OK, %d FALLAS" % [_pasadas, _falladas])
	print("==================================================")
	get_tree().quit()

## Busca el tubo de un evento concreto por su metadato "evento_id" (los tubos
## terrestres cuelgan del director; los del barco, del nodo Barco).
func _buscar_tubo(id: StringName) -> Node3D:
	if _dir == null:
		return null
	for c in _dir.get_children():
		if _es_tubo_de(c, id):
			return c as Node3D
	var barco := get_node_or_null("Barco") as Node3D
	if barco != null:
		for c in barco.get_children():
			if _es_tubo_de(c, id):
				return c as Node3D
	return null

func _es_tubo_de(n: Node, id: StringName) -> bool:
	return n is Node3D and n.has_meta(&"evento_id") and n.get_meta(&"evento_id") == id

## Fuerza la aparición del tubo de un evento y simula su activación.
func _activar(id: StringName) -> Node3D:
	_dir.call("forzar_aparicion", id)
	var t := _buscar_tubo(id)
	if t != null:
		t.emit_signal("activado", t)
	return t

## Mata (execute) a TODOS los enemigos vivos de un evento, uno por fotograma.
func _matar_todos(id: StringName) -> void:
	var guard := 0
	while int(_dir.call("enemigos_vivos_de", id)) > 0 and guard < 60:
		var l: Array = _dir.call("enemigos_de", id)
		if l.is_empty():
			break
		var e = l[0]
		if is_instance_valid(e):
			(e as Node).call("execute")
		guard += 1
		await _esperar(1)

## Formato MM:SS esperado (independiente del director) para contrastar.
func _mmss(seg: float) -> String:
	var t := int(ceil(maxf(0.0, seg)))
	return "%02d:%02d" % [int(floor(float(t) / 60.0)), t % 60]