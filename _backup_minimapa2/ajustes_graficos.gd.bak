class_name AjustesGraficosService
extends Node

## Ajustes gráficos del juego (autoload, nombre global `AjustesGraficos`).
##
## Es el ÚNICO punto donde se aplican y se guardan los ajustes gráficos, de modo
## que el menú de configuración solo pide cambios y este nodo los ejecuta:
##   · Modo de pantalla (ventana / pantalla completa).
##   · Resolución de la ventana.
##   · Contador de FPS (overlay propio, creado una sola vez aquí).
##   · Distancia de visión (far de la cámara + niebla).
##
## Persistencia: un ConfigFile propio (user://ajustes_graficos.cfg) con solo la
## sección "graficos". No toca otros guardados del proyecto.
##
## No modifica la física, las transformaciones ni el generador de ciudad.

signal cambiado

const RUTA := "user://ajustes_graficos.cfg"
const SECCION := "graficos"

## Lista EXACTA de resoluciones disponibles, en el orden pedido.
const RESOLUCIONES: Array[Vector2i] = [
	Vector2i(640, 480),
	Vector2i(720, 480),
	Vector2i(720, 570),
	Vector2i(800, 600),
	Vector2i(1024, 768),
	Vector2i(1152, 864),
	Vector2i(1176, 664),
	Vector2i(1280, 720),
	Vector2i(1280, 768),
	Vector2i(1280, 800),
	Vector2i(1280, 960),
	Vector2i(1280, 1024),
	Vector2i(1360, 768),
	Vector2i(1366, 768),
	Vector2i(1440, 900),
	Vector2i(1440, 1080),
	Vector2i(1600, 900),
	Vector2i(1600, 1024),
	Vector2i(1680, 1050),
	Vector2i(1920, 1080),
]

## Distancia de visión: nivel 0..10 -> far de la cámara.
const DISTANCIA_MIN := 0
const DISTANCIA_MAX := 10
const FAR_MIN := 120.0
const FAR_MAX := 4000.0     # == far por defecto de Godot: nivel 10 no cambia nada
const NIEBLA_BASE := 0.00035

## Estado actual (lectura directa desde el menú).
var pantalla_completa: bool = false
var resolucion_idx: int = 7          # 1280 x 720 por defecto hasta leer el real
var mostrar_fps: bool = false
var distancia: int = DISTANCIA_MAX

var _fps_capa: CanvasLayer
var _fps_label: Label

func _ready() -> void:
	var tenia_guardado := _cargar()
	_crear_overlay_fps()
	_aplicar_fps()
	if tenia_guardado and not Engine.is_embedded_in_editor():
		# Restaurar solo en ventana independiente; el Game embebido restringe size/mode.
		await _aplicar_pantalla()
	else:
		# En el editor embebido reflejar lo real sin destruir la preferencia guardada.
		pantalla_completa = _modo_es_completa()
		_sincronizar_resolucion_real()
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_reaplicar_distancia")

# ---------------------------------------------------------------- pantalla
func _modo_es_completa() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

## Aplica el modo y, en modo ventana, el tamaño real de la ventana. Godot no
## cambia la resolución física del monitor al pasar a fullscreen.
func _aplicar_pantalla() -> void:
	if Engine.is_embedded_in_editor():
		# El editor embebido impide cambiar mode/size: mantener UI fiel al estado real.
		pantalla_completa = _modo_es_completa()
		_sincronizar_resolucion_real()
		return

	if pantalla_completa:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var screen: int = DisplayServer.window_get_current_screen()
		var area: Rect2i = DisplayServer.screen_get_usable_rect(screen)
		var solicitado: Vector2i = RESOLUCIONES[resolucion_idx]
		var aplicado := Vector2i(mini(solicitado.x, area.size.x), mini(solicitado.y, area.size.y))
		DisplayServer.window_set_size(aplicado)
		_centrar_ventana(aplicado, area)

	# Dar tiempo a DisplayServer/SO para aplicar y consultar luego el estado real.
	await get_tree().process_frame
	pantalla_completa = _modo_es_completa()
	if not pantalla_completa:
		_sincronizar_resolucion_real()

## Sincroniza al entrar en GRÁFICOS, incluso si el sistema operativo/usuario
## cambió la ventana por fuera del menú.
func sincronizar_estado_ventana() -> void:
	pantalla_completa = _modo_es_completa()
	if not pantalla_completa:
		_sincronizar_resolucion_real()

## En modo ventana refleja el tamaño real. En fullscreen conserva la resolución
## de ventana elegida para restaurarla al salir; no afirma cambiar el monitor.
func _sincronizar_resolucion_real() -> void:
	if _modo_es_completa():
		return
	var idx: int = _indice_resolucion_mas_cercana(DisplayServer.window_get_size())
	if idx != resolucion_idx:
		resolucion_idx = idx

