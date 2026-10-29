extends Node3D

# Suite C del SISTEMA DE ESTAMINA sobre el jugador REAL (parte 3: águila/vuelo,
# regeneración y muerte/respawn):
#   1.  Vuelo: el despegue se paga UNA vez; volar consume continuamente.
#   2.  Con 0 de estamina el ave hace un DESCENSO forzado y controlado (aterriza,
#       nunca cae en seco ni queda la estamina negativa). Sin despegar si no
#       alcanza el coste; con estamina vuelve a volar y baja cuando quiere.
#   3.  Pluma (paga por disparo), palmazo (paga al ejecutarse) y garras (sin presa
#       no cobra): la activación real es la que paga.
#   4.  El golpe de suelo del águila cobra una vez al lanzarse.
#   5.  Regeneración: espera corta y luego ~velocidad_regen_estamina/s; desde 0
#       también recupera; nunca pasa del máximo; NUNCA regenera durante un consumo
#       sostenido; el gasto sostenido jamás deja la estamina en negativo.
#   6.  Muerte: un personaje muerto no gasta ni regenera; reiniciar() limpia
#       (respawn con todo a tope).
#
# Las mediciones leen SIEMPRE la estamina interna del personaje (`_leer`).
# No forma parte del juego: vive en res://pruebas/ y se ejecuta como ESCENA.

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

const F_HUMANO := 0
const F_VUELO := 5

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

## Espera (en fotogramas físicos, con tope de 5 s) a que el RELOJ de gasto del
## humano llegue a `seg`: la espera de la regeneración se mide con el reloj real.
func _esperar_reloj(seg: float) -> void:
	var e := _stats._estados[&"humano"] as Dictionary
	var t := 0.0
	while float(e["t_desde_gasto"]) < seg and t < 5.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0

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

func _tasa_para(id: StringName, clave: StringName) -> float:
	return CostosEstamina.costo_movimiento(id, clave)

