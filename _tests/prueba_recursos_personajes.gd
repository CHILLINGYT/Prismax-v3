extends Node3D

## Arnés de prueba (headless, como ESCENA) de los RECURSOS POR PERSONAJE:
## vida y escudo INDEPENDIENTES para cada una de las cinco formas del jugador, y
## su regeneración (el activo al 100 %, cada inactivo exactamente al 50 %).
##
## Trabaja sobre el jugador REAL (`leo_jugador.tscn`) con su HUD real, así que
## valida también que el HUD muestra al personaje activo y se actualiza al
## cambiar de forma, y que la transformación real del controlador cambia los
## recursos. Se ejecuta como escena (necesita el mundo en marcha):
##
##   godot --headless --path . _tests/prueba_recursos_personajes.tscn

const FORMA_VELOCISTA := 1
const MAX_ESPERA_TRANSICION := 900
const FORMAS := [&"humano", &"velocista", &"pes", &"tanque", &"combate"]

var _pasadas := 0
var _falladas := 0

@onready var jug: ControladorLeo = $Jugador
var _stats: EstadisticasJugador = null
var _hud: Node = null

func _ready() -> void:
	_stats = jug.get_node_or_null("Estadisticas") as EstadisticasJugador
	_hud = jug.get_node_or_null("HUD")
	call_deferred("_correr")

func _check(nombre: String, ok: bool, detalle: String = "") -> void:
	var sufijo := (" — " + detalle) if detalle != "" else ""
	if ok:
		_pasadas += 1
		print("[OK]    ", nombre, sufijo)
	else:
		_falladas += 1
		print("[FALLA] ", nombre, sufijo)

