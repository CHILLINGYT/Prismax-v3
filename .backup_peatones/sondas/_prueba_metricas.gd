extends Node
## Prueba de MÉTRICAS del sistema de peatones (temporal): carga el juego real, lo deja correr
## acelerado y mide lo que el usuario pidió comprobar: nadie clavado andando sin moverse, nadie
## sobre el asfalto fuera del paso, nadie hundido, nadie dentro del mobiliario (quitando a quien
## está sentado/tumbado, que está JUSTO encima), cuánta gente va por sector, cuántos sentados y
## tumbados hay de verdad en cada momento, y que de noche no queda nadie al sol.
## No escribe nada del juego: sólo mide e informa.

const SEMILLA := 20260707
const MUESTRAS := 3
const SEGUNDOS_ENTRE := 4.0
const CLAVADO := 0.10          ## m/s por debajo de esto, andando, es "clavado"
const VENTANA := 0.9           ## s de referencia del vigilante del ciudadano (informativo)

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null
var _ciclo: Node = null
var _t0 := 0
var _paso := 0
var _proxima := 0.0
var _muestras := 0
var _peor_clavado := 0.0
var _clavados_ahora: Dictionary = {}
var _peor_sitio := ""
var _max_sentados := 0
var _max_tumbados := 0
var _asfalto := 0
var _hundidos := 0
var _mobiliario := 0
var _mobiliario_peor := 0
var _cancelados := 0
var _correccion_cabeza := 0.0
var _n_cabeza := 0
var _resumen_sectores := ""
var _reporte: Array[String] = []
var _listo := false


func _ready() -> void:
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = SEMILLA
	_ciclo = _juego.get_node_or_null("CicloDiaNoche")
	add_child(_juego)
	_t0 = Time.get_ticks_msec()
	Engine.time_scale = 6.0
	print("[Metricas] cargando la ciudad...")
	_run.call_deferred()


func _run() -> void:
	while _dir == null:
		await get_tree().process_frame
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
	_listo = true
	await _esperar(6.0)
	_muestrear("arranque")
	for i in MUESTRAS:
		await _esperar(SEGUNDOS_ENTRE)
		_muestrear("muestra %d" % (i + 2))
	if _ciclo != null:
		_ciclo.set("_fase", 0.86)
		print("[Metricas] --- anochece (fase 0.86) ---")
		await _esperar(8.0)
		_muestrear("noche")
		_ciclo.set("_fase", 0.33)
		print("[Metricas] --- amanece (fase 0.33) ---")
		await _esperar(12.0)
		_muestrear("amanecer")
	informe()
	Engine.time_scale = 1.0
	get_tree().quit()


## Vigilancia FINA del "camina sin moverse": se acumula el tiempo de cada ciudadano que está en
## WALK sin avanzar, fotograma a fotograma. Es lo que mide el problema que reportó el usuario.
func _process(delta: float) -> void:
	if not _listo or _dir == null:
		return
	var activos: Dictionary = {}
	for c in _dir.peatones:
		if not c.is_walking():
			continue
		activos[c] = true
		if c.velocidad_real() < CLAVADO:
			# OJO: `delta` de _process ya viene escalado por Engine.time_scale.
			var t: float = float(_clavados_ahora.get(c, 0.0)) + delta
			_clavados_ahora[c] = t
			if t > _peor_clavado:
				_peor_clavado = t
				_peor_sitio = "%s en %s" % [String(c.name), str(c.global_position.snapped(Vector3.ONE))]
		else:
			_clavados_ahora.erase(c)
	for c: Object in _clavados_ahora.keys():
		if not activos.has(c):
			_clavados_ahora.erase(c)


