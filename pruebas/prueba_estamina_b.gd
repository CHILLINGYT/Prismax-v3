extends Node3D

# Suite B del SISTEMA DE ESTAMINA sobre el jugador REAL (parte 2: pez, tanque y
# combate FreeFlow):
#   1. Las 4 habilidades acuáticas cobran al ACTIVARSE; con 0 no se encienden (y
#      el enfriamiento no se consume).
#   2. Turbo acuático: activación única + consumo de la propulsión (dos cobros);
#      con 0 no arranca. Nadar vs nadado rápido consumen diferente.
#   3. Golpe del pez: cobra al arrancar; con 0 no sale.
#   4. Tanque: golpe/patada cobran una vez al ARRANCAR (incluido el combo); con 0
#      no arrancan; una diferencia pequeña NUNCA corta un ataque ya iniciado.
#   5. Pisotón, embestida, roca y supersalto: cobran su activación; con 0 no
#      arrancan (el supersalto cae al salto BÁSICO, que nunca se bloquea).
#   6. FreeFlow: el golpe cobra una vez al iniciar la fase; con 0 no arranca.
#
# No forma parte del juego: vive en res://pruebas/ y se ejecuta como ESCENA.

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

const F_ACUATICO := 2
const F_FUERZA := 3
const F_COMBATE := 4
const F_SALTO := 6.5

var _pasadas := 0
var _falladas := 0
var _jug: ControladorLeo
var _stats: EstadisticasJugador

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

func _esperar_seg(s: float) -> void:
	await _esperar(int(ceil(s * 60.0)))

func _leer(id: StringName) -> float:
	return float(_stats.estado_de_forma(id).get("stamina", -1.0))

func _poner(id: StringName, valor: float) -> void:
	var e := _stats._estados[id] as Dictionary
	e["stamina"] = valor
	e["t_desde_gasto"] = 0.0
	if id == _stats.forma_actual():
		_stats._sincronizar_activa()

func _cambiar_forma(id: StringName, forma: int) -> bool:
	_jug._on_transformacion_elegida(id)
	var t := 0
	while (int(_jug.forma) != forma or _jug._transformando) and t < 900:
		await get_tree().physics_frame
		t += 1
	await _esperar(10)
	return int(_jug.forma) == forma

func _tasa_para(id: StringName, clave: StringName) -> float:
	return CostosEstamina.costo_movimiento(id, clave)

## Deja al tanque en posición de golpear (sin ataques ni habilidades en curso).
func _limpiar_tanque() -> void:
	_jug.f_ataque = false
	_jug.f_recuperacion = 0.0
	_jug.f_embestiendo = false
	_jug.f_slam = false
	_jug.f_cargando_roca = false
	_jug.f_super_cargando = false
	_jug.f_super_carga = 0.0
	_jug.velocity = Vector3.ZERO

