extends Node3D

# HISTORIAL (SUPERADA): version larga de la suite de estamina, escrita antes de
# dividirla en prueba_estamina.gd (A: HUD+movimiento), prueba_estamina_b.gd
# (B: pez/tanque/combate) y prueba_estamina_c.gd (C: águila+regeneración+muerte).
# Se conserva SOLO como referencia: sus mediciones leían el espejo público de
# EstadisticasJugador (que puede ir un fotograma por detrás de `_estados` al
# fijar valores a mano), así que alguna comprobación puede dar falso negativo.
# Usar las tres suites A/B/C actuales.
#
# Suite automática (se ejecuta como ESCENA) del SISTEMA DE ESTAMINA COMPLETO sobre
# el jugador REAL, con las tablas centralizadas de CostosEstamina:
#   1.  La barra existe UNA sola vez, a la IZQUIERDA de la pantalla y centrada.
#   2.  El color de la barra es el de cada personaje (6 formas) y el borde
#       contrasta cuando hace falta (combate oscuro, águila clara).
#   3.  El relleno se mueve SUAVE (nunca salta de golpe al valor real).
#   4.  Caminar / correr / esprintar consumen DIFERENTE (tasas de la tabla) y
#       estando quieto no se gasta nada.
#   5.  Sin estamina se bloquea CORRER (velocidad de paseo, no de carrera), pero
#       caminar sigue siempre disponible.
#   6.  Cada golpe cobra UNA vez al arrancar (tanque golpe/patada, pez, combate
#       FreeFlow, velocista) y NO vuelve a cobrar en el impacto.
#   7.  Combo del velocista: cada golpe aceptado paga; la pulsación se filtra sin
#       estamina; una diferencia pequeña NUNCA corta un ataque ya iniciado.
#   8.  Todas las habilidades: agua 1-4 + turbo, tanque embestida/pisotón/roca/
#       supersalto, velocista dash/supervelocidad, águila despegue/palmazo.
#   9.  Con 0 de estamina: no arrancan ataques ni habilidades nuevas; el salto
#       BÁSICO sigue vivo (el supersalto cae al salto normal).
#   10. Turbo acuático: activación + propulsión sostenida (dos cobros distintos).
#   11. Vuelo: despegue pagado una vez, consumo continuo al volar, descenso
#       FORZADO y controlado al agotarse (aterriza, nunca negativo).
#   12. Regeneración: espera corta, luego ~velocidad_regen_estamina/s; desde 0
#       también recupera; nunca pasa del máximo; NUNCA regenera mientras haya
#       consumo sostenido; un personaje muerto no regenera.
#   13. Transformarse NO restaura la estamina (cada personaje conserva la suya).
#   14. Nunca queda en negativo y reiniciar() la devuelve a tope.
#
# No forma parte del juego: vive en res://_tests/ y se ejecuta como ESCENA:
#   godot --headless --path . res://_tests/prueba_estamina.tscn
# También se puede abrir y ejecutar desde el editor (F6).

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

const F_HUMANO := 0
const F_VELOCISTA := 1
const F_ACUATICO := 2
const F_FUERZA := 3
const F_COMBATE := 4
const F_VUELO := 5

var _pasadas := 0
var _falladas := 0
var _jug: ControladorLeo
var _stats: EstadisticasJugador
var _hud: HUDCircular

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

## Estamina cruda de una forma (para fijar valores exactos en las mediciones).
func _est_de(id: StringName) -> Dictionary:
	return _stats._estados[id] as Dictionary

## Fija la estamina de una forma y bloquea su regeneración en la ventana de la
## medición (el reloj de gasto vuelve a 0: la espera tiene que pasar entera).
func _poner(id: StringName, valor: float) -> void:
	var e := _est_de(id)
	e["stamina"] = valor
	e["t_desde_gasto"] = 0.0

func _leer(id: StringName) -> float:
	return float(_stats.estado_de_forma(id).get("stamina", -1.0))

## Cambia de forma con la misma vía del juego (menú). Volver a humano es un
## TOGGLE: se emite el id ACTUAL, no "humano".
func _cambiar_forma(id: StringName, forma: int) -> bool:
	_jug._on_transformacion_elegida(id)
	var t := 0
	while (int(_jug.forma) != forma or _jug._transformando) and t < 900:
		await get_tree().physics_frame
		t += 1
	await _esperar(10)
	return int(_jug.forma) == forma

func _volver_humano() -> bool:
	if int(_jug.forma) == F_HUMANO:
		return true
	_jug._on_transformacion_elegida(_jug.id_forma())
	var t := 0
	while (int(_jug.forma) != F_HUMANO or _jug._transformando) and t < 900:
		await get_tree().physics_frame
		t += 1
	await _esperar(10)
	return int(_jug.forma) == F_HUMANO

## Pulsa una acción FÍSICA de verdad (evento): just_pressed real.
func _tecla_accion(accion: StringName) -> void:
	if not InputMap.has_action(accion):
		InputMap.add_action(accion)
	var ev := InputEventAction.new()
	ev.action = accion
	ev.pressed = true
	Input.parse_input_event(ev)
	await _esperar(2)
	var suelta := InputEventAction.new()
	suelta.action = accion
	suelta.pressed = false
	Input.parse_input_event(suelta)
	await _esperar(1)

