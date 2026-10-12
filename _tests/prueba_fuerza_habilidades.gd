extends Node3D

# Suite automática (se ejecuta como ESCENA) de las DOS habilidades del personaje
# de FUERZA sobre el jugador REAL:
#   P3 — Supersalto con carga (ESPACIO mantenido en el suelo):
#     1. toque corto = salto normal (6.5 m/s);
#     2. mantener a medias carga proporcional (≈12 m/s a 0.6 s) y salta más alto;
#     3. mantener hasta el tope: la carga NO crece sin fin (capada a 1.4 s) y el
#        impulso llega al máximo (21 m/s);
#     4. mantener ESPACIO al aterrizar no repite el salto (nada de saltos solos);
#     5. pulsar en el AIRE no inicia carga (sólo vale con los pies en el suelo);
#     6. en otras formas la carga no se activa (sólo es del personaje de fuerza).
#   P4 — Pisotón aéreo (E en el aire, onda al aterrizar):
#     7. E en el SUELO no hace nada (ni daño ni animación de ataque);
#     8. saltar + E en el aire activa el descenso y al impactar crea UNA onda;
#     9. el enemigo a 1.5 m pierde ≈ 40 PV (daño moderado, ≤ golpe normal pleno),
#        el de 3 m pierde menos (caída por distancia), el de 6.5 m NADA (radio 4.5);
#    10. el daño se aplica UNA vez por impacto (sin repetirse fotograma a fotograma);
#    11. el impacto deja recuperación (0.35 s) y después se recupera el control;
#    12. pulsar E varias veces en un mismo salto produce UN solo impacto;
#    13. transformarse en plena caída del pisotón no deja estados atascados;
#    14. el jugador no se daña a sí mismo con su propia onda.
#
# No forma parte del juego: vive en res://_tests/ y se ejecuta como ESCENA:
#   godot --headless --path . res://_tests/prueba_fuerza_habilidades.tscn
# También se puede abrir y ejecutar desde el editor (F6).

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")
const ESCENA_ENEMIGO := preload("res://Enemigos Prueba/Scenes/enemigo_prueba.tscn")

const FORMA_HUMANO := 0
const FORMA_VELOCISTA := 1
const FORMA_FUERZA := 3
const F_SALTO := 6.5
const CARGA_MAX := 1.4
const VEL_TOPE := 21.0
const SLAM_DANIO_CENTRO := 30.0 / 0.61     # F_SLAM_DANIO = golpe normal pleno
const RECUP_SLAM := 0.35

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

## Enemigo real congelado (sin IA): la distancia del caso no se mueve sola.
func _crear_enemigo(pos: Vector3) -> Node3D:
	var e := ESCENA_ENEMIGO.instantiate() as Node3D
	add_child(e)
	e.global_position = pos
	e.set_physics_process(false)
	return e

## Pulsa una acción FÍSICA de verdad (evento): la E del pisotón pasa por
## _unhandled_input, así que Input.action_press no la dispararía.
func _tecla_accion(accion: StringName) -> void:
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

## Salta (toque corto) midiendo el pico de altura; espera al aterrizaje.
func _pico_salto(t_max: float) -> float:
	var base := _jug.global_position.y
	var pico := base
	var t := 0.0
	while t < t_max:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		pico = maxf(pico, _jug.global_position.y)
		if t > 0.35 and _jug.is_on_floor():
			break
	return pico - base

