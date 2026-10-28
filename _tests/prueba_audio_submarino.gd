extends Node3D
## PRUEBAS del AUDIO SUMERGIDO (Tarea 10): con la cámara real bajo el agua el
## sonido del juego se amortigua (filtro paso-bajo en los buses del proyecto) y al
## salir vuelve EXACTAMENTE a como estaba. El estado es el MISMO `inmersion()` de
## la vista subacuática (cámara real, ya suavizado): imagen y sonido entran juntos.
##
##  1. fuera del agua no hay amortiguación (filtro apagado, corte máximo);
##  2. los buses del proyecto siguen teniendo sus volúmenes (ajustes de audio);
##  3. bajo el agua el filtro se enciende y el corte baja (sonido "bajo el agua");
##  4. al salir, el audio queda exactamente como estaba;
##  5. no se acumulan filtros: cada vista añade el suyo y lo retira al irse;
##  6. se puede desactivar (no toca nada) sin romper el resto.
##
##   godot --headless --path <proyecto> res://_tests/prueba_audio_submarino.tscn

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const CLASE_VISTA := preload("res://personaje/base/efectos/vista_submarina.gd")
const BUSES := ["Efectos", "Musica", "Dialogos"]

var _ok := 0
var _fallos := 0
var _jug: Node3D
var _vista: Node3D
var _cam: Camera3D
var _vol_buses: Dictionary = {}

func _ready() -> void:
	_piso()
	_jug = (load(JUGADOR) as PackedScene).instantiate() as Node3D
	_jug.position = Vector3(0, 0.1, 0)
	add_child(_jug)
	# La cámara de la PRUEBA manda: es la que ve la vista subacuática. Se apagan
	# las del jugador para que la "cámara real" sea una sola y controlable.
	for n in _jug.find_children("*", "Camera3D", true, false):
		(n as Camera3D).current = false
	_cam = Camera3D.new()
	_cam.name = "CamaraPrueba"
	_cam.position = Vector3(0.0, 3.0, 8.0)
	_cam.look_at_from_position(Vector3(0.0, 3.0, 8.0), Vector3(0.0, 1.0, 0.0))
	add_child(_cam)
	_cam.current = true
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
	await get_tree().create_timer(1.0).timeout

	_vista = _jug.get_node_or_null("VistaSubmarina")
	_check(_vista != null, "el jugador tiene su vista subacuática (mismo detector de agua)")
	if _vista == null:
		_fin()
		return
	_check(get_viewport().get_camera_3d() == _cam, "la prueba controla la cámara real")
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		_check(idx >= 0, "el bus '%s' del proyecto existe" % bus)
		if idx >= 0:
			_vol_buses[bus] = AudioServer.get_bus_volume_db(idx)

	# --- 1 y 2. Fuera del agua ---------------------------------------------
	await get_tree().create_timer(0.4).timeout
	_check(is_equal_approx(float(_vista.call("inmersion")), 0.0),
			"con la cámara fuera del agua la inmersión es 0 (%.2f)" % float(_vista.call("inmersion")))
	_check(_contar_filtros() == BUSES.size(),
			"cada bus de sonido tiene su filtro paso-bajo (%d)" % _contar_filtros())
	_check(_corte_min() >= 20000.0,
			"fuera del agua no se filtra nada (corte al máximo, %.0f Hz)" % _corte_min())

	# --- 3. Bajo el agua ----------------------------------------------------
	_cam.global_position = Vector3(0.0, Relieve.NIVEL_MAR - 6.0, 8.0)
	await get_tree().create_timer(1.2).timeout
	var inmersion := float(_vista.call("inmersion"))
	_check(inmersion > 0.9, "con la cámara bajo el agua la inmersión sube (%.2f)" % inmersion)
	_check(_corte_min() <= 1000.0, "bajo el agua el sonido se AMORTIGUA (corte %.0f Hz)" % _corte_min())
	var intactos := true
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0 and not is_equal_approx(AudioServer.get_bus_volume_db(idx), float(_vol_buses[bus])):
			intactos = false
	_check(intactos, "el filtro no toca los volúmenes de los ajustes de audio")

	# --- 4. De vuelta fuera ------------------------------------------------
	_cam.global_position = Vector3(0.0, Relieve.NIVEL_MAR + 6.0, 8.0)
	await get_tree().create_timer(1.2).timeout
	_check(is_equal_approx(float(_vista.call("inmersion")), 0.0),
			"al salir del agua la inmersión vuelve a 0 (%.2f)" % float(_vista.call("inmersion")))
	_check(_corte_min() >= 20000.0,
			"al salir el audio queda como estaba (corte %.0f Hz)" % _corte_min())

	# --- 5. Sin acumulación: cada vista añade y retira lo suyo --------------
	var base := _contar_filtros()
	var extra := Node3D.new()
	extra.set_script(CLASE_VISTA)
	extra.name = "VistaExtra"
	add_child(extra)
	await get_tree().create_timer(0.3).timeout
	_check(_contar_filtros() == base + BUSES.size(),
			"otra vista añade exactamente un filtro por bus (%d → %d)" % [base, _contar_filtros()])
	extra.queue_free()
	await get_tree().create_timer(0.4).timeout
	_check(_contar_filtros() == base,
			"al retirarse la vista deja los buses como estaban (%d)" % _contar_filtros())

	# --- 6. Desactivable ----------------------------------------------------
	var sorda := Node3D.new()
	sorda.set_script(CLASE_VISTA)
	sorda.name = "VistaSinAudio"
	sorda.set("audio_sumergido", false)
	add_child(sorda)
	await get_tree().create_timer(0.3).timeout
	_check(_contar_filtros() == base, "con el audio sumergido desactivado no toca ningún bus")
	sorda.queue_free()
	await get_tree().create_timer(0.2).timeout

	# Y con la vista apagada, la inmersión sigue funcionando (no se rompe nada).
	_cam.global_position = Vector3(0.0, Relieve.NIVEL_MAR - 6.0, 8.0)
	await get_tree().create_timer(0.8).timeout
	_check(float(_vista.call("inmersion")) > 0.9, "el resto del sistema subacuático sigue igual")
	_fin()


# ------------------------------------------------------------------ auxiliares
func _contar_filtros() -> int:
	var n := 0
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		for i in AudioServer.get_bus_effect_count(idx):
			if AudioServer.get_bus_effect(idx, i) is AudioEffectLowPassFilter:
				n += 1
	return n


func _corte_min() -> float:
	var minimo := 1e9
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		for i in AudioServer.get_bus_effect_count(idx):
			var e := AudioServer.get_bus_effect(idx, i)
			if e is AudioEffectLowPassFilter:
				minimo = minf(minimo, (e as AudioEffectLowPassFilter).cutoff_hz)
	return minimo


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[audio-agua] OK   ", texto)
	else:
		_fallos += 1
		print("[audio-agua] FALLO ", texto)


func _fin() -> void:
	print("==================== AUDIO SUMERGIDO: %d OK / %d FALLO ====================" % [_ok, _fallos])


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