func _pulsar(accion: StringName) -> void:
	Input.action_press(accion)

func _soltar(accion: StringName) -> void:
	Input.action_release(accion)

## Consumo medido durante `seg` segundos con las acciones dadas pulsadas.
func _medir_movimiento(acciones: Array, seg: float) -> float:
	var antes := _stats.stamina
	for a in acciones:
		_pulsar(a)
	await _esperar_seg(seg)
	for a in acciones:
		_soltar(a)
	await _esperar(1)
	return antes - _stats.stamina

func _tasa(clave: StringName) -> float:
	return CostosEstamina.costo_movimiento(_stats.forma_actual(), clave)

func _correr() -> void:
	print("=== PRUEBA: sistema de estamina (HUD, costes, bloqueo, regeneración) ===")

	var suelo := StaticBody3D.new()
	var forma_s := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(300.0, 1.0, 300.0)
	forma_s.shape = caja
	suelo.add_child(forma_s)
	suelo.position = Vector3(0.0, -0.5, 0.0)
	add_child(suelo)

	_jug = JUGADOR.instantiate() as ControladorLeo
	_jug.position = Vector3(0.0, 0.1, 0.0)
	add_child(_jug)
	_stats = _jug.get_node_or_null("Estadisticas") as EstadisticasJugador
	for n in _jug.get_children():
		if n is HUDCircular:
			_hud = n
	await _esperar(30)
	if _stats == null or _hud == null:
		_check("jugador, estadísticas y HUD listos", false,
				"stats=%s hud=%s" % [_stats != null, _hud != null])
		_resumen()
		return
	_check("jugador, estadísticas y HUD listos", true)
	await _esperar_seg(0.4)

	# ------------------------------------------------ 1. Barra única, a la derecha
	var barra: Node = _hud.get_node_or_null("Raiz/BarraEstamina")
	var vista := get_viewport().get_visible_rect().size
	var pos := (barra as Control) .position if barra != null else Vector2.ZERO
	_check("1. La barra de estamina existe en el HUD", barra != null)
	_check("1. VERTICAL a la DERECHA de la vida (fondo %s)" % str(_hud._est_fondo.size),
			barra != null and pos.x > vista.x * 0.5 \
				and _hud._est_fondo.size.y > _hud._est_fondo.size.x,
			"pos=%s vista=%s" % [pos, vista])
	_check("1. La estamina arranca al máximo",
			is_equal_approx(_stats.stamina, _stats.stamina_max),
			"%.1f / %.1f" % [_stats.stamina, _stats.stamina_max])

	# ------------------------------------------------ 2. Colores por personaje
	var colores_ok := true
	var detalle_colores := ""
	for id in [&"humano", &"velocista", &"pes", &"tanque", &"combate", &"aguila"]:
		_jug.forma_cambiada.emit(id)  # el mismo aviso que da el juego al entrar
		var c := _hud._est_relleno.color
		var esperado := CostosEstamina.color_de(id)
		if not c.is_equal_approx(esperado):
			colores_ok = false
			detalle_colores += "%s: %s != %s " % [id, c, esperado]
	_check("2. Cada forma pinta su color en la barra (señal de transformación)",
			colores_ok, detalle_colores)
	# Rasgos pedidos: violeta/rosa, rojo, azul, naranja, oscuro y blanco plateado.
	var ch := CostosEstamina.color_de(&"humano")
	var cv := CostosEstamina.color_de(&"velocista")
	var cp := CostosEstamina.color_de(&"pes")
	var ct := CostosEstamina.color_de(&"tanque")
	var cc := CostosEstamina.color_de(&"combate")
	var ca := CostosEstamina.color_de(&"aguila")
	_check("2. Max (humano) = violeta rosado (híbrido)", ch.r > 0.6 and ch.g < 0.6 and ch.b > 0.85,
			str(ch))
	_check("2. Velocista = rojo intenso", cv.r > 0.9 and cv.g < 0.3 and cv.b < 0.3, str(cv))
	_check("2. Pez = azul intenso", cp.b > 0.9 and cp.r < 0.3, str(cp))
	_check("2. Tanque = naranja intenso", ct.r > 0.9 and ct.g > 0.3 and ct.g < 0.7 and ct.b < 0.3,
			str(ct))
	_check("2. Combate = oscuro con borde de contraste claro",
			cc.r < 0.3 and cc.g < 0.3 and cc.b < 0.3 \
				and CostosEstamina.borde_de(&"combate").get_luminance() > 0.6,
			str(cc))
	_check("2. Águila = blanco plateado con borde oscuro",
			ca.r > 0.9 and ca.g > 0.9 and ca.b > 0.9 \
				and CostosEstamina.borde_de(&"aguila").get_luminance() < 0.3,
			str(ca))
	_jug.forma_cambiada.emit(&"humano")
	# La barra se queda UNA sola (no se duplicó con las 6 transformaciones).
	var n_barras := 0
	for n in _hud.get_node("Raiz").get_children():
		if n.name == "BarraEstamina":
			n_barras += 1
	_check("2. Sigue habiendo UNA sola barra tras 6 transformaciones", n_barras == 1,
			"barras=%d" % n_barras)

	# ------------------------------------------------ 3. Relleno suave
	_poner(&"humano", 20.0)
	_stats.stamina_cambiada.emit(_stats.stamina, _stats.stamina_max)
	await _esperar(1)
	_check("3. El objetivo salta al valor real pero el relleno NO (transición suave)",
			is_equal_approx(_hud._est_objetivo, 0.2) and _hud._est_mostrado > 0.5,
			"objetivo=%.2f mostrado=%.2f" % [_hud._est_objetivo, _hud._est_mostrado])
	await _esperar_seg(1.2)
	_check("3. El relleno alcanza el valor real suavemente",
			absf(_hud._est_mostrado - 0.2) < 0.05,
			"mostrado=%.2f" % _hud._est_mostrado)

	# ------------------------------------------------ 4. Caminar / correr / quieto
	_poner(&"humano", 100.0)
	var g_caminar := await _medir_movimiento([&"mover_adelante"], 1.2)
	_check("4. Caminar NO consume estamina", is_zero_approx(g_caminar),
			"gastado=%.3f" % g_caminar)
	_poner(&"humano", 100.0)
	var g_correr := await _medir_movimiento([&"mover_adelante", &"correr"], 1.2)
	var esperado_correr := _tasa(&"correr") * 1.2
	_check("4. Correr con Shift SÍ consume (%.1f/s)" % _tasa(&"correr"),
			g_correr >= esperado_correr * 0.7 and g_correr <= esperado_correr * 1.3,
			"gastado=%.1f (esperado≈%.1f)" % [g_correr, esperado_correr])
	_poner(&"humano", 60.0)
	await _esperar_seg(1.0)
	_check("4. Quieto (sin acciones) NO gasta nada", is_equal_approx(_stats.stamina, 60.0),
			"%.2f" % _stats.stamina)

	# ------------------------------------------------ 5. Agotado: sin correr, caminar sí
	_poner(&"humano", 0.0)
	await _esperar(2)
	var vel_agotado := await _medir_velocidad([&"mover_adelante", &"correr"], 0.8)
	_check("5. Con 0 de estamina el correr queda bloqueado (velocidad de paseo)",
			vel_agotado > 0.5 and vel_agotado <= _jug.H_VEL_CAMINAR + 0.6,
			"vel=%.2f (paseo %.1f)" % [vel_agotado, _jug.H_VEL_CAMINAR])
	_poner(&"humano", 80.0)
	var vel_normal := await _medir_velocidad([&"mover_adelante", &"correr"], 0.8)
	_check("5. Con estamina el mismo input SÍ corre",
			vel_normal > vel_agotado + 1.5, "vel=%.2f" % vel_normal)
	await _esperar(2)

	# ------------------------------------------------ 13. Transformar no restaura
	_poner(&"humano", 40.0)
	var humano_al_salir := _stats.stamina
	var ok_v := await _cambiar_forma(&"velocista", F_VELOCISTA)
	_check("13. Transformado a velocista", ok_v, "forma=%d" % int(_jug.forma))
	_check("13. El velocista arranca con SU estamina (no hereda la del humano)",
			is_equal_approx(_leer(&"velocista"), _stats.stamina_max),
			"velocista=%.1f humano=%.1f" % [_leer(&"velocista"), _leer(&"humano")])
	_check("13. El humano conserva la suya al salir (no se restaura)",
			_leer(&"humano") <= humano_al_salir + 25.0, "humano=%.1f" % _leer(&"humano"))

	# ------------------------------------------------ 6/7. Velocista: golpe y esprint
	_poner(&"velocista", 100.0)
	var g_esprint := await _medir_movimiento([&"mover_adelante", &"correr"], 1.2)
	var esperado_esprint := _tasa(&"esprintar") * 1.2
	_check("4/7. El velocista esprinta fuerte (%.1f/s > %.1f/s del humano)" % [_tasa(&"esprintar"), CostosEstamina.costo_movimiento(&"humano", &"correr")],
			g_esprint >= esperado_esprint * 0.7 and g_esprint <= esperado_esprint * 1.3 \
				and _tasa(&"esprintar") > CostosEstamina.costo_movimiento(&"humano", &"correr"),
			"gastado=%.1f (esperado≈%.1f)" % [g_esprint, esperado_esprint])
	await _esperar_seg(0.3)
	_poner(&"velocista", 50.0)
	_jug.combate.intentar_golpe()
	await _esperar(3)
	var tras_golpe := _stats.stamina
	_check("6. Un golpe del velocista cobra UNA vez (%.1f)" % _tasa(&"golpe"),
			absf(tras_golpe - (50.0 - _tasa(&"golpe"))) < 0.6,
			"%.2f → %.2f" % [50.0, tras_golpe])
	await _esperar_seg(0.6)
	_check("6. El golpe NO vuelve a cobrar al conectarse",
			absf(_stats.stamina - tras_golpe) < 0.6,
			"%.2f" % _stats.stamina)
	# Pulsación con 0: el sistema ni se entera (gate de puede_ataque en el input).
	_poner(&"velocista", 0.0)
	_jug._ataque_activo = false
	await _tecla_accion(&"atacar")
	await _esperar(6)
	_check("7. Con 0 de estamina la pulsación de ataque NO llega al sistema",
			not _jug._ataque_activo and is_equal_approx(_stats.stamina, 0.0),
			"ataque_activo=%s" % _jug._ataque_activo)

	# ------------------------------------------------ 8. Dash y supervelocidad
	_poner(&"velocista", 50.0)
	_jug._intentar_dash()
	await _esperar(2)
	_check("8. Dash: cobra %.1f al arrancar y cambia el estado" % _tasa(&"dash"),
			absf(_stats.stamina - (50.0 - CostosEstamina.costo_habilidad(&"velocista", &"dash"))) < 0.6 \
				and _jug.estado != 0,
			"estamina=%.1f estado=%d" % [_stats.stamina, _jug.estado])
	_jug._detener_velocista()
	await _esperar(2)
	_poner(&"velocista", 50.0)
	_jug._iniciar_recorrido()
	await _esperar(2)
	_check("8. Supervelocidad: cobra la activación y arranca la ejecución (%.1f)" % \
				CostosEstamina.costo_habilidad(&"velocista", &"supervelocidad"),
			absf(_stats.stamina - (50.0 - CostosEstamina.costo_habilidad(&"velocista", &"supervelocidad"))) < 0.6 \
				and _jug.estado == 1,
			"estamina=%.1f estado=%d" % [_stats.stamina, _jug.estado])
	var super_antes := _stats.stamina
	await _esperar_seg(0.6)
	_check("8. La supervelocidad consume por segundo mientras corre (%.1f/s)" % _tasa(&"supervelocidad"),
			super_antes - _stats.stamina > _tasa(&"supervelocidad") * 0.25,
			"gastado=%.2f en 0.6 s" % (super_antes - _stats.stamina))
	_jug._detener_velocista()
	await _esperar(2)
	_poner(&"velocista", 0.0)
	_jug._iniciar_recorrido()
	await _esperar(2)
	_check("8. Sin estamina la supervelocidad se cancela con seguridad (estado normal)",
			_jug.estado == 0 and is_equal_approx(_stats.stamina, 0.0),
			"estado=%d" % _jug.estado)

	# ------------------------------------------------ 12. Regeneración
	_poner(&"velocista", 40.0)
	_stats.probar_gasto(10.0, &"prueba")
	_check("12. probar_gasto cobra una vez y deja registro",
			is_equal_approx(_stats.stamina, 30.0) and _stats.ultimo_gasto == &"prueba",
			"%.1f motivo=%s" % [_stats.stamina, _stats.ultimo_gasto])
	var espera := _stats.espera_regen_estamina
	await _esperar_seg(espera + 0.5)
	_check("12. Tras la espera (%.1f s) regenera a ~%.0f/s" % [espera, _stats.velocidad_regen_estamina],
			_stats.stamina > 30.0 and _stats.stamina <= 30.0 + _stats.velocidad_regen_estamina * 0.5 + 3.0,
			"%.1f" % _stats.stamina)
	# Desde CERO también recupera.
	_poner(&"velocista", 0.0)
	await _esperar(2)
	await _esperar_seg(espera + 1.0)
	_check("12. Desde 0 la estamina SE RECUPERA (sin quedarse trabada)",
			_stats.stamina > _stats.velocidad_regen_estamina * 0.5,
			"%.1f" % _stats.stamina)
	# No pasa del máximo.
	_poner(&"velocista", _stats.stamina_max - 3.0)
	await _esperar_seg(espera + 0.8)
	_check("12. La regeneración NUNCA pasa del máximo",
			_stats.stamina <= _stats.stamina_max + 0.001,
			"%.2f / %.2f" % [_stats.stamina, _stats.stamina_max])
	# Consumo sostenido: la regeneración queda apagada.
	_poner(&"velocista", 50.0)
	var t_cons := 0
	while t_cons < 120:
		_stats.gastar_continuo(0.2)
		await get_tree().physics_frame
		t_cons += 1
	_check("12. Mientras hay consumo sostenido NO regenera (sólo descuenta)",
			absf(_stats.stamina - (50.0 - 0.2 * 120.0)) < 1.0,
			"%.1f (esperado≈%.1f)" % [_stats.stamina, 50.0 - 24.0])
	# Nunca negativo.
	_stats.gastar_continuo(999.0)
	_check("14. El gasto sostenido nunca deja la estamina en negativo",
			_stats.stamina >= 0.0 and is_zero_approx(_stats.stamina), "%.3f" % _stats.stamina)

	# ------------------------------------------------ 8. Pez: habilidades de agua y turbo
	var ok_p := await _cambiar_forma(&"pes", F_ACUATICO)
	_check("pea. Transformado al pez (acuático)", ok_p, "forma=%d" % int(_jug.forma))
	var costes_agua := [
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
		var gastado := 100.0 - _stats.stamina
		if absf(gastado - costes_agua[i]) > 0.6:
			ok_agua = false
			det_agua += "[%d: %.1f != %.1f] " % [i + 1, gastado, costes_agua[i]]
		_jug.a_en_habilidad = false
		_jug.a_pendiente = 0
		_jug.a_t_habilidad = 0.0
		_jug.a_cooldowns.clear()
	_check("8. Las 4 habilidades acuáticas se cobran al activarse (%.0f/%.0f/%.0f/%.0f)" % \
				[costes_agua[0], costes_agua[1], costes_agua[2], costes_agua[3]],
			ok_agua, det_agua)
	_poner(&"pes", 0.0)
	_jug.a_en_habilidad = false
	_jug.a_pendiente = 0
	_jug.a_t_habilidad = 0.0
	_jug.a_cooldowns.clear()
	_jug._intentar_habilidad_agua(1)
	await _esperar(3)
	_check("9. Sin estamina la habilidad de agua NO se enciende (ni gasta enfriamiento)",
			not _jug.a_en_habilidad and is_equal_approx(_stats.stamina, 0.0) \
				and is_zero_approx(float(_jug.a_cooldowns.get(1, 0.0))),
			"en_habilidad=%s" % _jug.a_en_habilidad)
	# Turbo: activación + propulsión sostenida (dos cobros distintos).
	_poner(&"pes", 60.0)
	_jug.a_nadando = true
	_jug.a_turbo_t = 0.0
	_jug.a_turbo_cooldown = 0.0
	_jug._intentar_turbo_acuatico()
	var t_activacion := _stats.stamina
	var tras_turbo_act := is_equal_approx(t_activacion,
			60.0 - CostosEstamina.costo_habilidad(&"pes", &"turbo")) and _jug.a_turbo_t > 0.0
	# La propulsión sostenida: un "segundo" de consumo con la propulsión activa.
	_jug.velocity = Vector3(4.6, 0.0, 0.0)
	_jug._procesar_estamina_movimiento(1.0)
	var prop := t_activacion - _stats.stamina
	var esperado_prop := _tasa_para(&"pes", &"turbo") + _tasa_para(&"pes", &"nadar")
	_jug.a_nadando = false
	_jug.a_turbo_t = 0.0
	_jug.a_turbo_cooldown = 999.0
	_jug.velocity = Vector3.ZERO
	_check("10. Turbo acuático: cobra la activación (%.1f) Y consume durante la propulsión" % \
				CostosEstamina.costo_habilidad(&"pes", &"turbo"),
			tras_turbo_act and absf(prop - esperado_prop) < 1.5,
			"activación=%.1f propulsión=%.2f (esperado≈%.2f)" % [60.0 - t_activacion, prop, esperado_prop])
	_poner(&"pes", 5.0)
	_jug.a_nadando = true
	_jug.a_turbo_t = 0.0
	_jug.a_turbo_cooldown = 0.0
	_jug._intentar_turbo_acuatico()
	_check("9. Sin estamina suficiente el turbo no arranca",
			is_zero_approx(_jug.a_turbo_t) and is_equal_approx(_stats.stamina, 5.0),
			"turbo_t=%.2f" % _jug.a_turbo_t)
	_jug.a_nadando = false
	_jug.a_turbo_cooldown = 999.0
	# Nadar vs nadado rápido (mismo truco: se mide el tramo elegido, sin agua real).
	_poner(&"pes", 100.0)
	_jug.a_nadando = true
	_jug.velocity = Vector3(4.6, 0.0, 0.0)
	_jug._procesar_estamina_movimiento(1.0)
	var g_nadar := 100.0 - _stats.stamina
	_poner(&"pes", 100.0)
	_pulsar(&"correr")
	_jug._procesar_estamina_movimiento(1.0)
	_soltar(&"correr")
	var g_nadar_rapido := 100.0 - _stats.stamina
	_jug.a_nadando = false
	_jug.velocity = Vector3.ZERO
	_check("4. Nadar (%.1f/s) y nadado rápido (%.1f/s) consumen diferente" % \
				[_tasa_para(&"pes", &"nadar"), _tasa_para(&"pes", &"nadar_rapido")],
			g_nadar_rapido > g_nadar * 1.5 and g_nadar > 1.0,
			"nadar=%.2f rápido=%.2f" % [g_nadar, g_nadar_rapido])
	# Golpe del pez: cobro único al arrancar.
	_poner(&"pes", 50.0)
	_jug._iniciar_ataque_acuatico("Attack")
	await _esperar(2)
	_check("6. El golpe del pez cobra una vez al arrancar",
			absf(_stats.stamina - (50.0 - CostosEstamina.costo_ataque(&"pes", &"golpe"))) < 0.6 \
				and _jug.a_ataque_activo,
			"%.2f" % _stats.stamina)
	_jug.a_ataque_activo = false
	_jug.a_ataque_clip = ""
	_jug.a_ataque_dur = 0.0
	_poner(&"pes", 0.0)
	_jug._iniciar_ataque_acuatico("Attack")
	await _esperar(2)
	_check("9. Sin estamina el golpe del pez no arranca", not _jug.a_ataque_activo)

	# ------------------------------------------------ 6/8/9. Tanque
	var ok_t := await _cambiar_forma(&"tanque", F_FUERZA)
	_check("tanq. Transformado a Fuerza (tanque)", ok_t, "forma=%d" % int(_jug.forma))
	_limpiar_tanque()
	_poner(&"tanque", 50.0)
	_jug._golpe_fuerza(false)
	await _esperar(3)
	var tras_puno := _stats.stamina
	_check("6. El golpe del tanque cobra UNA vez (%.1f) y el ataque arranca" % \
				CostosEstamina.costo_ataque(&"tanque", &"golpe"),
			absf(tras_puno - (50.0 - CostosEstamina.costo_ataque(&"tanque", &"golpe"))) < 0.6 \
				and _jug.f_ataque,
			"%.2f" % tras_puno)
	_check("7. Una diferencia pequeña NO corta el ataque empezado",
			_jug.f_ataque, "f_ataque=%s" % _jug.f_ataque)
	# Con el golpe en curso, la estamina a cero: el clip termina solo.
	_poner(&"tanque", 0.0)
	await _esperar(4)
	_check("7. El ataque iniciado sigue hasta el final aunque la estamina llegue a 0",
			_jug.f_ataque, "f_ataque=%s" % _jug.f_ataque)
	var t_fin := 0.0
	while _jug.f_ataque and t_fin < 2.5:
		await get_tree().physics_frame
		t_fin += 1.0 / 60.0
	_check("6. El golpe NO volvió a cobrar al terminar (estamina intacta en 0)",
			is_equal_approx(_stats.stamina, 0.0), "%.2f" % _stats.stamina)
	# Sin estamina: ni puñetazo ni patada nuevos.
	_limpiar_tanque()
	_jug._golpe_fuerza(false)
	await _esperar(2)
	_check("9. Sin estamina no arranca un puñetazo nuevo", not _jug.f_ataque)
	_jug._golpe_fuerza(true)
	await _esperar(2)
	_check("9. Sin estamina no arranca una patada nueva", not _jug.f_ataque)
	# Con estamina: la patada cobra su precio propio.
	_limpiar_tanque()
	_poner(&"tanque", 50.0)
	_jug._golpe_fuerza(true)
	await _esperar(3)
	_check("6. La patada del tanque cobra su coste propio (%.1f)" % \
				CostosEstamina.costo_ataque(&"tanque", &"patada"),
			absf(_stats.stamina - (50.0 - CostosEstamina.costo_ataque(&"tanque", &"patada"))) < 0.6 \
				and _jug.f_ataque,
			"%.2f" % _stats.stamina)
	_limpiar_tanque()
	# Pisotón aéreo.
	_poner(&"tanque", 50.0)
	_jug.global_position.y += 3.0
	await _esperar(3)
	_jug._intentar_slam_fuerza()
	_check("8. Pisotón: cobra %.1f al arrancar" % CostosEstamina.costo_habilidad(&"tanque", &"pisotón"),
			absf(_stats.stamina - (50.0 - CostosEstamina.costo_habilidad(&"tanque", &"pisotón"))) < 0.6 \
				and _jug.f_slam,
			"estamina=%.1f" % _stats.stamina)
	_jug.f_slam = false
	_poner(&"tanque", 0.0)
	_jug._intentar_slam_fuerza()
	_check("9. Sin estamina el pisotón no arranca", not _jug.f_slam)
	await _esperar_seg(1.0)  # aterrizar
	# Embestida.
	_limpiar_tanque()
	_poner(&"tanque", 50.0)
	_jug._iniciar_embestida_fuerza()
	_check("8. Embestida: cobra %.1f al arrancar" % CostosEstamina.costo_habilidad(&"tanque", &"embestida"),
			absf(_stats.stamina - (50.0 - CostosEstamina.costo_habilidad(&"tanque", &"embestida"))) < 0.6 \
				and _jug.f_embestiendo,
			"estamina=%.1f" % _stats.stamina)
	_jug.f_embestiendo = false
	_jug.velocity = Vector3.ZERO
	_poner(&"tanque", 0.0)
	_jug._iniciar_embestida_fuerza()
	_check("9. Sin estamina la embestida no arranca", not _jug.f_embestiendo)
	# Roca.
	_limpiar_tanque()
	_poner(&"tanque", 50.0)
	_jug._intentar_roca_fuerza()
	await _esperar(2)
	_check("8. Arrancar la roca cobra %.1f al empezar" % CostosEstamina.costo_habilidad(&"tanque", &"roca"),
			absf(_stats.stamina - (50.0 - CostosEstamina.costo_habilidad(&"tanque", &"roca"))) < 0.6 \
				and _jug.f_cargando_roca,
			"estamina=%.1f roca=%s" % [_stats.stamina, _jug.f_cargando_roca])
	# Limpieza de la roca (el hecho se prueba aquí; el objeto no debe quedar vivo).
	if _jug.f_roca != null and is_instance_valid(_jug.f_roca):
		_jug.f_roca.queue_free()
	_jug.f_roca = null
	_jug.f_cargando_roca = false
	_jug.f_roca_lista = false
	_limpiar_tanque()
	_poner(&"tanque", 0.0)
	_jug._intentar_roca_fuerza()
	await _esperar(2)
	_check("9. Sin estamina la roca no se intenta", not _jug.f_cargando_roca and _jug.f_roca == null)
	# Supersalto: se paga al ejecutarse; sin estamina salta el salto NORMAL.
	_limpiar_tanque()
	_poner(&"tanque", 50.0)
	_jug.f_super_cargando = true
	_jug.f_super_carga = 1.4
	_jug._ejecutar_super()
	await _esperar(2)
	_check("8. Supersalto: cobra %.1f y sale con el impulso máximo" % \
				CostosEstamina.costo_habilidad(&"tanque", &"super_salto"),
			absf(_stats.stamina - (50.0 - CostosEstamina.costo_habilidad(&"tanque", &"super_salto"))) < 0.6 \
				and _jug.velocity.y > 15.0,
			"estamina=%.1f vel=%.1f" % [_stats.stamina, _jug.velocity.y])
	await _esperar_seg(2.0)  # aterrizar
	_limpiar_tanque()
	_poner(&"tanque", 3.0)
	_jug.f_super_cargando = true
	_jug.f_super_carga = 1.4
	_jug._ejecutar_super()
	await _esperar(2)
	_check("9. Sin estamina el supersalto cae al salto BÁSICO (nunca se bloquea saltar)",
			_jug.velocity.y > 5.0 and _jug.velocity.y < 8.0 and is_equal_approx(_stats.stamina, 3.0),
			"vel=%.1f estamina=%.1f" % [_jug.velocity.y, _stats.stamina])
	await _esperar_seg(2.0)

	# ------------------------------------------------ 6. Combate FreeFlow
	var ok_c := await _cambiar_forma(&"combate", F_COMBATE)
	_check("comb. Transformado a Combate (FreeFlow)", ok_c, "forma=%d" % int(_jug.forma))
	_poner(&"combate", 50.0)
	_jug._iniciar_golpe_combate()
	await _esperar(3)
	_check("6. El golpe FreeFlow cobra una vez al iniciar la fase (%.1f)" % \
				CostosEstamina.costo_ataque(&"combate", &"golpe"),
			absf(_stats.stamina - (50.0 - CostosEstamina.costo_ataque(&"combate", &"golpe"))) < 0.6,
			"estamina=%.1f" % _stats.stamina)
	_jug._detener_combate()
	await _esperar(2)
	_poner(&"combate", 0.0)
	_jug._iniciar_golpe_combate()
	await _esperar(3)
	_check("9. Sin estamina el golpe FreeFlow no arranca",
			is_equal_approx(_stats.stamina, 0.0), "estamina=%.1f" % _stats.stamina)
	_jug._detener_combate()
	await _esperar(2)

	# ------------------------------------------------ 11. Águila: vuelo y habilidades
	Misiones.marcar_completada(Misiones.MISION_PROFUGOS)
	var ok_a := await _cambiar_forma(&"aguila", F_VUELO)
	_check("agu. Transformado al águila (vuelo)", ok_a, "forma=%d" % int(_jug.forma))
	await _esperar_seg(0.6)
	var fc: Node = _jug.vuelo.get_node_or_null("FlightController")
	_check("11. El cuerpo volador existe con su FlightController", fc != null)
	if fc != null:
		# Despegue pagado una vez.
		_poner(&"aguila", 100.0)
		await _tecla_accion(&"toggle_flight")
		await _esperar(5)
		_check("11. Despegue: cobra %.1f una sola vez y levanta el vuelo" % \
					CostosEstamina.costo_habilidad(&"aguila", &"despegue"),
				bool(fc.is_flying) and absf(_stats.stamina - (100.0 - CostosEstamina.costo_habilidad(&"aguila", &"despegue"))) < 1.2,
				"vuela=%s estamina=%.1f" % [fc.is_flying, _stats.stamina])
		# Consumo continuo al volar.
		_poner(&"aguila", 80.0)
		await _esperar_seg(1.0)
		var g_volar := 80.0 - _stats.stamina
		_check("11. Volar consume progresivamente (%.1f/s)" % _tasa_para(&"aguila", &"volar"),
				g_volar > _tasa_para(&"aguila", &"volar") * 0.6 \
					and g_volar < _tasa_para(&"aguila", &"volar") * 1.4,
				"gastado=%.1f en 1 s" % g_volar)
		# Agotamiento en pleno vuelo: descenso forzado y aterrizaje.
		_poner(&"aguila", 0.2)
		await _esperar(3)
		var descendiendo := bool(fc.descenso_forzado)
		var t_baja := 0.0
		while bool(fc.is_flying) and t_baja < 4.0:
			await get_tree().physics_frame
			t_baja += 1.0 / 60.0
		_check("11. Con 0 de estamina el vuelo hace un DESCENSO forzado y aterriza",
				descendiendo and not bool(fc.is_flying) and t_baja < 4.0,
				"descenso=%s aterrizó en %.1f s" % [descendiendo, t_baja])
		_check("14. Tras el descenso la estamina sigue sin ser negativa",
				_stats.stamina >= 0.0, "%.2f" % _stats.stamina)
		await _esperar_seg(0.5)
		# Sin estamina no se despega.
		_poner(&"aguila", 5.0)
		await _tecla_accion(&"toggle_flight")
		await _esperar(5)
		_check("9. Sin estamina suficiente el despegue queda bloqueado",
				not bool(fc.is_flying) and is_equal_approx(_stats.stamina, 5.0),
				"vuela=%s estamina=%.1f" % [fc.is_flying, _stats.stamina])
		# Con estamina se puede volver a volar y bajar a voluntad.
		_poner(&"aguila", 60.0)
		await _tecla_accion(&"toggle_flight")
		await _esperar(5)
		var volvio := bool(fc.is_flying)
		await _tecla_accion(&"toggle_flight")
		await _esperar_seg(1.5)
		_check("11. Con estamina vuelve a volar y puede bajar cuando quiere",
				volvio and not bool(fc.is_flying) and not bool(fc.descenso_forzado),
				"volvió=%s" % volvio)
	# Pluma: cada disparo paga.
	var plumas: Node = _jug.vuelo.get_node_or_null("FeatherAbility")
	_check("8. La habilidad de plumas existe", plumas != null)
	if plumas != null:
		_poner(&"aguila", 50.0)
		plumas.call("_disparo_con_clip")
		await _esperar(2)
		_check("6. Cada pluma cobra al dispararse (%.1f)" % CostosEstamina.costo_ataque(&"aguila", &"pluma"),
				absf(_stats.stamina - (50.0 - CostosEstamina.costo_ataque(&"aguila", &"pluma"))) < 0.6,
				"estamina=%.1f" % _stats.stamina)
		_poner(&"aguila", 0.0)
		var antes_pluma := _stats.stamina
		plumas.call("_disparo_con_clip")
		await _esperar(2)
		_check("9. Sin estamina la pluma no se dispara (no hay cobro)",
				is_equal_approx(_stats.stamina, antes_pluma))
	# Palmazo: cobra al ejecutarse.
	var palmazo: Node = null
	for n in _jug.vuelo.find_children("*", "", true, false):
		var sc: Script = n.get_script() as Script
		if sc != null and String(sc.resource_path).ends_with("palmazo_viento.gd"):
			palmazo = n
	_check("8. La habilidad del palmazo existe", palmazo != null)
	if palmazo != null:
		palmazo.set("_cd", 0.0)
		_poner(&"aguila", 50.0)
		await _tecla_accion(&"palmazo")
		await _esperar(3)
		_check("8. Palmazo: cobra %.1f al ejecutarse" % CostosEstamina.costo_habilidad(&"aguila", &"palmazo"),
				absf(_stats.stamina - (50.0 - CostosEstamina.costo_habilidad(&"aguila", &"palmazo"))) < 0.6,
				"estamina=%.1f" % _stats.stamina)
		palmazo.set("_cd", 0.0)
		_poner(&"aguila", 0.0)
		var antes_palmazo := _stats.stamina
		await _tecla_accion(&"palmazo")
		await _esperar(3)
		_check("9. Sin estamina el palmazo no se ejecuta",
				is_equal_approx(_stats.stamina, antes_palmazo))
	# Garras: sin nada agarrable no se cobra (falla antes de ejecutarse).
	var garras: Node = _jug.vuelo.get_node_or_null("TalonsAbility")
	_check("8. La habilidad de garras existe", garras != null)
	if garras != null:
		_poner(&"aguila", 100.0)
		garras.call("_intentar_agarrar")
		await _esperar(2)
		_check("8. Garras sin presa a mano: NO cobra (falla antes de ejecutarse)",
				is_equal_approx(_stats.stamina, 100.0), "estamina=%.1f" % _stats.stamina)
	# Golpe del águila en el combo de suelo.
	var gc: Node = _jug.vuelo.get_node_or_null("GroundCombat")
	_check("8. El combate de suelo del águila existe", gc != null)
	if gc != null and not (gc.get("cadena") as Array).is_empty():
		_poner(&"aguila", 50.0)
		gc.call("_lanzar", 0)
		await _esperar(3)
		_check("6. El golpe del águila cobra una vez al lanzarse (%.1f)" % \
					CostosEstamina.costo_ataque(&"aguila", &"golpe"),
				absf(_stats.stamina - (50.0 - CostosEstamina.costo_ataque(&"aguila", &"golpe"))) < 0.6,
				"estamina=%.1f" % _stats.stamina)
		gc.call("cancelar_todo")

	# ------------------------------------------------ 14. Muerte / reinicio
	var ok_h := await _volver_humano()
	_check("14. Vuelta a humano correcta", ok_h, "forma=%d" % int(_jug.forma))
	_poner(&"humano", 30.0)
	_stats.recibir_danio(9999.0)
	await _esperar(3)
	_check("14. El personaje muere con el escudo y la vida a cero", _stats.muerto)
	_check("14. Un personaje muerto no gasta estamina al pedirla",
			not _stats.probar_gasto(1.0) and is_equal_approx(_stats.stamina, 30.0),
			"%.1f" % _stats.stamina)
	_stats.gastar_continuo(5.0)
	await _esperar_seg(1.0)
	_check("14. Un personaje muerto tampoco regenera ni gasta",
			is_equal_approx(_stats.stamina, 30.0), "%.1f" % _stats.stamina)
	_stats.reiniciar()
	await _esperar(3)
	_check("14. reiniciar() devuelve vida y estamina a tope (respawn limpio)",
			is_equal_approx(_stats.vida, _stats.vida_max) \
				and is_equal_approx(_stats.stamina, _stats.stamina_max) and not _stats.muerto,
			"vida=%.0f estamina=%.0f" % [_stats.vida, _stats.stamina])

	_resumen()

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

## Velocidad horizontal media alcanzada con las acciones dadas.
func _medir_velocidad(acciones: Array, seg: float) -> float:
	for a in acciones:
		_pulsar(a)
	var v_max := 0.0
	var t := 0.0
	while t < seg:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t > 0.4:
			v_max = maxf(v_max, Vector2(_jug.velocity.x, _jug.velocity.z).length())
	for a in acciones:
		_soltar(a)
	await _esperar(1)
	return v_max

func _resumen() -> void:
	print("=====================================================")
	print("RESUMEN: %d OK, %d FALLA" % [_pasadas, _falladas])
	print("=====================================================")