func _correr() -> void:
	print("=== PRUEBA: supersalto con carga y pisotón del personaje de Fuerza ===")

	var suelo := StaticBody3D.new()
	var forma_s := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(200.0, 1.0, 200.0)
	forma_s.shape = caja
	suelo.add_child(forma_s)
	suelo.position = Vector3(0.0, -0.5, 0.0)
	add_child(suelo)

	_jug = JUGADOR.instantiate() as ControladorLeo
	_jug.position = Vector3(0.0, 0.1, 0.0)
	add_child(_jug)
	_stats = _jug.get_node_or_null("Estadisticas") as EstadisticasJugador
	await _esperar(25)
	if _stats == null:
		_check("jugador y estadísticas listos", false)
		_resumen()
		return
	_check("jugador y estadísticas listos", true)

	var ok := await _cambiar_forma(&"tanque", FORMA_FUERZA)
	_check("transformado a Fuerza (tanque)", ok, "forma=%d" % int(_jug.forma))
	await _esperar_seg(0.3)

	# ------------------------------------------------ 7. E en el SUELO: nada
	var vida_jug0 := _stats.vida
	await _tecla_accion(&"fuerza_slam")
	await _esperar_seg(0.2)
	_check("7. E en el suelo no activa el pisotón",
			not _jug.f_slam and _jug.is_on_floor())

	# -------------------------------------- P3.1 toque corto = salto normal
	Input.action_press(&"saltar")
	await _esperar(3)
	Input.action_release(&"saltar")
	await _esperar(2)
	var vel_tap := _jug.velocity.y
	_check("1. Toque corto: salto normal de siempre", vel_tap > 5.0 and vel_tap <= F_SALTO + 0.2,
			"vel=%.2f" % vel_tap)
	var pico_tap := await _pico_salto(1.4)
	_check("1. El toque corto aterriza y no repite salto solo",
			_jug.is_on_floor(), "pico=%.2f m" % pico_tap)

	# --------------------------------- P3.2 carga a medias: más impulso/altura
	Input.action_press(&"saltar")
	await _esperar_seg(0.6)
	_check("2. Mantener ESPACIO carga con respuesta visible",
			_jug.f_super_cargando and _jug.f_super_carga >= 0.5 and _jug.f_super_carga <= 0.72,
			"carga=%.2f s" % _jug.f_super_carga)
	Input.action_release(&"saltar")
	await _esperar(2)
	var vel_medio := _jug.velocity.y
	_check("2. A media carga el impulso es intermedio", vel_medio >= 10.2 and vel_medio <= 13.2,
			"vel=%.2f" % vel_medio)
	var pico_medio := await _pico_salto(2.0)
	_check("2. Más carga = salto más alto", pico_medio > pico_tap + 0.7,
			"pico %.2f > %.2f" % [pico_medio, pico_tap])

	# ---------------------- P3.3 carga al tope: capada y con impulso máximo
	Input.action_press(&"saltar")
	await _esperar_seg(1.7)
	var carga_tope := _jug.f_super_carga
	await _esperar(3)
	_check("3. La carga se CAPA (no crece sin fin)",
			is_equal_approx(carga_tope, CARGA_MAX) and is_equal_approx(_jug.f_super_carga, CARGA_MAX),
			"carga=%.2f s (tope %.2f)" % [carga_tope, CARGA_MAX])
	Input.action_release(&"saltar")
	await _esperar(2)
	var vel_tope := _jug.velocity.y
	_check("3. Con la carga al tope el impulso llega al máximo",
			vel_tope >= VEL_TOPE - 1.5 and vel_tope <= VEL_TOPE + 0.2,
			"vel=%.2f" % vel_tope)

	# ---------------------- P3.4 mantener al aterrizar NO repite el salto
	# (se vuelve a pulsar y se MANTIENE durante todo el vuelo y el aterrizaje)
	Input.action_press(&"saltar")
	var pico_tope := await _pico_salto(3.2)
	var y_aterrizaje := _jug.global_position.y
	await _esperar_seg(0.5)
	_check("4. Mantener ESPACIO al aterrizar NO salta de nuevo",
			_jug.is_on_floor() and not _jug.f_super_cargando \
				and _jug.velocity.y <= 0.5 and absf(_jug.global_position.y - y_aterrizaje) < 0.15,
			"pico=%.2f m, y=%.2f" % [pico_tope, _jug.global_position.y])
	Input.action_release(&"saltar")
	await _esperar(3)
	_check("4. El tope salta lo más alto de todos", pico_tope > pico_medio + 2.0,
			"pico %.2f > %.2f" % [pico_tope, pico_medio])

	# ------------------------------------------- 8/9/10/11. pisotón real (E)
	var enemigo_cerca := _crear_enemigo(Vector3(1.5, 0.2, 0.0))
	var enemigo_medio := _crear_enemigo(Vector3(3.0, 0.2, 0.0))
	var enemigo_lejos := _crear_enemigo(Vector3(6.5, 0.2, 0.0))
	await _esperar(4)

	Input.action_press(&"saltar")
	await _esperar_seg(1.2)
	Input.action_release(&"saltar")
	await _esperar(20)
	await _tecla_accion(&"fuerza_slam")
	_check("8. E en el AIRE activa el descenso del pisotón", _jug.f_slam)
	# Aterrizaje (caída recta y rápida): se espera al impacto.
	var impacto := false
	var t := 0.0
	while t < 2.0 and not impacto:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		impacto = not _jug.f_slam and _jug.is_on_floor()
	_check("8. Aterriza y cierra el pisotón (recuperación activa)",
			impacto and _jug.f_recuperacion > 0.0 and _jug.f_recuperacion <= RECUP_SLAM,
			"recuperación=%.2f" % _jug.f_recuperacion)

	var dano_cerca := 60.0 - _vida(enemigo_cerca)
	var dano_medio := 60.0 - _vida(enemigo_medio)
	var dano_lejos := 60.0 - _vida(enemigo_lejos)
	_check("9. El enemigo a 1.5 m recibe daño moderado (≈40 PV)",
			dano_cerca >= 33.0 and dano_cerca <= 47.0,
			"daño=%.1f" % dano_cerca)
	_check("9. Nunca más que un golpe normal pleno del Tanque (%.1f)" % SLAM_DANIO_CENTRO,
			dano_cerca <= SLAM_DANIO_CENTRO + 0.5, "daño=%.1f" % dano_cerca)
	_check("9. El de 3 m recibe MENOS (caída por distancia) y el de 6.5 m NADA",
			dano_medio > 1.0 and dano_medio < dano_cerca and is_zero_approx(dano_lejos),
			"3m=%.1f 6.5m=%.1f" % [dano_medio, dano_lejos])
	_check("9. El jugador no se daña con su propia onda",
			is_equal_approx(_stats.vida, vida_jug0))
	# Una sola aplicación: 1 s después, la vida no cambió.
	await _esperar_seg(1.0)
	_check("10. El daño del pisotón se aplica UNA vez por impacto",
			is_equal_approx(60.0 - _vida(enemigo_cerca), dano_cerca) \
				and is_equal_approx(60.0 - _vida(enemigo_medio), dano_medio),
			"%.1f / %.1f" % [60.0 - _vida(enemigo_cerca), 60.0 - _vida(enemigo_medio)])
	_check("11. Tras la recuperación (%.2f s) el control vuelve" % RECUP_SLAM,
			_jug.f_recuperacion <= 0.0)

	# ---------------------- 12. E repetida en un mismo salto = UN impacto
	var enemigo_doble := _crear_enemigo(Vector3(-1.5, 0.2, 0.0))
	await _esperar(4)
	Input.action_press(&"saltar")
	await _esperar_seg(1.2)
	Input.action_release(&"saltar")
	await _esperar(20)
	await _tecla_accion(&"fuerza_slam")
	await _esperar(3)
	await _tecla_accion(&"fuerza_slam")
	# Aterrizar.
	t = 0.0
	while t < 2.0 and not _jug.is_on_floor():
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await _esperar_seg(0.4)
	var dano_doble := 60.0 - _vida(enemigo_doble)
	_check("12. E repetida en un mismo salto produce UN solo impacto",
			dano_doble >= 33.0 and dano_doble <= 47.0, "daño=%.1f" % dano_doble)

	# ---------------------- 13. transformarse en pleno pisotón: sin atasco
	var enemigo_transform := _crear_enemigo(Vector3(0.0, 0.2, -1.5))
	await _esperar(4)
	Input.action_press(&"saltar")
	await _esperar_seg(1.2)
	Input.action_release(&"saltar")
	await _esperar(20)
	await _tecla_accion(&"fuerza_slam")
	var ok_vel := await _cambiar_forma(&"velocista", FORMA_VELOCISTA)
	_check("13. Transformarse en plena caída del pisotón funciona", ok_vel,
			"forma=%d" % int(_jug.forma))
	_check("13. La transformación limpia el estado del pisotón",
			not _jug.f_slam and _jug.f_recuperacion <= 0.0)
	# Al transformarse, el pisotón se CANCELA limpiamente (f_slam queda limpio): o
	# no hay impacto (0 daño) o el cuerpo llegó a tocar el suelo antes y hubo UN
	# impacto real. Lo que jamás puede pasar es daño "fantasma" fuera de rango.
	var dano_transform := 60.0 - _vida(enemigo_transform)
	_check("13. Sin daño fantasma al transformarse (cancelado o impacto real único)",
			is_zero_approx(dano_transform) or (dano_transform >= 33.0 and dano_transform <= 47.0),
			"daño=%.1f" % dano_transform)
	# Sin estado atascado: el velocista responde (salta o se mueve al menos).
	Input.action_press(&"saltar")
	await _esperar(6)
	Input.action_release(&"saltar")
	await _esperar_seg(0.4)
	_check("13. El velocista recupera el control (responde tras la transformación)",
			not _jug.is_on_floor() or _jug.velocity.y > 0.5 or _jug.velocity.length() > 1.0)

	# ---------------------- 6/14. otras formas: ni carga ni pisotón
	# (primero, sin ningún enemigo cerca: la forma tiene su propio movimiento)
	Input.action_press(&"saltar")
	await _esperar_seg(0.5)
	_check("6. En otra forma ESPACIO no inicia la carga del supersalto",
			not _jug.f_super_cargando)
	Input.action_release(&"saltar")
	await _esperar_seg(0.6)
	var enemigo_otras := _crear_enemigo(Vector3(1.2, 0.2, 1.2))
	await _esperar(4)
	await _tecla_accion(&"fuerza_slam")
	await _esperar_seg(0.3)
	_check("14. En otra forma E no daña ni activa el pisotón (sólo es de Fuerza)",
			not _jug.f_slam and is_equal_approx(_vida(enemigo_otras), 60.0),
			"vida enemigo=%.1f" % _vida(enemigo_otras))
	_check("14. El enemigo de fuera del radio sigue intacto (6.5 m)",
			is_equal_approx(_vida(enemigo_lejos), 60.0))

	_resumen()

func _resumen() -> void:
	print("=====================================================")
	print("RESUMEN: %d OK, %d FALLA" % [_pasadas, _falladas])
	print("=====================================================")