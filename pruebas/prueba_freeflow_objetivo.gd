extends Node3D

## Suite (ESCENA) del FREEFLOW COMBAT de la forma Ataque:
##   1. apuntar a otro enemigo cambia el objetivo de inmediato (el siguiente golpe
##      va al nuevo, sin cancelar el combate ni esperar al final de la cadena);
##   2. cambiar de objetivo NO reinicia la cadena de combos (el golpe siguiente usa
##      la siguiente etapa de la cadena);
##   3. el indicador circular aparece sólo sobre el objetivo activo, se mueve con
##      él, cambia de enemigo y desaparece si el objetivo deja de ser válido;
##   4. no quedan indicadores duplicados ni errores con objetivos muertos.
##
## Usa el método de apuntado REAL del juego (la intención = dirección de movimiento
## + cámara + orientación, CombatTargeting) y el CombatManager del módulo.
##
##   godot --headless --path . pruebas/prueba_freeflow_objetivo.tscn

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")
const GestorCombate := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_manager.gd")
const ConfigCombate := preload("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")
const ESCENA_ENEMIGO := preload("res://enemigos/Scenes/enemigo_prueba.tscn")

const FORMA_COMBATE := 4
const NOMBRE_INDICADOR := "IndicadorObjetivoFreeFlow"
const ALTURA_INDICADOR := 1.45

var _pasadas := 0
var _falladas := 0
var _jug: ControladorLeo
var _a: Node3D = null
var _b: Node3D = null

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

func _frente() -> Vector3:
	var f := -_jug.pivote.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD

func _derecha() -> Vector3:
	var d := _jug.pivote.global_transform.basis.x
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.RIGHT

func _vida(e) -> float:
	if e == null or not is_instance_valid(e):
		return -1.0
	if e.has_method("vida_actual"):
		return float(e.call("vida_actual"))
	return float(e.get("vida_actual"))

func _vivo(e) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	if not e.has_method("is_alive"):
		return false
	return bool(e.call("is_alive"))

func _indicador() -> MeshInstance3D:
	return _jug._indicador_objetivo as MeshInstance3D

func _dist_indicador(e) -> float:
	if e == null or not is_instance_valid(e):
		return -1.0
	var ind := _indicador()
	if ind == null or not is_instance_valid(ind):
		return -1.0
	var centro: Vector3 = e.global_position + Vector3.UP * 2.45
	if e.has_method("get_hit_center"):
		var c: Vector3 = e.call("get_hit_center")
		centro = c + Vector3.UP * ALTURA_INDICADOR
	return ind.global_position.distance_to(centro)

func _contar_indicadores(n: Node) -> int:
	var c := 1 if n.name == NOMBRE_INDICADOR else 0
	for h in n.get_children():
		c += _contar_indicadores(h)
	return c

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

func _crear_enemigo(pos: Vector3) -> Node3D:
	var e := ESCENA_ENEMIGO.instantiate()
	add_child(e)
	e.global_position = pos
	e.set_physics_process(false)      # quieto: el caso mide objetivo, no IA
	return e

func _cambiar_forma(id: StringName, forma: int) -> bool:
	_jug._on_transformacion_elegida(id)
	var t := 0
	while (int(_jug.forma) != forma or _jug._transformando) and t < 900:
		await get_tree().physics_frame
		t += 1
	await _esperar(10)
	return int(_jug.forma) == forma

## Un toque de ataque (como un clic real) manteniendo SÓLO la dirección pedida:
## antes se sueltan las demás, porque dos direcciones opuestas se anulan y la
## intención de apuntado quedaría sin dirección.
func _atacar(tecla: String) -> void:
	for a in ["mover_adelante", "mover_atras", "mover_izquierda", "mover_derecha"]:
		if a != tecla:
			Input.action_release(a)
	Input.action_press(tecla)
	await _esperar(3)
	Input.action_press("atacar")
	await _esperar(4)
	Input.action_release("atacar")
	await _esperar(3)

func _soltar() -> void:
	for a in ["mover_adelante", "mover_atras", "mover_izquierda", "mover_derecha", "atacar"]:
		Input.action_release(a)

