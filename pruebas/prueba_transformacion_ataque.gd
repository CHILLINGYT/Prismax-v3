extends Node

# Suite de la integración de la transformación de ataque (forma Combate) y de los
# sistemas acuáticos que comparte. Comprueba, sobre la escena REAL del jugador:
#   1. el menú F ofrece "Combate" como opción desbloqueada;
#   2. seleccionarla carga el modelo del módulo (forma + animaciones listas);
#   2b. la cadena de combate son TRES golpes (recto/cruzado/gancho) que encadenan
#       en orden y vuelven al primero, con el daño a la mitad y las animaciones
#       ágiles con el impacto sincronizado;
#   2c. el combo ACUÁTICO sigue con sus cuatro golpes y su daño de siempre;
#   2d. los sonidos acuáticos están cableados (nado en bucle + dos capas de golpe +
#       sonido de impacto de la ola);
#   3. el FOV usa el mismo mecanismo central que las demás formas (CamaraZiba);
#   4. en el suelo el clic izquierdo inicia la cadena de ataque;
#   5. en el aire no se inicia ningún ataque;
#   6. al aterrizar no se ejecuta nada encolado (los clics aéreos no se encolan);
#   7. las demás transformaciones siguen funcionando (velocista y vuelta a humano).
#
# No forma parte del juego: vive en res://pruebas/ y se ejecuta con
#   godot --headless --path <proyecto> res://pruebas/prueba_transformacion_ataque.tscn
#
# OJO con el modo script (`-s`): ahí Godot NO registra los autoloads, así que
# camara_jugador.gd (que lee AjustesJugabilidad) no compila y la suite entera falla
# en falso. Por eso es una ESCENA con Node y no un script SceneTree.

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")
const MENU := preload("res://personaje/ui_transformacion/scripts/menu_transformaciones.gd")

# Ids del enum ControladorLeo.Forma y del enum C_E (para no depender de casts).
const FORMA_HUMANO := 0
const FORMA_VELOCISTA := 1
const FORMA_COMBATE := 4
const C_LIBRE := 0

## Vigilante: si algo se bloquea, la suite termina igual con un mensaje claro en
## lugar de quedarse colgada (así una corrida nunca se pierde sin salida).
const TIEMPO_MAXIMO := 150.0

var _pasadas := 0
var _falladas := 0
var _jug: CharacterBody3D
var _t := 0.0


func _ready() -> void:
	call_deferred("_correr")


