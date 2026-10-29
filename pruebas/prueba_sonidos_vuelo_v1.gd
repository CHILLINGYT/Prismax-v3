extends Node3D
## Prueba EN VIVO de los SONIDOS DE VUELO (5 archivos) sobre el personaje REAL:
##  A) aleteo (sin número) en cada aleteo REAL de la animación (hover y ascenso),
##     y NADA cuando el aleteo está congelado (picado/planeo);
##  B) despegue 2.2: una sola vez, al despegar del suelo;
##  C) aire 2.1: en la transición real reposo (~1 s) → movimiento;
##  D) sin bloqueos entre sí; y los GOLPES 3/4 SÓLO con daño confirmado.
##
## Las acciones que el juego lee como "mantenidas" (saltar, fly_down, mover_*)
## se SOSTIENEN de verdad; las de "just_pressed" se pulsan un fotograma.

var _r: Node = null
var _snd: Node = null
var _fc: Node = null
var _cuerpo: CharacterBody3D = null
var _enemigo: Node = null

var _a0: AudioStreamPlayer = null
var _a1: AudioStreamPlayer = null
var _despegue: AudioStreamPlayer = null
var _aire: AudioStreamPlayer = null
var _g3: AudioStreamPlayer = null
var _g4: AudioStreamPlayer = null

var _t := 0.0
var _paso := 0
var _ok := 0
var _mal := 0
var _fallos: Array[String] = []
var _soltar: Array[StringName] = []
var _mantenidas: Array[StringName] = []
var _a0_suena := false
var _a1_suena := false
var _flaps := 0
var _flaps_marca := 0
var _flaps_win := 0
var _flaps_hover := -1
var _flaps_asc := -1
var _despegues := 0
var _aires := 0
var _veces3 := 0
var _veces4 := 0
var _v3_antes := 0
var _v4_antes := 0
var _flag3 := false
var _flag4 := false
var _independencia := "no evaluada"
var _quieto_ini := -1.0
var _t_estado := 0.0

func _ready() -> void:
	_r = get_node_or_null("Jugador")
	_snd = _r.get_node_or_null("Vuelo/SonidosVuelo") if _r != null else null
	_fc = _r.get_node_or_null("Vuelo/FlightController") if _r != null else null
	_cuerpo = _r.get_node_or_null("Vuelo") as CharacterBody3D if _r != null else null
	_enemigo = get_node_or_null("Enemigo")
	if _snd != null:
		_a0 = _snd.get_node_or_null("Aleteo_A")
		_a1 = _snd.get_node_or_null("Aleteo_B")
		_despegue = _snd.get_node_or_null("Despegue")
		_aire = _snd.get_node_or_null("AireRetomar")
		_g3 = _snd.get_node_or_null("Golpe3")
		_g4 = _snd.get_node_or_null("Golpe4")
	print("[VUELO-AUDIO] snd=", _snd, " aleteo=", _a0 != null, " ", _a1 != null, " despegue=", _despegue != null, " aire=", _aire != null, " g3=", _g3 != null, " g4=", _g4 != null)

func _physics_process(delta: float) -> void:
	# Las pulsaciones de un fotograma se sueltan ya; las mantenidas siguen.
	for n in _soltar:
		Input.action_release(n)
	_soltar.clear()
	_t += delta
	_muestrear()
	_pasos()
	if _t - _t_estado >= 0.5 and _t_muerte_de_prueba():
		_t_estado = _t
		print("[VUELO-AUDIO t=%.1f] volando=%s picado=%s y=%.2f vy=%.2f flaps=%d aire=%d g3=%d g4=%d" % [
			_t, str(_fc.get("is_flying")), str(_fc.get("is_diving")),
			_cuerpo.global_position.y if _cuerpo != null else 0.0,
			_cuerpo.velocity.y if _cuerpo != null else 0.0,
			_flaps, _aires, _veces3, _veces4,
		])

func _t_muerte_de_prueba() -> bool:
	return _t > 1.4

