extends Node3D
## PRUEBAS de la CAPA DE PULIDO del combate (JuiceCombate).
##
## Jugador REAL (leo_jugador.tscn) en la forma Combate por el camino del menú, con
## el CombatManager del módulo y un enemigo real delante. Comprueba, efecto por
## efecto, que se dispara SÓLO con impacto confirmado, que su interruptor lo apaga
## y que no deja secuelas (p. ej. Engine.time_scale vuelve a 1).
##
##   godot --path <proyecto> res://_tests/prueba_juice_combate.tscn

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const GestorCombate := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_manager.gd")
const ConfigCombate := preload("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")
const ENEMIGO := "res://Enemigos Prueba/Scenes/enemigo_prueba.tscn"
const FORMA_COMBATE := 4
const C_LIBRE := 0

var _ok := 0
var _fallos := 0
var _jug: Node3D
var _juice: Node
var _enemigo: Node3D
var _min_escala := 1.0
var _golpes_sonados := 0
var _conectados := 0
var _lanzados := 0


func _ready() -> void:
	_piso()
	var mgr := Node.new()
	mgr.name = "CombatManager"
	mgr.set_script(GestorCombate)
	mgr.set("config", ConfigCombate)
	add_child(mgr)
	_jug = (load(JUGADOR) as PackedScene).instantiate() as Node3D
	_jug.position = Vector3(0, 0.1, 0)
	add_child(_jug)
	await get_tree().create_timer(0.9).timeout
	_juice = _jug.get_node_or_null("JuiceCombate")
	_check(_juice != null, "LeoJugador tiene el nodo JuiceCombate")
	_jug.connect("golpe_conectado", func(_o: Node3D, _d: Vector3, _i: int, _r: bool) -> void: _conectados += 1)
	_jug.connect("golpe_lanzado", func(_i: int) -> void: _lanzados += 1)
	var pasos: Node = _jug.get_node_or_null("Pasos")
	if pasos != null and pasos.has_signal("golpe"):
		pasos.connect("golpe", func() -> void: _golpes_sonados += 1)

	_jug.call("_on_transformacion_elegida", &"combate")
	var t := 0.0
	while (int(_jug.get("forma")) != FORMA_COMBATE or bool(_jug.get("_transformando"))) and t < 8.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await get_tree().create_timer(0.6).timeout
	_check(int(_jug.get("forma")) == FORMA_COMBATE, "el jugador entró en la forma Combate")

	# --- 1. Golpe AL AIRE: se lanza pero no conecta, no suena impacto, no hay hitstop
	_reset_medidas()
	await _lanzar_golpe()
	_check(_lanzados == 1, "golpe al aire: se emite golpe_lanzado (%d)" % _lanzados)
	_check(_conectados == 0, "golpe al aire: NO se emite golpe_conectado (%d)" % _conectados)
	_check(_golpes_sonados == 0, "golpe al aire: el sonido de IMPACTO no suena (%d)" % _golpes_sonados)
	_check(_min_escala > 0.99, "golpe al aire: no hay hitstop (escala mínima %.2f)" % _min_escala)
	await get_tree().create_timer(2.6).timeout   # se agota la ventana de combo

	# --- 2. Golpe que CONECTA: hitstop real y vuelta a 1 ---------------------
	_enemigo = (load(ENEMIGO) as PackedScene).instantiate() as Node3D
	_enemigo.name = "Blanco"
	add_child(_enemigo)
	_enemigo.set("_vida", 500.0)
	_enemigo.global_position = _jug.global_position + (_jug.get("ataque_visual") as Node3D).global_transform.basis * Vector3(0.0, 0.0, -1.5)
	await get_tree().create_timer(0.5).timeout
	_reset_medidas()
	await _lanzar_golpe()
	_check(_conectados == 1, "golpe que conecta: golpe_conectado una vez (%d)" % _conectados)
	_check(_golpes_sonados == 1, "golpe que conecta: el impacto suena UNA vez (%d)" % _golpes_sonados)
	_check(_min_escala < 0.1, "hitstop: el tiempo se congeló al impactar (escala mínima %.3f)" % _min_escala)
	await get_tree().create_timer(0.3).timeout
	_check(is_equal_approx(Engine.time_scale, 1.0), "hitstop: Engine.time_scale vuelve a 1 (%.3f)" % Engine.time_scale)

	# --- 3. Interruptor apagado: sin hitstop ----------------------------------
	_juice.set("hitstop_activo", false)
	_reset_medidas()
	await _lanzar_golpe()
	_check(_conectados == 1, "con hitstop apagado el golpe sigue conectando (%d)" % _conectados)
	_check(_min_escala > 0.99, "hitstop_activo=false: el tiempo no se toca (escala mínima %.2f)" % _min_escala)
	_juice.set("hitstop_activo", true)

	await _secciones_extra()
	print("==================== JUICE COMBATE: %d OK / %d FALLO ====================" % [_ok, _fallos])


