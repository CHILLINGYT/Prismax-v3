extends Node
## HERRAMIENTA TEMPORAL (dot-folder): hornea los bancos de pasos en clips individuales.
##
## Por qué captura de bus y no lectura del archivo: los WAV del proyecto están en
## formato QOA (comprimido) y los pasos de Fuerza/Golpe son MP3. Ninguno de los dos
## expone PCM al script (`AudioStreamWAV.save_to_wav()` devuelve ERR_UNAVAILABLE con
## QOA). La captura por bus SÍ funciona con cualquier formato soportado por el motor.
##
## Cómo: se crea un bus "ZivaCaptura" con un AudioEffectCapture, se enruta ahí el
## reproductor y se BAJA EL MASTER a -80 dB, así el usuario no escucha nada mientras
## se hornea. El archivo original NUNCA se toca.

## Frecuencia de muestreo de la captura. NO se asume: la captura de bus entrega
## fotogramas al ritmo REAL del motor, así que este valor se lee en _ready
## (AudioServer.get_mix_rate()). Usar otro valor desplaza tiempos y afina mal los
## recortes al reproducirlos.
var RATE := 48000.0
const WIN := 0.005          # ventana de envolvente (s)
const PRE := 0.010          # margen antes del ataque (s)
const COLA := 0.060         # margen después del último sonido audible (s)
const UMBRAL_REL := 0.06    # umbral relativo al pico del banco
const MIN_DUR := 0.030      # descarta fragmentos más cortos que esto (s)
const UNIR := 0.150         # une regiones separadas por menos que esto (transitorios del MISMO paso)
const PICO_OBJETIVO := 0.90 # normalización de pico de cada variante

const BANCOS := [
	{"forma": "base", "ruta": "res://Audio/personaje/base y combate/pasos.wav", "guardar": 8, "pico_min": 0.0},
	{"forma": "combate", "ruta": "res://Audio/personaje/transformacion/combate/pasos.wav", "guardar": 8, "pico_min": 0.0},
	{"forma": "fuerza", "ruta": "res://Audio/personaje/transformacion/fuerza/pasos.mp3", "guardar": 6, "pico_min": 0.30, "dur_max": 1.40},
	{"forma": "velocidad", "ruta": "res://Audio/personaje/transformacion/velocidad/pasos.wav", "guardar": 8, "pico_min": 0.0},
	{"forma": "golpe", "ruta": "res://Audio/personaje/transformacion/combate/golpe.mp3", "guardar": 0, "pico_min": 0.0},
]
const SALIDA := "res://Audio/personaje/pasos"

var _bus := -1
var _cap: AudioEffectCapture = null
var _player: AudioStreamPlayer = null
var _acum := PackedVector2Array()
var _idx := 0
var _t_fin := 0.0
var _estado := "preparando"
var _t0 := 0.0
var _vol_master := 0.0


func _ready() -> void:
	_vol_master = AudioServer.get_bus_volume_db(0)
	_bus = AudioServer.bus_count
	AudioServer.add_bus(_bus)
	AudioServer.set_bus_name(_bus, "ZivaCaptura")
	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 4.0
	AudioServer.add_bus_effect(_bus, _cap)
	_player = AudioStreamPlayer.new()
	_player.bus = "ZivaCaptura"
	_player.volume_db = 0.0
	add_child(_player)
	print("[horneado] bus de captura creado (%s) | Master silenciado mientras dura el horneado" % str(AudioServer.get_bus_name(_bus)))
	RATE = float(AudioServer.get_mix_rate())
	print("[horneado] mix rate del motor: %d Hz" % int(RATE))
	_siguiente()


func _siguiente() -> void:
	if _idx >= BANCOS.size():
		print("\n[horneado] FIN. Se restauró el volumen del Master.")
		AudioServer.set_bus_volume_db(0, _vol_master)
		get_tree().quit()
		return
	var b: Dictionary = BANCOS[_idx]
	var st: AudioStream = load(String(b["ruta"]))
	if st == null:
		print("\n!! no se pudo cargar %s" % b["ruta"])
		_idx += 1
		_siguiente()
		return
	_acum = PackedVector2Array()
	AudioServer.set_bus_volume_db(0, -80.0)
	_player.stream = st
	_player.play()
	_t_fin = float(st.get_length()) + 0.4
	_t0 = Time.get_ticks_msec() / 1000.0
	_estado = "capturando"
	print("\n===== %s: %s (%.3f s, %s) =====" % [
			String(b["forma"]).to_upper(), b["ruta"], st.get_length(), st.get_class()])