func _pasos() -> void:
	match _paso:
		0:
			if _t >= 0.2:
				_paso = 1
				_r.call("_on_transformacion_elegida", &"aguila")
		1:
			if _t >= 1.5:
				_paso = 2
				_informe("tras transformar")
				_pulsar(&"toggle_flight")
		2:
			if _t >= 1.85:
				_paso = 3
				_comprobar(_despegues == 1, "despegue 2.2: suena UNA vez al despegar del suelo")
				_flaps_win = _flaps  # ventana de hover (2.4 s)
		3:
			if _t >= 4.25:
				_paso = 4
				_flaps_hover = _flaps - _flaps_win
				_comprobar(_flaps_hover >= 1, "aleteo en HOVER: %d aleteos en 2.4 s (ciclo 1.5 s)" % _flaps_hover)
				_mantener(&"saltar")
				_flaps_win = _flaps  # ventana de ascenso (2.4 s)
		4:
			if _t >= 6.65:
				_paso = 5
				_flaps_asc = _flaps - _flaps_win
				_comprobar(_flaps_asc >= 3, "aleteo en ASCENSO: %d aleteos en 2.4 s (más rápido)" % _flaps_asc)
				_soltar_accion(&"saltar")
				_mantener(&"fly_down")
		5:
			if _t >= 7.05:
				_paso = 6
				_flaps_marca = _flaps
				_comprobar(bool(_fc.get("is_diving")), "el picado se comprometió de verdad (is_diving)")
		6:
			if _t >= 7.75:
				_paso = 7
				_comprobar(_flaps == _flaps_marca, "en PICADO/planeo (aleteo congelado) NO suenan aleteos")
				_soltar_accion(&"fly_down")
				_mantener(&"saltar")  # recuperar altura
		7:
			if _t >= 9.45:
				_paso = 8
				_soltar_accion(&"saltar")
				_informe("tras recuperar altura")
				_comprobar(_cuerpo.global_position.y > 2.0, "quedó en el aire a %.2f m para la prueba de reposo" % _cuerpo.global_position.y)
		8:
			if _t >= 10.45:
				_paso = 9
				_quieto_ini = _t  # desde acá: quieto en el aire
		9:
			if _quieto_ini > 0.0 and _t >= _quieto_ini + 2.0:
				_paso = 10
				_comprobar(_aires == 0, "aire 2.1: NO suena mientras el ave está quieta")
				_mantener(&"mover_adelante")
		10:
			if _t >= _quieto_ini + 2.7:
				_paso = 11
				_comprobar(_aires == 1, "aire 2.1: suena UNA vez en la retomada real tras ~2 s de reposo")
		11:
			# Independencia: con un aleteo sonando, el golpe NO lo corta.
			if _independencia == "no evaluada" and (_a0.playing or _a1.playing):
				_snd.call("golpe", 0)
				var flap := _a0.playing or _a1.playing
				_independencia = ("OK" if (flap and _g3.playing) else "FALLO")
				if _independencia == "OK":
					_ok += 1
				else:
					_mal += 1
					_fallos.append("aleteo y golpe a la vez")
				print("[VUELO-AUDIO] independencia (aleteo + golpe sonando juntos): ", _independencia)
			if _t >= _quieto_ini + 3.6:
				_paso = 12
				_soltar_accion(&"mover_adelante")
				_pulsar(&"toggle_flight")  # aterrizar
		12:
			if _t >= 14.4:
				_paso = 13
				_comprobar(not bool(_fc.get("is_flying")), "aterrizó (el vuelo se desactivó solo al tocar suelo)")
				_colocar_enemigo()
				_v3_antes = _veces3
				_v4_antes = _veces4
				_pulsar(&"melee_light")
		13:
			if _t >= 15.6:
				_paso = 14
				_comprobar(_veces3 > _v3_antes, "golpe 1 de la cadena → sonido 3")
				_v3_antes = _veces3
				_v4_antes = _veces4
				_pulsar(&"melee_light")
		14:
			if _t >= 16.8:
				_paso = 15
				_comprobar(_veces4 > _v4_antes, "golpe 2 de la cadena → sonido 4")
				if _enemigo is Node3D:
					(_enemigo as Node3D).global_position += Vector3(0.0, 0.0, -30.0)
				_v3_antes = _veces3
				_v4_antes = _veces4
				_pulsar(&"melee_light")
		15:
			if _t >= 18.0:
				_paso = 16
				_comprobar(_veces3 == _v3_antes and _veces4 == _v4_antes, "golpe al aire (sin objetivo): NO suena ningún golpe")
				_resultado()
		16:
			if _t >= 18.6:
				_paso = 17
				_soltar_todo()
				print("[VUELO-AUDIO] altura final=%.2f; DIRECCIONES: %s" % [_cuerpo.global_position.y if _cuerpo != null else 0.0, _independencia])
				print("[VUELO-AUDIO] FIN")

