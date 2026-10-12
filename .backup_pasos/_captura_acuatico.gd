extends Node
## VARIANTE del horneador de pisadas para el banco ACUÁTICO únicamente.
## No procesa los otros 5 bancos (el original los reescribe): así NO se tocan los
## recortes de base/combate/fuerza/velocidad. El audio original nunca se modifica.
## Basado en res://.backup_pasos/_captura_pasos.gd (misma lógica de captura por bus).
##
## GUARDAR = 0 -> SOLO ANALIZA (no escribe nada). >0 -> hornea N variantes.

var RATE := 48000.0
const WIN := 0.005
const PRE := 0.010
const COLA := 0.060
const UMBRAL_REL := 0.06
const MIN_DUR := 0.030
const UNIR := 0.150
const PICO_OBJETIVO := 0.90

const FORMA := "acuatico"
const RUTA := "res://Audio/personaje/pasos/acuatico/pasos.mp3"
const SALIDA := "res://Audio/personaje/pasos"
const GUARDAR := 8        ## 0 = SOLO ANALIZAR
const PICO_MIN := 0.25    ## descarta eventos débiles (ruido/colas) del banco
const DUR_MAX := 0.60     ## descarta fragmentos largos que no son un paso

var _bus := -1
var _cap: AudioEffectCapture = null
var _player: AudioStreamPlayer = null
var _acum := PackedVector2Array()
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
	add_child(_player)
	RATE = float(AudioServer.get_mix_rate())
	var st: AudioStream = load(RUTA)
	print("[acuatico] banco=%s clase=%s dura=%.3f s mix_rate=%d GUARDAR=%d" % [RUTA, st.get_class(), st.get_length(), int(RATE), GUARDAR])
	AudioServer.set_bus_volume_db(0, -80.0)
	_player.stream = st
	_player.play()
	_t_fin = float(st.get_length()) + 0.4
	_t0 = Time.get_ticks_msec() / 1000.0
	_estado = "capturando"


func _process(_d: float) -> void:
	if _estado == "drenando":
		while _cap.get_frames_available() > 0:
			_cap.get_buffer(_cap.get_frames_available())
		if Time.get_ticks_msec() / 1000.0 >= _t_fin:
			print("[acuatico] FIN. Master restaurado a %.1f dB." % _vol_master)
			AudioServer.set_bus_volume_db(0, _vol_master)
			get_tree().quit()
		return
	if _estado != "capturando":
		return
	var disp := _cap.get_frames_available()
	while disp > 0:
		_acum.append_array(_cap.get_buffer(disp))
		disp = _cap.get_frames_available()
	if Time.get_ticks_msec() / 1000.0 - _t0 >= _t_fin:
		_player.stop()
		var resto := _cap.get_frames_available()
		if resto > 0:
			_acum.append_array(_cap.get_buffer(resto))
		_analizar()
		_estado = "drenando"
		_t_fin = Time.get_ticks_msec() / 1000.0 + 0.2


