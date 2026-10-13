extends Node3D
## Prueba EN VIVO de los SONIDOS DE VUELO (5 archivos) sobre el personaje REAL:
##  1) golpes 3/4 al EJECUTAR el gesto (suenan también al aire; el daño sólo si
##     conecta), UNA vez por golpe (sin duplicar al impactar) y NADA si el gesto
##     se corta antes del punto de extensión — en el piso;
##  2) despegue 2.2: una sola vez, al despegar del suelo;
##  3) aleteo (sin número) en cada aleteo REAL (hover y ascenso) y NADA con el
##     aleteo congelado (picado/planeo);
##  4) aire 2.1: sólo en la transición real reposo (~1 s) → movimiento;
##  5) sin bloqueos entre sonidos (un golpe no corta el aleteo).
## Las acciones "mantenidas" se sostienen de verdad; las de un fotograma se pulsan.

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
var _marca_aires := 0
var _marca_mov := 0
var _veces3 := 0
var _veces4 := 0
var _v3_antes := 0
var _v4_antes := 0
var _flag3 := false
var _flag4 := false
var _flag_aire := false
var _independencia := "no evaluada"
var _quieto_ini := -1.0
var _t_estado := 0.0
## Anclas de tiempo relativas (el encadenado de la prueba no es fijo).
var _t_base := 0.0
var _t_corte := 0.0
var _salto_visto := false
var _vida_enemigo := -1.0

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
	for n in _soltar:
		Input.action_release(n)
	_soltar.clear()
	_t += delta
	# Mientras se prueba el corte del gesto, se recuerda si el cuerpo llegó a
	# dejar el suelo (control de que el corte fue real, no un falso positivo).
	if _paso >= 45 and _paso <= 47 and _cuerpo != null and not _cuerpo.is_on_floor():
		_salto_visto = true
	_muestrear()
	_pasos()
	if _t > 1.3 and _t - _t_estado >= 0.6:
		_t_estado = _t
		print("[VUELO-AUDIO t=%.1f] volando=%s picado=%s y=%.2f vy=%.2f flaps=%d aire=%d g3=%d g4=%d" % [
			_t, str(_fc.get("is_flying")), str(_fc.get("is_diving")),
			_cuerpo.global_position.y if _cuerpo != null else 0.0,
			_cuerpo.velocity.y if _cuerpo != null else 0.0,
			_flaps, _aires, _veces3, _veces4,
		])