func _esperar(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame

func _esperar_seg(s: float) -> void:
	await _esperar(int(ceil(s * 60.0)))

func _datos(id: StringName) -> Dictionary:
	return _stats.estado_de_forma(id)

func _contar_estadisticas(n: Node) -> int:
	var c := 1 if n is EstadisticasJugador else 0
	for h in n.get_children():
		c += _contar_estadisticas(h)
	return c

func _resumen() -> void:
	print("=== RESULTADO: %d OK, %d FALLOS ===" % [_pasadas, _falladas])
	get_tree().quit(1 if _falladas > 0 else 0)

func _correr() -> void:
	print("=== PRUEBA: recursos (vida/escudo) por personaje + regeneración ===")
	if _stats == null:
		_check("el jugador tiene el nodo Estadisticas", false, "no encontrado")
		_resumen()
		return
	_check("el jugador tiene el nodo Estadisticas", true)
	_check("el jugador tiene su HUD real", _hud != null)
	await _esperar(20)

	# --- 1: estado inicial ---------------------------------------------------
	_check("arranca con el humano como personaje activo",
			_stats.forma_actual() == &"humano", "forma=%s" % _stats.forma_actual())
	_check("arranca a tope (vida y escudo)",
			is_equal_approx(_stats.vida, _stats.vida_max)
			and is_equal_approx(_stats.resistencia, _stats.resistencia_max),
			"vida=%.1f/%.1f escudo=%.1f/%.1f" % [_stats.vida, _stats.vida_max,
					_stats.resistencia, _stats.resistencia_max])

	# --- 1b: máximos propios de cada personaje ------------------------------
	var esperados := {
		&"humano": Vector2(50.0, 50.0),
		&"velocista": Vector2(80.0, 120.0),
		&"pes": Vector2(100.0, 140.0),
		&"tanque": Vector2(140.0, 60.0),
		&"combate": Vector2(110.0, 90.0),
	}
	for id in esperados.keys():
		_stats.aplicar_forma(id)
	var tabla_ok := true
	var filas := ""
	for id in esperados.keys():
		var e := _datos(id)
		var vm: float = e["vida_max"]
		var rm: float = e["resistencia_max"]
		filas += "%s %.0f/%.0f  " % [id, vm, rm]
		if not (is_equal_approx(vm, esperados[id].x) and is_equal_approx(rm, esperados[id].y)):
			tabla_ok = false
		if not (is_equal_approx(float(e["vida"]), vm) and is_equal_approx(float(e["resistencia"]), rm)):
			tabla_ok = false
	_check("cada personaje usa SUS máximos y arranca a tope", tabla_ok, filas)
	_stats.aplicar_forma(&"humano")

	# --- 2: los recursos son independientes por personaje --------------------
	_stats.recibir_danio(50.0)
	var h1 := _datos(&"humano")
	_check("el daño al humano baja SU vida y SU escudo",
			is_equal_approx(h1["vida"], 40.0) and is_equal_approx(h1["resistencia"], 10.0),
			"vida=%.1f escudo=%.1f" % [h1["vida"], h1["resistencia"]])

	_stats.aplicar_forma(&"velocista")
	var v1 := _datos(&"velocista")
	_check("el velocista entra con recursos PROPIOS e intactos",
			is_equal_approx(v1["vida"], 80.0) and is_equal_approx(v1["resistencia"], 120.0),
			"vida=%.1f escudo=%.1f" % [v1["vida"], v1["resistencia"]])
	_check("el daño del humano no tocó al velocista",
			is_equal_approx(_datos(&"humano")["vida"], 40.0)
			and is_equal_approx(_datos(&"humano")["resistencia"], 10.0))

	_stats.recibir_danio(30.0)
	var v2 := _datos(&"velocista")
	_check("el daño al velocista baja los suyos",
			is_equal_approx(v2["vida"], 74.0) and is_equal_approx(v2["resistencia"], 96.0),
			"vida=%.1f escudo=%.1f" % [v2["vida"], v2["resistencia"]])
	_check("el daño del velocista no tocó al humano",
			is_equal_approx(_datos(&"humano")["vida"], 40.0)
			and is_equal_approx(_datos(&"humano")["resistencia"], 10.0))

	_stats.aplicar_forma(&"humano")
	var h2 := _datos(&"humano")
	_check("al volver al humano sus recursos siguen ahí (no se restauran)",
			is_equal_approx(h2["vida"], 40.0) and is_equal_approx(h2["resistencia"], 10.0),
			"vida=%.1f escudo=%.1f" % [h2["vida"], h2["resistencia"]])

	# --- 3: regeneración (activo 100 %, inactivo 50 %) -----------------------
	# Los dos candidatos reciben su daño en el MISMO fotograma: así la única
	# diferencia entre ellos es ser el activo o el inactivo.
	_stats.reiniciar()                   # todos a tope con SUS máximos
	_stats.aplicar_forma(&"humano")
	_stats.recibir_danio(70.0)           # humano (50/50): escudo a 0, vida a 30
	_stats.aplicar_forma(&"velocista")
	_stats.recibir_danio(170.0)          # velocista (80/120): escudo a 0, vida a 30
	_stats.aplicar_forma(&"pes")         # este debe llegar JUSTO al tope
	_stats.recibir_danio(0.5)
	_stats.aplicar_forma(&"combate")     # este muere: no regenera ni revive
	_stats.recibir_danio(400.0)
	_check("un golpe de 400 mata al personaje en curso",
			bool(_datos(&"combate")["muerto"]), "vida=%.1f" % _datos(&"combate")["vida"])

	# Activo = velocista; inactivos = humano (y pes, combate).
	_stats.aplicar_forma(&"velocista")
	await _esperar_seg(_stats.espera_regeneracion + 0.6)
	var a := {"humano": _datos(&"humano"), "velocista": _datos(&"velocista")}
	var t_a := Time.get_ticks_msec()
	await _esperar_seg(1.6)
	var b := {"humano": _datos(&"humano"), "velocista": _datos(&"velocista")}
	var t_b := Time.get_ticks_msec()

	var dt := maxf(0.2, float(t_b - t_a) / 1000.0)
	var tasa_esc_act: float = (float(b["velocista"]["resistencia"]) - float(a["velocista"]["resistencia"])) / dt
	var tasa_esc_ina: float = (float(b["humano"]["resistencia"]) - float(a["humano"]["resistencia"])) / dt
	var tasa_vid_act: float = (float(b["velocista"]["vida"]) - float(a["velocista"]["vida"])) / dt
	var tasa_vid_ina: float = (float(b["humano"]["vida"]) - float(a["humano"]["vida"])) / dt
	var esperado_esc: float = _stats.velocidad_regeneracion
	var esperado_vid: float = _stats.velocidad_regen_vida
	var fac: float = _stats.factor_inactivo

	_check("el personaje ACTIVO regenera el escudo a su ritmo",
			absf(tasa_esc_act - esperado_esc) <= esperado_esc * 0.15,
			"%.1f/s (configurado %.1f/s)" % [tasa_esc_act, esperado_esc])
	_check("el personaje INACTIVO regenera el escudo al 50 %",
			absf(tasa_esc_ina - esperado_esc * fac) <= esperado_esc * fac * 0.2,
			"%.1f/s (esperado %.1f/s)" % [tasa_esc_ina, esperado_esc * fac])
	_check("la regeneración de escudo del inactivo es la MITAD de la del activo",
			absf(tasa_esc_ina / maxf(tasa_esc_act, 0.001) - fac) <= 0.06,
			"ratio=%.3f" % (tasa_esc_ina / maxf(tasa_esc_act, 0.001)))
	_check("el personaje ACTIVO regenera la vida a su ritmo",
			absf(tasa_vid_act - esperado_vid) <= esperado_vid * 0.2,
			"%.1f/s (configurado %.1f/s)" % [tasa_vid_act, esperado_vid])
	_check("la regeneración de vida del inactivo es la MITAD de la del activo",
			absf(tasa_vid_ina / maxf(tasa_vid_act, 0.001) - fac) <= 0.08,
			"ratio=%.3f (%.1f/s vs %.1f/s)" % [
					tasa_vid_ina / maxf(tasa_vid_act, 0.001), tasa_vid_ina, tasa_vid_act])

	var pe := _datos(&"pes")
	_check("la regeneración llega JUSTO al tope y no lo sobrepasa",
			is_equal_approx(pe["vida"], pe["vida_max"])
			and is_equal_approx(pe["resistencia"], pe["resistencia_max"]),
			"vida=%.3f/%.1f escudo=%.3f/%.1f" % [pe["vida"], pe["vida_max"],
					pe["resistencia"], pe["resistencia_max"]])
	var co := _datos(&"combate")
	_check("un personaje muerto NO regenera ni revive solo",
			is_equal_approx(co["vida"], 0.0) and bool(co["muerto"]),
			"vida=%.3f muerto=%s" % [co["vida"], str(co["muerto"])])
	_check("hay UN solo nodo de estadísticas (sin regeneración duplicada)",
			_contar_estadisticas(jug) == 1, "nodos=%d" % _contar_estadisticas(jug))

	# --- 4: el HUD muestra al personaje ACTIVO -------------------------------
	var f_vel: float = _datos(&"velocista")["vida"] / _datos(&"velocista")["vida_max"]
	_check("el HUD muestra la vida del personaje activo (velocista)",
			absf(_hud._anillo_vida._valor - f_vel) <= 0.02,
			"hud=%.3f real=%.3f" % [_hud._anillo_vida._valor, f_vel])

	_stats.aplicar_forma(&"humano")
	var hh := _datos(&"humano")
	var f_hum: float = hh["vida"] / hh["vida_max"]
	_check("al cambiar de personaje el HUD se actualiza en el mismo fotograma",
			absf(_hud._anillo_vida._valor - f_hum) <= 0.02 and absf(f_hum - f_vel) > 0.02,
			"hud=%.3f humano=%.3f velocista=%.3f" % [_hud._anillo_vida._valor, f_hum, f_vel])
	_check("el HUD también cambia el escudo al personaje nuevo",
			absf(_hud._anillo_resist._valor - hh["resistencia"] / hh["resistencia_max"]) <= 0.02,
			"hud=%.3f real=%.3f" % [_hud._anillo_resist._valor,
					hh["resistencia"] / hh["resistencia_max"]])

	# --- 5: la transformación REAL del controlador cambia los recursos -------
	jug._on_transformacion_elegida(&"velocista")
	var t := 0
	while (int(jug.forma) != FORMA_VELOCISTA or jug._transformando) and t < MAX_ESPERA_TRANSICION:
		await get_tree().physics_frame
		t += 1
	_check("el velocista entra por el menú de transformaciones",
			int(jug.forma) == FORMA_VELOCISTA, "forma=%d" % int(jug.forma))
	_check("el controlador cambia los recursos al personaje nuevo",
			_stats.forma_actual() == &"velocista", "stats=%s" % _stats.forma_actual())
	var v3 := _datos(&"velocista")
	_check("y el HUD pasa a mostrar los del velocista",
			absf(_hud._anillo_vida._valor - v3["vida"] / v3["vida_max"]) <= 0.02,
			"hud=%.3f real=%.3f" % [_hud._anillo_vida._valor, v3["vida"] / v3["vida_max"]])

	# --- 6: cambiar de personaje no acumula ni duplica ----------------------
	var antes_h := _datos(&"humano")
	for i in 6:
		_stats.aplicar_forma(&"pes" if i % 2 == 0 else &"humano")
		await get_tree().physics_frame
	var desp_h := _datos(&"humano")
	var salto: float = float(desp_h["vida"]) - float(antes_h["vida"])
	_check("cambiar de personaje en bucle no restaura ni acumula recursos",
			salto >= 0.0 and salto <= 1.0
			and float(desp_h["vida"]) < float(desp_h["vida_max"]) - 5.0,
			"vida %.2f → %.2f (salto %.2f)" % [antes_h["vida"], desp_h["vida"], salto])

	for id in FORMAS:
		_stats.aplicar_forma(id)
	var tan := _datos(&"tanque")
	_check("las cinco formas tienen recursos propios registrados",
			_stats.formas().size() >= 5, "formas=%d" % _stats.formas().size())
	_check("los personajes sin daño siguen a tope y el muerto sigue muerto",
			is_equal_approx(tan["vida"], tan["vida_max"]) and bool(_datos(&"combate")["muerto"])
			and float(_datos(&"combate")["vida"]) <= 0.001,
			"tanque=%.1f combate=%.3f (muerto=%s)" % [tan["vida"],
					_datos(&"combate")["vida"], str(_datos(&"combate")["muerto"])])

	_stats.aplicar_forma(&"humano")
	_resumen()