func _analizar() -> void:
	var n := _acum.size()
	print("[acuatico] capturados %d fotogramas (%.3f s)" % [n, float(n) / RATE])
	if n == 0:
		return
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
	var ordenada := Array(env)
	ordenada.sort()
	var suelo := 0.0
	if ordenada.size() > 20:
		suelo = float(ordenada[int(ordenada.size() * 0.2)])
	var umbral := maxf(maxf(pico * UMBRAL_REL, suelo * 3.0), 0.002)
	print("[acuatico] pico=%.3f suelo(p20)=%.4f umbral=%.4f" % [pico, suelo, umbral])
	var regs: Array = []
	var ini := -1
	for k in env.size():
		var alto := env[k] > umbral
		if alto and ini < 0:
			ini = k
		elif not alto and ini >= 0:
			regs.append([ini, k]); ini = -1
	if ini >= 0:
		regs.append([ini, env.size()])
	var unidas: Array = []
	for r: Array in regs:
		if not unidas.is_empty() and (int(r[0]) - int(unidas[-1][1])) * WIN < UNIR:
			unidas[-1][1] = r[1]
		else:
			unidas.append([r[0], r[1]])
	var utiles: Array = []
	for r2: Array in unidas:
		if (int(r2[1]) - int(r2[0])) * WIN >= MIN_DUR:
			utiles.append(r2)
	print("[acuatico] regiones sobre umbral=%d | tras unir/cortar=%d" % [regs.size(), utiles.size()])
	var pre := int(RATE * PRE)
	var cola := int(RATE * COLA)
	var finales: Array[int] = []
	var pasos: Array = []
	for r3: Array in utiles:
		finales.append(int(r3[1]) * win)
	for k in utiles.size():
		var r4: Array = utiles[k]
		var f0: int = int(r4[0]) * win
		var f1: int = int(r4[1]) * win
		var ini2: int = maxi(f0 - pre, 0 if k == 0 else (finales[k - 1] + f0) / 2)
		var fin2: int = mini(f1 + cola, n if k == utiles.size() - 1 else (f1 + int(utiles[k + 1][0]) * win) / 2)
		var pk := 0.0
		for j in range(ini2, fin2):
			var v2 := _acum[j]
			pk = maxf(pk, maxf(absf(v2.x), absf(v2.y)))
		pasos.append({"ini": ini2, "fin": fin2, "ataque": f0, "apaga": f1,
				"silencio_previo": (f0 - (0 if k == 0 else finales[k - 1])) / RATE,
				"cola": ((n if k == utiles.size() - 1 else int(utiles[k + 1][0]) * win) - f1) / RATE, "pico": pk})
	print("[acuatico] INVENTARIO de pasos detectados:")
	for k in pasos.size():
		var p: Dictionary = pasos[k]
		print("   paso %2d: ataque %6.3f s | apagado %6.3f s | dura %5.3f s | silencio previo %5.3f s | cola %5.3f s | pico %.3f" % [
				k + 1, float(p["ataque"]) / RATE, float(p["apaga"]) / RATE,
				(float(p["apaga"]) - float(p["ataque"])) / RATE, p["silencio_previo"], p["cola"], p["pico"]])
	var inter: Array = []
	for k in range(1, pasos.size()):
		inter.append((float(pasos[k]["ataque"]) - float(pasos[k - 1]["ataque"])) / RATE)
	if not inter.is_empty():
		inter.sort()
		print("[acuatico] cadencia (mediana entre ataques) = %.3f s (min %.3f, max %.3f)" % [
				float(inter[inter.size() / 2]), float(inter[0]), float(inter[-1])])
	if GUARDAR <= 0:
		print("[acuatico] GUARDAR=0 -> solo análisis, no se escribió nada.")
		return
	var candidatos: Array = []
	for k in pasos.size():
		var dur := (float(pasos[k]["apaga"]) - float(pasos[k]["ataque"])) / RATE
		if float(pasos[k]["pico"]) >= PICO_MIN and dur <= DUR_MAX:
			candidatos.append(pasos[k])
	print("[acuatico] candidatos (pico>=%.2f, dura<=%.2f): %d de %d" % [PICO_MIN, DUR_MAX, candidatos.size(), pasos.size()])
	var quiero := mini(GUARDAR, candidatos.size())
	if quiero <= 0:
		print("[acuatico] sin candidatos: no se escribieron recortes.")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/%s" % [SALIDA, FORMA]))
	var dir_sal := DirAccess.open("%s/%s" % [SALIDA, FORMA])
	if dir_sal != null:
		for viejo in dir_sal.get_files():
			var sv := String(viejo)
			if sv.begins_with("paso_") and sv.ends_with(".tres"):
				dir_sal.remove(sv)
	var total := candidatos.size()
	var elegidos: Array = []
	for k in quiero:
		elegidos.append(int(round(float(k) * float(total - 1) / maxf(1.0, float(quiero) - 1))))
	var vistos := {}
	var contador := 0
	for e in elegidos:
		if vistos.has(e):
			continue
		vistos[e] = true
		var p2: Dictionary = candidatos[e]
		var st2 := _construir(int(p2["ini"]), int(p2["fin"]), float(p2["pico"]))
		if st2 == null:
			continue
		contador += 1
		var ruta := "%s/%s/paso_%02d.tres" % [SALIDA, FORMA, contador]
		var err := ResourceSaver.save(st2, ruta)
		if err != OK:
			print("   !! no pude guardar %s (%s)" % [ruta, error_string(err)]); continue
		var recargado: AudioStream = load(ruta)
		print("   guardado %s | dura %.3f s | pico recargado %.3f | %s" % [
				ruta, recargado.get_length() if recargado != null else -1.0,
				_pico_de(recargado), "OK" if recargado is AudioStreamWAV else "REVISAR"])
	print("[acuatico] variantes guardadas: %d" % contador)


func _construir(ini: int, fin: int, pico: float) -> AudioStreamWAV:
	var frames := fin - ini
	if frames <= 8:
		return null
	var ganancia := 1.0
	if pico > 0.0001:
		ganancia = clampf(PICO_OBJETIVO / pico, 0.05, 20.0)
	var datos := PackedByteArray()
	datos.resize(frames * 4)
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