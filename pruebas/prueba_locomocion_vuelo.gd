extends Node3D
## PRUEBAS OBLIGATORIAS (puntos 4, 5 y 6): locomoción TERRESTRE del personaje de
## VUELO con el clip del personaje de COMBATE retargeteado, pisadas sincronizadas
## con la animación real y compatibilidad con el audio de vuelo.
## Cada comprobación imprime OK/FALLO y al final el total.

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
## Calibración del clip (m/s que cubre con escala 1) = referencia medida del
## personaje de Combate.
const REF_VEL := 2.95
## Duración del ciclo del clip retargeteado (s).
const CICLO := 0.533333

var _ok := 0
var _fallos := 0
var _jug: Node3D
var _vuelo: CharacterBody3D
var _ap: AnimationPlayer
var _ctrl: Node
var _fc: Node
var _pasos: PasosJugador
var _sonidos: Node
var _piel: Skeleton3D

var _ventana := ""
var _pisadas_vuelo := 0
var _pisadas_walk := 0
var _pisadas_run := 0
var _pisadas_idle := 0
var _pisadas_aire := 0
var _aleteos := 0
var _aleteos_en_suelo := 0
var _aleteo_prev := false

func _ready() -> void:
	_piso()
	var ps := load(JUGADOR) as PackedScene
	_jug = ps.instantiate() as Node3D
	_jug.position = Vector3.ZERO
	add_child(_jug)
	_vuelo = _jug.get_node("Vuelo") as CharacterBody3D
	_ap = _vuelo.get_node("VisualRoot/AnimationLibrary_Godot_Standard/AnimationPlayer") as AnimationPlayer
	_piel = _vuelo.get_node("VisualRoot/AnimationLibrary_Godot_Standard/Rig/GeneralSkeleton") as Skeleton3D
	_ctrl = _vuelo.get_node("AnimationController")
	_fc = _vuelo.get_node("FlightController")
	_sonidos = _vuelo.get_node("SonidosVuelo")
	_jug.call("_on_transformacion_elegida", &"aguila")
	await get_tree().create_timer(2.0).timeout

	# --- Recepción de pisadas (contadas por ventana) -------------------------
	_pasos = _vuelo.get_node_or_null("Pasos") as PasosJugador
	if _pasos != null:
		_pasos.call("silenciar", false)  # los ajustes del usuario no deben alterar la prueba
		_pasos.pisada.connect(_on_pisada)

	# --- Comprobaciones de ESTRUCTURA ---------------------------------------
	_check(_ap.has_animation_library(&"vuelo_walk"), "librería 'vuelo_walk' (clip del combate retargeteado) registrada en el reproductor del vuelo")
	_check(String(_ctrl.get("_walk_animation_name")).ends_with("vuelo_walk") \
			and String(_ctrl.get("_walk_animation_name")) != "Walk",
			"el clip de caminata resuelto es el retargeteado ('%s'), no el del maniquí" % String(_ctrl.get("_walk_animation_name")))
	_check(String(_ctrl.get("_sprint_animation_name")).ends_with("vuelo_walk") \
			and String(_ctrl.get("_sprint_animation_name")) != "Sprint",
			"el clip de carrera usa el mismo retargeteado ('%s'): la forma Combate no tiene uno aparte" % String(_ctrl.get("_sprint_animation_name")))
	_check(_pasos != null, "el sistema de pisadas compartido (PasosJugador) existe en el cuerpo de vuelo")
	var nodos_pasos := _vuelo.find_children("Pasos", "Node", false, false)
	_check(nodos_pasos.size() == 1, "hay UN solo nodo de pisadas (sin duplicados): %d" % nodos_pasos.size())
	if _pasos != null:
		_check(_pasos.get_node_or_null("GolpeCombate") == null, "el sistema de pisadas del vuelo NO crea el reproductor del golpe de Combate (el vuelo ya tiene Golpe3/Golpe4)")
		_check(_pasos.get_node_or_null("Paso1") != null, "el fondo común de reproductores de paso está creado")
	var golpes := 0
	for n in _jug.find_children("*", "AudioStreamPlayer", true, false):
		if String(n.name) == "GolpeCombate":
			golpes += 1
	_check(golpes == 1, "sólo existe UN reproductor GolpeCombate en todo el jugador: %d" % golpes)
	# Animaciones de vuelo conservadas.
	var conservadas := 0
	for clip in ["Idle", "Jump", "Jump_Land", "VueloHeroe", "Planeo", "PosePicado", "CaidaLibre"]:
		if String(_ctrl.call("_find_opcional", StringName(clip))) != "":
			conservadas += 1
	_check(conservadas >= 6, "las animaciones de vuelo siguen disponibles (%d/7 clave)" % conservadas)

	# --- El clip está alineado al suelo y sin pistas rotas -------------------
	var clip := _ap.get_animation(&"vuelo_walk/vuelo_walk")
	if clip == null:
		clip = _ap.get_animation(&"vuelo_walk")
	var huesos_ok := 0
	var pistas := 0
	for p in clip.get_track_count():
		var ruta := String(clip.track_get_path(p))
		pistas += 1
		var hueso := ruta.substr(ruta.find(":") + 1)
		var i := _piel.find_bone(StringName(hueso))
		if i >= 0:
			huesos_ok += 1
	_check(huesos_ok == pistas, "TODAS las pistas del clip apuntan a huesos reales del esqueleto (%d/%d, sin deformaciones por rutas rotas)" % [huesos_ok, pistas])
	var min_pie := _min_pie_del_clip(clip)
	_check(min_pie > -0.06 and min_pie <= 0.02, "el punto más bajo del pie toca el suelo sin hundirse (mín = %.3f m)" % min_pie)

	# --- Caminata ------------------------------------------------------------
	_ventana = "walk"
	Input.action_press("mover_adelante")
	await get_tree().create_timer(1.6).timeout
	var vel_walk := _vel_h()
	var esc_walk := _ap.speed_scale
	var esperado_walk: float = clampf(vel_walk / REF_VEL, 0.8, 3.0)
	print("[suite] caminando: vel=%.2f m/s escala=%.3f (esperada %.3f) clip=%s" % [vel_walk, esc_walk, esperado_walk, String(_ap.current_animation)])
	_check(vel_walk > 3.0, "al mantener 'adelante' el cuerpo camina de verdad (%.2f m/s)" % vel_walk)
	_check(String(_ap.current_animation).ends_with("vuelo_walk"), "la caminata reproduce el clip del combate retargeteado (clip actual: %s)" % String(_ap.current_animation))
	_check(absf(esc_walk - esperado_walk) < 0.12, "el ciclo se escala a la velocidad REAL (escala %.3f ≈ vel/%.2f = %.3f): sin deslizamiento" % [esc_walk, REF_VEL, esperado_walk])
	var esperadas_walk := 1.6 * 2.0 * esc_walk / CICLO
	_check(_pisadas_walk >= 2, "se oyen pisadas al caminar: %d" % _pisadas_walk)
	_check(_pisadas_walk >= esperadas_walk * 0.55 and _pisadas_walk <= esperadas_walk * 1.35, "la cadencia de pisadas sigue la del clip real (%.1f pasos, esperado ≈ %.1f)" % [_pisadas_walk, esperadas_walk])
	Input.action_release("mover_adelante")

	# --- Quieto --------------------------------------------------------------
	# Media pausa para que la DESACELERACIÓN termine: mientras el cuerpo todavía
	# se mueve, una pisada es correcta (no es estar quieto).
	await get_tree().create_timer(0.5).timeout
	_ventana = "idle"
	await get_tree().create_timer(1.2).timeout
	print("[suite] quieto: clip=%s pisadas=%d" % [String(_ap.current_animation), _pisadas_idle])
	_check(_pisadas_idle == 0, "quieto NO se pisa (%d pisadas), aunque el reproductor siga sobre el clip de locomoción" % _pisadas_idle)

	# --- Carrera -------------------------------------------------------------
	_ventana = "run"
	Input.action_press("mover_adelante")
	Input.action_press("correr")
	await get_tree().create_timer(1.8).timeout
	var vel_run := _vel_h()
	var esc_run := _ap.speed_scale
	var esperado_run: float = clampf(vel_run / REF_VEL, 0.8, 3.0)
	print("[suite] corriendo: vel=%.2f m/s escala=%.3f (esperada %.3f) clip=%s" % [vel_run, esc_run, esperado_run, String(_ap.current_animation)])
	_check(vel_run > vel_walk + 1.5, "correr sube la velocidad real (%.2f > %.2f m/s)" % [vel_run, vel_walk])
	_check(String(_ap.current_animation).ends_with("vuelo_walk"), "la carrera sigue usando el clip del combate (clip actual: %s)" % String(_ap.current_animation))
	_check(absf(esc_run - esperado_run) < 0.15, "el ciclo se acelera con la velocidad REAL al correr (escala %.3f ≈ %.3f)" % [esc_run, esperado_run])
	_check(esc_run > esc_walk + 0.5, "la escala de carrera es mayor que la de caminata (%.3f > %.3f)" % [esc_run, esc_walk])
	_check(_pisadas_run > float(_pisadas_walk) * 1.2, "la CADENCIA de pisadas sube al correr (%d en 1.8 s vs %d en 1.6 s)" % [_pisadas_run, _pisadas_walk])
	Input.action_release("correr")
	Input.action_release("mover_adelante")
	await get_tree().create_timer(0.8).timeout

	# --- Salto (aire) --------------------------------------------------------
	_ventana = "aire"
	Input.action_press("saltar")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("saltar")
	await get_tree().create_timer(0.25).timeout
	var en_aire: bool = not _vuelo.is_on_floor()
	await get_tree().create_timer(0.9).timeout
	print("[suite] salto: en el aire durante la ventana=%s, pisadas=%d" % [str(en_aire), _pisadas_aire])
	_check(en_aire, "el salto despega del suelo de verdad (control de la propia prueba)")
	_check(_pisadas_aire == 0, "en el aire NO se pisa (%d pisadas)" % _pisadas_aire)
	await get_tree().create_timer(0.6).timeout

	# --- Vuelo ---------------------------------------------------------------
	_ventana = ""
	Input.action_press("toggle_flight")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("toggle_flight")
	await get_tree().create_timer(0.9).timeout
	var volando: bool = bool(_fc.get("is_flying"))
	print("[suite] vuelo activado = %s" % str(volando))
	_ventana = "vuelo"
	Input.action_press("mover_adelante")
	await get_tree().create_timer(1.3).timeout
	Input.action_release("mover_adelante")
	print("[suite] volando: pisadas=%d aleteos=%d" % [_pisadas_vuelo, _aleteos])
	_check(volando, "el vuelo se activó (control de la propia prueba)")
	_check(_pisadas_vuelo == 0, "volando NO se pisa (los pasos no se cuelan en el vuelo): %d" % _pisadas_vuelo)
	_check(_aleteos > 0, "el ALETEO sigue sonando en vuelo (%d ciclos): el sistema de pasos no lo interfiere" % _aleteos)
	# Pisadas y aleteo no se solapan: mientras hubo pasos (suelo) no hubo aleteo.
	_check(_aleteos_en_suelo == 0, "el aleteo NO sonó durante la caminata/carrera (%d arranques en ventanas de suelo)" % _aleteos_en_suelo)
	# Apagar el vuelo y volver al suelo.
	print("[suite] antes del 2º toggle: is_flying=%s en_suelo=%s y=%.2f clip=%s vel=%.2f" % [str(_fc.get("is_flying")), str(_vuelo.is_on_floor()), _vuelo.global_position.y, String(_ap.current_animation), _vel_h()])
	Input.action_press("toggle_flight")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("toggle_flight")
	print("[suite] tras el 2º toggle:  is_flying=%s" % str(_fc.get("is_flying")))
	await get_tree().create_timer(1.6).timeout
	print("[suite] tras aterrizar: is_flying=%s en_suelo=%s y=%.2f clip=%s" % [str(_fc.get("is_flying")), str(_vuelo.is_on_floor()), _vuelo.global_position.y, String(_ap.current_animation)])
	_check(not bool(_fc.get("is_flying")) and _vuelo.is_on_floor(), "el vuelo se apaga y el cuerpo vuelve al suelo (toca suelo y pasa a modo terrestre)")

	# --- Captura final: caminando de perfil, cerca de la cámara --------------
	_ventana = "captura"
	_vuelo.global_position = Vector3(0.3, 0.35, 0.0)
	_jug.global_position = Vector3(0.3, 0.35, 0.0)
	_vuelo.velocity = Vector3.ZERO
	await get_tree().create_timer(0.6).timeout
	Input.action_press("mover_izquierda")
	await get_tree().create_timer(0.55).timeout
	print("[suite] captura: vel=%.2f escala=%.3f clip=%s" % [_vel_h(), _ap.speed_scale, String(_ap.current_animation)])
	print("==================== RESULTADO: %d OK / %d FALLO ====================" % [_ok, _fallos])

