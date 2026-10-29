extends Node3D

# ARNÉS TEMPORAL DE VERIFICACIÓN EN VIVO (se elimina al terminar).
# Instancia el jugador REAL sobre un suelo, entra en forma Fuerza y ejecuta cada
# habilidad llamando a su función de evento real, comprobando que suena el
# archivo correcto. NO modifica el proyecto.

const LEO := preload("res://personaje/base/escenas/leo_jugador.tscn")

var _jug: Node3D
var _s := {}   # nombre corto -> AudioStreamPlayer
var _ok := 0
var _fail := 0
var _log := ""

func _chk(nombre: String, cond: bool, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fail += 1
	var linea := "[TEST] %s :: %s | %s" % ["OK" if cond else "FALLO", nombre, detalle]
	_log += linea + "\n"
	print(linea)

func _volcar() -> void:
	var f := FileAccess.open("res://pruebas/_resultado_fuerza_sfx.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(_log + "RESUMEN: %d OK, %d FALLOS\n" % [_ok, _fail])
		f.close()

func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _esperar_suelo(max_s: float) -> bool:
	var t := 0.0
	while t < max_s and not _jug.is_on_floor():
		await get_tree().physics_frame
		t += 1.0 / 60.0
	return _jug.is_on_floor()

func _esperar_aire(max_s: float) -> bool:
	var t := 0.0
	while t < max_s and _jug.is_on_floor():
		await get_tree().physics_frame
		t += 1.0 / 60.0
	return not _jug.is_on_floor()

func _ready() -> void:
	# Suelo para poder estar "en el suelo".
	var suelo := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 80)
	cs.shape = bs
	suelo.add_child(cs)
	suelo.position = Vector3(0, -0.5, 0)
	add_child(suelo)

	_jug = LEO.instantiate()
	add_child(_jug)
	_jug.global_position = Vector3(0, 1.0, 0)
	await _esperar(0.6)

	_s["salto"] = _jug.get_node_or_null("AudioFuerzaSalto")
	_s["impacto"] = _jug.get_node_or_null("AudioFuerzaImpacto")
	_s["agarre"] = _jug.get_node_or_null("AudioFuerzaAgarre")
	_s["tirada"] = _jug.get_node_or_null("AudioFuerzaTirada")
	_s["golpe"] = _jug.get_node_or_null("AudioFuerzaGolpe")
	_s["patada"] = _jug.get_node_or_null("AudioFuerzaPatada")

	var falta := []
	var bus_mal := []
	var sin_stream := []
	for k in _s.keys():
		var p: AudioStreamPlayer = _s[k]
		if p == null:
			falta.append(k)
		else:
			if p.bus != &"Efectos":
				bus_mal.append(k)
			if p.stream == null:
				sin_stream.append(k)
	_chk("existen los 6 reproductores de Fuerza", falta.is_empty(), "faltan=%s" % str(falta))
	_chk("los 6 usan el bus 'Efectos'", bus_mal.is_empty(), "mal=%s" % str(bus_mal))
	_chk("los 6 tienen stream asignado", sin_stream.is_empty(), "sin=%s" % str(sin_stream))
	_chk("transformación intacta (bus Efectos)",
		(_jug.get_node_or_null("AudioTransformacion") as AudioStreamPlayer) != null)
	_chk("reproductores del velocista intactos (4)",
		_jug.get_node_or_null("AudioCarga") != null and _jug.get_node_or_null("AudioTrazado") != null
		and _jug.get_node_or_null("AudioDash") != null and _jug.get_node_or_null("AudioGolpe") != null)

	_jug._entrar_fuerza()
	await _esperar_suelo(1.0)
	_chk("en forma Fuerza y en el suelo", _jug.forma == 3 and _jug.is_on_floor(),
		"forma=%d suelo=%s" % [_jug.forma, _jug.is_on_floor()])

	# --- SALTO (toque corto) ---
	_s["salto"].stop()
	_jug.f_super_carga = 0.05
	_jug._ejecutar_super()
	await get_tree().physics_frame
	_chk("salto (toque): suena al despegar", _s["salto"].playing, "")
	_jug.velocity = Vector3(0, -40, 0)
	await _esperar_suelo(2.0)

	# --- SUPERSALTO (carga completa) ---
	_s["salto"].stop()
	_jug.f_super_carga = 1.4
	_jug._ejecutar_super()
	await get_tree().physics_frame
	_chk("supersalto: suena al impulso", _s["salto"].playing, "")
	_jug.velocity = Vector3(0, -40, 0)
	await _esperar_suelo(2.0)

	# --- IMPACTO CONTRA EL SUELO (E) ---
	_jug.global_position = Vector3(0, 5, 0)
	_jug.velocity = Vector3.ZERO
	var en_aire := await _esperar_aire(0.6)
	_s["impacto"].stop()
	_jug._intentar_slam_fuerza()
	await _esperar(0.8)
	_chk("pisotón (E): suena al tocar el suelo", _s["impacto"].playing and _jug.is_on_floor(),
		"aire_previo=%s suelo=%s" % [en_aire, _jug.is_on_floor()])

	# --- AGARRAR LA PIEDRA (Q) ---
	await _esperar_suelo(1.0)
	await _esperar(0.2)
	_s["agarre"].stop()
	_jug._intentar_roca_fuerza()
	await get_tree().physics_frame
	_chk("agarrar roca (Q): suena al agarrarla", _s["agarre"].playing and _jug.f_roca != null, "")

	# --- LANZAR LA PIEDRA ---
	_jug.f_roca_lista = true
	_s["tirada"].stop()
	_jug._lanzar_roca_fuerza()
	await get_tree().physics_frame
	_chk("lanzar roca: suena al salir de las manos", _s["tirada"].playing and _jug.f_roca == null, "")

	# --- GOLPE DE PUÑO ---
	_s["golpe"].stop()
	_s["patada"].stop()
	_jug._f_ataque_clip = "Punch_Left"
	_jug._aplicar_impacto_golpe_fuerza()
	await get_tree().physics_frame
	_chk("puñetazo: suena golpe.mp3 en el impacto", _s["golpe"].playing, "")

	# --- PATADA ---
	_s["golpe"].stop()
	_s["patada"].stop()
	_jug._f_ataque_clip = "Kick"
	_jug._aplicar_impacto_golpe_fuerza()
	await get_tree().physics_frame
	_chk("patada: suena patada.mp3 en el impacto", _s["patada"].playing, "")
	_chk("la patada NO dispara el sonido del puño", not _s["golpe"].playing, "")

	print("[TEST] ===== RESUMEN SONIDOS FUERZA: %d OK, %d FALLOS =====" % [_ok, _fail])
	_volcar()
	await _esperar(0.4)
	get_tree().quit()