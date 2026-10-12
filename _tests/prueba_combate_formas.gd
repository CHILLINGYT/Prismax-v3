extends Node3D

## Suite de prueba (headless, como ESCENA) del DAÑO REAL de las formas Velocista y
## Tanque, sobre el jugador REAL y con enemigos REALES (`EnemigoPrueba`) y el
## CombatManager del módulo FreeFlow:
##   1. el clic izquierdo del Velocista quita vida al enemigo (20) UNA sola vez;
##   2. no alcanza a quien está lejos ni a quien está detrás (arco frontal);
##   3. el combo tumba al enemigo estándar (3 golpes = 60 PV) y el remate pega más;
##   4. la supervelocidad empuja al enemigo y le quita poco daño (5), sin repetirlo
##      cada fotograma;
##   5. el golpe del Tanque quita la mitad de la vida del enemigo estándar;
##   6. el jugador no está en "damageable": no hay fuego amigo.
##
##   godot --headless --path . _tests/prueba_combate_formas.tscn

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")
const GestorCombate := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_manager.gd")
const ConfigCombate := preload("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")
const ESCENA_ENEMIGO := preload("res://Enemigos Prueba/Scenes/enemigo_prueba.tscn")

const FORMA_VELOCISTA := 1
const FORMA_FUERZA := 3
const PUNIO_TANQUE := 30.0
const PATADA_TANQUE := 36.0
const DANIO_VEL := 7.0
const DANIO_SUPER := 5.0

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

## Frente real del cuerpo (el ataque sale de la orientación del modelo visible).
func _frente() -> Vector3:
	var f := -_jug.visual.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD

## Enemigo real congelado (sin IA) para que la distancia del caso no se mueva.
func _crear_enemigo(desde_jugador: Vector3, congelado: bool = true) -> Node3D:
	var e := ESCENA_ENEMIGO.instantiate()
	add_child(e)
	e.global_position = _jug.global_position + desde_jugador + Vector3.UP * 0.1
	if congelado:
		e.set_physics_process(false)
	return e

## Vida del enemigo; -1.0 si ya no existe (al morir, el enemigo se retira solo).
## El parámetro va sin tipo a propósito: un nodo ya liberado no puede pasarse como
## Node.
func _vida(e) -> float:
	if e == null or not is_instance_valid(e):
		return -1.0
	if e.has_method("vida_actual"):
		return float(e.call("vida_actual"))
	return float(e.get("vida_actual"))

## Vida MÁXIMA del enemigo (la de su escena/instancia): las comprobaciones nunca
## hardcodean la vida base, así la suite no se rompe si el enemigo sube de vida.
func _vida_max_de(e) -> float:
	if e == null or not is_instance_valid(e):
		return -1.0
	return float(e.get("vida_max"))

func _vivo(e) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	if not e.has_method("is_alive"):
		return false
	return bool(e.call("is_alive"))

func _cambiar_forma(id: StringName, forma: int) -> bool:
	_jug._on_transformacion_elegida(id)
	var t := 0
	while (int(_jug.forma) != forma or _jug._transformando) and t < 900:
		await get_tree().physics_frame
		t += 1
	await _esperar(10)
	return int(_jug.forma) == forma

func _montar() -> void:
	var suelo := StaticBody3D.new()
	suelo.name = "Suelo"
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(200.0, 1.0, 200.0)
	forma.shape = caja
	suelo.add_child(forma)
	suelo.position = Vector3(0.0, -0.5, 0.0)
	add_child(suelo)

	var mgr := Node.new()
	mgr.name = "CombatManager"
	mgr.set_script(GestorCombate)
	mgr.set("config", ConfigCombate)
	add_child(mgr)

	_jug = JUGADOR.instantiate()
	_jug.position = Vector3(0.0, 0.1, 0.0)
	add_child(_jug)
	_stats = _jug.get_node_or_null("Estadisticas") as EstadisticasJugador

