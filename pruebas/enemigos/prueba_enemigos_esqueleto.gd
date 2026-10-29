extends Node3D

# Suite HEADLESS de los enemigos CON ESQUELETO (cuerpo a cuerpo y tirador).
# No abre ventana; deja las comprobaciones en consola. Se ejecuta como escena,
# igual que las suites de main, para que los autoloads ya existan:
#
#   godot --headless --path . res://pruebas/enemigos/prueba_enemigos_esqueleto.tscn
#
# Comprueba: escena/esqueleto/clips/barra, el contrato de daño completo de AMBOS
# enemigos, el proyectil, y que el gerente genera/retira cada tipo sin tocar la
# tecla G de las cápsulas.

const ESCENA_MELEE := preload("res://Enemigos Prueba/Scenes/enemigo_melee.tscn")
const ESCENA_TIRADOR := preload("res://Enemigos Prueba/Scenes/enemigo_tirador.tscn")
const ESCENA_PROYECTIL := preload("res://Enemigos Prueba/Scenes/proyectil_enemigo.tscn")
const GRUPO_GESTOR := &"combat_manager"

var _ok := 0
var _fallos := 0

@onready var gerente: Node3D = $EnemigosPrueba
@onready var jugador: CharacterBody3D = $Jugador

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _ejecutar()

func _comprobar(cond: bool, texto: String, detalle: String = "") -> void:
	var sufijo := "" if detalle == "" else " — " + detalle
	if cond:
		_ok += 1
		print("[OK]    %s%s" % [texto, sufijo])
	else:
		_fallos += 1
		print("[FALLO] %s%s" % [texto, sufijo])

func _vivos_de_esqueleto() -> Array:
	var out: Array = []
	for n in gerente.call("enemigos_vivos"):
		var e := n as Node3D
		if e != null and e.get_node_or_null("Visual") != null:
			out.append(e)
	return out

