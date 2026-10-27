extends Node3D

# Suite automática (se ejecuta como ESCENA) del COMBATE de la forma VUELO (águila)
# integrada en el mundo real: jugador REAL (leo_jugador), enemigos REALES de
# "Enemigos Prueba" con su gerente y el CombatManager del módulo FreeFlow.
#
# Objetivo (P1 del encargo): los enemigos deben detectar la posición REAL del
# jugador (cuerpo activo) en TODAS las situaciones, y los ataques del águila deben
# dañar de verdad a los enemigos:
#   1. jugador humano: el objetivo del gerente es la raíz (sin cambios);
#   2. enemigos generados ANTES de transformar: al transformar a águila y moverse
#      el CUERPO VOLADOR, persiguen la posición NUEVA (no el ancla vieja);
#   3. enemigos generados DESPUÉS de transformar: aparecen alrededor del cuerpo
#      volador, no del ancla;
#   4. volando ALTO, el melee terrestre no conecta golpes (alcance vertical);
#   5. al bajar junto al enemigo, el golpe enemigo daña por la posición real;
#   6. el golpe del águila (melee_light) quita vida al enemigo real UNA vez;
#   7. el palmazo (ráfaga) también daña al enemigo real, una vez;
#   8. nadie detrás del jugador recibe daño (sin impactos fantasma);
#   9. volver a humano restaura el objetivo raíz (sin regresiones).
#
# No forma parte del juego: vive en res://_tests/ y se ejecuta como ESCENA:
#   godot --headless --path . res://_tests/prueba_vuelo_combate.tscn
# También se puede abrir y ejecutar desde el editor (F6).

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")
const GestorCombate := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_manager.gd")
const ConfigCombate := preload("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")
const GerenteScript := preload("res://Enemigos Prueba/Scripts/gerente_enemigos_prueba.gd")

const FORMA_HUMANO := 0
const FORMA_VUELO := 5
const TIPO_MELEE := 1
const TIPO_TIRADOR := 2
const DANIO_MELEE_AGUILA := 8.0      # cadena 8 + indice*4 (eslabón 0)
const DANIO_PALMAZO := 8.0
const TOL := 0.6

var _pasadas := 0
var _falladas := 0
var _jug: ControladorLeo
var _stats: EstadisticasJugador
var _gerente: Node3D
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

func _esperar_seg(s: float) -> void:
	await _esperar(int(ceil(s * 60.0)))

## Vida del enemigo real; -1.0 si ya no existe.
func _vida(e) -> float:
	if e == null or not is_instance_valid(e):
		return -1.0
	if e.has_method("vida_actual"):
		return float(e.call("vida_actual"))
	return float(e.get("vida_actual"))

func _cambiar_forma(id: StringName, forma: int) -> bool:
	_jug._on_transformacion_elegida(id)
	var t := 0
	while (int(_jug.forma) != forma or _jug._transformando) and t < 900:
		await get_tree().physics_frame
		t += 1
	await _esperar(10)
	return int(_jug.forma) == forma

func _cuerpo_vuelo() -> Node3D:
	var n := _jug.get_node_or_null("Vuelo")
	return n as Node3D