func _process(_d: float) -> void:
	if _estado == "drenando":
		# Vaciar TODO lo que quede del banco anterior: si no, su audio entra en la
		# captura del siguiente y desplaza los tiempos medidos.
		while _cap.get_frames_available() > 0:
			_cap.get_buffer(_cap.get_frames_available())
		if Time.get_ticks_msec() / 1000.0 >= _t_fin:
			_siguiente()
		return
	if _estado != "capturando":
		return
	var disp := _cap.get_frames_available()
	while disp > 0:
		var trozo := _cap.get_buffer(disp)
		_acum.append_array(trozo)
		disp = _cap.get_frames_available()
	if Time.get_ticks_msec() / 1000.0 - _t0 >= _t_fin:
		_player.stop()
		# vaciar lo que quede en el buffer
		var resto := _cap.get_frames_available()
		if resto > 0:
			_acum.append_array(_cap.get_buffer(resto))
		_estado = "analizando"
		_analizar()


func _analizar() -> void:
	var b: Dictionary = BANCOS[_idx]
	var n := _acum.size()
	print("[horneado] capturados %d fotogramas (%.3f s de audio)" % [n, float(n) / RATE])
	if n == 0:
		_avanzar()
		return
	# Envolvente por ventanas
	var win := maxi(1, int(RATE * WIN))
	var env := PackedFloat32Array()
	var i := 0
	while i < n:
		var p := 0.0
		var fin := mini(i + win, n)
		for k in range(i, fin):
			var v := _acum[k]
			p = maxf(p, maxf(absf(v.x), absf(v.y)))
		env.append(p)
		i += win
	var pico := 0.0
	for v in env:
		pico = maxf(pico, v)
	# Umbral: relativo al pico y por encima del ruido de fondo (percentil bajo)
	var ordenada := Array(env)
	ordenada.sort()
	var suelo := 0.0
	if ordenada.size() > 20:
		suelo = float(ordenada[int(ordenada.size() * 0.2)])
	var umbral := maxf(maxf(pico * UMBRAL_REL, suelo * 3.0), 0.002)
	print("[horneado] pico del banco %.3f | suelo (p20) %.4f | umbral %.4f" % [pico, suelo, umbral])
	# Regiones por encima del umbral
	var regs: Array = []
	var ini := -1
	for k in env.size():
		var alto := env[k] > umbral
		if alto and ini < 0:
			ini = k
		elif not alto and ini >= 0:
			regs.append([ini, k])
			ini = -1
	if ini >= 0:
		regs.append([ini, env.size()])
	# Unir regiones cercanas
	var unidas: Array = []
	for r: Array in regs:
		if not unidas.is_empty() and (int(r[0]) - int(unidas[-1][1])) * WIN < UNIR:
			unidas[-1][1] = r[1]
		else:
			unidas.append([r[0], r[1]])
	# Descartar fragmentos muy cortos
	var utiles: Array = []
	for r2: Array in unidas:
		if (int(r2[1]) - int(r2[0])) * WIN >= MIN_DUR:
			utiles.append(r2)
	print("[horneado] regiones sobre el umbral: %d | tras unir/cortar: %d" % [regs.size(), utiles.size()])
	# Límites en fotogramas de cada paso (con márgenes, sin invadir al vecino)
	var pasos: Array = []
	var pre := int(RATE * PRE)
	var cola := int(RATE * COLA)
	var finales: Array[int] = []
	for r3: Array in utiles:
		finales.append(int(r3[1]) * win)
	for k in utiles.size():
		var r4: Array = utiles[k]
		var f0: int = int(r4[0]) * win
		var f1: int = int(r4[1]) * win
		var ini2: int = maxi(f0 - pre, 0 if k == 0 else (finales[k - 1] + f0) / 2)
		var fin2: int = mini(f1 + cola, n if k == utiles.size() - 1 else (f1 + int(utiles[k + 1][0]) * win) / 2)
		pasos.append({"ini": ini2, "fin": fin2, "ataque": f0, "apaga": f1,
				"silencio_previo": (f0 - (0 if k == 0 else finales[k - 1])) / RATE,
				"cola": ((n if k == utiles.size() - 1 else int(utiles[k + 1][0]) * win) - f1) / RATE})
	print("[horneado] inventario de pasos detectados (ataque, apagado, duración, silencio previo, cola):")
	for k in pasos.size():
		var p: Dictionary = pasos[k]
		var pk := 0.0
		for j in range(int(p["ini"]), int(p["fin"])):
			var v2 := _acum[j]
			pk = maxf(pk, maxf(absf(v2.x), absf(v2.y)))
		p["pico"] = pk
		print("   paso %2d: ataque %6.3f s | apagado %6.3f s | dura %5.3f s | silencio previo %5.3f s | cola %5.3f s | pico %.3f" % [
				k + 1, float(p["ataque"]) / RATE, float(p["apaga"]) / RATE,
				(float(p["apaga"]) - float(p["ataque"])) / RATE,
				p["silencio_previo"], p["cola"], pk])
	# Cadencia: intervalo entre ataques consecutivos (mediana)
	var inter: Array = []
	for k in range(1, pasos.size()):
		inter.append((float(pasos[k]["ataque"]) - float(pasos[k - 1]["ataque"])) / RATE)
	if not inter.is_empty():
		inter.sort()
		var cad := float(inter[inter.size() / 2])
		print("[horneado] cadencia del banco (Mediana entre ataques): %.3f s (min %.3f, max %.3f)" % [
				cad, float(inter[0]), float(inter[-1])])
	# Solo son variantes los pasos con el pico suficiente (descarta ruido/silencios)
	var pico_min := float(b.get("pico_min", 0.0))
	var dur_max := float(b.get("dur_max", 99.0))
	var candidatos: Array = []
	for k in pasos.size():
		var dur := (float(pasos[k]["apaga"]) - float(pasos[k]["ataque"])) / RATE
		if float(pasos[k]["pico"]) >= pico_min and dur <= dur_max:
			candidatos.append(pasos[k])
	print("[horneado] candidatos a variante (pico >= %.2f y dura <= %.2f s): %d de %d" % [
			pico_min, dur_max, candidatos.size(), pasos.size()])
	# Guardar variantes repartidas por el banco
	var quiero := int(b["guardar"])
	if quiero > 0 and not candidatos.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/%s" % [SALIDA, b["forma"]]))
		# Limpieza: los recortes viejos se borran ANTES de guardar los nuevos. Si no,
		# al bajar la cantidad de variantes quedarían archivos sueltos de una corrida
		# anterior (y el sistema los cargaría como si fueran válidos).
		var dir_sal := DirAccess.open("%s/%s" % [SALIDA, b["forma"]])
		if dir_sal != null:
			for viejo in dir_sal.get_files():
				var sv := String(viejo)
				if sv.begins_with("paso_") and sv.ends_with(".tres"):
					dir_sal.remove(sv)
		var elegidos: Array = []
		var total := candidatos.size()
		for k in mini(quiero, total):
			elegidos.append(int(round(float(k) * float(total - 1) / maxf(1.0, float(mini(quiero, total) - 1)))))
		var vistos := {}
		for e in elegidos:
			if vistos.has(e):
				continue
			vistos[e] = true
		var guardados: Array[String] = []
		var contador := 0
		for e2 in vistos.keys():
			var p2: Dictionary = candidatos[e2]
			var st2 := _construir(int(p2["ini"]), int(p2["fin"]), float(p2["pico"]))
			if st2 == null:
				continue
			contador += 1
			var ruta := "%s/%s/paso_%02d.tres" % [SALIDA, b["forma"], contador]
			var err := ResourceSaver.save(st2, ruta)
			if err != OK:
				print("   !! no pude guardar %s (%s)" % [ruta, error_string(err)])
				continue
			var recargado: AudioStream = load(ruta)
			guardados.append(ruta)
			print("   guardado %s | dura %.3f s | pico recargado %.3f | formato %d | %s" % [
					ruta, recargado.get_length() if recargado != null else -1.0,
					_pico_de(recargado), recargado.format if recargado is AudioStreamWAV else -1,
					"OK" if recargado is AudioStreamWAV else "REVISAR"])
		print("[horneado] variantes guardadas para %s: %d" % [b["forma"], guardados.size()])
	_avanzar()


