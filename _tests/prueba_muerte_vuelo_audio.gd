extends Node3D
## Prueba EN VIVO de la MUERTE DEL VUELO con sonidos: el ave muere EN EL AIRE,
## el cadáver cae con física real y el 3 suena al GOLPEAR el suelo; 1+2 al
## arrancar y 4 (si la pose llega a arrodillarse) una sola vez.

var _r: Node = null
var _fc: Node = null
var _cuerpo: CharacterBody3D = null
var _p: Array[AudioStreamPlayer] = []
var _nombres: Array[String] = ["AudioMuerte1", "AudioMuerte2", "AudioMuerte3", "AudioMuerte4"]
var _sonaba: Dictionary = {}
var _veces: Dictionary = {}
var _t_arranque: Dictionary = {}
var _altura_arranque: Dictionary = {}
var _t := 0.0
var _paso := 0
var _ok := 0
var _mal := 0
var _fallos: Array[String] = []
var _soltar: Array[StringName] = []
var _mantenidas: Array[StringName] = []
var _t_muerte := -1.0
var _t_morido := -1.0
var _y_muerte := 0.0
var _t_muestra := 0.0

func _ready() -> void:
	_r = get_node_or_null("Jugador")
	_fc = _r.get_node_or_null("Vuelo/FlightController")
	_cuerpo = _r.get_node_or_null("Vuelo") as CharacterBody3D
	for n in _nombres:
		var p := _r.get_node_or_null(n) as AudioStreamPlayer
		_p.append(p)
		_sonaba[n] = false
		_veces[n] = 0
		_t_arranque[n] = -1.0
		_altura_arranque[n] = -1.0
		if p == null:
			_fallos.append("Falta el reproductor " + n)
	print("[MUERTE-VUELO] cuerpo=", _cuerpo, " fc=", _fc)

func _physics_process(delta: float) -> void:
	for n in _soltar:
		Input.action_release(n)
	_soltar.clear()
	_t += delta
	_muestrear()
	match _paso:
		0:
			if _t >= 0.2:
				_paso = 1
				_r.call("_on_transformacion_elegida", &"aguila")
		1:
			if _t >= 1.5:
				_paso = 2
				Input.action_press("toggle_flight")
				_soltar.append(&"toggle_flight")
		2:
			if _t >= 1.8:
				_paso = 3
				_mantener(&"saltar")  # subir de verdad antes de morir
		3:
			if _t >= 3.9:
				_paso = 4
				_soltar_accion(&"saltar")
				_y_muerte = _cuerpo.global_position.y
				print("[MUERTE-VUELO] muere EN EL AIRE a y=%.2f (en_suelo=%s volando=%s)" % [_y_muerte, str(_cuerpo.is_on_floor()), str(_fc.get("is_flying"))])
				_comprobar(_y_muerte > 2.0, "murió en el aire de verdad (altura %.2f m)" % _y_muerte)
				_r.get_node("Estadisticas").call("recibir_danio", 9999.0)
				_t_muerte = _t
		4:
			if _t >= _t_muerte + 0.35:
				_paso = 5
				_comprobar(bool(_sonaba["AudioMuerte1"]) and bool(_sonaba["AudioMuerte2"]), "1 y 2 suenan JUNTOS al arrancar la muerte en el aire")
				_comprobar(int(_veces["AudioMuerte1"]) == 1 and int(_veces["AudioMuerte2"]) == 1, "1 y 2 arrancan UNA sola vez")
		5:
			if int(_r.get("_muerte_estado")) == 2:
				_paso = 6
				_t_morido = _t
				print("[MUERTE-VUELO] pasa a `morido` a los %.2f s de morir" % (_t - _t_muerte))
			elif _t >= _t_muerte + 18.0:
				_paso = 6
				_t_morido = _t
				_fallos.append("no llegó a `morido` en 18 s")
		6:
			if _t >= _t_morido + 2.0:
				_paso = 7
				_final()
		7:
			if _t >= _t_morido + 2.3:
				_paso = 8
				_resultado()