func _correr() -> void:
	print("=== PRUEBA ESTAMINA B: pez, tanque y combate ===")

	var suelo := StaticBody3D.new()
	var forma_s := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(400.0, 1.0, 400.0)
	forma_s.shape = caja
	suelo.add_child(forma_s)
	suelo.position = Vector3(0.0, -0.5, 0.0)
	add_child(suelo)

	_jug = JUGADOR.instantiate() as ControladorLeo
	_jug.position = Vector3(0.0, 0.1, 0.0)
	add_child(_jug)
	_stats = _jug.get_node_or_null("Estadisticas") as EstadisticasJugador
	await _esperar(30)
	if _stats == null:
		_check("jugador y estadísticas listos", false)
		_resumen()
		return
	_check("jugador y estadísticas listos", true)
	await _esperar_seg(0.3)

	# ------------------------------------------------ 1. Pez: habilidades de agua
	var ok_p := await _cambiar_forma(&"pes", F_ACUATICO)
	_check("1. Transformado al pez (acuático)", ok_p, "forma=%d" % int(_jug.forma))
	var costes := [
		CostosEstamina.costo_habilidad(&"pes", &"proyectil"),
		CostosEstamina.costo_habilidad(&"pes", &"esfera"),
		CostosEstamina.costo_habilidad(&"pes", &"prision"),
		CostosEstamina.costo_habilidad(&"pes", &"oleada"),
	]
	var ok_agua := true
	var det_agua := ""
	for i in 4:
		_poner(&"pes", 100.0)
		_jug.a_en_habilidad = false
		_jug.a_pendiente = 0
		_jug.a_t_habilidad = 0.0
		_jug.a_cooldowns.clear()
		_jug._intentar_habilidad_agua(i + 1)
		await _esperar(3)
		var gastado := 100.0 - _leer(&"pes")
		if absf(gastado - costes[i]) > 0.8:
			ok_agua = false
			det_agua += "[%d: %.1f != %.1f] " % [i + 1, gastado, costes[i]]
		_jug.a_en_habilidad = false
		_jug.a_pendiente = 0
		_jug.a_t_habilidad = 0.0
		_jug.a_cooldowns.clear()
	_check("1. Las 4 habilidades acuáticas cobran al activarse (%.0f/%.0f/%.0f/%.0f)" % \
				[costes[0], costes[1], costes[2], costes[3]], ok_agua, det_agua)
	_poner(&"pes", 0.0)
	_jug.a_en_habilidad = false
	_jug.a_pendiente = 0
	_jug.a_t_habilidad = 0.0
	_jug.a_cooldowns.clear()
	_jug._intentar_habilidad_agua(1)
	await _esperar(3)
	_check("1. Con 0 de estamina la habilidad NO se enciende (ni gasta enfriamiento)",
			not _jug.a_en_habilidad and is_zero_approx(_leer(&"pes")) \
				and is_zero_approx(float(_jug.a_cooldowns.get(1, 0.0))),
			"en_habilidad=%s" % _jug.a_en_habilidad)

	# ------------------------------------------------ 2. Turbo acuático
	_poner(&"pes", 60.0)
	_jug.a_nadando = true
	_jug.a_turbo_t = 0.0
	_jug.a_turbo_cooldown = 0.0
	_jug._intentar_turbo_acuatico()
	var t_activacion := _leer(&"pes")
	var coste_turbo := CostosEstamina.costo_habilidad(&"pes", &"turbo")
	var act_ok := absf(t_activacion - (60.0 - coste_turbo)) < 0.8 and _jug.a_turbo_t > 0.0
	# Propulsión: un segundo simulado de consumo con el turbo activo (nadando).
	_jug.velocity = Vector3(4.6, 0.0, 0.0)
	_jug._procesar_estamina_movimiento(1.0)
	var prop := t_activacion - _leer(&"pes")
	var esperado_prop := _tasa_para(&"pes", &"turbo") + _tasa_para(&"pes", &"nadar")
	_jug.a_nadando = false
	_jug.a_turbo_t = 0.0
	_jug.a_turbo_cooldown = 999.0
	_jug.velocity = Vector3.ZERO
	_check("2. Turbo: cobra la activación (%.1f) Y la propulsión (≈%.1f/s)" % [coste_turbo, esperado_prop],
			act_ok and absf(prop - esperado_prop) < 1.5,
			"activación=%.1f propulsión=%.2f" % [60.0 - t_activacion, prop])
	_poner(&"pes", 5.0)
	_jug.a_nadando = true
	_jug.a_turbo_t = 0.0
	_jug.a_turbo_cooldown = 0.0
	_jug._intentar_turbo_acuatico()
	_check("2. Sin estamina suficiente el turbo no arranca",
			is_zero_approx(_jug.a_turbo_t) and is_equal_approx(_leer(&"pes"), 5.0),
			"turbo_t=%.2f" % _jug.a_turbo_t)
	_jug.a_nadando = false
	_jug.a_turbo_cooldown = 999.0
	# Nadar vs nadado rápido (tramo elegido por el propio sistema, 1 s simulado).
	_poner(&"pes", 100.0)
	_jug.a_nadando = true
	_jug.velocity = Vector3(4.6, 0.0, 0.0)
	_jug._procesar_estamina_movimiento(1.0)
	var g_nadar := 100.0 - _leer(&"pes")
	_poner(&"pes", 100.0)
	Input.action_press(&"correr")
	_jug._procesar_estamina_movimiento(1.0)
	Input.action_release(&"correr")
	var g_rapido := 100.0 - _leer(&"pes")
	_jug.a_nadando = false
	_jug.velocity = Vector3.ZERO
	_check("2. Nadar (%.1f/s) y nadado rápido (%.1f/s) consumen diferente" % \
				[_tasa_para(&"pes", &"nadar"), _tasa_para(&"pes", &"nadar_rapido")],
			g_rapido > g_nadar * 1.5 and g_nadar > 1.0,
			"nadar=%.2f rápido=%.2f" % [g_nadar, g_rapido])
	# ------------------------------------------------ 3. Golpe del pez
	_poner(&"pes", 50.0)
	_jug._iniciar_ataque_acuatico("attack")
	await _esperar(2)
	var coste_golpe_p := CostosEstamina.costo_ataque(&"pes", &"golpe")
	_check("3. El golpe del pez cobra una vez al arrancar (%.1f)" % coste_golpe_p,
			absf(_leer(&"pes") - (50.0 - coste_golpe_p)) < 0.8 and _jug.a_ataque_activo,
			"estamina=%.1f" % _leer(&"pes"))
	_jug.a_ataque_activo = false
	_jug.a_ataque_clip = ""
	_jug.a_ataque_dur = 0.0
	_poner(&"pes", 0.0)
	_jug._iniciar_ataque_acuatico("attack")
	await _esperar(2)
	_check("3. Sin estamina el golpe del pez no arranca", not _jug.a_ataque_activo)

	# ------------------------------------------------ 4/5. Tanque
	var ok_t := await _cambiar_forma(&"tanque", F_FUERZA)
	_check("4. Transformado a Fuerza (tanque)", ok_t, "forma=%d" % int(_jug.forma))
	_limpiar_tanque()
	_poner(&"tanque", 50.0)
	_jug._golpe_fuerza(false)
	await _esperar(3)
	var coste_puno := CostosEstamina.costo_ataque(&"tanque", &"golpe")
	_check("4. El golpe del tanque cobra UNA vez (%.1f) y el ataque arranca" % coste_puno,
			absf(_leer(&"tanque") - (50.0 - coste_puno)) < 0.6 and _jug.f_ataque,
			"estamina=%.1f" % _leer(&"tanque"))
	# Con el golpe YA iniciado, la estamina a 0: el clip termina solo.
	_poner(&"tanque", 0.0)
	await _esperar(4)
	var seguia := _jug.f_ataque
	var t_fin := 0.0
	while _jug.f_ataque and t_fin < 2.5:
		await get_tree().physics_frame
		t_fin += 1.0 / 60.0
	_check("4. Una diferencia pequeña NUNCA corta el ataque empezado (terminó solo)",
			seguia and t_fin < 2.5, "seguía=%.1f s" % t_fin)
	_check("4. El golpe NO volvió a cobrar al terminar (sigue en 0)",
			is_zero_approx(_leer(&"tanque")), "%.2f" % _leer(&"tanque"))
	# Combo encadenado: el segundo golpe cobra OTRA vez (una por golpe real).
	_limpiar_tanque()
	_poner(&"tanque", 50.0)
	_jug._golpe_fuerza(false)
	await _esperar(3)
	var coste2 := CostosEstamina.costo_ataque(&"tanque", &"golpe")
	_check("4. Cada golpe del combo cobra el suyo (uno por ejecución)",
			absf(_leer(&"tanque") - (50.0 - coste2)) < 0.6, "estamina=%.1f" % _leer(&"tanque"))
	# Sin estamina: ni puñetazo ni patada nuevos.
	_limpiar_tanque()
	_poner(&"tanque", 0.0)
	_jug._golpe_fuerza(false)
	await _esperar(2)
	_check("4. Sin estamina no arranca un puñetazo nuevo", not _jug.f_ataque)
	_jug._golpe_fuerza(true)
	await _esperar(2)
	_check("4. Sin estamina no arranca una patada nueva", not _jug.f_ataque)
	# Con estamina: la patada cobra su precio propio.
	_limpiar_tanque()
	_poner(&"tanque", 50.0)
	_jug._golpe_fuerza(true)
	await _esperar(3)
	var coste_patada := CostosEstamina.costo_ataque(&"tanque", &"patada")
	_check("4. La patada del tanque cobra su coste propio (%.1f)" % coste_patada,
			absf(_leer(&"tanque") - (50.0 - coste_patada)) < 0.6 and _jug.f_ataque,
			"estamina=%.1f" % _leer(&"tanque"))
	_limpiar_tanque()
	# Pisotón aéreo.
	_poner(&"tanque", 50.0)
	var coste_slam := CostosEstamina.costo_habilidad(&"tanque", &"pisotón")
	_jug.global_position.y += 3.0
	await _esperar(3)
	_jug._intentar_slam_fuerza()
	_check("5. Pisotón: cobra %.1f al arrancar" % coste_slam,
			absf(_leer(&"tanque") - (50.0 - coste_slam)) < 0.6 and _jug.f_slam,
			"estamina=%.1f" % _leer(&"tanque"))
	_jug.f_slam = false
	_poner(&"tanque", 0.0)
	_jug._intentar_slam_fuerza()
	_check("5. Sin estamina el pisotón no arranca", not _jug.f_slam)
	await _esperar_seg(1.0)  # aterrizar
	# Embestida.
	_limpiar_tanque()
	_poner(&"tanque", 50.0)
	var coste_emb := CostosEstamina.costo_habilidad(&"tanque", &"embestida")
	_jug._iniciar_embestida_fuerza()
	_check("5. Embestida: cobra %.1f al arrancar" % coste_emb,
			absf(_leer(&"tanque") - (50.0 - coste_emb)) < 0.6 and _jug.f_embestiendo,
			"estamina=%.1f" % _leer(&"tanque"))
	_jug.f_embestiendo = false
	_jug.velocity = Vector3.ZERO
	_poner(&"tanque", 0.0)
	_jug._iniciar_embestida_fuerza()
	_check("5. Sin estamina la embestida no arranca", not _jug.f_embestiendo)
	# Roca.
	_limpiar_tanque()
	_poner(&"tanque", 50.0)
	var coste_roca := CostosEstamina.costo_habilidad(&"tanque", &"roca")
	_jug._intentar_roca_fuerza()
	await _esperar(2)
	_check("5. Arrancar la roca cobra %.1f al empezar" % coste_roca,
			absf(_leer(&"tanque") - (50.0 - coste_roca)) < 0.6 and _jug.f_cargando_roca,
			"estamina=%.1f roca=%s" % [_leer(&"tanque"), _jug.f_cargando_roca])
	if _jug.f_roca != null and is_instance_valid(_jug.f_roca):
		_jug.f_roca.queue_free()
	_jug.f_roca = null
	_jug.f_cargando_roca = false
	_jug.f_roca_lista = false
	_limpiar_tanque()
	_poner(&"tanque", 0.0)
	_jug._intentar_roca_fuerza()
	await _esperar(2)
	_check("5. Sin estamina la roca no se intenta",
			not _jug.f_cargando_roca and _jug.f_roca == null)
	# Supersalto: se paga al ejecutarse; sin estamina salta el salto NORMAL.
	_limpiar_tanque()
	_poner(&"tanque", 50.0)
	var coste_super := CostosEstamina.costo_habilidad(&"tanque", &"super_salto")
	_jug.f_super_cargando = true
	_jug.f_super_carga = 1.4
	_jug._ejecutar_super()
	await _esperar(2)
	_check("5. Supersalto: cobra %.1f y sale con el impulso máximo" % coste_super,
			absf(_leer(&"tanque") - (50.0 - coste_super)) < 0.6 and _jug.velocity.y > 15.0,
			"estamina=%.1f vel=%.1f" % [_leer(&"tanque"), _jug.velocity.y])
	await _esperar_seg(1.8)  # aterrizar
	_limpiar_tanque()
	_poner(&"tanque", 3.0)
	_jug.f_super_cargando = true
	_jug.f_super_carga = 1.4
	_jug._ejecutar_super()
	await _esperar(2)
	_check("5. Sin estamina el supersalto cae al salto BÁSICO (saltar nunca se bloquea)",
			_jug.velocity.y > F_SALTO - 1.5 and _jug.velocity.y < F_SALTO + 1.5 \
				and is_equal_approx(_leer(&"tanque"), 3.0),
			"vel=%.1f estamina=%.1f" % [_jug.velocity.y, _leer(&"tanque")])
	await _esperar_seg(1.2)

	# ------------------------------------------------ 6. Combate FreeFlow
	var ok_c := await _cambiar_forma(&"combate", F_COMBATE)
	_check("6. Transformado a Combate (FreeFlow)", ok_c, "forma=%d" % int(_jug.forma))
	_poner(&"combate", 50.0)
	var coste_ff := CostosEstamina.costo_ataque(&"combate", &"golpe")
	_jug._iniciar_golpe_combate()
	await _esperar(3)
	_check("6. El golpe FreeFlow cobra una vez al iniciar la fase (%.1f)" % coste_ff,
			absf(_leer(&"combate") - (50.0 - coste_ff)) < 0.6,
			"estamina=%.1f" % _leer(&"combate"))
	_jug._detener_combate()
	await _esperar(2)
	_poner(&"combate", 0.0)
	_jug._iniciar_golpe_combate()
	await _esperar(3)
	_check("6. Sin estamina el golpe FreeFlow no arranca",
			is_zero_approx(_leer(&"combate")), "estamina=%.1f" % _leer(&"combate"))
	_jug._detener_combate()

	_resumen()

func _resumen() -> void:
	print("=====================================================")
	print("RESUMEN B: %d OK, %d FALLA" % [_pasadas, _falladas])
	print("=====================================================")