func _correr() -> void:
	print("=== PRUEBA ESTAMINA C: águila, regeneración y muerte ===")

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

	# ------------------------------------------------ 5. Regeneración
	var espera := _stats.espera_regen_estamina
	_poner(&"humano", 40.0)
	_stats.probar_gasto(10.0, &"prueba")
	_check("5. probar_gasto cobra una vez y deja registro",
			is_equal_approx(_leer(&"humano"), 30.0) and _stats.ultimo_gasto == &"prueba",
			"%.1f motivo=%s" % [_leer(&"humano"), _stats.ultimo_gasto])
	# La espera se comprueba sobre el RELOJ REAL del gasto (t_desde_gasto), no
	# sobre una cuenta de fotogramas: la medición no depende del ritmo de render.
	await _esperar_reloj(espera)
	var s0 := _leer(&"humano")
	await _esperar_seg(0.6)
	var subida := _leer(&"humano") - s0
	_check("5. Cumplida la espera (%.1f s) regenera (~%.0f/s)" % [espera, _stats.velocidad_regen_estamina],
			subida > 2.0 and subida <= _stats.velocidad_regen_estamina * 0.6 + 3.0,
			"subió %.1f en 0.6 s (desde %.1f)" % [subida, s0])
	# Desde CERO también recupera.
	_poner(&"humano", 0.0)
	await _esperar(2)
	await _esperar_reloj(espera)
	await _esperar_seg(0.5)
	_check("5. Desde 0 la estamina SE RECUPERA (no queda trabada)",
			_leer(&"humano") > 2.0, "%.1f" % _leer(&"humano"))
	# No pasa del máximo.
	_poner(&"humano", _stats.stamina_max - 3.0)
	await _esperar_seg(espera + 0.8)
	_check("5. La regeneración NUNCA pasa del máximo",
			_leer(&"humano") <= _stats.stamina_max + 0.001,
			"%.2f / %.2f" % [_leer(&"humano"), _stats.stamina_max])
	# Consumo sostenido: la regeneración queda apagada.
	_poner(&"humano", 50.0)
	var t_cons := 0
	while t_cons < 120:
		_stats.gastar_continuo(0.2)
		await get_tree().physics_frame
		t_cons += 1
	_check("5. Mientras hay consumo sostenido NO regenera (sólo descuenta)",
			_leer(&"humano") <= 50.0 - 24.0 + 1.5 and _leer(&"humano") > 10.0,
			"%.1f (descuento puro≈26.0; cualquier valor igual o menor prueba que no hubo regeneración)" % _leer(&"humano"))
	_stats.gastar_continuo(999.0)
	_check("5. El gasto sostenido nunca deja la estamina en negativo",
			_leer(&"humano") >= 0.0 and is_zero_approx(_leer(&"humano")),
			"%.3f" % _leer(&"humano"))

	# ------------------------------------------------ 1/2. Águila: vuelo
	# Vuelo está BLOQUEADO hasta completar la misión de Iván: se completa para
	# poder probar la estamina del águila (el bloqueo en sí no se prueba aquí).
	Misiones.marcar_completada(Misiones.MISION_PROFUGOS)
	var ok_a := await _cambiar_forma(&"aguila", F_VUELO)
	_check("1. Transformado al águila (vuelo)", ok_a, "forma=%d" % int(_jug.forma))
	await _esperar_seg(0.6)
	var fc: Node = _jug.vuelo.get_node_or_null("FlightController")
	_check("1. El cuerpo volador existe con su FlightController", fc != null)
	if fc == null:
		_resumen()
		return
	# Despegue pagado una vez.
	_poner(&"aguila", 100.0)
	await _tecla_accion(&"toggle_flight")
	await _esperar(5)
	var coste_despegue := CostosEstamina.costo_habilidad(&"aguila", &"despegue")
	_check("1. Despegue: cobra %.1f una sola vez y levanta el vuelo" % coste_despegue,
			bool(fc.is_flying) and absf(_leer(&"aguila") - (100.0 - coste_despegue)) < 1.5,
			"vuela=%s estamina=%.1f" % [fc.is_flying, _leer(&"aguila")])
	# Consumo continuo al volar.
	_poner(&"aguila", 80.0)
	await _esperar_seg(1.0)
	var g_volar := 80.0 - _leer(&"aguila")
	var tasa_volar := _tasa_para(&"aguila", &"volar")
	_check("1. Volar consume progresivamente (%.1f/s)" % tasa_volar,
			g_volar > tasa_volar * 0.6 and g_volar < tasa_volar * 1.4,
			"gastado=%.1f en 1 s" % g_volar)
	# Agotamiento en pleno vuelo: descenso forzado y aterrizaje.
	_poner(&"aguila", 0.2)
	await _esperar(3)
	var descendiendo := bool(fc.descenso_forzado)
	var t_baja := 0.0
	while bool(fc.is_flying) and t_baja < 4.0:
		await get_tree().physics_frame
		t_baja += 1.0 / 60.0
	_check("2. Con 0 de estamina el vuelo hace un DESCENSO forzado y aterriza",
			descendiendo and not bool(fc.is_flying) and t_baja < 4.0,
			"descenso=%s aterrizó en %.1f s" % [descendiendo, t_baja])
	_check("2. Tras el descenso la estamina sigue sin ser negativa",
			_leer(&"aguila") >= 0.0, "%.2f" % _leer(&"aguila"))
	await _esperar_seg(0.5)
	# Sin estamina no se despega.
	_poner(&"aguila", 5.0)
	await _tecla_accion(&"toggle_flight")
	await _esperar(5)
	_check("2. Sin estamina suficiente el despegue queda bloqueado",
			not bool(fc.is_flying) and is_equal_approx(_leer(&"aguila"), 5.0),
			"vuela=%s estamina=%.1f" % [fc.is_flying, _leer(&"aguila")])
	# Con estamina se puede volver a volar y bajar a voluntad.
	_poner(&"aguila", 60.0)
	await _tecla_accion(&"toggle_flight")
	await _esperar(5)
	var volvio := bool(fc.is_flying)
	await _tecla_accion(&"toggle_flight")
	await _esperar_seg(1.5)
	_check("2. Con estamina vuelve a volar y baja cuando quiere (sin descenso forzado)",
			volvio and not bool(fc.is_flying) and not bool(fc.descenso_forzado),
			"volvió=%s" % volvio)

	# ------------------------------------------------ 3. Pluma, palmazo y garras
	var plumas: Node = _jug.vuelo.get_node_or_null("FeatherAbility")
	_check("3. La habilidad de plumas existe", plumas != null)
	if plumas != null:
		_poner(&"aguila", 50.0)
		var coste_pluma := CostosEstamina.costo_ataque(&"aguila", &"pluma")
		plumas.call("_disparo_con_clip")
		await _esperar(2)
		_check("3. Cada pluma cobra al dispararse (%.1f)" % coste_pluma,
				absf(_leer(&"aguila") - (50.0 - coste_pluma)) < 0.6,
				"estamina=%.1f" % _leer(&"aguila"))
		_poner(&"aguila", 0.0)
		plumas.call("_disparo_con_clip")
		await _esperar(2)
		_check("3. Sin estamina la pluma no se dispara (sin cobro)",
				is_zero_approx(_leer(&"aguila")))
	var palmazo: Node = null
	for n in _jug.vuelo.find_children("*", "", true, false):
		var sc: Script = n.get_script() as Script
		if sc != null and String(sc.resource_path).ends_with("palmazo_viento.gd"):
			palmazo = n
	_check("3. La habilidad del palmazo existe", palmazo != null)
	if palmazo != null:
		palmazo.set("_cd", 0.0)
		_poner(&"aguila", 50.0)
		var coste_palmazo := CostosEstamina.costo_habilidad(&"aguila", &"palmazo")
		await _tecla_accion(&"palmazo")
		await _esperar(3)
		_check("3. Palmazo: cobra %.1f al ejecutarse" % coste_palmazo,
				absf(_leer(&"aguila") - (50.0 - coste_palmazo)) < 0.6,
				"estamina=%.1f" % _leer(&"aguila"))
		palmazo.set("_cd", 0.0)
		_poner(&"aguila", 0.0)
		await _tecla_accion(&"palmazo")
		await _esperar(3)
		_check("3. Sin estamina el palmazo no se ejecuta", is_zero_approx(_leer(&"aguila")))
	var garras: Node = _jug.vuelo.get_node_or_null("TalonsAbility")
	_check("3. La habilidad de garras existe", garras != null)
	if garras != null:
		_poner(&"aguila", 100.0)
		garras.call("_intentar_agarrar")
		await _esperar(2)
		_check("3. Garras sin presa a mano: NO cobra (falla antes de ejecutarse)",
				is_equal_approx(_leer(&"aguila"), 100.0), "estamina=%.1f" % _leer(&"aguila"))
	# ------------------------------------------------ 4. Golpe de suelo del águila
	var gc: Node = _jug.vuelo.get_node_or_null("GroundCombat")
	_check("4. El combate de suelo del águila existe", gc != null)
	if gc != null and not (gc.get("cadena") as Array).is_empty():
		_poner(&"aguila", 50.0)
		var coste_golpe_a := CostosEstamina.costo_ataque(&"aguila", &"golpe")
		gc.call("_lanzar", 0)
		await _esperar(3)
		_check("4. El golpe del águila cobra una vez al lanzarse (%.1f)" % coste_golpe_a,
				absf(_leer(&"aguila") - (50.0 - coste_golpe_a)) < 0.6,
				"estamina=%.1f" % _leer(&"aguila"))
		gc.call("cancelar_todo")

	# ------------------------------------------------ 6. Muerte / reinicio
	var ok_h := await _volver_humano()
	_check("6. Vuelta a humano correcta", ok_h, "forma=%d" % int(_jug.forma))
	_poner(&"humano", 30.0)
	_stats.recibir_danio(9999.0)
	await _esperar(3)
	_check("6. El personaje muere con el escudo y la vida a cero", _stats.muerto)
	_check("6. Un personaje muerto no gasta estamina al pedirla",
			not _stats.probar_gasto(1.0) and is_equal_approx(_leer(&"humano"), 30.0),
			"%.1f" % _leer(&"humano"))
	_stats.gastar_continuo(5.0)
	await _esperar_seg(1.0)
	_check("6. Un personaje muerto tampoco regenera ni gasta",
			is_equal_approx(_leer(&"humano"), 30.0), "%.1f" % _leer(&"humano"))
	_stats.reiniciar()
	await _esperar(3)
	_check("6. reiniciar() devuelve vida y estamina a tope (respawn limpio)",
			is_equal_approx(_stats.vida, _stats.vida_max) \
				and is_equal_approx(_leer(&"humano"), _stats.stamina_max) and not _stats.muerto,
			"vida=%.0f estamina=%.0f" % [_stats.vida, _leer(&"humano")])

	_resumen()

func _resumen() -> void:
	print("=====================================================")
	print("RESUMEN C: %d OK, %d FALLA" % [_pasadas, _falladas])
	print("=====================================================")