func _correr() -> void:
	print("=== PRUEBA: cambio de objetivo en FreeFlow (inmediato, sin reiniciar combo) ===")
	_montar()
	await _esperar(30)
	_check("jugador listo", _jug != null)
	var ok := await _cambiar_forma(&"combate", FORMA_COMBATE)
	_check("la forma Ataque entra por el menú de transformaciones", ok, "forma=%d" % int(_jug.forma))

	var frente := _frente()
	var derecha := _derecha()
	_a = _crear_enemigo(_jug.global_position + frente * 1.7 + derecha * 1.4)
	_b = _crear_enemigo(_jug.global_position + frente * 1.7 - derecha * 1.4)
	await _esperar(20)
	_check("los dos enemigos están registrados como activos en el combate",
			is_instance_valid(_a) and is_instance_valid(_b))
	_check("todavía no hay ningún indicador en la escena",
			_contar_indicadores(get_parent()) == 0, "nodos=%d" % _contar_indicadores(get_parent()))

	# --- 1: primer golpe a A (dirección de la intención: hacia A) ------------
	await _atacar("mover_derecha")
	await _esperar_seg(0.45)
	var vida_a := _vida(_a)
	var vida_b := _vida(_b)
	_check("1. apuntando hacia A, el objetivo es A",
			_jug.c_objetivo == _a, "objetivo=%s" % ("A" if _jug.c_objetivo == _a else
					("B" if _jug.c_objetivo == _b else "otro/ninguno")))
	_check("1. el golpe daña a A y no a B",
			vida_a < 60.0 and is_equal_approx(vida_b, 60.0),
			"vida A=%.1f vida B=%.1f" % [vida_a, vida_b])
	_check("1. el indicador aparece SOBRE A", _indicador() != null
			and _indicador().visible and _dist_indicador(_a) <= 0.3,
			"visible=%s dist a A=%.2f m" % [str(_indicador() != null and _indicador().visible),
					_dist_indicador(_a)])
	_check("1. hay UN solo indicador en toda la escena",
			_contar_indicadores(get_parent()) == 1, "nodos=%d" % _contar_indicadores(get_parent()))
	_check("1. la cadena del combo está en su primera etapa",
			_jug.c_cadena == 0, "c_cadena=%d" % _jug.c_cadena)

	# --- 2: apuntar a B y golpear: objetivo NUEVO y combo que NO se reinicia --
	var cadena_datos: Array = _jug._c_cadena_datos
	var esperado_2: float = float(cadena_datos[1].damage) if cadena_datos.size() > 1 else -1.0
	await _atacar("mover_izquierda")
	await _esperar_seg(0.5)
	_check("2. apuntando hacia B, el objetivo cambia a B de inmediato",
			_jug.c_objetivo == _b, "objetivo=%s" % ("A" if _jug.c_objetivo == _a else
					("B" if _jug.c_objetivo == _b else "otro/ninguno")))
	_check("2. el golpe nuevo va a B (A no recibe más daño)",
			is_equal_approx(_vida(_a), vida_a) and _vida(_b) < 60.0,
			"vida A=%.1f (antes %.1f) vida B=%.1f" % [_vida(_a), vida_a, _vida(_b)])
	_check("2. la cadena de combos NO se reinicia al cambiar de objetivo",
			_jug.c_cadena == 1, "c_cadena=%d (1 = siguiente etapa de la cadena)" % _jug.c_cadena)
	_check("2. el golpe encadenado usa la etapa 2 de la cadena (daño de la tabla)",
			esperado_2 > 0.0 and is_equal_approx(60.0 - _vida(_b), esperado_2),
			"quitado a B=%.2f (etapa 2=%.2f)" % [60.0 - _vida(_b), esperado_2])
	_check("2. el indicador ya no está sobre A", _dist_indicador(_a) > 0.8,
			"dist a A=%.2f m" % _dist_indicador(_a))
	_check("2. el indicador se ha movido a B", _indicador() != null
			and _indicador().visible and _dist_indicador(_b) <= 0.3,
			"visible=%s dist a B=%.2f m" % [str(_indicador() != null and _indicador().visible),
					_dist_indicador(_b)])
	_check("2. sigue habiendo UN solo indicador",
			_contar_indicadores(get_parent()) == 1, "nodos=%d" % _contar_indicadores(get_parent()))

	# --- 3: el objetivo muere: indicador fuera y se puede seguir -----------
	_b.call("take_hit", 999.0, Vector3.FORWARD, 0.0, 0.0)
	await _esperar_seg(0.4)
	_check("3. el objetivo muere de verdad", not _vivo(_b))
	_check("3. con el objetivo muerto el indicador se apaga",
			_indicador() == null or not _indicador().visible,
			"visible=%s" % str(_indicador() != null and _indicador().visible))
	await _atacar("mover_derecha")
	await _esperar_seg(0.6)
	var gestor_diag := _jug._gestor_encuentro()
	var activos: Array = gestor_diag.get_active_enemies() if gestor_diag != null else []
	print("[DIAG] tras morir el objetivo: c_objetivo=%s estado=%d cadena=%d activos=%d" % [
			str(_jug.c_objetivo), int(_jug.c_estado), _jug.c_cadena, activos.size()])
	print("[DIAG] dir_entrada=%s cam=%s | derecha pulsada=%s izquierda=%s adelante=%s" % [
			str(_jug._direccion_entrada()), str(_jug._direccion_camara_horizontal()),
			str(Input.is_action_pressed("mover_derecha")), str(Input.is_action_pressed("mover_izquierda")),
			str(Input.is_action_pressed("mover_adelante"))])
	for e in activos:
		var d: Vector3 = e.global_position - _jug.global_position
		d.y = 0.0
		print("[DIAG]   activo=%s dist=%.2f m vivo=%s" % [e.name, d.length(), str(_vivo(e))])
	_check("3. se puede seguir apuntando a otro enemigo válido sin errores",
			_jug.c_objetivo != null and is_instance_valid(_jug.c_objetivo)
			and _vivo(_jug.c_objetivo), "objetivo válido=%s" % str(_jug.c_objetivo != null
					and is_instance_valid(_jug.c_objetivo) and _vivo(_jug.c_objetivo)))
	_check("3. el objetivo recuperado es el enemigo que sigue vivo (A)",
			_jug.c_objetivo == _a and _vivo(_a), "es A=%s vivo=%s" % [
					str(_jug.c_objetivo == _a), str(_vivo(_a))])
	_check("3. el indicador vuelve a estar sobre el enemigo válido",
			_indicador() != null and _indicador().visible and _dist_indicador(_a) <= 0.3,
			"dist a A=%.2f m" % _dist_indicador(_a))
	_check("3. no quedan indicadores duplicados", _contar_indicadores(get_parent()) == 1,
			"nodos=%d" % _contar_indicadores(get_parent()))

	# --- 4: el indicador pertenece al FreeFlow: al salir de la forma se apaga --
	# Salir de una forma es elegir SU MISMO icono otra vez en el menú radial (el
	# controlador alterna a humano; el antiguo id directo "humano" ya no existe en
	# `_on_transformacion_elegida`). Se usa esa vía real, la misma del jugador.
	var salio := await _cambiar_forma(&"combate", 0)
	await _esperar_seg(0.3)
	_check("4. elegir otra vez la forma Ataque devuelve a humano (vía real del menú)",
			salio, "forma=%d" % int(_jug.forma))
	_check("4. al salir de la forma Ataque el indicador se apaga",
			_indicador() == null or not _indicador().visible,
			"visible=%s" % str(_indicador() != null and _indicador().visible))
	_check("4. el indicador sigue existiendo una sola vez (se reutiliza)",
			_contar_indicadores(get_parent()) == 1, "nodos=%d" % _contar_indicadores(get_parent()))

	_soltar()
	_resumen()

func _resumen() -> void:
	print("=== RESULTADO: %d OK, %d FALLOS ===" % [_pasadas, _falladas])
	get_tree().quit(1 if _falladas > 0 else 0)