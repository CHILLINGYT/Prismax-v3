extends SceneTree

# Suite headless (SceneTree) de la integración de la transformación de ataque
# (forma Combate). Comprueba, sobre la escena REAL del jugador:
#   1. el menú F ofrece "Combate" como opción desbloqueada;
#   2. seleccionarla carga el modelo del módulo (forma + animaciones listas);
#   3. el FOV usa el mismo mecanismo central que las demás formas (CamaraZiba);
#   4. en el suelo el clic izquierdo inicia la cadena de ataque;
#   5. en el aire no se inicia ningún ataque;
#   6. al aterrizar no se ejecuta nada encolado (los clics aéreos no se encolan);
#   7. las demás transformaciones siguen funcionando (velocista y vuelta a humano).
#
# No forma parte del juego: vive en res://_tests/ y se ejecuta con
#   godot --headless --path <proyecto> -s res://_tests/prueba_transformacion_ataque.gd

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")
const MENU := preload("res://personaje/ui_transformacion/scripts/menu_transformaciones.gd")

# Ids del enum ControladorLeo.Forma y del enum C_E (para no depender de casts).
const FORMA_HUMANO := 0
const FORMA_VELOCISTA := 1
const FORMA_COMBATE := 4
const C_LIBRE := 0

var _pasadas := 0
var _falladas := 0
var _jug: CharacterBody3D

func _initialize() -> void:
	call_deferred("_correr")

func _check(nombre: String, ok: bool, detalle: String = "") -> void:
	var sufijo := (" — " + detalle) if detalle != "" else ""
	if ok:
		_pasadas += 1
		print("[OK]    ", nombre, sufijo)
	else:
		_falladas += 1
		print("[FALLA] ", nombre, sufijo)

func _esperar_frames(n: int) -> void:
	for _i in n:
		await physics_frame