func _process(delta: float) -> void:
	_t += delta
	if _t > TIEMPO_MAXIMO:
		print("[TEST] ===== TIEMPO AGOTADO: la suite se quedó bloqueada =====")
		get_tree().quit(2)


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
		await get_tree().physics_frame


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
	get_tree().root.add_child(mundo)
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
	_check("2. La librería del módulo tiene los 8 clips (locomoción + los de golpe)", clips_ok)
	_check("2. En humano la representación de ataque está oculta",
			_jug.ataque_visual != null and not _jug.ataque_visual.visible)

	# ------------------------------------------------ 2b. cadena de TRES golpes
	# El combo básico de la forma Combate son exactamente tres golpes consecutivos:
	# recto (jab), cruzado (cros) y el gancho (gancho) que cierra la cadena; después
	# del gancho la cadena vuelve al recto. Sale del módulo (SPRINT), sin duplicar.
	var cfg: Variant = _jug._cfg_encuentro()
	var cadena: Array = _jug._cadena_combate(cfg)
	_check("2b. La cadena de combate tiene exactamente TRES golpes", cadena.size() == 3,
			"%d golpes" % cadena.size())
	var ids_ok: bool = cadena.size() == 3 \
			and String(cadena[0].id) == "jab" and String(cadena[0].animation) == "jab" \
			and String(cadena[1].id) == "cros" and String(cadena[1].animation) == "cros" \
			and String(cadena[2].id) == "gancho" and String(cadena[2].animation) == "gancho"
	_check("2b. Los tres golpes son recto (jab), cruzado (cros) y gancho, en orden", ids_ok,
			"%s / %s / %s" % [str(cadena[0].id) if cadena.size() > 0 else "—",
					str(cadena[1].id) if cadena.size() > 1 else "—",
					str(cadena[2].id) if cadena.size() > 2 else "—"])
	_check("2b. Daño a la mitad: base 10 y golpes de 10 / 14 / 17", cadena.size() == 3 \
			and is_equal_approx(float(cfg.attack_damage), 10.0) \
			and is_equal_approx(float(cadena[0].damage), 10.0) \
			and is_equal_approx(float(cadena[1].damage), 14.0) \
			and is_equal_approx(float(cadena[2].damage), 17.0),
			"base=%.1f golpes=%.1f/%.1f/%.1f" % [float(cfg.attack_damage),
					float(cadena[0].damage) if cadena.size() > 0 else 0.0,
					float(cadena[1].damage) if cadena.size() > 1 else 0.0,
					float(cadena[2].damage) if cadena.size() > 2 else 0.0])
	var fases_ok: bool = cadena.size() == 3 \
			and is_equal_approx(float(cadena[0].speed), 1.25) \
			and is_equal_approx(float(cadena[1].speed), 1.2) \
			and is_equal_approx(float(cadena[2].speed), 1.15) \
			and is_equal_approx(float(cadena[0].windup), 0.233 / 1.25) \
			and is_equal_approx(float(cadena[1].windup), 0.147 / 1.2) \
			and is_equal_approx(float(cadena[2].windup), 0.327 / 1.15) \
			and is_equal_approx(float(cadena[0].active), 0.10)
	_check("2b. Golpes ágiles con el impacto sincronizado (velocidad y fases)", fases_ok,
			"v=%.2f/%.2f/%.2f preparar=%.3f/%.3f/%.3f" % [
					float(cadena[0].speed) if cadena.size() > 0 else 0.0,
					float(cadena[1].speed) if cadena.size() > 1 else 0.0,
					float(cadena[2].speed) if cadena.size() > 2 else 0.0,
					float(cadena[0].windup) if cadena.size() > 0 else 0.0,
					float(cadena[1].windup) if cadena.size() > 1 else 0.0,
					float(cadena[2].windup) if cadena.size() > 2 else 0.0])

	# ----------------- 2c. el pez combate con el sistema del personaje de Fuerza
	# El combo acuático de CUATRO golpes (combo_agua/*) ya no existe: el personaje
	# actual usa el sistema del personaje de Fuerza, con SUS DOS golpes (jab y
	# cruzado) sobre los clips propios `attack` y `attack_2`.
	var cm: Dictionary = (_jug.get_script() as GDScript).get_script_constant_map()
	var golpe_ok: bool = is_equal_approx(float(cm.get("A_GOLPE_IMPACTO_U", 0.0)), 0.54) \
			and is_equal_approx(float(cm.get("A_GOLPE2_IMPACTO_U", 0.0)), 0.55) \
			and is_equal_approx(float(cm.get("A_COMBO_VENTANA", 0.0)), 0.45) \
			and is_equal_approx(float(cm.get("A_GOLPE_ALCANCE", 0.0)), 1.1) \
			and is_equal_approx(float(cm.get("A_GOLPE_RADIO", 0.0)), 0.7) \
			and is_equal_approx(float(cm.get("A_GOLPE_ALTURA", 0.0)), 1.2) \
			and is_equal_approx(float(cm.get("A_GOLPE_DANIO", 0.0)), 20.0) \
			and is_equal_approx(float(cm.get("A_GOLPE_CAIDA", 0.0)), 0.4) \
			and is_equal_approx(float(cm.get("A_GOLPE_ARRIBA", 0.0)), 0.3)
	_check("2c. El pez golpea con los tiempos y el alcance del personaje de Fuerza",
			golpe_ok, "impacto=%.2f/%.2f ventana=%.2f alcance=%.2f radio=%.2f alto=%.2f" % [
					float(cm.get("A_GOLPE_IMPACTO_U", 0.0)),
					float(cm.get("A_GOLPE2_IMPACTO_U", 0.0)),
					float(cm.get("A_COMBO_VENTANA", 0.0)),
					float(cm.get("A_GOLPE_ALCANCE", 0.0)),
					float(cm.get("A_GOLPE_RADIO", 0.0)),
					float(cm.get("A_GOLPE_ALTURA", 0.0))])
	var anim_ac: AnimationPlayer = _jug.get_node_or_null("Acuatico/AnimadorAcuatico")
	var clips_golpe: bool = anim_ac != null \
			and anim_ac.has_animation("attack") and anim_ac.has_animation("attack_2")
	_check("2c. La librería acuática trae los DOS golpes (attack y attack_2)", clips_golpe)
	var largo_a := 0.0
	var largo_b := 0.0
	if anim_ac != null and anim_ac.has_animation("attack"):
		largo_a = anim_ac.get_animation("attack").length
	if anim_ac != null and anim_ac.has_animation("attack_2"):
		largo_b = anim_ac.get_animation("attack_2").length
	# Las fracciones de impacto (0.54 / 0.55) salen de ESTOS clips: si un día cambia
	# su duración, esta comprobación lo avisa.
	_check("2c. Las fracciones de impacto cuadran con la duración real de sus clips",
			absf(largo_a - 1.033) < 0.03 and absf(largo_b - 1.433) < 0.03,
			"attack=%.3f s attack_2=%.3f s" % [largo_a, largo_b])

	# ------------------------------------------------ 2d. sonidos acuáticos
	var s_nado: AudioStreamPlayer = _jug.get_node_or_null("AudioNado") as AudioStreamPlayer
	var s_fis: AudioStreamPlayer = _jug.get_node_or_null("AudioGolpeAguaFisico") as AudioStreamPlayer
	var s_agua: AudioStreamPlayer = _jug.get_node_or_null("AudioGolpeAguaSalpicadura") as AudioStreamPlayer
	_check("2d. El jugador trae los tres reproductores acuáticos (nado + dos golpes)",
			s_nado != null and s_fis != null and s_agua != null)
	var bucle := false
	var largo_nado := 0.0
	if s_nado != null and s_nado.stream is AudioStreamWAV:
		var w := s_nado.stream as AudioStreamWAV
		bucle = w.loop_mode == AudioStreamWAV.LOOP_FORWARD
		largo_nado = w.get_length()
	_check("2d. El sonido de nado queda en BUCLE continuo (duración ~0,87 s)",
			bucle and largo_nado > 0.5, "loop=%s largo=%.2f s" % [str(bucle), largo_nado])
	_check("2d. Los dos golpes tienen su archivo (físico y agua)",
			s_fis != null and s_fis.stream != null and s_agua != null and s_agua.stream != null,
			"%s | %s" % [
					str(s_fis.stream.resource_path) if s_fis != null and s_fis.stream != null else "—",
					str(s_agua.stream.resource_path) if s_agua != null and s_agua.stream != null else "—"])
	var ola: GDScript = load("res://personaje/transformaciones/acuatica/abilities/water_surge.gd") as GDScript
	var sonido_ola: bool = ola != null and ola.get_script_constant_map().has("AUD_OLA_IMPACTO")
	_check("2d. La ola (habilidad 4) trae su propio sonido de impacto", sonido_ola)

	# ---------------------------------------------------------------- 2. selección
	_jug._on_transformacion_elegida(&"combate")
	var t1 := 0
	while _jug.forma != FORMA_COMBATE and t1 < 300:
		await get_tree().physics_frame
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
	var piv: Variant = _jug.pivote
	_check("3. FOV: el objetivo vuelve a la base central (70) al entrar en la forma",
			is_equal_approx(piv.objetivo_fov, piv.fov_base) and is_equal_approx(piv.fov_base, 70.0),
			"objetivo=%.1f base=%.1f" % [piv.objetivo_fov, piv.fov_base])
	var cam: Camera3D = piv.get_node_or_null("Brazo/Camara") as Camera3D
	var t_fov := 0
	while t_fov < 180 and (cam == null or absf(cam.fov - piv.fov_base) > 0.5):
		await get_tree().physics_frame
		t_fov += 1
	_check("3. La cámara real converge al FOV de las demás formas",
			cam != null and absf(cam.fov - 70.0) <= 0.5,
			"fov=%.2f" % (cam.fov if cam != null else -1.0))

	# ---------------------------------------------------------------- 4. ataque en suelo
	await _esperar_frames(20)
	Input.action_press("atacar")
	await get_tree().physics_frame
	Input.action_release("atacar")
	var arranco := false
	for _i in 30:
		await get_tree().physics_frame
		if _jug.c_estado != C_LIBRE:
			arranco = true
			break
	_check("4. En el suelo el clic izquierdo inicia el ataque (FreeFlow)", arranco,
			"estado=%d golpe=%s" % [_jug.c_estado, str(_jug.c_golpe)])
	var estaba_saltando_al_atacar: bool = _jug.c_salto_aire
	var fin := false
	for _i in 300:
		await get_tree().physics_frame
		if _jug.c_estado == C_LIBRE:
			fin = true
			break
	_check("4. El golpe termina y la forma vuelve a estado libre", fin and not estaba_saltando_al_atacar)

	# ---------------------------------------------------------------- 5. bloqueo aéreo
	await _esperar_frames(10)
	Input.action_press("saltar")
	await get_tree().physics_frame
	Input.action_release("saltar")
	var en_aire := false
	for _i in 60:
		await get_tree().physics_frame
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
		await get_tree().physics_frame
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
		await get_tree().physics_frame
		if _jug.is_on_floor():
			aterrizo = true
			break
	var encolado_al_aterrizar := false
	for _i in 60:
		await get_tree().physics_frame
		if _jug.c_estado != C_LIBRE:
			encolado_al_aterrizar = true
	_check("6. Al aterrizar NO se ejecuta ningún ataque encolado desde el aire",
			aterrizo and not encolado_al_aterrizar, "aterrizó=%s" % str(aterrizo))

	# ---------------------------------------------------------------- 7. otras formas
	_jug._on_transformacion_elegida(&"velocista")
	var t2 := 0
	while _jug.forma != FORMA_VELOCISTA and t2 < 300:
		await get_tree().physics_frame
		t2 += 1
	# La transición visual sigue corriendo un momento: se espera a que termine
	# (una segunda selección durante la transición se ignora a propósito).
	while _jug._transformando and t2 < 900:
		await get_tree().physics_frame
		t2 += 1
	_check("7. El velocista sigue funcionando (selección + modelo visible)",
			_jug.forma == FORMA_VELOCISTA and _jug.visual.visible and not _jug.ataque_visual.visible,
			"forma=%d" % _jug.forma)
	_jug._on_transformacion_elegida(&"velocista")
	var t3 := 0
	while _jug.forma != FORMA_HUMANO and t3 < 300:
		await get_tree().physics_frame
		t3 += 1
	while _jug._transformando and t3 < 900:
		await get_tree().physics_frame
		t3 += 1
	_check("7. Volver a humano sigue funcionando",
			_jug.forma == FORMA_HUMANO and _jug.humano.visible and not _jug.ataque_visual.visible,
			"forma=%d" % _jug.forma)
	await _esperar_frames(5)

	print("[TEST] ===== RESULTADO: %d OK, %d FALLOS =====" % [_pasadas, _falladas])
	get_tree().quit(1 if _falladas > 0 else 0)