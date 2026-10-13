extends Node3D

# Suite A del SISTEMA DE ESTAMINA sobre el jugador REAL (parte 1: HUD, movimiento
# del humano y del velocista):
#   1.  La barra existe UNA sola vez, a la IZQUIERDA de la pantalla y centrada.
#   2.  Colores por personaje (6 formas) + una sola barra tras 6 transformaciones.
#   3.  El relleno se mueve SUAVE (nunca salta de golpe al valor real).
#   4.  Caminar consume poco y correr más (tasas de la tabla); quieto no gasta nada.
#   5.  Sin estamina: correr bloqueado (velocidad de paseo) pero caminar SIEMPRE vivo.
#   6.  Transformarse NO restaura (cada personaje conserva SU estamina).
#   7.  Velocista: esprinta y consume al ritmo del esprint (la tasa más alta).
#   8.  Golpe del velocista: cobra UNA vez; no vuelve a cobrar; con 0 la pulsación
#       ni siquiera llega al sistema.
#   9.  Dash y supervelocidad: activación única + consumo sostenido del trayecto;
#       sin estamina se cancelan con seguridad (estado normal, sin atascos).
#
# Las mediciones leen SIEMPRE la estamina interna del personaje (`_leer`), no el
# espejo público, así no dependen de cuándo se sincronizó por última vez.
# No forma parte del juego: vive en res://_tests/ y se ejecuta como ESCENA.

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

const F_HUMANO := 0
const F_VELOCISTA := 1

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

## Estamina cruda (interna) de una forma: la medida NO depende del espejo público.
func _leer(id: StringName) -> float:
	return float(_stats.estado_de_forma(id).get("stamina", -1.0))

## Fija la estamina de una forma y deja su regeneración detenida en la ventana de
## la medición (el reloj de gasto vuelve a 0). Sincroniza el espejo público si esa
## forma es la activa (es lo que vería el HUD).
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

func _tasa(clave: StringName) -> float:
	return CostosEstamina.costo_movimiento(_stats.forma_actual(), clave)

## Consumo + velocidad máxima observada durante `seg` con las acciones pulsadas.
func _medir_movimiento(acciones: Array, seg: float) -> Dictionary:
	var id := _stats.forma_actual()
	var antes := _leer(id)
	for a in acciones:
		Input.action_press(a)
	var v_max := 0.0
	var t := 0.0
	while t < seg:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		v_max = maxf(v_max, Vector2(_jug.velocity.x, _jug.velocity.z).length())
	for a in acciones:
		Input.action_release(a)
	await _esperar(1)
	return {"gastado": antes - _leer(id), "v_max": v_max}

## Velocidad horizontal máxima alcanzada con las acciones dadas (ignora el arranque).
func _medir_velocidad(acciones: Array, seg: float) -> float:
	for a in acciones:
		Input.action_press(a)
	var v_max := 0.0
	var t := 0.0
	while t < seg:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t > 0.4:
			v_max = maxf(v_max, Vector2(_jug.velocity.x, _jug.velocity.z).length())
	for a in acciones:
		Input.action_release(a)
	await _esperar(1)
	return v_max

