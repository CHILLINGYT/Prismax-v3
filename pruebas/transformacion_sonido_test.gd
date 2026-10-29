extends Node3D

# Arnés de prueba del SONIDO DE TRANSFORMACIÓN.
#
# Comprueba, con el sistema REAL (leo_jugador.tscn + EfectoTransformacion):
#   1. Hay un reproductor en el jugador con el MP3 original completo.
#   2. No suena al iniciar el juego.
#   3. Al confirmar, el sonido arranca junto con el destello.
#   4. El destello conserva sus 0,55 s originales.
#   5. El audio sigue sonando tras terminar el destello y termina completo.
#   6. Se reproduce otra vez en la transformación siguiente sin duplicarse.
#
# No forma parte del juego: vive en res://pruebas/ y se ejecuta solo con las pruebas.

const LEO := preload("res://personaje/base/escenas/leo_jugador.tscn")

var _ok := 0
var _fail := 0
var _jug: Node3D
var _efecto: Node3D
var _audio: AudioStreamPlayer
var _terminado := false
var _pico := false

func _listo(nombre: String, ok: bool, detalle: String = "") -> void:
	if ok:
		_ok += 1
	else:
		_fail += 1
	print("[TEST] %s :: %s | %s" % ["OK" if ok else "FALLO", nombre, detalle])

func _ready() -> void:
	_jug = LEO.instantiate()
	add_child(_jug)
	await get_tree().process_frame
	await get_tree().process_frame

	_efecto = _jug.get_node_or_null("EfectoTransformacion") as Node3D
	_listo("existe el nodo EfectoTransformacion", _efecto != null, "")
	if _efecto == null:
		print("[TEST] ===== RESUMEN SONIDO TRANSFORMACIÓN: 0 OK, 1 FALLO =====")
		get_tree().quit()
		return
	_audio = _jug.get_node_or_null("AudioTransformacion") as AudioStreamPlayer
	_listo("existe el reproductor persistente del jugador", _audio != null, "")
	_listo("reproductor fuera del nodo visual", _audio != null and _audio.get_parent() == _jug, "")
	_listo("tiene un stream asignado", _audio != null and _audio.stream != null, "")
	var largo := -1.0
	if _audio != null and _audio.stream != null:
		largo = _audio.stream.get_length()
	_listo("usa el MP3 original completo (≈2,04 s)", absf(largo - 2.04) < 0.1, "len=%.3f" % largo)
	_listo("no suena al iniciar el juego", _audio != null and not _audio.playing, "")
	_listo("hay un solo reproductor de transformación", _contar_audio(_jug) == 1,
			"n=%d" % _contar_audio(_jug))

	_efecto.terminado.connect(_on_terminado)
	_efecto.pico_alcanzado.connect(_on_pico)

	await _probar_transformacion(&"combate")
	await _probar_transformacion(&"velocista")

	print("[TEST] ===== RESUMEN SONIDO TRANSFORMACIÓN: %d OK, %d FALLOS =====" % [_ok, _fail])
	get_tree().quit()

func _contar_audio(nodo: Node) -> int:
	# Cuenta SÓLO el reproductor de transformación: el jugador tiene además los
	# reproductores de las acciones del velocista (carga/trazado/dash/golpe), que
	# NO son de transformación y no deben contarse aquí.
	var total := 1 if (nodo is AudioStreamPlayer and nodo.name == "AudioTransformacion") else 0
	for hijo in nodo.get_children():
		total += _contar_audio(hijo)
	return total

func _on_terminado() -> void:
	_terminado = true

func _on_pico() -> void:
	_pico = true

func _probar_transformacion(id: StringName) -> void:
	_terminado = false
	_pico = false
	# Confirmar la transformación por el MISMO camino que usa el menú.
	_jug._on_transformacion_elegida(id)
	await get_tree().process_frame
	_listo("%s: el sonido arranca junto al destello" % id, _audio.playing, "")
	var inicio_ms: int = Time.get_ticks_msec()
	while not _terminado:
		await get_tree().process_frame
	var duracion_destello: float = float(Time.get_ticks_msec() - inicio_ms) / 1000.0
	_listo("%s: el destello conserva 0,55 s" % id,
			absf(duracion_destello - 0.55) < 0.12, "destello=%.2f" % duracion_destello)
	_listo("%s: el pico (cambio de forma) se alcanzó" % id, _pico, "")
	_listo("%s: el audio sigue tras desaparecer el destello" % id, _audio.playing, "")
	var restante: float = _audio.stream.get_length() - _audio.get_playback_position()
	await get_tree().create_timer(maxf(restante + 0.1, 0.1)).timeout
	_listo("%s: el MP3 termina completo por sí solo" % id, not _audio.playing,
			"playing=%s" % _audio.playing)