func _muestrear() -> void:
	if _a0 == null or _a1 == null:
		return
	# Cada VOZ cuenta su propio arranque: dos aleteos seguidos nunca se confunden.
	var suena0 := _a0.playing
	if suena0 and not _a0_suena:
		_flaps += 1
	_a0_suena = suena0
	var suena1 := _a1.playing
	if suena1 and not _a1_suena:
		_flaps += 1
	_a1_suena = suena1
	if _despegue != null and _despegue.playing and _despegues == 0:
		_despegues = 1
		print("[VUELO-AUDIO] ▶ despegue 2.2 a t=%.2f" % _t)
	if _aire != null and _aire.playing and _aires == 0:
		_aires = 1
		print("[VUELO-AUDIO] ▶ aire 2.1 a t=%.2f (retomada real)" % _t)
	if _g3 != null and _g3.playing:
		if not _flag3:
			_flag3 = true
			_veces3 += 1
			print("[VUELO-AUDIO] ▶ golpe sonido 3 a t=%.2f" % _t)
	else:
		_flag3 = false
	if _g4 != null and _g4.playing:
		if not _flag4:
			_flag4 = true
			_veces4 += 1
			print("[VUELO-AUDIO] ▶ golpe sonido 4 a t=%.2f" % _t)
	else:
		_flag4 = false

func _pulsar(nombre: StringName) -> void:
	Input.action_press(nombre)
	_soltar.append(nombre)

func _mantener(nombre: StringName) -> void:
	Input.action_press(nombre)
	if not _mantenidas.has(nombre):
		_mantenidas.append(nombre)

func _soltar_accion(nombre: StringName) -> void:
	Input.action_release(nombre)
	_mantenidas.erase(nombre)

func _soltar_todo() -> void:
	for n in _mantenidas:
		Input.action_release(n)
	_mantenidas.clear()

func _colocar_enemigo() -> void:
	if _cuerpo == null or not (_enemigo is Node3D):
		return
	var cam := get_viewport().get_camera_3d()
	var frente := Vector3.FORWARD
	if cam != null:
		frente = -cam.global_transform.basis.z
		frente.y = 0.0
		frente = frente.normalized()
	(_enemigo as Node3D).global_position = _cuerpo.global_position + frente * 2.2
	print("[VUELO-AUDIO] enemigo colocado a %.2f m del cuerpo" % (_enemigo as Node3D).global_position.distance_to(_cuerpo.global_position))

func _informe(etiqueta: String) -> void:
	if _cuerpo == null:
		print("[VUELO-AUDIO] %s → SIN cuerpo de vuelo" % etiqueta)
		return
	print("[VUELO-AUDIO] %s → forma=%s volando=%s en_suelo=%s y=%.2f" % [
		etiqueta, str(_r.get("forma")), str(_fc.get("is_flying")), str(_cuerpo.is_on_floor()),
		_cuerpo.global_position.y,
	])

func _comprobar(cond: bool, texto: String) -> void:
	if cond:
		_ok += 1
		print("[VUELO-AUDIO] OK  ", texto)
	else:
		_mal += 1
		_fallos.append(texto)
		print("[VUELO-AUDIO] FALLO  ", texto)

func _resultado() -> void:
	print("[VUELO-AUDIO] aleteos=%d (hover=%d ascenso=%d) despegues=%d aires=%d g3=%d g4=%d" % [
		_flaps, _flaps_hover, _flaps_asc, _despegues, _aires, _veces3, _veces4,
	])
	print("[VUELO-AUDIO] RESULTADO: ", _ok, " OK / ", _mal, " fallos")
	for f in _fallos:
		print("[VUELO-AUDIO] fallo: ", f)