func _correr() -> void:
	print("=== PRUEBA ESTAMINA A: HUD, movimiento y velocista ===")

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
	for n in _jug.get_children():
		if n is HUDCircular:
			_hud = n
	await _esperar(30)
	if _stats == null or _hud == null:
		_check("jugador, estadísticas y HUD listos", false)
		_resumen()
		return
	_check("jugador, estadísticas y HUD listos", true)
	await _esperar_seg(0.4)

	# ------------------------------------------------ 1. Barra única, a la izquierda
	var barra: Node = _hud.get_node_or_null("Raiz/BarraEstamina")
	var vista := get_viewport().get_visible_rect().size
	var pos: Vector2 = (barra as Control).position if barra != null else Vector2.ZERO
	_check("1. La barra de estamina existe en el HUD", barra != null)
	_check("1. A la IZQUIERDA de la pantalla (margen %.0f) y centrada en vertical" % CostosEstamina.EST_MARGEN_X,
			barra != null and is_equal_approx(pos.x, CostosEstamina.EST_MARGEN_X) \
				and pos.x < vista.x * 0.5 \
				and absf(pos.y - (vista.y * 0.5 - CostosEstamina.EST_ALTO * 0.5)) < 3.0,
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
		if not c.is_equal_approx(CostosEstamina.color_de(id)):
			colores_ok = false
			detalle_colores += "%s: %s " % [id, c]
	_check("2. Cada forma pinta SU color con la señal de transformación",
			colores_ok, detalle_colores)
	var ch := CostosEstamina.color_de(&"humano")
	var cv := CostosEstamina.color_de(&"velocista")
	var cp := CostosEstamina.color_de(&"pes")
	var ct := CostosEstamina.color_de(&"tanque")
	var cc := CostosEstamina.color_de(&"combate")
	var ca := CostosEstamina.color_de(&"aguila")
	_check("2. Max = violeta rosado; velocista = rojo; pez = azul; tanque = naranja",
			ch.r > 0.6 and ch.g < 0.6 and ch.b > 0.85 \
				and cv.r > 0.9 and cv.g < 0.3 and cv.b < 0.3 \
				and cp.b > 0.9 and cp.r < 0.3 \
				and ct.r > 0.9 and ct.g > 0.3 and ct.g < 0.7 and ct.b < 0.3)
	_check("2. Combate = oscuro con borde claro; águila = blanco con borde oscuro",
			cc.r < 0.3 and cc.g < 0.3 and cc.b < 0.3 \
				and CostosEstamina.borde_de(&"combate").get_luminance() > 0.6 \
				and ca.r > 0.9 and ca.g > 0.9 and ca.b > 0.9 \
				and CostosEstamina.borde_de(&"aguila").get_luminance() < 0.3)
	_jug.forma_cambiada.emit(&"humano")
	var n_barras := 0
	for n in _hud.get_node("Raiz").get_children():
		if n.name == "BarraEstamina":
			n_barras += 1
	_check("2. Sigue habiendo UNA sola barra tras 6 transformaciones", n_barras == 1)

	# ------------------------------------------------ 3. Relleno suave
	_poner(&"humano", 20.0)
	_stats.stamina_cambiada.emit(_stats.stamina, _stats.stamina_max)
	await _esperar(1)
	_check("3. El objetivo salta al valor real pero el relleno NO (suave)",
			is_equal_approx(_hud._est_objetivo, 0.2) and _hud._est_mostrado > 0.5,
			"objetivo=%.2f mostrado=%.2f" % [_hud._est_objetivo, _hud._est_mostrado])
	await _esperar_seg(1.0)
	_check("3. El relleno llega al valor real suavemente",
			absf(_hud._est_mostrado - 0.2) < 0.06,
			"mostrado=%.2f" % _hud._est_mostrado)

	# ------------------------------------------------ 4. Caminar / correr / quieto
	_poner(&"humano", 100.0)
	var m_cam := await _medir_movimiento([&"mover_adelante"], 1.2)
	var esp_cam := _tasa(&"caminar") * 1.2
	_check("4. Caminar consume poco (%.1f/s)" % _tasa(&"caminar"),
			m_cam["gastado"] >= esp_cam * 0.7 and m_cam["gastado"] <= esp_cam * 1.3,
			"gastado=%.1f (esperado≈%.1f) v_max=%.1f" % [m_cam["gastado"], esp_cam, m_cam["v_max"]])
	_poner(&"humano", 100.0)
	var m_cor := await _medir_movimiento([&"mover_adelante", &"correr"], 1.2)
	var esp_cor := _tasa(&"correr") * 1.2
	_check("4. Correr consume MÁS que caminar (%.1f/s > %.1f/s)" % [_tasa(&"correr"), _tasa(&"caminar")],
			m_cor["gastado"] > m_cam["gastado"] * 1.6 \
				and m_cor["gastado"] >= esp_cor * 0.7 and m_cor["gastado"] <= esp_cor * 1.3,
			"gastado=%.1f (esperado≈%.1f) v_max=%.1f" % [m_cor["gastado"], esp_cor, m_cor["v_max"]])
	await _esperar_seg(0.4)  # que el cuerpo quede del todo quieto
	_poner(&"humano", 60.0)
	await _esperar_seg(1.0)
	_check("4. Quieto (sin acciones) NO gasta nada", is_equal_approx(_leer(&"humano"), 60.0),
			"%.2f (vel=%.2f)" % [_leer(&"humano"), Vector2(_jug.velocity.x, _jug.velocity.z).length()])

	# ------------------------------------------------ 5. Agotado: sin correr, caminar sí
	_poner(&"humano", 0.0)
	await _esperar(2)
	var vel_agotado := await _medir_velocidad([&"mover_adelante", &"correr"], 1.0)
	_check("5. Con 0 de estamina el correr queda bloqueado (velocidad de paseo)",
			vel_agotado > 0.5 and vel_agotado <= _jug.H_VEL_CAMINAR + 0.6,
			"vel=%.2f (paseo %.1f)" % [vel_agotado, _jug.H_VEL_CAMINAR])
	_poner(&"humano", 80.0)
	var vel_normal := await _medir_velocidad([&"mover_adelante", &"correr"], 1.0)
	_check("5. Con estamina el mismo input SÍ corre",
			vel_normal > vel_agotado + 1.5, "vel=%.2f" % vel_normal)
	await _esperar_seg(0.4)

	# ------------------------------------------------ 6. Transformar no restaura
	_poner(&"humano", 40.0)
	var humano_al_salir := _leer(&"humano")
	var ok_v := await _cambiar_forma(&"velocista", F_VELOCISTA)
	_check("6. Transformado a velocista", ok_v, "forma=%d" % int(_jug.forma))
	_check("6. El velocista arranca con SU estamina (no hereda la del humano)",
			is_equal_approx(_leer(&"velocista"), _stats.stamina_max),
			"velocista=%.1f humano=%.1f" % [_leer(&"velocista"), _leer(&"humano")])
	_check("6. El humano conserva la suya al salir (no se restaura)",
			_leer(&"humano") <= humano_al_salir + 25.0, "humano=%.1f" % _leer(&"humano"))

	# ------------------------------------------------ 7. Velocista: esprint
	_poner(&"velocista", 100.0)
	var m_esp := await _medir_movimiento([&"mover_adelante", &"correr"], 1.2)
	var esp_esp := _tasa(&"esprintar") * 1.2
	_check("7. El velocista esprinta (%.1f/s) y se cobra esa tasa" % _tasa(&"esprintar"),
			m_esp["gastado"] >= esp_esp * 0.7 and m_esp["gastado"] <= esp_esp * 1.3,
			"gastado=%.1f (esperado≈%.1f) v_max=%.1f" % [m_esp["gastado"], esp_esp, m_esp["v_max"]])
	_check("7. La tasa de esprint del velocista es la más alta de las formas terrestres",
			_tasa(&"esprintar") > CostosEstamina.costo_movimiento(&"humano", &"correr") \
				and _tasa(&"esprintar") > _tasa(&"caminar"))

	# ------------------------------------------------ 8. Golpe del velocista
	await _esperar_seg(0.4)
	_poner(&"velocista", 50.0)
	_jug.combate.intentar_golpe()
	await _esperar(3)
	var tras_golpe := _leer(&"velocista")
	var coste_golpe := CostosEstamina.costo_ataque(&"velocista", &"golpe")
	_check("8. Un golpe del velocista cobra UNA vez (%.1f)" % coste_golpe,
			absf(tras_golpe - (50.0 - coste_golpe)) < 0.6,
			"%.2f → %.2f" % [50.0, tras_golpe])
	await _esperar_seg(0.6)
	_check("8. El golpe NO vuelve a cobrar al conectarse",
			absf(_leer(&"velocista") - tras_golpe) < 0.6, "%.2f" % _leer(&"velocista"))
	# Pulsación con 0: el gate del input ni la deja llegar al sistema.
	_poner(&"velocista", 0.0)
	_jug._ataque_activo = false
	await _tecla_accion(&"atacar")
	await _esperar(6)
	_check("8. Con 0 de estamina la pulsación de ataque NO llega al sistema",
			not _jug._ataque_activo and is_zero_approx(_leer(&"velocista")),
			"ataque_activo=%s" % _jug._ataque_activo)

	# ------------------------------------------------ 9. Dash y supervelocidad
	_poner(&"velocista", 50.0)
	_jug._intentar_dash()
	await _esperar(2)
	var coste_dash := CostosEstamina.costo_habilidad(&"velocista", &"dash")
	_check("9. Dash: cobra %.1f al arrancar y cambia el estado" % coste_dash,
			absf(_leer(&"velocista") - (50.0 - coste_dash)) < 0.6 and _jug.estado != 0,
			"estamina=%.1f estado=%d" % [_leer(&"velocista"), _jug.estado])
	_jug._detener_velocista()
	await _esperar(2)
	# Activación de la supervelocidad (sincrónica: se lee al volver).
	_poner(&"velocista", 50.0)
	_jug._iniciar_recorrido()
	var coste_super := CostosEstamina.costo_habilidad(&"velocista", &"supervelocidad")
	_check("9. Supervelocidad: la activación cobra %.1f" % coste_super,
			absf(_leer(&"velocista") - (50.0 - coste_super)) < 0.6,
			"estamina=%.1f" % _leer(&"velocista"))
	_jug._detener_velocista()
	await _esperar(2)
	# Consumo sostenido del trayecto (tramo EJECUCION) en un segundo simulado.
	_jug.estado = 5  # Estado.EJECUCION
	_poner(&"velocista", 50.0)
	_jug._procesar_estamina_movimiento(1.0)
	var g_super := 50.0 - _leer(&"velocista")
	_jug._detener_velocista()
	await _esperar(2)
	_check("9. La supervelocidad consume por segundo mientras corre (%.1f/s)" % _tasa(&"supervelocidad"),
			absf(g_super - _tasa(&"supervelocidad")) < 1.0,
			"gastado=%.2f en 1 s simulado" % g_super)
	# Sin estamina: la ruta se cancela con seguridad.
	_poner(&"velocista", 0.0)
	_jug._iniciar_recorrido()
	await _esperar(2)
	_check("9. Sin estamina la supervelocidad se cancela con seguridad (estado normal)",
			_jug.estado == 0 and is_zero_approx(_leer(&"velocista")),
			"estado=%d" % _jug.estado)

	_resumen()

func _resumen() -> void:
	print("=====================================================")
	print("RESUMEN A: %d OK, %d FALLA" % [_pasadas, _falladas])
	print("=====================================================")