## Punto de extensión: las mejoras siguientes añaden aquí sus comprobaciones.
func _secciones_extra() -> void:
	await _seccion_camara()
	await _seccion_audio()
	await _seccion_destello()


func _seccion_destello() -> void:
	await get_tree().create_timer(2.6).timeout
	var antes := int(_juice.call("estallidos_creados"))
	var fuerza_max := 0.0
	# Cámara lateral SOLO para la foto (la del jugador queda tapada por Leo).
	var cam_previa := get_viewport().get_camera_3d()
	var lateral := Camera3D.new()
	add_child(lateral)
	var medio := (_jug.global_position + _enemigo.global_position) * 0.5
	var eje := (_enemigo.global_position - _jug.global_position).normalized()
	var costado := eje.cross(Vector3.UP).normalized()
	lateral.look_at_from_position(medio + costado * 3.2 + Vector3.UP * 1.5, medio + Vector3.UP * 1.1)
	lateral.current = true
	Input.action_press("atacar")
	await get_tree().physics_frame
	Input.action_release("atacar")
	var foto := false
	for _i in 240:
		await get_tree().process_frame
		var mat: ShaderMaterial = _enemigo.get_meta(&"juice_destello") as ShaderMaterial if _enemigo.has_meta(&"juice_destello") else null
		if mat != null:
			var f := float(mat.get_shader_parameter("fuerza"))
			fuerza_max = maxf(fuerza_max, f)
			if f > 0.6 and not foto:
				foto = true
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				_foto("juice_impacto")
		if int(_jug.get("c_estado")) == C_LIBRE and fuerza_max > 0.0:
			break
	lateral.queue_free()
	if cam_previa != null:
		cam_previa.current = true
	_check(fuerza_max > 0.9, "destello: el overlay del enemigo se enciende al impactar (máx %.2f)" % fuerza_max)
	_check(int(_juice.call("estallidos_creados")) > antes, "estallido: se crea luz en el punto de contacto")
	await get_tree().create_timer(0.5).timeout
	var mat2: ShaderMaterial = _enemigo.get_meta(&"juice_destello") as ShaderMaterial if _enemigo.has_meta(&"juice_destello") else null
	_check(mat2 != null and float(mat2.get_shader_parameter("fuerza")) < 0.01, "destello: se apaga solo")
	_check(get_tree().current_scene.find_children("JuiceEstallido", "", true, false).is_empty(),
			"estallido: los quads se liberan solos")
	var barra := _enemigo.get_node_or_null("BarraVida/Barra") as MeshInstance3D
	_check(barra == null or barra.material_overlay == null, "la barra de vida no recibe el destello")