func _centrar_ventana(tam: Vector2i, area: Rect2i) -> void:
	var centro := Vector2(area.position) + (Vector2(area.size) - Vector2(tam)) * 0.5
	var pos := Vector2i(int(centro.x), int(centro.y))
	pos.x = clampi(pos.x, area.position.x, area.position.x + maxi(0, area.size.x - tam.x))
	pos.y = clampi(pos.y, area.position.y, area.position.y + maxi(0, area.size.y - tam.y))
	DisplayServer.window_set_position(pos)

func _indice_resolucion_mas_cercana(tam: Vector2i) -> int:
	var mejor := 0
	var mejor_d := INF
	for i in RESOLUCIONES.size():
		var d := RESOLUCIONES[i].distance_squared_to(tam)
		if d < mejor_d:
			mejor_d = d
			mejor = i
	return mejor

func texto_resolucion() -> String:
	var real: Vector2i
	if _modo_es_completa():
		real = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	else:
		real = DisplayServer.window_get_size()
	return "%d x %d" % [real.x, real.y]

# ---------------------------------------------------------------- distancia
func _far_para_nivel(nivel: int) -> float:
	var t := float(nivel) / float(DISTANCIA_MAX)
	return lerpf(FAR_MIN, FAR_MAX, pow(t, 1.6))

func _reaplicar_distancia() -> void:
	_aplicar_distancia()

func _aplicar_distancia() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	cam.far = _far_para_nivel(distancia)
	var env := cam.get_world_3d().environment
	if env != null:
		# Sube la niebla al acercar el recorte para que el borde no sea un corte duro.
		env.fog_density = clampf(NIEBLA_BASE * (FAR_MAX / cam.far), NIEBLA_BASE, 0.03)

func _on_node_added(n: Node) -> void:
	# Al cargar una escena nueva aparecen cámara y entorno: reaplica la distancia.
	if n is Camera3D or n is WorldEnvironment:
		call_deferred("_reaplicar_distancia")

# ---------------------------------------------------------------- overlay FPS
func _crear_overlay_fps() -> void:
	_fps_capa = CanvasLayer.new()
	_fps_capa.name = "ContadorFPSGlobal"
	_fps_capa.layer = 20
	add_child(_fps_capa)
	_fps_label = Label.new()
	_fps_label.name = "ContadorFPS"
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fps_label.position = Vector2(12, 8)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_fps_label.add_theme_constant_override("shadow_offset_x", 1)
	_fps_label.add_theme_constant_override("shadow_offset_y", 1)
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_capa.add_child(_fps_label)

func _aplicar_fps() -> void:
	if _fps_label != null:
		_fps_label.visible = mostrar_fps

func _process(_delta: float) -> void:
	if _fps_label != null and _fps_label.visible:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

# ---------------------------------------------------------------- API (menú)
func poner_pantalla_completa(v: bool) -> void:
	if v == pantalla_completa:
		return
	pantalla_completa = v
	await _aplicar_pantalla()
	_guardar()
	cambiado.emit()

func alternar_pantalla() -> void:
	await poner_pantalla_completa(not pantalla_completa)

func poner_resolucion(idx: int) -> void:
	# En fullscreen convencional Godot usa el tamaño del monitor; no puede aplicar
	# las 20 resoluciones como modos físicos de pantalla. No simular un cambio.
	if _modo_es_completa():
		return
	idx = wrapi(idx, 0, RESOLUCIONES.size())
	if idx == resolucion_idx:
		return
	resolucion_idx = idx
	await _aplicar_pantalla()
	_guardar()
	cambiado.emit()

func poner_mostrar_fps(v: bool) -> void:
	if v == mostrar_fps:
		return
	mostrar_fps = v
	_aplicar_fps()
	_guardar()
	cambiado.emit()

func poner_distancia(nivel: int) -> void:
	nivel = clampi(nivel, DISTANCIA_MIN, DISTANCIA_MAX)
	if nivel == distancia:
		return
	distancia = nivel
	_aplicar_distancia()
	_guardar()
	cambiado.emit()

# ---------------------------------------------------------------- persistencia
func _guardar() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECCION, "pantalla_completa", pantalla_completa)
	cf.set_value(SECCION, "resolucion", RESOLUCIONES[resolucion_idx])
	cf.set_value(SECCION, "mostrar_fps", mostrar_fps)
	cf.set_value(SECCION, "distancia", distancia)
	cf.save(RUTA)

## Devuelve true si existía el archivo de preferencias.
func _cargar() -> bool:
	var cf := ConfigFile.new()
	if cf.load(RUTA) != OK:
		mostrar_fps = false
		distancia = DISTANCIA_MAX
		return false
	pantalla_completa = bool(cf.get_value(SECCION, "pantalla_completa", false))
	var res = cf.get_value(SECCION, "resolucion", DisplayServer.window_get_size())
	resolucion_idx = _indice_resolucion_mas_cercana(res if res is Vector2i else DisplayServer.window_get_size())
	mostrar_fps = bool(cf.get_value(SECCION, "mostrar_fps", false))
	distancia = clampi(int(cf.get_value(SECCION, "distancia", DISTANCIA_MAX)), DISTANCIA_MIN, DISTANCIA_MAX)
	return true