func _construir(ini: int, fin: int, pico: float) -> AudioStreamWAV:
	var frames := fin - ini
	if frames <= 8:
		return null
	var ganancia := 1.0
	if pico > 0.0001:
		ganancia = PICO_OBJETIVO / pico
		ganancia = clampf(ganancia, 0.05, 20.0)
	var datos := PackedByteArray()
	datos.resize(frames * 4)   # 2 canales * 2 bytes
	var o := 0
	for j in range(ini, fin):
		var v := _acum[j]
		datos.encode_s16(o, int(clampf(v.x * ganancia, -1.0, 1.0) * 32767.0))
		datos.encode_s16(o + 2, int(clampf(v.y * ganancia, -1.0, 1.0) * 32767.0))
		o += 4
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = int(RATE)
	st.stereo = true
	st.data = datos
	st.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return st


func _pico_de(st: AudioStream) -> float:
	if not (st is AudioStreamWAV):
		return -1.0
	var w := st as AudioStreamWAV
	var p := 0.0
	var n := w.data.size() / 4
	for i in n:
		p = maxf(p, absf(w.data.decode_s16(i * 4) / 32768.0))
	return p


func _avanzar() -> void:
	_idx += 1
	_estado = "drenando"
	_t_fin = Time.get_ticks_msec() / 1000.0 + 0.45