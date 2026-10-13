extends Node3D
## Prueba EN VIVO de los SONIDOS DE MUERTE sobre el jugador REAL (forma humana):
##  1+2 al arrancar la animación y la caída (a la vez, el 2 más bajo, una vez);
##  4 al arrodillarse y 3 al golpear el suelo siguiendo la altura REAL de la
##  cadera del esqueleto; sin repetirse en `morido`. Imprime la línea de tiempo.

var _r: Node = null
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
var _t_muerte := -1.0
var _t_morido := -1.0
var _t_muestra := 0.0

func _ready() -> void:
	_r = get_node_or_null("Jugador")
	for n in _nombres:
		var p := _r.get_node_or_null(n) as AudioStreamPlayer
		_p.append(p)
		_sonaba[n] = false
		_veces[n] = 0
		_t_arranque[n] = -1.0
		_altura_arranque[n] = -1.0
		if p == null:
			_fallos.append("Falta el reproductor " + n)
	print("[MUERTE-AUDIO] reproductores 1=", _p[0] != null, " 2=", _p[1] != null, " 3=", _p[2] != null, " 4=", _p[3] != null)
	if _p[0] != null and _p[1] != null and _p[2] != null and _p[3] != null:
		print("[MUERTE-AUDIO] volúmenes: 1=%.1f dB  2=%.1f dB  3=%.1f dB  4=%.1f dB" % [_p[0].volume_db, _p[1].volume_db, _p[2].volume_db, _p[3].volume_db])
		_comprobar(_p[0].volume_db <= -5.0 and _p[0].volume_db >= -8.5, "el sonido 1 quedó dentro del rango pedido (%.1f dB)" % _p[0].volume_db)
		_comprobar(_p[1].volume_db < _p[0].volume_db, "el 2 es capa de fondo: volumen propio más bajo que el 1")
		_comprobar(is_equal_approx(_p[2].volume_db, 0.0) and is_equal_approx(_p[3].volume_db, 0.0), "los volúmenes de 3 y 4 NO se tocaron (%.1f y %.1f dB)" % [_p[2].volume_db, _p[3].volume_db])

func _physics_process(delta: float) -> void:
	_t += delta
	_muestrear()
	match _paso:
		0:
			if _t >= 0.3:
				_paso = 1
				print("[MUERTE-AUDIO] forma=%s estado=%d" % [str(_r.get("forma")), int(_r.get("_muerte_estado"))])
				_r.get_node("Estadisticas").call("recibir_danio", 9999.0)
				_t_muerte = _t
		1:
			if _t >= _t_muerte + 0.35:
				_paso = 2
				_comprobar(bool(_sonaba["AudioMuerte1"]) and bool(_sonaba["AudioMuerte2"]), "1 y 2 suenan JUNTOS al arrancar la animación y la caída")
				_comprobar(int(_veces["AudioMuerte1"]) == 1 and int(_veces["AudioMuerte2"]) == 1, "1 y 2 arrancan UNA sola vez")
				_comprobar(bool(_r.get("_snd_muerte_inicio")), "el aviso de inicio queda marcado (no se repite)")
		2:
			if int(_r.get("_muerte_estado")) == 2:
				_paso = 3
				_t_morido = _t
				print("[MUERTE-AUDIO] pasa a `morido` a los %.2f s de morir" % (_t - _t_muerte))
			elif _t >= _t_muerte + 16.0:
				_paso = 3
				_t_morido = _t
				_fallos.append("no llegó a `morido` en 16 s")
		3:
			if _t >= _t_morido + 2.0:
				_paso = 4
				_final()
		4:
			if _t >= _t_morido + 2.3:
				_paso = 5
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
				print("[MUERTE-AUDIO] ▶ %s a t=%.2f (altura cadera %.3f)" % [n, _t - _t_muerte, _altura()])
		_sonaba[n] = suena
	if _t_muerte >= 0.0 and _t - _t_muestra >= 0.3:
		_t_muestra = _t
		print("[MUERTE-AUDIO t=%5.2f] estado=%d altura=%6.3f  sonando=%s  veces=%s" % [
			_t - _t_muerte, int(_r.get("_muerte_estado")), _altura(),
			str([_sonaba["AudioMuerte1"], _sonaba["AudioMuerte2"], _sonaba["AudioMuerte3"], _sonaba["AudioMuerte4"]]),
			str([_veces["AudioMuerte1"], _veces["AudioMuerte2"], _veces["AudioMuerte3"], _veces["AudioMuerte4"]]),
		])

func _altura() -> float:
	return float(_r.call("_altura_cadera_muerte"))

func _final() -> void:
	_comprobar(int(_veces["AudioMuerte4"]) == 1, "el 4 (arrodillarse) suena UNA vez")
	_comprobar(int(_veces["AudioMuerte3"]) == 1, "el 3 (golpe contra el suelo) suena UNA vez")
	if int(_veces["AudioMuerte4"]) == 1 and int(_veces["AudioMuerte3"]) == 1:
		_comprobar(float(_t_arranque["AudioMuerte4"]) <= float(_t_arranque["AudioMuerte3"]) + 0.01, "orden real: primero el rodillazo (4) y después el suelo (3)")
	_comprobar(float(_altura_arranque["AudioMuerte4"]) <= 0.62, "el 4 sale con la pierna ya encogida (medida cadera−pies: %.3f m)" % float(_altura_arranque["AudioMuerte4"]))
	_comprobar(float(_altura_arranque["AudioMuerte3"]) <= 0.40, "el 3 sale con la pierna casi extendida en el piso (%.3f m)" % float(_altura_arranque["AudioMuerte3"]))
	_comprobar(int(_veces["AudioMuerte1"]) == 1 and int(_veces["AudioMuerte2"]) == 1, "en `morido` NO se repiten el 1 ni el 2")
	_comprobar(not _sonaba["AudioMuerte1"] and not _sonaba["AudioMuerte2"], "1 y 2 ya terminaron antes del fundido de `morido`")
	_comprobar(int(_r.get("_muerte_estado")) == 2, "estado final: MORIDO")

func _comprobar(cond: bool, texto: String) -> void:
	if cond:
		_ok += 1
		print("[MUERTE-AUDIO] OK  ", texto)
	else:
		_mal += 1
		_fallos.append(texto)
		print("[MUERTE-AUDIO] FALLO  ", texto)

func _resultado() -> void:
	print("[MUERTE-AUDIO] veces: ", str([_veces["AudioMuerte1"], _veces["AudioMuerte2"], _veces["AudioMuerte3"], _veces["AudioMuerte4"]]))
	print("[MUERTE-AUDIO] arranques (s desde la muerte): ", str([_t_arranque["AudioMuerte1"], _t_arranque["AudioMuerte2"], _t_arranque["AudioMuerte3"], _t_arranque["AudioMuerte4"]]))
	print("[MUERTE-AUDIO] altura de cadera en el arranque: ", str([_altura_arranque["AudioMuerte1"], _altura_arranque["AudioMuerte2"], _altura_arranque["AudioMuerte3"], _altura_arranque["AudioMuerte4"]]))
	print("[MUERTE-AUDIO] RESULTADO: ", _ok, " OK / ", _mal, " fallos")
	for f in _fallos:
		print("[MUERTE-AUDIO] fallo: ", f)