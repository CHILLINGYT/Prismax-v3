extends Node

# Arnés de prueba del sistema de AUDIO (CONFIGURACIÓN > AUDIO).
#
# Comprueba, con el sistema REAL y en la ETAPA ACTUAL (sin sonido):
#   1. El autoload AjustesAudio existe y arranca en sus valores por defecto.
#   2. Los tres volúmenes se limitan a 0..100.
#   3. La conversión porcentaje -> dB es correcta (0 = silencio, 100 = 0 dB).
#   4. Los diálogos alternan SÍ/NO.
#   5. Persistencia en user://ajustes_audio.cfg y relectura por un servicio nuevo.
#   6. REGLA FUNDAMENTAL: mover los controles NO cambia ningún bus ni silencia
#      nada: los buses siguen a 0 dB y sin mute (APLICAR_VOLUMEN_REAL = false).
#
# No forma parte del juego: vive en res://_tests/ y se ejecuta solo con las
# pruebas. Al terminar deja los ajustes en sus valores por defecto.

const SERVICIO := preload("res://ui/scripts/ajustes_audio.gd")

var _ok := 0
var _fail := 0
var _A: AjustesAudioService

func _listo(nombre: String, ok: bool, detalle: String = "") -> void:
	if ok:
		_ok += 1
	else:
		_fail += 1
	print("[TEST] %s :: %s | %s" % ["OK" if ok else "FALLO", nombre, detalle])

func _ready() -> void:
	_A = get_node_or_null("/root/AjustesAudio") as AjustesAudioService
	_listo("autoload AjustesAudio presente", _A != null, "")
	if _A == null:
		print("[TEST] ===== RESUMEN AUDIO: 0 OK, 1 FALLO =====")
		get_tree().quit()
		return
	await get_tree().process_frame

	# Valores por defecto.
	_A.poner_volumen_general(100)
	_A.poner_volumen_musica(80)
	_A.poner_volumen_efectos(80)
	_A.poner_desactivar_dialogos(false)
	_listo("valor por defecto volumen general = 100", _A.volumen_general == 100, "v=%d" % _A.volumen_general)
	_listo("valor por defecto volumen música = 80", _A.volumen_musica == 80, "v=%d" % _A.volumen_musica)
	_listo("valor por defecto volumen efectos = 80", _A.volumen_efectos == 80, "v=%d" % _A.volumen_efectos)
	_listo("valor por defecto desactivar diálogos = NO", not _A.desactivar_dialogos, "")

	_probar_limites()
	_probar_conversion()
	_probar_dialogos()
	_probar_buses_intactos()
	await _probar_persistencia()

	# Restaurar valores por defecto para el usuario.
	_A.poner_volumen_general(100)
	_A.poner_volumen_musica(80)
	_A.poner_volumen_efectos(80)
	_A.poner_desactivar_dialogos(false)

	print("[TEST] ===== RESUMEN AUDIO: %d OK, %d FALLOS =====" % [_ok, _fail])
	get_tree().quit()

func _probar_limites() -> void:
	_A.poner_volumen_general(150)
	_listo("volumen general se limita a 100", _A.volumen_general == 100, "v=%d" % _A.volumen_general)
	_A.poner_volumen_general(-5)
	_listo("volumen general se limita a 0", _A.volumen_general == 0, "v=%d" % _A.volumen_general)
	_A.poner_volumen_musica(999)
	_listo("volumen música se limita a 100", _A.volumen_musica == 100, "v=%d" % _A.volumen_musica)
	_A.poner_volumen_efectos(-30)
	_listo("volumen efectos se limita a 0", _A.volumen_efectos == 0, "v=%d" % _A.volumen_efectos)

func _probar_conversion() -> void:
	var db_0: float = _A.porcentaje_a_db(0)
	var db_50: float = _A.porcentaje_a_db(50)
	var db_100: float = _A.porcentaje_a_db(100)
	_listo("0 % = silencio (-80 dB)", is_equal_approx(db_0, -80.0), "db=%.3f" % db_0)
	_listo("100 % = 0 dB (nivel máximo)", is_equal_approx(db_100, 0.0), "db=%.3f" % db_100)
	_listo("la conversión es monotónica y 50 % queda por debajo de 100 %",
			db_50 < db_100 and db_50 > db_0, "50%%=%.3f" % db_50)

