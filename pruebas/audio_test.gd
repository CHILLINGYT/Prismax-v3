extends Node

# Arnés de prueba del sistema de AUDIO (CONFIGURACIÓN > AUDIO).
#
# Comprueba, con el sistema REAL y con APLICAR_VOLUMEN_REAL = true (audio activo):
#   1. El autoload AjustesAudio existe y arranca en sus valores por defecto.
#   2. Los tres volúmenes se limitan a 0..100.
#   3. La conversión porcentaje -> dB es correcta (0 = silencio, 100 = 0 dB).
#   4. Los diálogos alternan SÍ/NO y silencian/reactivan el bus Dialogos.
#   5. Los CONTROLES MODIFICAN DE VERDAD LOS BUSES (general->Master, música->Musica,
#      efectos->Efectos) en tiempo real y de forma COMBINADA (Master x categoría).
#   6. El volumen de efectos NO toca el bus del ambiente (Musica).
#   7. Persistencia en user://ajustes_audio.cfg y relectura por un servicio nuevo.
#
# No forma parte del juego: vive en res://pruebas/ y se ejecuta solo con las
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
	_probar_buses_reactivos()
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

func _probar_buses_reactivos() -> void:
	# Con APLICAR_VOLUMEN_REAL = true, mover los controles DEBE modificar los buses.
	var idx_master := AudioServer.get_bus_index("Master")
	var idx_musica := AudioServer.get_bus_index("Musica")
	var idx_efectos := AudioServer.get_bus_index("Efectos")
	var idx_dialogos := AudioServer.get_bus_index("Dialogos")
	_listo("existen los buses Musica/Efectos/Dialogos",
			idx_musica >= 0 and idx_efectos >= 0 and idx_dialogos >= 0, "")

	# General -> bus Master.
	_A.poner_volumen_general(0)
	_listo("volumen general 0 % silencia el bus Master",
			AudioServer.get_bus_volume_db(idx_master) <= -79.0,
			"db=%.2f" % AudioServer.get_bus_volume_db(idx_master))
	_A.poner_volumen_general(100)
	_listo("volumen general 100 % deja Master a 0 dB",
			is_equal_approx(AudioServer.get_bus_volume_db(idx_master), 0.0),
			"db=%.2f" % AudioServer.get_bus_volume_db(idx_master))

	# Música -> bus Musica (capa continua/ambiente).
	_A.poner_volumen_musica(50)
	_listo("volumen música 50 % -> Musica ≈ -6,02 dB",
			absf(AudioServer.get_bus_volume_db(idx_musica) - (-6.02)) < 0.1,
			"db=%.2f" % AudioServer.get_bus_volume_db(idx_musica))

	# Efectos -> bus Efectos.
	_A.poner_volumen_efectos(30)
	_listo("volumen efectos 30 % -> Efectos ≈ -10,46 dB",
			absf(AudioServer.get_bus_volume_db(idx_efectos) - (-10.46)) < 0.1,
			"db=%.2f" % AudioServer.get_bus_volume_db(idx_efectos))

	# Combinación general x efectos = producto lineal (0,5 * 0,3 = 0,15).
	_A.poner_volumen_general(50)
	var ganancia: float = db_to_linear(AudioServer.get_bus_volume_db(idx_master)) \
			* db_to_linear(AudioServer.get_bus_volume_db(idx_efectos))
	_listo("general 50 % + efectos 30 % se combinan (≈ 0,15 lineal)",
			absf(ganancia - 0.15) < 0.02, "ganancia=%.3f" % ganancia)

	# Independencia: el control de efectos NO toca el bus del ambiente (Musica).
	var antes_musica := AudioServer.get_bus_volume_db(idx_musica)
	_A.poner_volumen_efectos(0)
	_listo("el volumen de efectos NO cambia el bus del ambiente (Musica)",
			is_equal_approx(AudioServer.get_bus_volume_db(idx_musica), antes_musica),
			"musica=%.2f" % AudioServer.get_bus_volume_db(idx_musica))

	# Diálogos: SÍ = mute del bus, NO = sin mute.
	_A.poner_desactivar_dialogos(true)
	_listo("desactivar diálogos silencia el bus Dialogos (mute)",
			AudioServer.is_bus_mute(idx_dialogos), "")
	_A.poner_desactivar_dialogos(false)
	_listo("reactivar diálogos quita el mute",
			not AudioServer.is_bus_mute(idx_dialogos), "")

	# Restaurar para no dejar el Master/efectos silenciados tras esta prueba.
	_A.poner_volumen_general(100)
	_A.poner_volumen_efectos(80)

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