func _foto(nombre: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://_tests/capturas/%s.png" % nombre))


func _seccion_audio() -> void:
	await get_tree().create_timer(2.6).timeout   # cadena a 0 → jab
	var antes := int(_juice.call("sonidos_disparados"))
	await _lanzar_golpe()
	var jab := int(_juice.call("sonidos_disparados")) - antes
	_check(jab == 2, "audio jab que conecta: whoosh + puñetazo = 2 capas (%d)" % jab)
	antes = int(_juice.call("sonidos_disparados"))
	await _lanzar_golpe()
	var cros := int(_juice.call("sonidos_disparados")) - antes
	_check(cros == 3, "audio cros: whoosh + puñetazo pesado + golpe sordo = 3 capas (%d)" % cros)
	# Golpe al aire: solo el whoosh.
	var pos := _enemigo.global_position
	_enemigo.global_position = pos + Vector3(30, 0, 30)
	await get_tree().create_timer(2.6).timeout
	antes = int(_juice.call("sonidos_disparados"))
	await _lanzar_golpe()
	var aire := int(_juice.call("sonidos_disparados")) - antes
	_check(aire == 1, "audio golpe al aire: solo el whoosh (%d)" % aire)
	_juice.set("audio_capas_activo", false)
	antes = int(_juice.call("sonidos_disparados"))
	await _lanzar_golpe()
	_check(int(_juice.call("sonidos_disparados")) == antes, "audio_capas_activo=false: no suena ninguna capa nueva")
	_juice.set("audio_capas_activo", true)
	_enemigo.global_position = pos
	await get_tree().create_timer(0.5).timeout


func _golpe_y_maximos(lectura: Callable) -> float:
	var maximo := 0.0
	Input.action_press("atacar")
	await get_tree().physics_frame
	Input.action_release("atacar")
	var visto := false
	for _i in 200:
		await get_tree().process_frame
		maximo = maxf(maximo, float(lectura.call()))
		var e := int(_jug.get("c_estado"))
		if e != C_LIBRE:
			visto = true
		elif visto:
			break
	await get_tree().create_timer(0.15).timeout
	return maximo


func _seccion_camara() -> void:
	var piv: Node = _jug.get_node("PivoteCamara")
	await get_tree().create_timer(2.6).timeout   # cadena a 0 → jab
	var trauma := await _golpe_y_maximos(func() -> float: return float(piv.call("trauma_actual")))
	_check(trauma > 0.2, "sacudida: el impacto suma trauma a la cámara (máx %.2f)" % trauma)
	var fov := await _golpe_y_maximos(func() -> float: return -float(piv.call("fov_extra_actual")))
	_check(fov > 0.5, "FOV punch: la cámara se acerca un instante (máx %.2f°)" % fov)
	await get_tree().create_timer(1.0).timeout
	var cam := piv.get_node("Brazo/Camara") as Camera3D
	_check(absf(cam.rotation.z) < 0.002 and absf(cam.h_offset) < 0.01,
			"la cámara vuelve a reposo (roll %.4f, h_offset %.4f)" % [cam.rotation.z, cam.h_offset])
	_juice.set("sacudida_activa", false)
	_juice.set("fov_punch_activo", false)
	var t_off := await _golpe_y_maximos(func() -> float: return float(piv.call("trauma_actual")))
	var f_off := await _golpe_y_maximos(func() -> float: return absf(float(piv.call("fov_extra_actual"))))
	_check(t_off < 0.001 and f_off < 0.01, "interruptores apagados: ni sacudida ni FOV (%.3f / %.3f)" % [t_off, f_off])
	_juice.set("sacudida_activa", true)
	_juice.set("fov_punch_activo", true)


func _process(_delta: float) -> void:
	_min_escala = minf(_min_escala, Engine.time_scale)


func _reset_medidas() -> void:
	_min_escala = 1.0
	_golpes_sonados = 0
	_conectados = 0
	_lanzados = 0


func _lanzar_golpe() -> void:
	Input.action_press("atacar")
	await get_tree().physics_frame
	Input.action_release("atacar")
	var visto := false
	for _i in 200:
		await get_tree().process_frame
		var e := int(_jug.get("c_estado"))
		if e != C_LIBRE:
			visto = true
		elif visto:
			break
	await get_tree().create_timer(0.15).timeout


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[juice-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[juice-suite] FALLO ", texto)


func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Piso"
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(120, 1, 120)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.5, 0)
	add_child(cuerpo)
	var malla := MeshInstance3D.new()
	var caja_malla := BoxMesh.new()
	caja_malla.size = Vector3(120, 1, 120)
	malla.mesh = caja_malla
	cuerpo.add_child(malla)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