func _correr() -> void:
	print("=== PRUEBA: daño real del Velocista y del Tanque ===")
	_montar()
	await _esperar(30)
	if _jug == null or _stats == null:
		_check("jugador y estadísticas listos", false)
		_resumen()
		return
	_check("jugador y estadísticas listos", true)
	_check("el jugador NO está en el grupo de daño (sin fuego amigo)",
			not _jug.is_in_group("damageable"))
	await _esperar(20)

	# --- 1 y 2: ataque del Velocista ----------------------------------------
	var ok_forma := await _cambiar_forma(&"velocista", FORMA_VELOCISTA)
	_check("el velocista entra por el menú de transformaciones", ok_forma, "forma=%d" % int(_jug.forma))
	var frente := _frente()
	var vida_jug_antes := _stats.vida

	var objetivo := _crear_enemigo(frente * 1.5)
	var lejano := _crear_enemigo(frente * 8.0)
	var detras := _crear_enemigo(-frente * 1.5)
	await _esperar(6)
	# La vida del enemigo es la de SU escena (75 hoy): se lee de la instancia en
	# lugar de hardcodearla.
	var vmax := _vida_max_de(objetivo)
	_check("el enemigo de prueba arranca con su vida completa",
			is_equal_approx(_vida(objetivo), vmax),
			"vida=%.1f (max %.1f)" % [_vida(objetivo), vmax])

	Input.action_press("atacar")
	await _esperar(3)
	Input.action_release("atacar")
	await _esperar_seg(0.5)
	_check("el clic izquierdo del velocista quita vida al enemigo",
			is_equal_approx(_vida(objetivo), vmax - DANIO_VEL),
			"vida=%.1f (esperado %.1f)" % [_vida(objetivo), vmax - DANIO_VEL])
	_check("el golpe no alcanza a quien está lejos",
			is_equal_approx(_vida(lejano), _vida_max_de(lejano)), "vida=%.1f" % _vida(lejano))
	_check("el golpe no alcanza a quien está detrás",
			is_equal_approx(_vida(detras), _vida_max_de(detras)), "vida=%.1f" % _vida(detras))
	_check("el ataque del velocista no daña al propio jugador",
			is_equal_approx(_stats.vida, vida_jug_antes),
			"vida %.1f → %.1f" % [vida_jug_antes, _stats.vida])

	var antes_de_esperar := _vida(objetivo)
	await _esperar_seg(0.7)
	_check("un solo golpe aplica el daño UNA vez (sin repetir por fotograma)",
			is_equal_approx(_vida(objetivo), antes_de_esperar),
			"%.1f → %.1f" % [antes_de_esperar, _vida(objetivo)])

	# --- 3: la cadena del combo sigue con el daño nuevo ----------------------
	# Ya se dio un golpe normal. Dos más (3 golpes normales en la cadena) y el
	# cuarto, que es el remate: su daño es 7 x 1,6 = 11,2, NUNCA el antiguo 28.
	for _i in 3:
		Input.action_press("atacar")
		await _esperar(3)
		Input.action_release("atacar")
		await _esperar_seg(0.35)
	await _esperar_seg(0.5)
	var esperado := vmax - (3.0 * float(_jug.VEL_ATAQUE_DANIO)
			+ float(_jug.VEL_ATAQUE_DANIO_REMATE))
	_check("el combo avanza golpe a golpe con el daño nuevo (3 x 7 + remate)",
			absf(_vida(objetivo) - esperado) <= 1.0 and _vivo(objetivo),
			"vida=%.1f (esperado %.1f) vivo=%s" % [_vida(objetivo), esperado,
					str(_vivo(objetivo))])
	_check("el golpe normal quita 7 y el remate NO conserva el daño antiguo (28)",
			is_equal_approx(float(_jug.VEL_ATAQUE_DANIO), 7.0)
			and float(_jug.VEL_ATAQUE_DANIO_REMATE) > 7.0
			and float(_jug.VEL_ATAQUE_DANIO_REMATE) < 20.0,
			"normal=%.2f remate=%.2f" % [float(_jug.VEL_ATAQUE_DANIO),
					float(_jug.VEL_ATAQUE_DANIO_REMATE)])

	# --- 4a: hasta dónde llega la trayectoria guiada -------------------------
	# La trayectoria sigue la MIRA (la base de la cámara), no el cuerpo.
	var cam_frente := -_jug.pivote.global_transform.basis.z
	cam_frente.y = 0.0
	cam_frente = cam_frente.normalized() if cam_frente.length_squared() > 0.0001 else frente
	print("[DIAG] frente cuerpo=%s frente mira=%s dot=%.2f" % [
			str(frente.snapped(Vector3(0.01, 0.01, 0.01))),
			str(cam_frente.snapped(Vector3(0.01, 0.01, 0.01))), frente.dot(cam_frente)])
	var sonda := _crear_enemigo(cam_frente * 14.0)   # lejos: no estorba la traza
	await _esperar(6)
	var p0 := _jug.global_position
	Input.action_press("cargar_poder")
	await _esperar_seg(1.0)
	Input.action_release("cargar_poder")
	await _esperar(2)
	var alcance_traza := 0.0
	if _jug._puntos.size() >= 2:
		var ultimo: Vector3 = _jug._puntos[_jug._puntos.size() - 1]
		alcance_traza = Vector3(ultimo.x - p0.x, 0.0, ultimo.z - p0.z).length()
	var t := 0.0
	while int(_jug.estado) != 0 and t < 4.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var recorrido := _jug.global_position - p0
	recorrido.y = 0.0
	print("[DIAG] traza: puntos=%d alcance_previsto=%.2f m recorrido_real=%.2f m estado=%d" % [
			_jug._puntos.size(), alcance_traza, recorrido.length(), int(_jug.estado)])
	_check("la supervelocidad se ejecuta y recorre su trayectoria",
			alcance_traza >= 1.0 and recorrido.length() >= 1.0,
			"previsto=%.2f m recorrido=%.2f m" % [alcance_traza, recorrido.length()])
	if sonda != null and is_instance_valid(sonda):
		sonda.queue_free()
	await _esperar(6)

	# --- 4b: enemigo EN la trayectoria (desviado un poco para no cortar la traza) ---
	var cam_derecha := _jug.pivote.global_transform.basis.x
	cam_derecha.y = 0.0
	cam_derecha = cam_derecha.normalized() if cam_derecha.length_squared() > 0.0001 else Vector3.RIGHT
	var dist_objetivo := clampf(minf(alcance_traza * 0.6, recorrido.length() * 0.8), 1.5, 9.0)
	var empujado := _crear_enemigo(cam_frente * dist_objetivo + cam_derecha * 0.7)
	await _esperar(6)
	var vida_super := _vida(empujado)
	print("[DIAG] supervelocidad: enemigo a %.2f m (traza %.2f m) lateral 0.70 m" % [dist_objetivo, alcance_traza])
	var p1 := _jug.global_position
	Input.action_press("cargar_poder")
	await _esperar_seg(1.0)
	Input.action_release("cargar_poder")
	# Se espera al impacto (o a que la habilidad termine).
	var hubo_impacto := false
	var vel_empuje := 0.0
	var t2 := 0.0
	while t2 < 4.0:
		await get_tree().physics_frame
		t2 += 1.0 / 60.0
		if not is_instance_valid(empujado):
			break
		if _vida(empujado) < vida_super - 0.001:
			hubo_impacto = true
			vel_empuje = empujado.velocity.length()
			break
	var rec2 := _jug.global_position - p1
	rec2.y = 0.0
	print("[DIAG] supervelocidad: puntos=%d recorrido=%.2f m estado=%d vida=%.1f" % [
			_jug._puntos.size(), rec2.length(), int(_jug.estado), _vida(empujado)])
	_check("la supervelocidad alcanza a un enemigo de su trayectoria", hubo_impacto)
	if hubo_impacto:
		_check("la supervelocidad quita mucho menos daño que el golpe normal",
				is_equal_approx(_vida(empujado), vida_super - DANIO_SUPER),
				"vida %.1f → %.1f (esperado %.1f)" % [vida_super, _vida(empujado),
						vida_super - DANIO_SUPER])
		_check("la supervelocidad empuja al enemigo de verdad",
				vel_empuje >= 8.0, "velocidad del enemigo tras el impacto=%.1f m/s" % vel_empuje)
		var pos_impacto := empujado.global_position
		empujado.set_physics_process(true)   # para ver el retroceso real
		await _esperar_seg(0.25)
		var despl := empujado.global_position - pos_impacto
		var dot := despl.normalized().dot(cam_frente) if despl.length() > 0.05 else -2.0
		_check("el enemigo retrocede en la dirección de la arremetida",
				despl.length() >= 0.25 and dot >= 0.3,
				"d=%.2f m dot=%.2f" % [despl.length(), dot])
		var vida_tras := _vida(empujado)
		await _esperar_seg(0.6)
		_check("la supervelocidad NO repite el daño cada fotograma",
				is_equal_approx(_vida(empujado), vida_tras),
				"%.1f → %.1f" % [vida_tras, _vida(empujado)])

	# --- 5: daño del Tanque --------------------------------------------------
	var ok_fuerza := await _cambiar_forma(&"tanque", FORMA_FUERZA)
	_check("el tanque entra por el menú de transformaciones", ok_fuerza, "forma=%d" % int(_jug.forma))
	frente = _frente()
	var tanque_obj := _crear_enemigo(frente * 1.2)
	await _esperar(6)
	print("[DIAG] tanque: constantes puño=%.1f patada=%.1f embestida=%.1f slam=%.1f | vida=%.1f dist=%.2f m" % [
			float(_jug.F_PUNIO_DANIO), float(_jug.F_PATADA_DANIO), float(_jug.F_EMBESTIDA_DANIO),
			float(_jug.F_SLAM_DANIO), _vida(tanque_obj),
			(tanque_obj.global_position - _jug.global_position).length()])
	Input.action_press("atacar")
	await _esperar(3)
	Input.action_release("atacar")
	for _i in 12:
		await _esperar(4)
		print("[DIAG] tanque: t=%.2f s vida=%.2f" % [_i * 4.0 / 60.0, _vida(tanque_obj)])
	var quitado := _vida_max_de(tanque_obj) - _vida(tanque_obj)
	_check("el golpe del Tanque quita la mitad de la vida del enemigo estándar",
			quitado >= PUNIO_TANQUE - 6.0 and quitado <= PATADA_TANQUE + 6.0,
			"quitó %.1f de 60 PV (referencia %.0f entregados)" % [quitado, PUNIO_TANQUE])

	_resumen()

func _resumen() -> void:
	print("=== RESULTADO: %d OK, %d FALLOS ===" % [_pasadas, _falladas])
	get_tree().quit(1 if _falladas > 0 else 0)