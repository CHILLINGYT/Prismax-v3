extends Node

# Arnés de prueba de los SONIDOS DE INTERFAZ (autoload SonidoUI).
#
# Comprueba, con el sistema REAL:
#   1. Los tres WAV de res://Audio/UI/ se cargan y son AudioStreamWAV.
#   2. Nada suena solo al iniciar (no autoplay).
#   3. Menú principal: hover en otra opción -> cursor; confirmar -> click.
#   4. Menú de pausa: navegar (teclado/mando) -> cursor; hover -> cursor;
#      confirmar -> click.
#   5. Selectores con flechas -> siyno (gráficos FPS, jugabilidad, diálogos).
#   6. Sliders (distancia, sensibilidad, volumen) -> NO reproducen ningún sonido.
#
# El truco de detección: SonidoUI reproduce cambiando el `stream` de su único
# reproductor. Tras fijar un centinela, si el stream sigue igual es que NO sonó.
#
# No forma parte del juego: vive en res://pruebas/ y se ejecuta solo con las
# pruebas. Restaura al final los ajustes que toca (distancia, sensibilidad...).

const MAIN_MENU := preload("res://ui/scenes/MainMenu.tscn")
const PAUSE_MENU := preload("res://ui/scenes/PauseMenu.tscn")

var _ok := 0
var _fail := 0
var _S: SonidoUIService
var _rep: AudioStreamPlayer

func _listo(nombre: String, ok: bool, detalle: String = "") -> void:
	if ok:
		_ok += 1
	else:
		_fail += 1
	print("[TEST] %s :: %s | %s" % ["OK" if ok else "FALLO", nombre, detalle])

func _ready() -> void:
	_S = get_node_or_null("/root/SonidoUI") as SonidoUIService
	_listo("autoload SonidoUI presente", _S != null, "")
	if _S == null:
		print("[TEST] ===== RESUMEN SONIDO UI: 0 OK, 1 FALLO =====")
		get_tree().quit()
		return
	await get_tree().process_frame
	_rep = _S.get_node_or_null("ReproductorUI") as AudioStreamPlayer
	_listo("reproductor único de interfaz presente", _rep != null, "")
	_listo("click.wav cargado como AudioStream",
			_S._click is AudioStream, "tipo=%s" % [_S._click])
	_listo("cursor.wav cargado como AudioStream",
			_S._cursor is AudioStream, "tipo=%s" % [_S._cursor])
	_listo("siyno.wav cargado como AudioStream",
			_S._siyno is AudioStream, "tipo=%s" % [_S._siyno])
	_listo("no hay autoplay al iniciar", not _rep.playing, "playing=%s" % _rep.playing)

	await _probar_menu_principal()
	await _probar_menu_pausa()

	print("[TEST] ===== RESUMEN SONIDO UI: %d OK, %d FALLOS =====" % [_ok, _fail])
	get_tree().quit()

func _probar_menu_principal() -> void:
	# Instantánea de ajustes que la prueba de sliders pueda tocar.
	var dist0: int = AjustesGraficos.distancia
	var sens0: int = AjustesJugabilidad.sensibilidad

	var menu := MAIN_MENU.instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	# Hover en una opción DISTINTA a la seleccionada -> cursor.
	_rep.stream = _S._click   # centinela
	menu._on_row_hovered(1)
	_listo("menú principal: hover en otra opción -> cursor", _rep.stream == _S._cursor, "")

	# Re-hover de la MISMA opción ya seleccionada -> no debe sonar (centinela intacto).
	_rep.stream = _S._click   # centinela
	menu._on_row_hovered(1)
	_listo("menú principal: re-hover de la misma opción no suena",
			_rep.stream == _S._click, "")

	# Confirmar (fila 0 = CONTINUAR: no cambia de escena) -> click.
	_rep.stream = _S._cursor  # centinela
	menu._activate(0)
	_listo("menú principal: confirmar opción -> click", _rep.stream == _S._click, "")

	menu.queue_free()
	await get_tree().process_frame
	AjustesGraficos.poner_distancia(dist0)
	AjustesJugabilidad.poner_sensibilidad(sens0)

func _probar_menu_pausa() -> void:
	var dist0: int = AjustesGraficos.distancia
	var sens0: int = AjustesJugabilidad.sensibilidad
	var fps0: bool = AjustesGraficos.mostrar_fps
	var inv0: bool = AjustesJugabilidad.invertir_eje_vertical
	var dia0: bool = AjustesAudio.desactivar_dialogos
	var vol0: int = AjustesAudio.volumen_general

	var pausa := PAUSE_MENU.instantiate()
	add_child(pausa)
	await get_tree().process_frame
	await get_tree().process_frame
	pausa.abrir()
	await get_tree().process_frame

	# Navegación con teclado/mando (menu_up/menu_down -> _move) -> cursor.
	_rep.stream = _S._click
	pausa._move(1)
	_listo("pausa: navegar con teclado -> cursor", _rep.stream == _S._cursor, "")

	# Hover en otra opción -> cursor.
	_rep.stream = _S._click
	pausa._on_row_hovered(pausa._items, 2)
	_listo("pausa: hover en otra opción -> cursor", _rep.stream == _S._cursor, "")

	# Selectores con flechas -> siyno (se pulsan dos veces para dejar el valor igual).
	_rep.stream = _S._click
	pausa._on_fps_paso()
	_listo("pausa: selector MOSTRAR FPS -> siyno", _rep.stream == _S._siyno, "")
	pausa._on_fps_paso()

	_rep.stream = _S._click
	pausa._on_invertir_paso()
	_listo("pausa: selector INVERTIR EJE -> siyno", _rep.stream == _S._siyno, "")
	pausa._on_invertir_paso()

	_rep.stream = _S._click
	pausa._on_dialogos_paso()
	_listo("pausa: selector DESACTIVAR DIÁLOGOS -> siyno", _rep.stream == _S._siyno, "")
	pausa._on_dialogos_paso()

	# SLIDERS: mover sus valores NO debe reproducir ninguno de los tres sonidos.
	_rep.stream = _S._click   # centinela
	pausa._dist_barra.poner_valor(clampi(pausa._dist_barra.valor + 1, 0, 10))
	pausa._sens_barra.poner_valor(clampi(pausa._sens_barra.valor + 1, 0, 10))
	pausa._vol_general_barra.poner_valor(clampi(pausa._vol_general_barra.valor - 1, 0, 100))
	_listo("sliders (distancia, sensibilidad, volumen) NO reproducen sonido",
			_rep.stream == _S._click, "stream=%s" % _rep.stream)

	# Confirmar opción -> click (fila 0 = CONTINUAR: cierra la pausa).
	_rep.stream = _S._cursor
	pausa._activate(0)
	_listo("pausa: confirmar opción -> click", _rep.stream == _S._click, "")

	pausa.queue_free()
	await get_tree().process_frame

	# Restaurar ajustes tocados por la prueba.
	AjustesGraficos.poner_distancia(dist0)
	AjustesJugabilidad.poner_sensibilidad(sens0)
	AjustesGraficos.poner_mostrar_fps(fps0)
	AjustesJugabilidad.poner_invertir_eje_vertical(inv0)
	AjustesAudio.poner_desactivar_dialogos(dia0)
	AjustesAudio.poner_volumen_general(vol0)