func _process(_delta: float) -> void:
	if _sonidos == null:
		return
	var a := _sonidos.get_node_or_null("Aleteo_A") as AudioStreamPlayer
	var b := _sonidos.get_node_or_null("Aleteo_B") as AudioStreamPlayer
	var sonando := (a != null and a.playing) or (b != null and b.playing)
	if sonando and not _aleteo_prev:
		_aleteos += 1
		if _ventana == "walk" or _ventana == "run" or _ventana == "idle" or _ventana == "aire":
			_aleteos_en_suelo += 1
	_aleteo_prev = sonando

func _on_pisada(_forma: String, _clip: String, _pie: String, _u: float, _variante: int) -> void:
	match _ventana:
		"walk":
			_pisadas_walk += 1
		"run":
			_pisadas_run += 1
		"idle":
			_pisadas_idle += 1
		"aire":
			_pisadas_aire += 1
		"vuelo":
			_pisadas_vuelo += 1

func _vel_h() -> float:
	var v: Vector3 = _vuelo.velocity
	return Vector2(v.x, v.z).length()

func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[suite] OK   %s" % texto)
	else:
		_fallos += 1
		print("[suite] FALLO %s" % texto)

## Altura mínima alcanzada por el pie (toes y tobillo, ambos pies) a lo largo del
## ciclo real del clip, muestreado a 240 Hz — debe quedar rozando el suelo.
func _min_pie_del_clip(clip: Animation) -> float:
	var nombre := &"vuelo_walk/vuelo_walk" if _ap.has_animation(&"vuelo_walk/vuelo_walk") else &"vuelo_walk"
	_ap.speed_scale = 0.0
	_ap.play(nombre)
	_ap.seek(0.0, true)
	var idxs: Array[int] = []
	for hueso in ["LeftToes", "LeftFoot", "RightToes", "RightFoot"]:
		var i := _piel.find_bone(StringName(hueso))
		if i >= 0:
			idxs.append(i)
	var mn := INF
	var n := int(clip.length * 240.0)
	for k in n + 1:
		_ap.seek(clip.length * float(k) / float(n), true)
		if _piel.has_method("force_update_all_bone_transforms"):
			_piel.call("force_update_all_bone_transforms")
		for i in idxs:
			mn = minf(mn, (_piel.global_transform * _piel.get_bone_global_pose(i).origin).y)
	_ap.speed_scale = 1.0
	return mn

func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Piso"
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(80, 1, 80)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.5, 0)
	add_child(cuerpo)
	var malla := MeshInstance3D.new()
	var caja_malla := BoxMesh.new()
	caja_malla.size = Vector3(80, 1, 80)
	malla.mesh = caja_malla
	cuerpo.add_child(malla)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.25, 3.6)
	cam.look_at_from_position(Vector3(0.0, 1.25, 3.6), Vector3(0.0, 0.9, 0.0))
	cam.current = true
	add_child(cam)