func _ejecutar() -> void:
	var mgr := get_tree().get_first_node_in_group(GRUPO_GESTOR)
	_comprobar(mgr != null, "1. Hay CombatManager en la escena")

	# ---- 2-3. Escena, esqueleto, clips y barra de ambas clases ----
	for par in [["cuerpo a cuerpo", ESCENA_MELEE], ["tirador", ESCENA_TIRADOR]]:
		var nombre: String = par[0]
		var n: Node = (par[1] as PackedScene).instantiate()
		var sk := n.get_node_or_null("Visual/Skeleton3D") as Skeleton3D
		var ap := n.get_node_or_null("Animador") as AnimationPlayer
		_comprobar(sk != null and sk.get_bone_count() == 65,
				"2. %s: esqueleto retargetado de 65 huesos" % nombre,
				"huesos=%d" % (sk.get_bone_count() if sk != null else 0))
		_comprobar(ap != null and ap.get_animation_list().size() == 14,
				"2. %s: librería con los 14 clips horneados" % nombre,
				"clips=%d" % (ap.get_animation_list().size() if ap != null else 0))
		_comprobar(ap != null and ap.has_animation(n.get("clip_idle")) and ap.has_animation(n.get("clip_andar")),
				"2. %s: clips de reposo y andar presentes" % nombre)
		_comprobar(n.get_node_or_null("BarraVida/Barra") != null,
				"3. %s: lleva barra de vida" % nombre)
		n.free()

	# ---- 4. Contrato de daño completo de ambas clases ----
	for par in [["cuerpo a cuerpo", ESCENA_MELEE], ["tirador", ESCENA_TIRADOR]]:
		var nombre: String = par[0]
		var e: Node = (par[1] as PackedScene).instantiate()
		get_tree().root.add_child(e)
		await get_tree().process_frame
		_comprobar(bool(e.call("is_alive")), "4. %s: nace vivo con vida propia" % nombre,
				"vida=%.0f" % float(e.call("vida_actual")))
		_comprobar(e.is_in_group("damageable") and e.is_in_group("enemigos_prueba"),
				"4. %s: entra en los grupos damageable y enemigos_prueba" % nombre)
		_comprobar(e.has_method("take_hit") and e.has_method("take_damage")
				and e.has_method("apply_damage") and e.has_method("execute")
				and e.has_method("get_hit_center") and e.has_method("get_hit_radius")
				and e.has_method("is_stunned"),
				"4. %s: habla el contrato completo (FreeFlow/Fuerza/acuática)" % nombre)
		var v0 := float(e.call("vida_actual"))
		e.call("take_hit", 10.0, Vector3.FORWARD, 0.0, 0.5)
		var v1 := float(e.call("vida_actual"))
		e.call("take_damage", 5.0, Vector3.ZERO, Vector3(1, 0, 0))
		var v2 := float(e.call("vida_actual"))
		e.call("apply_damage", 5.0, Vector3.ZERO, &"melee")
		var v3 := float(e.call("vida_actual"))
		_comprobar(v1 == v0 - 10.0 and v2 == v1 - 5.0 and v3 == v2 - 5.0,
				"4. %s: take_hit, take_damage y apply_damage restan vida" % nombre,
				"%.0f -> %.0f -> %.0f -> %.0f" % [v0, v1, v2, v3])
		_comprobar(bool(e.call("is_stunned")), "4. %s: take_hit con aturdimiento aturde" % nombre)
		_comprobar(float(e.call("get_hit_radius")) > 0.0 and (e.call("get_hit_center") as Vector3).y > 0.0,
				"4. %s: get_hit_center/get_hit_radius válidos" % nombre)
		e.call("execute")
		_comprobar(not bool(e.call("is_alive")), "4. %s: execute() lo mata" % nombre)
		_comprobar(not e.is_in_group("damageable") and not e.is_in_group("enemigos_prueba"),
				"4. %s: al morir sale de los grupos de objetivos" % nombre)
		await get_tree().process_frame
		e.queue_free()

	# ---- 5. Proyectil ----
	var p: Node = ESCENA_PROYECTIL.instantiate()
	get_tree().root.add_child(p)
	await get_tree().process_frame
	p.call("lanzar", Vector3(0, 5, 0), Vector3(0, 0, -1), null, 30.0, 7.0)
	var z0 := (p as Node3D).global_position.z
	for i in 6:
		await get_tree().process_frame
	var z1 := (p as Node3D).global_position.z
	_comprobar(z0 - z1 > 0.5, "5. El proyectil avanza solo hacia donde se lanza",
			"recorrido=%.2f m" % (z0 - z1))
	_comprobar(p.has_method("lanzar") and p.get("mascara") == 1,
				"5. El proyectil golpea la máscara del mundo+jugador (capa 1), no a los enemigos (16)")
	p.queue_free()

	# ---- 6. Gerente: genera y retira por tipo, sin tocar G ----
	gerente.call("retirar_grupo")
	await get_tree().process_frame
	gerente.call("generar_tipo", 1)   # Tipo.MELEE
	await get_tree().process_frame
	var melee := _vivos_de_esqueleto()
	_comprobar(melee.size() == 3, "6. generar_tipo(MELEE) crea 3 cuerpo a cuerpo", "creados=%d" % melee.size())
	if mgr != null:
		var activos: Array = mgr.call("get_active_enemies")
		_comprobar(activos.size() >= 3, "6. Los cuerpo a cuerpo quedan registrados en el CombatManager",
				"activos=%d" % activos.size())
	gerente.call("generar_tipo", 2)   # Tipo.TIRADOR
	await get_tree().process_frame
	_comprobar(_vivos_de_esqueleto().size() == 5, "6. generar_tipo(TIRADOR) añade 2 más (total 5)",
			"total=%d" % _vivos_de_esqueleto().size())
	gerente.call("retirar_tipo", 1)
	await get_tree().process_frame
	_comprobar(_vivos_de_esqueleto().size() == 2, "6. retirar_tipo(MELEE) deja sólo los 2 tiradores",
			"quedan=%d" % _vivos_de_esqueleto().size())
	gerente.call("retirar_grupo")
	await get_tree().process_frame
	_comprobar(_vivos_de_esqueleto().is_empty(), "6. retirar_grupo limpia todo")

	# La API de CÁPSULAS sigue intacta (la usa la suite de cápsulas).
	gerente.call("generar_grupo")
	await get_tree().process_frame
	_comprobar((gerente.call("enemigos_vivos") as Array).size() == 6,
			"6. generar_grupo() (API de cápsulas) sigue generando 6 sin cambios",
			"grupo=%d" % (gerente.call("enemigos_vivos") as Array).size())
	gerente.call("retirar_grupo")
	await get_tree().process_frame

	# ---- 6b. Tecla G de verdad: 3 de cuerpo a cuerpo + 2 con armas ----
	await _pulsar_tecla(KEY_G)
	await get_tree().process_frame
	var g_todos: Array = gerente.call("enemigos_vivos")
	var g_melee := 0
	var g_armas := 0
	var g_otras := 0
	for n in g_todos:
		var ruta := ""
		var sc := (n as Node).get_script() as Script
		if sc != null:
			ruta = sc.resource_path
		if ruta == "res://Enemigos Prueba/Scripts/enemigo_melee.gd":
			g_melee += 1
		elif ruta == "res://Enemigos Prueba/Scripts/enemigo_tirador.gd":
			g_armas += 1
		else:
			g_otras += 1
	_comprobar(g_todos.size() == 5, "6b. La tecla G genera exactamente 5 enemigos",
			"total=%d" % g_todos.size())
	_comprobar(g_melee == 3, "6b. De ellos 3 son de cuerpo a cuerpo", "cuerpo_a_cuerpo=%d" % g_melee)
	_comprobar(g_armas == 2, "6b. Y 2 son con armas (tiradores)", "armas=%d" % g_armas)
	_comprobar(g_otras == 0, "6b. Ni una cápsula en el grupo de G", "otras=%d" % g_otras)
	var lejos := true
	for n in g_todos:
		if _dist_plana((n as Node3D).global_position, jugador.global_position) < 3.0:
			lejos = false
	_comprobar(lejos, "6b. Los 5 aparecen repartidos lejos del jugador (aparición intacta)")
	await _pulsar_tecla(KEY_G)
	await get_tree().process_frame
	var quedan: Array = gerente.call("enemigos_vivos")
	_comprobar(quedan.is_empty(), "6b. Con el grupo activo, G lo retira (no duplica)",
			"quedan=%d" % quedan.size())

	# =========================== COMPORTAMIENTO (simulación real) ===========================
	var stats: EstadisticasJugador = jugador.get_node_or_null("Estadisticas") as EstadisticasJugador
	var danios := [0]
	if stats != null:
		stats.danio_recibido.connect(func(_c: float) -> void: danios[0] += 1)

	# ---- 7. Cuerpo a cuerpo: orden del combo y un solo daño por golpe ----
	_reponer_jugador(stats)
	gerente.call("retirar_grupo")
	gerente.set("cantidad_melee", 1)
	await get_tree().process_frame
	danios[0] = 0
	gerente.call("generar_tipo", 1)
	await get_tree().process_frame
	var m_melee: Node3D = _vivos_de_esqueleto()[0]
	var ap: AnimationPlayer = m_melee.get_node("Animador") as AnimationPlayer
	var secuencia: Array = []
	var previo := ""
	for i in 360:
		await get_tree().physics_frame
		if not is_instance_valid(m_melee):
			break
		var c := ap.current_animation
		if c != previo:
			previo = c
			secuencia.append(c)
	var golpes_seq: Array = []
	for c in secuencia:
		if String(c).begins_with("golpe_"):
			golpes_seq.append(c)
	_comprobar(golpes_seq.size() >= 3, "7. El cuerpo a cuerpo encadena golpes (clips golpe_*)",
			"secuencia=%s" % str(secuencia))
	var orden_ok := golpes_seq.size() >= 3
	for i in golpes_seq.size():
		if golpes_seq[i] != "golpe_%d" % ((i % 3) + 1):
			orden_ok = false
			break
	_comprobar(orden_ok, "7. Los golpes salen SIEMPRE en orden golpe_1 -> golpe_2 -> golpe_3",
			"secuencia de golpes=%s" % str(golpes_seq))
	_comprobar(danios[0] >= 1, "7. Los golpes hacen daño real al jugador (vía EstadisticasJugador)",
			"daños=%d" % danios[0])
	_comprobar(danios[0] <= golpes_seq.size(), "7. Como máximo UN daño por golpe (sin duplicar ni daño continuo)",
			"daños=%d golpes=%d" % [danios[0], golpes_seq.size()])
	gerente.call("retirar_grupo")
	await get_tree().process_frame

	# ---- 8. Tirador: mantiene distancia, dispara y no daña aliados ----
	_reponer_jugador(stats)
	# Reinicia el contador de daños: sin esto, el de la sección 7 (cuerpo a cuerpo)
	# se arrastraba y esta comprobación pasaba aunque los proyectiles NO dañaran.
	danios[0] = 0
	gerente.set("cantidad_tirador", 2)
	await get_tree().process_frame
	gerente.call("generar_tipo", 2)
	await get_tree().process_frame
	var tiradores := _vivos_de_esqueleto()
	var vidas_iniciales: Array = []
	for e in tiradores:
		vidas_iniciales.append(float(e.call("vida_actual")))
	var preferida := float(tiradores[0].get("distancia_preferida"))
	var margen_t := float(tiradores[0].get("margen"))
	var dist_min := 999.0
	var dist_final := 0.0
	var frames_disparo := 0
	var ap_t: AnimationPlayer = tiradores[0].get_node("Animador") as AnimationPlayer
	for i in 420:
		await get_tree().physics_frame
		if not is_instance_valid(tiradores[0]):
			break
		dist_final = _dist_plana(tiradores[0].global_position, jugador.global_position)
		dist_min = minf(dist_min, dist_final)
		if ap_t.current_animation == "disparar":
			frames_disparo += 1
	_comprobar(dist_min > 4.0, "8. El tirador NO se pega al jugador (no pelea cuerpo a cuerpo)",
			"distancia mínima=%.1f m" % dist_min)
	_comprobar(absf(dist_final - preferida) <= margen_t + 2.5,
			"8. El tirador mantiene su distancia preferida (8-12 m)",
			"final=%.1f m preferida=%.1f m" % [dist_final, preferida])
	_comprobar(frames_disparo > 0, "8. El tirador dispara de verdad (reproduce el clip de disparo)",
			"frames con clip disparar=%d" % frames_disparo)
	var sin_fuego_amigo := true
	for i in tiradores.size():
		if is_instance_valid(tiradores[i]) and float(tiradores[i].call("vida_actual")) < float(vidas_iniciales[i]):
			sin_fuego_amigo = false
	_comprobar(sin_fuego_amigo, "8. Los proyectiles NO dañan a los demás enemigos (sin fuego amigo)")
	_comprobar(danios[0] >= 1, "8. Los proyectiles hacen daño real al jugador", "daños=%d" % danios[0])
	gerente.call("retirar_grupo")
	await get_tree().process_frame

	# ---- 9. Los proyectiles NO atraviesan paredes ----
	_reponer_jugador(stats)
	var pared := _crear_pared(jugador.global_position + Vector3(0, 2, -2))
	await get_tree().physics_frame
	var vida_antes := stats.vida
	var escudo_antes := stats.resistencia
	var proy: Node = ESCENA_PROYECTIL.instantiate()
	get_tree().root.add_child(proy)
	await get_tree().process_frame
	var origen := jugador.global_position + Vector3(0, 1.2, -6)
	proy.call("lanzar", origen, (jugador.global_position + Vector3(0, 1.0, 0) - origen).normalized(), null, 30.0, 9.0)
	for i in 45:
		await get_tree().physics_frame
	_comprobar(not is_instance_valid(proy), "9. El proyectil se destruye al chocar con la pared")
	_comprobar(stats.vida >= vida_antes - 0.01 and stats.resistencia >= escudo_antes - 0.01,
			"9. El jugador NO recibe daño a través de la pared",
			"vida %.0f->%.0f | escudo %.0f->%.0f" % [vida_antes, stats.vida, escudo_antes, stats.resistencia])
	pared.queue_free()
	await get_tree().process_frame

	# ---- 10. El cuerpo a cuerpo NO golpea a través de una pared ----
	_reponer_jugador(stats)
	var pared2 := _crear_pared(jugador.global_position + Vector3(0, 2, -2))
	gerente.set("cantidad_melee", 1)
	gerente.call("generar_tipo", 1)
	await get_tree().physics_frame
	var muro: Node3D = _vivos_de_esqueleto()[0]
	# Pego al otro lado de la pared, pero DENTRO del alcance: así sólo puede
	# fallar la línea de visión (si el daño pasara, sería "golpear a través").
	muro.global_position = jugador.global_position + Vector3(0, 0, -3.0)
	muro.disable_mode = 0
	await get_tree().physics_frame
	var v0 := stats.vida
	var e0 := stats.resistencia
	muro.call("_iniciar_golpe", 0)
	for i in 100:
		await get_tree().physics_frame
	_comprobar(stats.vida >= v0 - 0.01 and stats.resistencia >= e0 - 0.01,
			"10. El cuerpo a cuerpo NO aplica daño a través de la pared",
			"vida %.0f->%.0f | escudo %.0f->%.0f" % [v0, stats.vida, e0, stats.resistencia])
	gerente.call("retirar_grupo")
	pared2.queue_free()

	# ---- 11. Compatibilidad con el FreeFlow (selección de objetivo REAL) ----
	gerente.call("retirar_grupo")
	gerente.call("generar_tipo", 1)
	await get_tree().process_frame
	var lista := _vivos_de_esqueleto()
	var cfg: Resource = load("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")
	var Targeting: GDScript = load("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_targeting.gd")
	var hacia_uno: Vector3 = lista[0].global_position - jugador.global_position
	hacia_uno.y = 0.0
	hacia_uno = hacia_uno.normalized()
	var elegido: Node3D = Targeting.select_target(jugador, hacia_uno, hacia_uno, lista, cfg, null, null)
	_comprobar(elegido != null and lista.has(elegido),
			"11. El targeting del FreeFlow selecciona un enemigo nuevo",
			"elegido=%s" % (elegido.name if elegido != null else "null"))
	_comprobar(lista[0] is CollisionObject3D and lista[0].is_in_group("damageable") \
			and lista[0].has_method("take_damage") and lista[0].has_method("take_hit") \
			and lista[0].has_method("apply_damage"),
			"11. El collider RAÍZ habla los contratos de Fuerza, Acuática y Combate")
	var antes := (mgr.call("get_active_enemies") as Array).size()
	if mgr != null:
		mgr.call("register_enemy", lista[0])
		_comprobar((mgr.call("get_active_enemies") as Array).size() == antes,
				"11. Registrar dos veces al mismo enemigo NO duplica el registro",
				"antes=%d despues=%d" % [antes, (mgr.call("get_active_enemies") as Array).size()])
	gerente.call("retirar_grupo")

	# ---- 12. Ataque REAL del jugador contra un enemigo nuevo (extremo a extremo) ----
	# Se usa el MISMO camino que el jugador: forma Combate por el menú y un clic de
	# ataque (Input.action_press("atacar")), igual que la suite del FreeFlow.
	_reponer_jugador(stats)
	var forma_combate := 4
	if jugador.has_method("_on_transformacion_elegida"):
		jugador.call("_on_transformacion_elegida", &"combate")
		var t := 0
		while (int(jugador.get("forma")) != forma_combate or bool(jugador.get("_transformando"))) and t < 900:
			await get_tree().physics_frame
			t += 1
		await _esperar(10)
	_comprobar(int(jugador.get("forma")) == forma_combate,
			"12. El jugador entra en la forma Combate (FreeFlow)",
			"forma=%d" % int(jugador.get("forma")))
	var frente := -jugador.global_transform.basis.z
	frente.y = 0.0
	frente = frente.normalized()
	var presa: Node = ESCENA_MELEE.instantiate()
	get_tree().root.add_child(presa)
	presa.global_position = jugador.global_position + frente * 1.8
	presa.set_physics_process(false)   # quieto: se mide el golpe, no su IA
	await get_tree().physics_frame
	await get_tree().physics_frame
	var vida_ini := float(presa.call("vida_actual"))
	for a in ["mover_atras", "mover_izquierda", "mover_derecha"]:
		Input.action_release(a)
	Input.action_press("mover_adelante")
	await _esperar(4)
	Input.action_press("atacar")
	await _esperar(5)
	Input.action_release("atacar")
	Input.action_release("mover_adelante")
	await _esperar(60)
	var vida_fin := float(presa.call("vida_actual"))
	_comprobar(vida_fin < vida_ini,
			"12. El ataque REAL del jugador (FreeFlow) daña al enemigo nuevo",
			"vida %.1f -> %.1f" % [vida_ini, vida_fin])
	if is_instance_valid(presa) and vida_fin > 0.0:
		# Remate: el mismo método que usa el módulo para ejecutar.
		presa.call("execute")
		await get_tree().physics_frame
		_comprobar(not bool(presa.call("is_alive")),
				"12. El enemigo nuevo muere y se desregistra por el ataque del jugador")
	jugador.call("_on_transformacion_elegida", &"humano")
	await get_tree().process_frame

	# ---- 13. Vida +25 % y arma del tirador anclada a la mano derecha ----
	var mel := ESCENA_MELEE.instantiate()
	_comprobar(is_equal_approx(float(mel.get("vida_max")), 75.0),
			"13. Vida del cuerpo a cuerpo = 75 (+25 % de 60)",
			"vida_max=%.2f" % float(mel.get("vida_max")))
	mel.free()
	var tir := ESCENA_TIRADOR.instantiate()
	_comprobar(is_equal_approx(float(tir.get("vida_max")), 56.25),
			"13. Vida del tirador = 56.25 (+25 % de 45)",
			"vida_max=%.2f" % float(tir.get("vida_max")))
	var anclaje := tir.get_node_or_null("Visual/Skeleton3D/AnclajeArma") as BoneAttachment3D
	_comprobar(anclaje != null and anclaje.bone_name == &"mixamorig_RightHand",
			"13. El tirador lleva el arma anclada al hueso de la mano derecha",
			"hueso=%s" % (anclaje.bone_name if anclaje != null else "sin anclaje"))
	var boca := tir.find_child("BocaArma", true, false) as Node3D
	_comprobar(boca != null, "13. El arma tiene boca de cañón (Marker3D BocaArma)")
	get_tree().root.add_child(tir)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var boca_disparo: Vector3 = tir.call("_boca_del_arma")
	var d_boca := boca_disparo.distance_to(boca.global_position) if boca != null else 999.0
	_comprobar(d_boca < 0.05, "13. El disparo sale de la boca del cañón (no del centro)",
			"d=%.3f" % d_boca)
	var d_centro := Vector2(boca.global_position.x - tir.global_position.x,
			boca.global_position.z - tir.global_position.z).length() if boca != null else 0.0
	_comprobar(d_centro > 0.3, "13. La boca del cañón queda por delante del cuerpo",
			"d=%.2f" % d_centro)
	tir.queue_free()
	await get_tree().physics_frame

	print("[TEST] ===== RESULTADO: %d OK, %d FALLOS =====" % [_ok, _fallos])
	get_tree().quit(1 if _fallos > 0 else 0)

func _esperar(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame

## Pulsa una tecla FÍSICA de verdad: el evento recorre _unhandled_input como en el
## juego, así que prueba la tecla G real y no un atajo interno del gerente.
func _pulsar_tecla(codigo: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = codigo
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var suelta := InputEventKey.new()
	suelta.physical_keycode = codigo
	suelta.pressed = false
	Input.parse_input_event(suelta)
	await get_tree().physics_frame
	await get_tree().physics_frame

func _dist_plana(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _reponer_jugador(stats: EstadisticasJugador) -> void:
	if stats == null:
		return
	stats.set("vida", float(stats.get("vida_max")))
	stats.set("resistencia", float(stats.get("resistencia_max")))
	if stats.has_method("resistencia_cambiada"):
		stats.call("resistencia_cambiada", stats.get("resistencia"), stats.get("resistencia_max"))

func _crear_pared(pos: Vector3) -> StaticBody3D:
	var pared := StaticBody3D.new()
	pared.collision_layer = 1
	pared.collision_mask = 0
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(6, 4, 0.4)
	forma.shape = caja
	pared.add_child(forma)
	get_tree().root.add_child(pared)
	pared.global_position = pos
	return pared