func _pasos() -> void:
	match _paso:
		0:
			if _t >= 0.2:
				_paso = 1
				_r.call("_on_transformacion_elegida", &"aguila")
		1:
			if _t >= 1.4:
				_paso = 2
				_informe("transformado")
				_colocar_enemigo()
				_v3_antes = _veces3
				_v4_antes = _veces4
				_pulsar(&"melee_light")
		2:
			if _t >= 1.9:
				_paso = 3
				_comprobar(_veces3 == _v3_antes + 1 and _veces4 == _v4_antes, "golpe 1 (con daño) → sonido 3 UNA vez (sin duplicar)")
				_v3_antes = _veces3
				_v4_antes = _veces4
				_pulsar(&"melee_light")
		3:
			if _t >= 2.6:
				_paso = 4
				_comprobar(_veces4 == _v4_antes + 1 and _veces3 == _v3_antes, "golpe 2 (con daño) → sonido 4 UNA vez (sin duplicar)")
				if _enemigo is Node3D:
					(_enemigo as Node3D).global_position += Vector3(0.0, 0.0, -30.0)
				if _enemigo != null and _enemigo.has_method("vida_actual"):
					_vida_enemigo = float(_enemigo.call("vida_actual"))
				_v3_antes = _veces3
				_v4_antes = _veces4
				_pulsar(&"melee_light")
		4:
			if _t >= 3.7:
				_paso = 45
				var vida_despues: float = float(_enemigo.call("vida_actual")) if (_enemigo != null and _enemigo.has_method("vida_actual")) else -1.0
				_comprobar(_veces3 == _v3_antes + 1 and _veces4 == _v4_antes, "golpe al aire (sin objetivo en alcance) → sonido 3 al EJECUTAR, UNA vez")
				_comprobar(_vida_enemigo >= 0.0 and is_equal_approx(vida_despues, _vida_enemigo), "el golpe al aire NO hace daño (vida del enemigo intacta)")
				# Gesto que se CORTA antes de la extensión: ni sonido ni daño.
				_v3_antes = _veces3
				_v4_antes = _veces4
				_pulsar(&"melee_light")
				_t_corte = _t
		45:
			if _t >= _t_corte + 0.02:
				_paso = 46
				# Al fotograma siguiente: dejar el suelo corta el gesto (_cortar), muy
				# antes de la extensión del puño (40 % del clip).
				_mantener(&"saltar")
		46:
			if _t >= _t_corte + 0.45:
				_paso = 47
				_soltar_accion(&"saltar")
		47:
			if _t >= _t_corte + 1.5:
				_paso = 5
				_comprobar(_salto_visto, "el corte fue real: el cuerpo dejó el suelo con el gesto en curso (control de la prueba)")
				_comprobar(_veces3 == _v3_antes and _veces4 == _v4_antes, "gesto cortado antes de la extensión (despegue) → NO suena ningún golpe")
				_t_base = _t
				_pulsar(&"toggle_flight")
		5:
			if _t >= _t_base + 1.05:
				_paso = 6
				_comprobar(_despegues == 1, "despegue 2.2: suena UNA vez al despegar del suelo")
				_flaps_win = _flaps  # ventana hover (2.4 s)
		6:
			if _t >= _t_base + 3.45:
				_paso = 7
				_flaps_hover = _flaps - _flaps_win
				_comprobar(_flaps_hover >= 1, "aleteo en HOVER: %d aleteos en 2.4 s (ciclo 1.5 s)" % _flaps_hover)
				_mantener(&"saltar")
				_flaps_win = _flaps  # ventana ascenso (2.4 s)
			else:
				_evaluar_independencia()
		7:
			if _t >= _t_base + 5.85:
				_paso = 8
				_flaps_asc = _flaps - _flaps_win
				_comprobar(_flaps_asc >= 3, "aleteo en ASCENSO: %d aleteos en 2.4 s (más rápido)" % _flaps_asc)
				_soltar_accion(&"saltar")
				_mantener(&"fly_down")
		8:
			if _t >= _t_base + 6.25:
				_paso = 9
				_flaps_marca = _flaps
				_comprobar(bool(_fc.get("is_diving")), "el picado se comprometió de verdad (is_diving)")
		9:
			if _t >= _t_base + 6.95:
				_paso = 10
				_comprobar(_flaps == _flaps_marca, "en PICADO/planeo (aleteo congelado) NO suenan aleteos")
				_soltar_accion(&"fly_down")
				_mantener(&"saltar")  # recuperar altura
		10:
			if _t >= _t_base + 8.65:
				_paso = 11
				_soltar_accion(&"saltar")
				_informe("tras recuperar altura")
				_comprobar(_cuerpo.global_position.y > 5.0, "quedó en el aire a %.2f m" % _cuerpo.global_position.y)
		11:
			if _t >= _t_base + 9.65:
				_paso = 12
				_quieto_ini = _t  # desde acá: QUIETO en el aire, sin tocar nada
				_marca_aires = _aires
		12:
			if _t >= _quieto_ini + 2.0:
				_paso = 13
				_comprobar(_aires == _marca_aires, "aire 2.1: NO suena mientras el ave está quieta")
				_marca_mov = _aires
				_mantener(&"mover_adelante")
		13:
			if _t >= _quieto_ini + 2.7:
				_paso = 14
				_comprobar(_aires == _marca_mov + 1, "aire 2.1: suena UNA vez en la retomada real tras el reposo")
		14:
			if _t >= _quieto_ini + 3.2:
				_paso = 15
				_soltar_accion(&"mover_adelante")
				_mantener(&"fly_down")  # bajar: aterrizaje real, sin cortar el vuelo a mano
		15:
			if not bool(_fc.get("is_flying")):
				_paso = 16
				_soltar_accion(&"fly_down")
				_comprobar(_cuerpo.is_on_floor(), "aterrizó de verdad (el vuelo se apagó solo al tocar suelo)")
				_informe("aterrizado")
			elif _t >= _quieto_ini + 7.0:
				_paso = 16
				_soltar_accion(&"fly_down")
				_comprobar(false, "no aterrizó por sí solo (timeout)")
		16:
			if _t >= _quieto_ini + 7.4:
				_paso = 17
				_resultado()
		17:
			if _t >= _quieto_ini + 7.9:
				_paso = 18
				_soltar_todo()
				print("[VUELO-AUDIO] FIN")

func _muestrear() -> void:
	if _a0 == null or _a1 == null:
		return
	# Cada VOZ cuenta su propio arranque (dos aleteos seguidos no se confunden).
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
	if _aire != null and _aire.playing:
		if not _flag_aire:
			_flag_aire = true
			_aires += 1
			print("[VUELO-AUDIO] ▶ aire 2.1 nº%d a t=%.2f (retomada real)" % [_aires, _t])
	else:
		_flag_aire = false
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

## Con un aleteo sonando, un golpe NO lo corta (reproductores independientes).
func _evaluar_independencia() -> void:
	if _independencia != "no evaluada" or _a0 == null or _a1 == null:
		return
	if not (_a0.playing or _a1.playing):
		return
	_snd.call("golpe", 0)
	var flap := _a0.playing or _a1.playing
	_independencia = ("OK" if (flap and _g3.playing) else "FALLO")
	if _independencia == "OK":
		_ok += 1
	else:
		_mal += 1
		_fallos.append("aleteo y golpe a la vez")
	print("[VUELO-AUDIO] independencia (aleteo + golpe sonando juntos): ", _independencia)

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