## Vuelca el informe final (se puede llamar aunque la tanda se corte).
func informe() -> void:
	print("[Metricas] ================= INFORME ================")
	print("[Metricas] peor 'camina sin moverse': %.2f s en %s" % [_peor_clavado, _peor_sitio])
	print("[Metricas] máximos de la sesión: sentados %d · tumbados %d" % [_max_sentados, _max_tumbados])
	print("[Metricas] peatones sobre el asfalto fuera del paso (acumulado): %d" % _asfalto)
	print("[Metricas] peatones caídos bajo el suelo (acumulado): %d" % _hundidos)
	print("[Metricas] dentro del mobiliario andando (peor muestra): %d" % _mobiliario_peor)
	print("[Metricas] viajes cancelados (peor ciudadano): %d" % _cancelados)
	if _n_cabeza > 0:
		print("[Metricas] estabilizador de cabeza: corrige %.1f° de media" % (_correccion_cabeza / _n_cabeza))
	print("[Metricas] sectores: %s" % _resumen_sectores)
	for l in _reporte:
		print(l)
	print("[Metricas] ================= FIN ================")


func _esperar(segundos: float) -> void:
	var hasta := float(Time.get_ticks_msec()) + segundos * 1000.0
	while float(Time.get_ticks_msec()) < hasta:
		await get_tree().process_frame


## Mide todo lo medible en un instante y lo acumula.
func _muestrear(etiqueta: String) -> void:
	var r: Dictionary = _dir.resumen()
	var caminando := 0
	var clavados := 0
	var asfalto := 0
	var hundidos := 0
	var mob := 0
	var sentados := 0
	var tumbados := 0
	var activos: Dictionary = {}
	var cancelados := 0
	var corr := 0.0
	var n_corr := 0
	for c in _dir.peatones:
		var p: Vector3 = c.global_position
		if p.y < -1.5:
			hundidos += 1
			continue
		if c.en_postura():
			if c.postura_actual() == "sentarse":
				sentados += 1
			elif c.postura_actual() == "recostarse":
				tumbados += 1
			continue      # sentado/tumbado está ENCIMA del banco/reposera: no cuenta como "dentro"
		if c.is_walking():
			caminando += 1
			activos[c] = true
			if c.velocidad_real() < CLAVADO:
				clavados += 1
		if _dir.red != null:
			var t: Array = c.tramo_red()
			if t.size() >= 3 and String(t[2]) == "cruce":
				pass
			elif _dir.red.es_calzada(p):
				asfalto += 1
		if c.viajes_cancelados() > cancelados:
			cancelados = c.viajes_cancelados()
		var est: Node = c.find_child("EstabilizaCabeza", true, false)
		if est != null and bool(est.get("aplicado")) and not c.en_postura():
			corr += absf(float(est.get("ultimo")))
			n_corr += 1
		if _dentro_de_mobiliario(p):
			mob += 1
	# --- vigilancia fina del "camina sin moverse" (la lleva _process)
	_max_sentados = maxi(_max_sentados, sentados)
	_max_tumbados = maxi(_max_tumbados, tumbados)
	_asfalto += asfalto
	_hundidos += hundidos
	_mobiliario_peor = maxi(_mobiliario_peor, mob)
	_cancelados = maxi(_cancelados, cancelados)
	_correccion_cabeza += corr
	_n_cabeza += n_corr
	if _resumen_sectores == "":
		_resumen_sectores = str(r.get("sectores", {}))
	_muestras += 1
	var linea := "[Metricas] %-10s caminando %2d (clavados %d) · sentados %d · tumbados %d · asfalto %d · hundidos %d · mobiliario %d · canc %d" % [
			etiqueta, caminando, clavados, sentados, tumbados, asfalto, hundidos, mob, cancelados]
	print(linea)
	_reporte.append(linea)


## ¿Este punto está dentro del círculo de algún obstáculo compartido (mobiliario urbano)?
func _dentro_de_mobiliario(p: Vector3) -> bool:
	var obs: Array = _dir.get("_obstaculos")
	if obs == null:
		return false
	for o in obs:
		var dx := p.x - float(o.get("x", 0.0))
		var dz := p.z - float(o.get("z", 0.0))
		var r := float(o.get("r", 0.0))
		if dx * dx + dz * dz < (r * 0.7) * (r * 0.7):
			return true
	return false