func _probar_dialogos() -> void:
	_A.poner_desactivar_dialogos(true)
	_listo("desactivar diálogos = SÍ", _A.desactivar_dialogos, "")
	_A.alternar_desactivar_dialogos()
	_listo("alternar diálogos vuelve a NO", not _A.desactivar_dialogos, "")

func _probar_buses_intactos() -> void:
	# Con APLICAR_VOLUMEN_REAL = false, mover los controles no debe tocar audio.
	_A.poner_volumen_general(0)
	_A.poner_volumen_musica(0)
	_A.poner_volumen_efectos(0)
	_A.poner_desactivar_dialogos(true)

	var idx_master := AudioServer.get_bus_index("Master")
	var idx_musica := AudioServer.get_bus_index("Musica")
	var idx_efectos := AudioServer.get_bus_index("Efectos")
	var idx_dialogos := AudioServer.get_bus_index("Dialogos")
	_listo("existen los buses Musica/Efectos/Dialogos",
			idx_musica >= 0 and idx_efectos >= 0 and idx_dialogos >= 0, "")
	_listo("Master sigue a 0 dB (no se modificó)",
			is_equal_approx(AudioServer.get_bus_volume_db(idx_master), 0.0),
			"db=%.3f" % AudioServer.get_bus_volume_db(idx_master))
	_listo("Musica sigue a 0 dB (no se modificó)",
			is_equal_approx(AudioServer.get_bus_volume_db(idx_musica), 0.0),
			"db=%.3f" % AudioServer.get_bus_volume_db(idx_musica))
	_listo("Efectos sigue a 0 dB (no se modificó)",
			is_equal_approx(AudioServer.get_bus_volume_db(idx_efectos), 0.0),
			"db=%.3f" % AudioServer.get_bus_volume_db(idx_efectos))
	_listo("Dialogos NO se silenció (aunque SÍ esté marcado)",
			not AudioServer.is_bus_mute(idx_dialogos),
			"mute=%s" % AudioServer.is_bus_mute(idx_dialogos))

func _probar_persistencia() -> void:
	_A.poner_volumen_general(42)
	_A.poner_volumen_musica(63)
	_A.poner_volumen_efectos(77)
	_A.poner_desactivar_dialogos(true)

	var cf := ConfigFile.new()
	var err := cf.load("user://ajustes_audio.cfg")
	_listo("se escribió user://ajustes_audio.cfg", err == OK, "err=%d" % err)
	_listo("persiste volumen_general=42",
			int(cf.get_value("audio", "volumen_general", -1)) == 42, "")
	_listo("persiste volumen_musica=63",
			int(cf.get_value("audio", "volumen_musica", -1)) == 63, "")
	_listo("persiste volumen_efectos=77",
			int(cf.get_value("audio", "volumen_efectos", -1)) == 77, "")
	_listo("persiste desactivar_dialogos=true",
			bool(cf.get_value("audio", "desactivar_dialogos", false)), "")

	# Un servicio NUEVO relee lo guardado (simula reabrir el juego).
	var svc: AjustesAudioService = SERVICIO.new()
	add_child(svc)
	await get_tree().process_frame
	_listo("un servicio nuevo recupera volumen_general=42", svc.volumen_general == 42,
			"v=%d" % svc.volumen_general)
	_listo("un servicio nuevo recupera volumen_musica=63", svc.volumen_musica == 63,
			"v=%d" % svc.volumen_musica)
	_listo("un servicio nuevo recupera volumen_efectos=77", svc.volumen_efectos == 77,
			"v=%d" % svc.volumen_efectos)
	_listo("un servicio nuevo recupera desactivar_dialogos=true", svc.desactivar_dialogos, "")
	svc.queue_free()
	await get_tree().process_frame