func _correr() -> void:
	# ---------------------------------------------------------------- 1. menú F
	var opcion: Dictionary = {}
	for t in MENU.TRANSFORMACIONES:
		if StringName(t["id"]) == &"combate":
			opcion = t
	_check("1. El menú F ofrece la transformación de ataque",
			not opcion.is_empty(), str(opcion.get("nombre", "")))
	_check("1. La casilla 'combate' está desbloqueada",
			bool(opcion.get("desbloqueada", false)))

	# ---------------------------------------------------------------- mundo mínimo
	var mundo := Node3D.new()
	mundo.name = "MundoPrueba"
	root.add_child(mundo)
	var suelo := StaticBody3D.new()
	suelo.position = Vector3(0.0, -0.5, 0.0)
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(40.0, 1.0, 40.0)
	forma.shape = caja
	suelo.add_child(forma)
	mundo.add_child(suelo)

	_jug = JUGADOR.instantiate()
	mundo.add_child(_jug)
	_jug.global_position = Vector3(0.0, 0.05, 0.0)
	await _esperar_frames(8)

	var anim_ataque: AnimationPlayer = _jug.get_node_or_null("Ataque/AnimadorAtaque")
	_check("2. La escena trae el nodo Ataque con su AnimationPlayer", anim_ataque != null)
	var clips_ok := anim_ataque != null \
			and anim_ataque.has_animation("combat_idle") \
			and anim_ataque.has_animation("walk") \
			and anim_ataque.has_animation("jump") \
			and anim_ataque.has_animation("jab") \
			and anim_ataque.has_animation("dos") \
			and anim_ataque.has_animation("cros") \
			and anim_ataque.has_animation("gancho")
	_check("2. La librería del módulo tiene los 8 clips (locomoción + 4 golpes)", clips_ok)
	_check("2. En humano la representación de ataque está oculta",
			_jug.ataque_visual != null and not _jug.ataque_visual.visible)

	# ---------------------------------------------------------------- 2. selección
	_jug._on_transformacion_elegida(&"combate")
	var t1 := 0
	while _jug.forma != FORMA_COMBATE and t1 < 300:
		await physics_frame
		t1 += 1
	_check("2. Seleccionar 'Combate' carga la forma", _jug.forma == FORMA_COMBATE,
			"forma=%d tras %d frames" % [_jug.forma, t1])
	_check("2. El modelo del módulo queda visible y los demás no",
			_jug.ataque_visual.visible and not _jug.visual.visible \
			and not _jug.acuatico.visible and not _jug.fuerza.visible and not _jug.humano.visible)
	_check("2. El id de forma es &\"combate\" (HUD/estadísticas lo reconocen)",
			_jug.id_forma() == &"combate", str(_jug.id_forma()))
	await _esperar_frames(12)
	_check("2. El Animator de la forma reproduce su idle de combate",
			anim_ataque.current_animation == "combat_idle",
			str(anim_ataque.current_animation))

	# ---------------------------------------------------------------- 3. FOV
	var piv = _jug.pivote
	_check("3. FOV: el objetivo vuelve a la base central (70) al entrar en la forma",
			is_equal_approx(piv.objetivo_fov, piv.fov_base) and is_equal_approx(piv.fov_base, 70.0),
			"objetivo=%.1f base=%.1f" % [piv.objetivo_fov, piv.fov_base])
	var cam: Camera3D = piv.get_node_or_null("Brazo/Camara")
	var t_fov := 0
	while t_fov < 180 and (cam == null or absf(cam.fov - piv.fov_base) > 0.5):
		await physics_frame
		t_fov += 1
	_check("3. La cámara real converge al FOV de las demás formas",
			cam != null and absf(cam.fov - 70.0) <= 0.5,
			"fov=%.2f" % (cam.fov if cam != null else -1.0))

	# ---------------------------------------------------------------- 4. ataque en suelo
	await _esperar_frames(20)
	Input.action_press("atacar")
	await physics_frame
	Input.action_release("atacar")
	var arranco := false
	for _i in 30:
		await physics_frame
		if _jug.c_estado != C_LIBRE:
			arranco = true
			break
	_check("4. En el suelo el clic izquierdo inicia el ataque (FreeFlow)", arranco,
			"estado=%d golpe=%s" % [_jug.c_estado, str(_jug.c_golpe)])
	var estaba_saltando_al_atacar: bool = _jug.c_salto_aire
	var fin := false
	for _i in 300:
		await physics_frame
		if _jug.c_estado == C_LIBRE:
			fin = true
			break
	_check("4. El golpe termina y la forma vuelve a estado libre", fin and not estaba_saltando_al_atacar)

	# ---------------------------------------------------------------- 5. bloqueo aéreo
	await _esperar_frames(10)
	Input.action_press("saltar")
	await physics_frame
	Input.action_release("saltar")
	var en_aire := false
	for _i in 60:
		await physics_frame
		if not _jug.is_on_floor():
			en_aire = true
			break
	_check("5. Salto: el cuerpo está en el aire", en_aire)
	var ataco_en_aire := false
	var frames_aire := 0
	# Clics repetidos SOLO mientras el cuerpo está en el aire (se comprueba
	# antes de pulsar para no colar un clic legítimo de suelo en el aterrizaje).
	for _i in 15:
		if _jug.is_on_floor():
			break
		Input.action_press("atacar")
		await physics_frame
		Input.action_release("atacar")
		frames_aire += 1
		if _jug.c_estado != C_LIBRE:
			ataco_en_aire = true
	_check("5. Pulsar ataque en el aire no inicia ningún ataque ni combo",
			not ataco_en_aire, "%d clics en el aire, estado=%d" % [frames_aire, _jug.c_estado])

	# ---------------------------------------------------------------- 6. anti-encolado
	# A partir de aquí NO se vuelve a pulsar: se deja caer y se comprueba que
	# ninguno de los clics aéreos se ejecuta al tocar el suelo.
	var aterrizo := false
	for _i in 240:
		await physics_frame
		if _jug.is_on_floor():
			aterrizo = true
			break
	var encolado_al_aterrizar := false
	for _i in 60:
		await physics_frame
		if _jug.c_estado != C_LIBRE:
			encolado_al_aterrizar = true
	_check("6. Al aterrizar NO se ejecuta ningún ataque encolado desde el aire",
			aterrizo and not encolado_al_aterrizar, "aterrizó=%s" % str(aterrizo))

	# ---------------------------------------------------------------- 7. otras formas
	_jug._on_transformacion_elegida(&"velocista")
	var t2 := 0
	while _jug.forma != FORMA_VELOCISTA and t2 < 300:
		await physics_frame
		t2 += 1
	# La transición visual sigue corriendo un momento: se espera a que termine
	# (una segunda selección durante la transición se ignora a propósito).
	while _jug._transformando and t2 < 900:
		await physics_frame
		t2 += 1
	_check("7. El velocista sigue funcionando (selección + modelo visible)",
			_jug.forma == FORMA_VELOCISTA and _jug.visual.visible and not _jug.ataque_visual.visible,
			"forma=%d" % _jug.forma)
	_jug._on_transformacion_elegida(&"velocista")
	var t3 := 0
	while _jug.forma != FORMA_HUMANO and t3 < 300:
		await physics_frame
		t3 += 1
	while _jug._transformando and t3 < 900:
		await physics_frame
		t3 += 1
	_check("7. Volver a humano sigue funcionando",
			_jug.forma == FORMA_HUMANO and _jug.humano.visible and not _jug.ataque_visual.visible,
			"forma=%d" % _jug.forma)
	await _esperar_frames(5)

	print("[TEST] ===== RESULTADO: %d OK, %d FALLOS =====" % [_pasadas, _falladas])
	quit(1 if _falladas > 0 else 0)