func _muestrear() -> void:
	for i in _nombres.size():
		var n: String = _nombres[i]
		var p: AudioStreamPlayer = _p[i]
		if p == null:
			continue
		var suena := p.playing
		if suena and not bool(_sonaba[n]):
			_veces[n] = int(_veces[n]) + 1
			if float(_t_arranque[n]) < 0.0:
				_t_arranque[n] = _t - _t_muerte
				_altura_arranque[n] = _altura()
				print("[MUERTE-VUELO] ▶ %s a t=%.2f (altura cadera %.3f, aterrizado=%s)" % [
					n, _t - _t_muerte, _altura(), str(_r.get("_muerte_vuelo_aterrizado")),
				])
		_sonaba[n] = suena
	if _t_muerte >= 0.0 and _t - _t_muestra >= 0.35:
		_t_muestra = _t
		print("[MUERTE-VUELO t=%5.2f] estado=%d altura=%6.3f y=%.2f aterrizado=%s vel_caida=%.1f  veces=%s" % [
			_t - _t_muerte, int(_r.get("_muerte_estado")), _altura(),
			_cuerpo.global_position.y if _cuerpo != null else 0.0,
			str(_r.get("_muerte_vuelo_aterrizado")), float(_r.get("_muerte_vuelo_vel")),
			str([_veces["AudioMuerte1"], _veces["AudioMuerte2"], _veces["AudioMuerte3"], _veces["AudioMuerte4"]]),
		])

func _altura() -> float:
	return float(_r.call("_altura_cadera_muerte"))

func _mantener(nombre: StringName) -> void:
	Input.action_press(nombre)
	if not _mantenidas.has(nombre):
		_mantenidas.append(nombre)

func _soltar_accion(nombre: StringName) -> void:
	Input.action_release(nombre)
	_mantenidas.erase(nombre)

func _final() -> void:
	var y_final := _cuerpo.global_position.y if _cuerpo != null else 0.0
	_comprobar(y_final < _y_muerte - 1.0, "el cadáver CAYÓ con física real: %.2f m → %.2f m" % [_y_muerte, y_final])
	_comprobar(int(_veces["AudioMuerte3"]) == 1, "el 3 (golpe contra el suelo) suena UNA vez")
	var por_aterrizaje := bool(_r.get("_muerte_vuelo_aterrizado")) and float(_r.get("_muerte_vuelo_vel")) >= 2.0
	var por_cadera := float(_altura_arranque["AudioMuerte3"]) <= 0.35
	if int(_veces["AudioMuerte3"]) == 1:
		_comprobar(por_aterrizaje or por_cadera, "el 3 sale en el instante real del golpe (aterrizaje=%s, altura cadera=%.3f)" % [str(por_aterrizaje), float(_altura_arranque["AudioMuerte3"])])
	_comprobar(int(_veces["AudioMuerte4"]) <= 1, "el 4 nunca se repite (%d vez/veces si la pose se arrodilla)" % int(_veces["AudioMuerte4"]))
	if int(_veces["AudioMuerte4"]) == 1:
		_comprobar(float(_altura_arranque["AudioMuerte4"]) <= 0.58, "el 4 sale con la cadera ya bajando (%.3f m)" % float(_altura_arranque["AudioMuerte4"]))
	_comprobar(int(_veces["AudioMuerte1"]) == 1 and int(_veces["AudioMuerte2"]) == 1, "en `morido` NO se repiten el 1 ni el 2")
	_comprobar(int(_r.get("_muerte_estado")) == 2, "estado final: MORIDO")

func _comprobar(cond: bool, texto: String) -> void:
	if cond:
		_ok += 1
		print("[MUERTE-VUELO] OK  ", texto)
	else:
		_mal += 1
		_fallos.append(texto)
		print("[MUERTE-VUELO] FALLO  ", texto)

func _resultado() -> void:
	print("[MUERTE-VUELO] veces: ", str([_veces["AudioMuerte1"], _veces["AudioMuerte2"], _veces["AudioMuerte3"], _veces["AudioMuerte4"]]))
	print("[MUERTE-VUELO] arranques (s desde la muerte): ", str([_t_arranque["AudioMuerte1"], _t_arranque["AudioMuerte2"], _t_arranque["AudioMuerte3"], _t_arranque["AudioMuerte4"]]))
	print("[MUERTE-VUELO] RESULTADO: ", _ok, " OK / ", _mal, " fallos")
	for f in _fallos:
		print("[MUERTE-VUELO] fallo: ", f)