func _plana_desde(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Pulsa una acción de entrada durante unos fotogramas (como el juego).
func _pulsar(accion: StringName, frames: int = 3) -> void:
	if not InputMap.has_action(accion):
		return
	Input.action_press(accion)
	await _esperar(frames)
	Input.action_release(accion)
	await _esperar(2)

func _correr() -> void:
	print("=== PRUEBA: combate de la forma VUELO contra enemigos reales ===")

	# ---------------------------------------------------------------- montaje
	var suelo := StaticBody3D.new()
	suelo.name = "Suelo"
	var forma_s := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(200.0, 1.0, 200.0)
	forma_s.shape = caja
	suelo.add_child(forma_s)
	suelo.position = Vector3(0.0, -0.5, 0.0)
	add_child(suelo)

	_mgr = Node.new()
	_mgr.name = "CombatManager"
	_mgr.set_script(GestorCombate)
	_mgr.set("config", ConfigCombate)
	add_child(_mgr)

	_jug = JUGADOR.instantiate() as ControladorLeo
	_jug.position = Vector3(0.0, 0.1, 0.0)
	add_child(_jug)
	_stats = _jug.get_node_or_null("Estadisticas") as EstadisticasJugador
	await _esperar(20)

	if _jug == null or _stats == null:
		_check("jugador y estadísticas listos", false)
		_resumen()
		return
	_check("jugador y estadísticas listos", true)

	_gerente = Node3D.new()
	_gerente.name = "EnemigosPrueba"
	_gerente.set_script(GerenteScript)
	_gerente.set("radio_aparicion", 7.0)
	_gerente.set("radio_cerco", 2.5)
	_gerente.set("vida_enemigo", 60.0)
	_gerente.set("dano_enemigo", 2.0)
	_gerente.set("dano_melee", 2.0)
	_gerente.set("dano_tirador", 2.0)
	_gerente.set("cantidad_melee_g", 4)
	_gerente.set("cantidad_tirador_g", 2)
	add_child(_gerente)
	await _esperar(6)

	# ---------------------------------------------- 1. objetivo base: la raíz
	_check("1. En humano el objetivo del gerente es la raíz del jugador",
			_gerente.call("jugador") == _jug)
	_check("1. cuerpo_activo() en humano es la propia raíz",
			_jug.cuerpo_activo() == _jug)

	# Enemigos ANTES de transformar (cuerpo a cuerpo).
	_gerente.call("generar_tipo", TIPO_MELEE)
	await _esperar(6)
	var melee_antes: Array = []
	for e in _gerente.call("enemigos_vivos"):
		if is_instance_valid(e):
			melee_antes.append(e)
	_check("2. Se generan enemigos melee antes de transformar",
			melee_antes.size() > 0, "n=%d" % melee_antes.size())

	# ---------------------------------------------------------------- transformar
	# Vuelo está BLOQUEADO hasta completar la misión de Iván: se completa para
	# poder probar aquí el combate en vuelo (el bloqueo no es objeto de esta suite).
	Misiones.marcar_completada(Misiones.MISION_PROFUGOS)
	var ok_forma := await _cambiar_forma(&"aguila", FORMA_VUELO)
	_check("2. La transformación a águila entra por el menú", ok_forma,
			"forma=%d" % int(_jug.forma))
	var cuerpo := _cuerpo_vuelo()
	if cuerpo == null or not is_instance_valid(cuerpo):
		_check("2. El cuerpo volador existe como nodo Vuelo", false)
		_resumen()
		return
	_check("2. cuerpo_activo() devuelve el cuerpo volador", _jug.cuerpo_activo() == cuerpo)
	_check("2. El gerente pasa a apuntar al cuerpo volador",
			_gerente.call("jugador") == cuerpo)

	# El cuerpo volador se desplaza 8 m (como al volar/moverse): el ancla raíz
	# se queda atrás A PROPÓSITO para que la prueba discrimine.
	cuerpo.global_position = _jug.global_position + Vector3(8.0, 0.0, 0.0)
	await _esperar(4)

	# Todos parten de una distancia conocida al cuerpo; se sigue al que estaba
	# más LEJOS (el más discriminante: sólo se acerca si mira la posición nueva).
	var seguido: Node3D = null
	var dist0 := -1.0
	for e in melee_antes:
		if not is_instance_valid(e):
			continue
		var d := _plana_desde((e as Node3D).global_position, cuerpo.global_position)
		if d > dist0:
			dist0 = d
			seguido = e as Node3D
	await _esperar_seg(1.6)
	if seguido != null:
		var dist1 := _plana_desde(seguido.global_position, cuerpo.global_position)
		_check("2. Un enemigo de antes persigue la posición NUEVA del volador",
				dist1 < dist0 - 1.5,
				"d0=%.1f d1=%.1f" % [dist0, dist1])
		# Y el destino de cerco que le da el propio gerente es el del CUERPO
		# volador (no el del ancla que quedó atrás).
		var destino: Vector3 = _gerente.call("posicion_de", seguido)
		_check("2. El destino de cerco que recibe es el del cuerpo volador",
				_plana_desde(destino, cuerpo.global_position) <= 4.0,
				"destino a %.1f m del volador / %.1f m del ancla" % [
					_plana_desde(destino, cuerpo.global_position),
					_plana_desde(destino, _jug.global_position)])
	else:
		_check("2. Un enemigo de antes persigue la posición NUEVA del volador", false)
		_check("2. El destino de cerco que recibe es el del cuerpo volador", false)

	# ------------------------------------------- 3. enemigos DESPUÉS de transformar
	_gerente.call("generar_tipo", TIPO_TIRADOR)
	await _esperar(6)
	var tiradores: Array = []
	for e in _gerente.call("enemigos_vivos"):
		if not is_instance_valid(e):
			continue
		# Sólo TIRADORES recién generados: se distinguen por sus export de
		# disparo (el melee ya existía de antes y va por su cuenta).
		if e.get("cadencia_disparo") == null:
			continue
		tiradores.append(e)
	var bien_cerca := true
	var alguno_lejos_del_ancla := false
	for e in tiradores:
		var d_cuerpo := _plana_desde((e as Node3D).global_position, cuerpo.global_position)
		var d_ancla := _plana_desde((e as Node3D).global_position, _jug.global_position)
		if d_cuerpo < 3.0 or d_cuerpo > 11.0:
			bien_cerca = false
		if d_ancla > 4.0:
			alguno_lejos_del_ancla = true
	_check("3. Los invocados tras transformar aparecen alrededor del volador",
			tiradores.size() > 0 and bien_cerca and alguno_lejos_del_ancla,
			"n=%d lejos_del_ancla=%s" % [tiradores.size(), str(alguno_lejos_del_ancla)])
	_gerente.call("retirar_tipo", TIPO_TIRADOR)
	await _esperar(4)

	# --------------------------------------- 4. volando ALTO no llegan los golpes
	# El cuerpo se aparca en el aire (7 m) para medir: el melee NO debe conectar.
	cuerpo.set_physics_process(false)
	cuerpo.global_position = _jug.global_position + Vector3(8.0, 7.0, 0.0)
	var vida_antes_alto := _stats.vida
	await _esperar_seg(2.5)
	_check("4. Volando alto, el melee terrestre no daña (alcance vertical)",
			is_equal_approx(_stats.vida, vida_antes_alto),
			"vida %.1f -> %.1f" % [vida_antes_alto, _stats.vida])

	# ------------------------------- 5. al bajar junto al enemigo, SÍ daña de verdad
	cuerpo.set_physics_process(true)
	var atacante: Node3D = seguido
	if atacante == null or not is_instance_valid(atacante):
		atacante = melee_antes[0] as Node3D
	cuerpo.global_position = atacante.global_position + Vector3(2.2, 0.1, 0.0)
	var vida_antes_suelo := _stats.vida
	var danado := false
	var t := 0.0
	while t < 4.5 and not danado:
		await _esperar_seg(0.25)
		t += 0.25
		danado = _stats.vida < vida_antes_suelo
	_check("5. En el suelo, el golpe enemigo daña por la posición real",
			danado, "vida %.1f -> %.1f (%.1fs)" % [vida_antes_suelo, _stats.vida, t])

	# ------------------------------------------- 6/7/8. ataques del águila
	# El golpe alinea el VISUAL con la CÁMARA al lanzar (_encarar_camara): el
	# objetivo de prueba se coloca según la dirección de la CÁMARA activa, que es
	# la que usa la esfera de impacto en el momento de conectar.
	var cam_combate := get_viewport().get_camera_3d()
	var frente := Vector3.FORWARD
	if cam_combate != null:
		frente = -cam_combate.global_transform.basis.z
	if frente.length_squared() < 0.0001:
		var vr := cuerpo.get_node_or_null("VisualRoot") as Node3D
		if vr != null:
			frente = -vr.global_transform.basis.z
	frente.y = 0.0
	frente = frente.normalized() if frente.length_squared() > 0.0001 else Vector3.FORWARD

	# Objetivo congelado DELANTE (a 1.3 m, dentro de la esfera del golpe).
	var objetivo: Node3D = null
	for e in melee_antes:
		if is_instance_valid(e) and e != atacante:
			objetivo = e as Node3D
			break
	if objetivo == null:
		_check("6. Objetivo congelado delante disponible", false)
	else:
		objetivo.set_physics_process(false)
		objetivo.global_position = cuerpo.global_position + frente * 1.3 + Vector3.UP * 0.1
		# Y un enemigo DETRÁS, congelado: no debe recibir nada.
		var detras: Node3D = null
		for e in melee_antes:
			if is_instance_valid(e) and e != atacante and e != objetivo:
				detras = e as Node3D
				break
		if detras != null:
			detras.set_physics_process(false)
			detras.global_position = cuerpo.global_position - frente * 1.3 + Vector3.UP * 0.1
		await _esperar(6)
		var vida_obj0 := _vida(objetivo)
		var vida_det0 := _vida(detras) if detras != null else -1.0

		# --- Golpe del combo (melee_light) ---
		await _pulsar(&"melee_light", 3)
		await _esperar_seg(1.0)
		var vida_obj1 := _vida(objetivo)
		_check("6. El golpe del águila daña al enemigo real",
				vida_obj1 <= vida_obj0 - DANIO_MELEE_AGUILA + TOL,
				"vida %.1f -> %.1f" % [vida_obj0, vida_obj1])
		_check("6. El daño del golpe se aplica UNA vez",
				is_equal_approx(vida_obj1, vida_obj0 - DANIO_MELEE_AGUILA),
				"delta=%.1f" % (vida_obj0 - vida_obj1))

		# --- Palmazo (ráfaga de viento) ---
		var cam := cam_combate
		if cam != null and InputMap.has_action(&"palmazo"):
			var dir := -cam.global_transform.basis.z
			dir.y = 0.0
			dir = dir.normalized() if dir.length_squared() > 0.0001 else frente
			objetivo.global_position = cuerpo.global_position + dir * 2.5 + Vector3.UP * 0.1
			await _esperar(4)
			var vida_p0 := _vida(objetivo)
			await _pulsar(&"palmazo", 4)
			await _esperar_seg(0.5)
			var vida_p1 := _vida(objetivo)
			_check("7. El palmazo también daña al enemigo real",
					vida_p1 <= vida_p0 - DANIO_PALMAZO + TOL,
					"vida %.1f -> %.1f" % [vida_p0, vida_p1])
			_check("7. El daño del palmazo se aplica UNA vez",
					is_equal_approx(vida_p1, vida_p0 - DANIO_PALMAZO),
					"delta=%.1f" % (vida_p0 - vida_p1))
		else:
			_check("7. El palmazo también daña al enemigo real", false,
					"sin cámara o sin acción palmazo")

		_check("8. El enemigo DETRÁS no recibe daño (sin impactos fantasma)",
				detras == null or is_equal_approx(_vida(detras), vida_det0),
				"vida=%.1f (antes %.1f)" % [_vida(detras), vida_det0])

	# ---------------------------------------------------------------- 9. vuelta
	# Volver a base: elegir OTRA VEZ la transformación activa (toggle del menú).
	var ok_vuelta := await _cambiar_forma(&"aguila", FORMA_HUMANO)
	_check("9. Volver a humano (toggle de la transformación) deja la forma base", ok_vuelta,
			"forma=%d" % int(_jug.forma))
	_check("9. Con el volador apagado, el objetivo vuelve a ser la raíz",
			_gerente.call("jugador") == _jug and _jug.cuerpo_activo() == _jug)

	_resumen()

func _resumen() -> void:
	print("=====================================================")
	print("RESUMEN: %d OK, %d FALLA" % [_pasadas, _falladas])
	print("=====================================================")