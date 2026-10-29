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

# =============================================================== CALIDAD GRÁFICA
##
## PERFIL DE CALIDAD (Baja / Media / Alta), pensado para que el juego sea fluido
## en equipos modestos. Los números NO son decorativos: salen de medir el mundo
## real en este equipo (Intel ADL-N, Forward+) con:
##    _tests/diagnostico_cuello.gd   (¿quién se come el fotograma?)
##    _tests/medir_rendimiento.gd    (comparativa por perfil)
##
## Lo medido, que es lo que decide los valores:
##   · El fotograma NO está limitado por píxeles: bajar la escala 3D a 0.50 subió
##     de 17.9 a 21.7 FPS (+21 %) con 4x menos píxeles. Con la escala a 0.75 el
##     coste de relleno deja de ser el problema; por eso BAJA no baja de 0.70.
##   · Apagar las sombras del sol subió de 17.8 a 25.4 FPS (+43 %) y redujo los
##     primitivos enviados de 1.97 M a 0.96 M. El coste va con la GEOMETRÍA
##     enviada (escena + pasada de sombras): de ahí que la distancia y la calidad
##     de sombra sean la palanca principal del perfil BAJA.
##   · La ciudad aporta ~1.96 k de los 2.02 k draw calls; el bosque son tarjetas
##     cruzadas en 17 trozos CON sombra y el terreno planta 15 034 matas. Las
##     sombras de vegetación son ruido visual y cuestan una pasada entera.
##
## Nada de esto cambia la física, la ciudad, los peatones, el combate ni el
## audio: sólo cómo se DIBUJA lo que ya existe.
enum Calidad { BAJA, MEDIA, ALTA }
const CALIDAD_NOMBRES: Array[String] = ["BAJA", "MEDIA", "ALTA"]
## Cielo ESTÁTICO que usa sólo el perfil BAJA (recurso aparte: el cielo
## dinámico del juego no se modifica). Se carga de forma perezosa.
const RUTA_CIELO_BAJA := "res://Cielo/cielo_panorama_baja.tres"

## Tabla por perfil. `ALTA` == configuración original del proyecto (escala 1.0,
## SSAO encendido, sombras del sol sin recortar, sin tocar la vegetación).
const PERFILES: Array[Dictionary] = [
	{	# --- BAJA ---
		"escala_3d": 0.70,
		"cielo_estatico": true,
		"lod_umbral": 8.0,
		"ssao": false,
		"ssil": false,
		"glow": false,
		"vol_fog": false,
		"sombra_distancia": 30.0,
		"sombra_atlas": 1024,
		"sombra_filtro": RenderingServer.SHADOW_QUALITY_HARD,
		"atlas_posicional": 512,
		"terreno_sombras": false,
		"vegetacion_sombras": false,
	},
	{	# --- MEDIA ---
		"escala_3d": 0.80,
		"cielo_estatico": false,
		"lod_umbral": 3.0,
		"ssao": false,
		"ssil": false,
		"glow": false,
		"vol_fog": false,
		"sombra_distancia": 50.0,
		"sombra_atlas": 2048,
		"sombra_filtro": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		"atlas_posicional": 1024,
		"terreno_sombras": false,
		"vegetacion_sombras": false,
	},
	{	# --- ALTA (original) ---
		"escala_3d": 1.0,
		"cielo_estatico": false,
		"lod_umbral": 1.0,
		"ssao": true,
		"ssil": null,          # null = dejar como está en la escena
		"glow": null,
		"vol_fog": null,
		"sombra_distancia": -1.0,   # -1 = la original de la escena
		"sombra_atlas": -1,
		"sombra_filtro": -1,
		"atlas_posicional": -1,
		"terreno_sombras": true,
		"vegetacion_sombras": true,
	},
]

# =============================================================== MODO DE AMBIENTE
## "Modo de ambiente" (menú GRÁFICOS): REALISTA = el juego tal cual (manda el
## perfil de CALIDAD) · PS2 = estética de PlayStation 2, que además RINDE MÁS
## porque recorta costes reales. Se cambia en caliente (sin reiniciar).
##
## Qué hace PS2 y por qué (la firma de la PS2, no la de la PS1):
##   · 3D a ~448 líneas (la PS2 sacaba 640x448), escalado BILINEAL: blando como
##     en un televisor, nunca pixel-art. Es también la mayor ganancia de FPS;
##   · post-proceso (ui/shaders/ambiente_ps2.gdshader) por DEBAJO del HUD:
##     rejilla de píxel + color de 16 bits con dithering 4x4 → la UI sigue nítida;
##   · texturas más blandas (mipmap bias +0,75, sin anisotrópico) como la poca
##     VRAM de la época, y saturación/contraste un poco más altos;
##   · niebla cercana y distancia de dibujo corta (far ≤ 450 m) + LOD agresivo;
##   · sin SSAO, SSIL, SSR, SDFGI, glow ni niebla volumétrica; sombra del sol a
##     1024 px, dura y sólo a 25 m (sombra "gorda" como las de la época), sin
##     sombras de terreno/vegetación y atlas de luces puntuales a 256.
##   · NO hay temblor de vértices ni texturas afines: eran de la PS1 (la PS2
##     corregía la perspectiva). Imitarlos marea y no es fiel a la referencia.
enum Ambiente { REALISTA, PS2 }
const AMBIENTE_NOMBRES: Array[String] = ["REALISTA", "PS2"]
const PS2_LINEAS := 448.0
const PS2_FAR := 450.0
const PS2_MIPMAP_BIAS := 0.75
const PS2_SATURACION := 1.15
const PS2_CONTRASTE := 1.06
const PS2_SOMBRA_DISTANCIA := 25.0
const PS2_SOMBRA_ATLAS := 1024
const PS2_ATLAS_POSICIONAL := 256
const PS2_LOD := 8.0
## Capa del post-proceso: por encima del 3D, por debajo de TODO el HUD (≥ 5).
const PS2_CAPA := 1
const SHADER_PS2 := preload("res://ui/shaders/ambiente_ps2.gdshader")
var modo_ambiente: int = Ambiente.REALISTA
var _capa_ps2: CanvasLayer = null
var _mat_ps2: ShaderMaterial = null

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
## Perfil de calidad activo. ALTA por defecto: así, sin tocar nada, el juego se ve
## exactamente como estaba antes de existir esta opción.
var calidad: int = Calidad.ALTA

# --- P10-B: streaming dinámico del mundo (opción OPCIONAL del jugador) --------
## Interruptor "Optimización agresiva del mundo". APAGADO por defecto: sin él el
## mundo se comporta como siempre (nada se descarga). Sólo si el jugador lo
## enciende se habilita el gestor central `StreamingMundo`.
var optimizacion_agresiva: bool = false
## Nivel 0..10 de la barra "Distancia de carga" (se traduce a metros reales).
var distancia_carga: int = 4
## Nivel 0..10 de la barra "Distancia de precarga" (margen añadido a la carga).
var distancia_precarga: int = 3
## Modo de diagnóstico del streaming (opcional; sólo para pruebas).
var modo_diagnostico_stream: bool = false

## Valores ORIGINALES del proyecto, capturados la primera vez que se aplica un
## perfil (no se escriben a mano: así ALTA devuelve de verdad lo que había).
var _orig: Dictionary = {}
## Sombras originales de cada MultiMeshInstance3D de vegetación, por instance id.
var _orig_sombras: Dictionary = {}
## Entorno duplicado en el que se aplican los efectos (nunca el recurso de la
## escena: si se compartiera, se ensuciarían otros escenarios).
var _entorno_copia: Environment = null
var _entorno_original: Environment = null
var _cielo_baja: Sky = null     # cielo panorámico estático de BAJA (pereza)

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
	call_deferred("_reaplicar_todo")

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
	var far := lerpf(FAR_MIN, FAR_MAX, pow(t, 1.6))
	# PS2: distancia de dibujo corta de la época (la niebla sube sola con ella).
	if modo_ambiente == Ambiente.PS2:
		far = minf(far, PS2_FAR)
	return far

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
	# Al cargar una escena nueva aparecen cámara y entorno: reaplica la distancia y
	# el perfil de calidad (el mundo nuevo trae su propio entorno y su propio sol).
	if n is Camera3D or n is WorldEnvironment:
		call_deferred("_reaplicar_todo")

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
	# A la DERECHA del minimapa: el minimapa ocupa el HUD arriba-izquierda con
	# margen 16 y lado 170, así que su borde derecho cae en x=186. Se deja un
	# margen de 10 px. El anclaje arriba-izquierda mantiene la etiqueta dentro de
	# la pantalla en cualquier resolución y evita solaparse con el minimapa.
	_fps_label.position = Vector2(196, 16)
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
	# Barato: sólo enciende/apaga la capa PS2 según haya o no cámara 3D.
	if _capa_ps2 != null and modo_ambiente == Ambiente.PS2:
		var hay_3d := get_viewport().get_camera_3d() != null
		if hay_3d != _capa_ps2.visible:
			_actualizar_capa_ps2()
		if hay_3d:
			_sincronizar_minimapa()
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
	cf.set_value(SECCION, "calidad", calidad)
	cf.set_value(SECCION, "modo_ambiente", modo_ambiente)
	cf.set_value(SECCION, "optimizacion_agresiva", optimizacion_agresiva)
	cf.set_value(SECCION, "distancia_carga", distancia_carga)
	cf.set_value(SECCION, "distancia_precarga", distancia_precarga)
	cf.set_value(SECCION, "modo_diagnostico_stream", modo_diagnostico_stream)
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
	calidad = clampi(int(cf.get_value(SECCION, "calidad", Calidad.ALTA)), 0, PERFILES.size() - 1)
	modo_ambiente = clampi(int(cf.get_value(SECCION, "modo_ambiente", Ambiente.REALISTA)), 0, AMBIENTE_NOMBRES.size() - 1)
	# P10-B: por defecto APAGADO; sólo se enciende si la preferencia guardada lo pidió.
	optimizacion_agresiva = bool(cf.get_value(SECCION, "optimizacion_agresiva", false))
	distancia_carga = clampi(int(cf.get_value(SECCION, "distancia_carga", 4)), 0, CARGA_NIVELES)
	distancia_precarga = clampi(int(cf.get_value(SECCION, "distancia_precarga", 3)), 0, CARGA_NIVELES)
	modo_diagnostico_stream = bool(cf.get_value(SECCION, "modo_diagnostico_stream", false))
	return true

# =============================================================== CALIDAD (aplicar)
## Reaplica TODO lo que depende del mundo cargado: distancia de visión + perfil de
## calidad. Se llama al arrancar, al cambiar de escena y al cambiar de perfil.
func _reaplicar_todo() -> void:
	_aplicar_distancia()
	_aplicar_calidad()
	_aplicar_streaming()

## Punto ÚNICO donde el perfil de calidad se traduce en ajustes de renderizado.
## Idempotente: se puede llamar tantas veces como haga falta.
##
## Nunca toca física, peatones, ciudad, combate, HUD ni audio: sólo cómo se dibuja
## lo que ya existe. Todos los valores originales se capturan antes de escribir
## nada, así ALTA devuelve el proyecto a como estaba.
func _aplicar_calidad() -> void:
	if get_viewport() == null:
		return
	var perfil: Dictionary = PERFILES[clampi(calidad, 0, PERFILES.size() - 1)]
	_capturar_originales()

	# --- viewport: escala de render 3D, agresividad del LOD, atlas puntual ----
	var vp := get_viewport()
	vp.scaling_3d_scale = float(perfil["escala_3d"])
	vp.mesh_lod_threshold = float(perfil["lod_umbral"])
	var atlas_pos := int(perfil["atlas_posicional"])
	vp.positional_shadow_atlas_size = atlas_pos if atlas_pos > 0 else int(_orig["atlas_posicional"])

	# --- atlas y filtro de sombras (ajustes del renderizador) ---------------
	var atlas := int(perfil["sombra_atlas"])
	RenderingServer.directional_shadow_atlas_set_size(
			atlas if atlas > 0 else int(_orig["sombra_atlas"]), true)
	var filtro := int(perfil["sombra_filtro"])
	RenderingServer.directional_soft_shadow_filter_set_quality(
			filtro if filtro >= 0 else int(_orig["sombra_filtro"]))
	RenderingServer.positional_soft_shadow_filter_set_quality(
			filtro if filtro >= 0 else int(_orig["sombra_filtro"]))

	# --- luz principal: distancia de su sombra ------------------------------
	var dist := float(perfil["sombra_distancia"])
	for n: Node in _buscar_por_clase("DirectionalLight3D"):
		var sol := n as DirectionalLight3D
		sol.directional_shadow_max_distance = dist if dist > 0.0 else float(_orig["sol_distancia"])
		sol.shadow_enabled = bool(_orig["sol_sombra"])

	# --- terreno y vegetación: proyección de sombras -------------------------
	_aplicar_sombra_terreno(bool(perfil["terreno_sombras"]))
	_aplicar_sombra_vegetacion(bool(perfil["vegetacion_sombras"]))

	# --- entorno: SSAO, SSIL, glow y niebla volumétrica ---------------------
	_entorno_con_perfil(perfil)

	# --- modo de ambiente (PS2 se aplica ENCIMA del perfil) -----------------
	_aplicar_ambiente()


## Modo de ambiente. Idempotente; en REALISTA devuelve lo que PS2 cambió y que el
## perfil de calidad no gobierna (bias de mipmaps, anisotrópico, modo de escalado,
## ajustes de color, post-proceso). Lo demás ya lo dejó el perfil.
func _aplicar_ambiente() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	if not _orig.has("escala_modo"):
		_orig["escala_modo"] = vp.scaling_3d_mode
		_orig["mip_bias"] = vp.texture_mipmap_bias
		_orig["aniso"] = vp.anisotropic_filtering_level
	var ps2 := modo_ambiente == Ambiente.PS2
	_asegurar_capa_ps2()
	if ps2:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = _escala_ps2()
		vp.texture_mipmap_bias = PS2_MIPMAP_BIAS
		vp.anisotropic_filtering_level = Viewport.ANISOTROPY_DISABLED
		vp.mesh_lod_threshold = maxf(vp.mesh_lod_threshold, PS2_LOD)
		vp.positional_shadow_atlas_size = PS2_ATLAS_POSICIONAL
		RenderingServer.directional_shadow_atlas_set_size(PS2_SOMBRA_ATLAS, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		for n: Node in _buscar_por_clase("DirectionalLight3D"):
			(n as DirectionalLight3D).directional_shadow_max_distance = PS2_SOMBRA_DISTANCIA
		_aplicar_sombra_terreno(false)
		_aplicar_sombra_vegetacion(false)
	else:
		vp.scaling_3d_mode = _orig["escala_modo"]
		vp.texture_mipmap_bias = float(_orig["mip_bias"])
		vp.anisotropic_filtering_level = _orig["aniso"]
	if _entorno_copia != null:
		var env := _entorno_copia
		if not _orig.has("env_adj"):
			_orig["env_adj"] = _entorno_original.adjustment_enabled
			_orig["env_sat"] = _entorno_original.adjustment_saturation
			_orig["env_con"] = _entorno_original.adjustment_contrast
			_orig["env_ssr"] = _entorno_original.ssr_enabled
			_orig["env_sdfgi"] = _entorno_original.sdfgi_enabled
		if ps2:
			env.ssao_enabled = false
			env.ssil_enabled = false
			env.glow_enabled = false
			env.volumetric_fog_enabled = false
			env.ssr_enabled = false
			env.sdfgi_enabled = false
			env.adjustment_enabled = true
			env.adjustment_saturation = PS2_SATURACION
			env.adjustment_contrast = PS2_CONTRASTE
		else:
			env.ssr_enabled = bool(_orig["env_ssr"])
			env.sdfgi_enabled = bool(_orig["env_sdfgi"])
			env.adjustment_enabled = bool(_orig["env_adj"])
			env.adjustment_saturation = float(_orig["env_sat"])
			env.adjustment_contrast = float(_orig["env_con"])
	_actualizar_capa_ps2()
	_sincronizar_minimapa()


## Escala 3D que da ~448 líneas a la resolución REAL de la ventana.
func _escala_ps2() -> float:
	var alto := float(maxi(get_viewport().size.y, 1))
	return clampf(PS2_LINEAS / alto, 0.2, 1.0)


func _asegurar_capa_ps2() -> void:
	if _capa_ps2 != null:
		return
	_capa_ps2 = CanvasLayer.new()
	_capa_ps2.name = "AmbientePS2"
	_capa_ps2.layer = PS2_CAPA
	add_child(_capa_ps2)
	var rect := ColorRect.new()
	rect.name = "Post"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat_ps2 = ShaderMaterial.new()
	_mat_ps2.shader = SHADER_PS2
	rect.material = _mat_ps2
	_capa_ps2.add_child(rect)
	_capa_ps2.visible = false
	get_viewport().size_changed.connect(_on_ventana_cambiada)


func _on_ventana_cambiada() -> void:
	if modo_ambiente == Ambiente.PS2:
		get_viewport().scaling_3d_scale = _escala_ps2()
		_actualizar_capa_ps2()


## El post-proceso sólo se dibuja en PS2 y si hay mundo 3D en pantalla (en el
## menú principal y en las pantallas de carga no se toca nada: allí todo es UI).
func _actualizar_capa_ps2() -> void:
	if _capa_ps2 == null:
		return
	var vp := get_viewport()
	var visible_ps2 := modo_ambiente == Ambiente.PS2 and vp.get_camera_3d() != null
	_capa_ps2.visible = visible_ps2
	if visible_ps2:
		var s := Vector2(vp.size) * vp.scaling_3d_scale
		_mat_ps2.set_shader_parameter("resolucion_baja", s.round())


func es_ps2() -> bool:
	return modo_ambiente == Ambiente.PS2


## El minimapa es una cámara cenital a cientos de metros que COMPARTE el entorno
## del mundo: con la niebla cercana de PS2 quedaba lavado. En PS2 su cámara usa
## una copia del entorno SIN niebla, que sigue cada fotograma los valores que
## mueve el ciclo de día y noche (luz ambiente). En REALISTA se le quita.
const PROPS_MINIMAPA := ["ambient_light_energy", "ambient_light_sky_contribution",
		"ambient_light_color", "ambient_light_source", "sky", "background_mode",
		"tonemap_mode", "tonemap_exposure", "adjustment_enabled",
		"adjustment_saturation", "adjustment_contrast"]
var _cam_minimapa: Camera3D = null
var _env_minimapa: Environment = null

func _sincronizar_minimapa() -> void:
	if _cam_minimapa == null or not is_instance_valid(_cam_minimapa):
		# Por GRUPO (lo pone minimapa.gd): en modo PS2 esto corre cada fotograma
		# mientras no haya minimapa, y recorrer todo el árbol de la ciudad era caro.
		_cam_minimapa = get_tree().get_first_node_in_group(&"camara_minimapa") as Camera3D
		if _cam_minimapa == null:
			return
	if modo_ambiente != Ambiente.PS2 or _entorno_copia == null:
		_cam_minimapa.environment = null
		return
	if _env_minimapa == null:
		_env_minimapa = Environment.new()
		_env_minimapa.fog_enabled = false
		_env_minimapa.volumetric_fog_enabled = false
	for p in PROPS_MINIMAPA:
		_env_minimapa.set(p, _entorno_copia.get(p))
	_cam_minimapa.environment = _env_minimapa

# ---------------------------------------------------------------- originales
## Captura el estado original UNA vez (el del proyecto, no un valor escrito a
## mano). Se usa para que ALTA restaure de verdad lo que había.
func _capturar_originales() -> void:
	if not _orig.is_empty():
		return
	var vp := get_viewport()
	_orig["atlas_posicional"] = vp.positional_shadow_atlas_size
	_orig["sombra_atlas"] = int(ProjectSettings.get_setting(
			"rendering/lights_and_shadows/directional_shadow/size", 4096))
	_orig["sombra_filtro"] = int(ProjectSettings.get_setting(
			"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
			RenderingServer.SHADOW_QUALITY_SOFT_LOW))
	_orig["sol_distancia"] = 100.0     # valor por defecto de DirectionalLight3D
	_orig["sol_sombra"] = true
	for n: Node in _buscar_por_clase("DirectionalLight3D"):
		var sol := n as DirectionalLight3D
		_orig["sol_distancia"] = sol.directional_shadow_max_distance
		_orig["sol_sombra"] = sol.shadow_enabled
		break

## Nodos de una clase en todo el árbol (incluidos los recién añadidos).
func _buscar_por_clase(clase: String) -> Array:
	if get_tree() == null or get_tree().root == null:
		return []
	return get_tree().root.find_children("*", clase, true, false)

## Terreno: las sombras del terreno arrastran también su vegetación instanciada
## (las 15 034 matas), que es una pasada de sombra entera.
func _aplicar_sombra_terreno(activar: bool) -> void:
	for n: Node in _buscar_por_clase("Terrain3D"):
		var terreno := n as Terrain3D
		if not _orig.has("terreno_sombras"):
			_orig["terreno_sombras"] = terreno.cast_shadows
		if activar:
			terreno.cast_shadows = _orig["terreno_sombras"]
		else:
			terreno.cast_shadows = RenderingServer.SHADOW_CASTING_SETTING_OFF

## Vegetación: las tarjetas cruzadas del bosque y de la ciudad se dibujan en 17
## trozos CON sombra. Su sombra es ruido visual y cuesta una pasada completa.
## Sólo se cambia la proyección de sombras: ni la malla, ni el material, ni el
## MultiMesh, ni la lógica (nada de esto se apaga). Reversible con `_orig_sombras`.
func _aplicar_sombra_vegetacion(activar: bool) -> void:
	for n: Node in _buscar_por_clase("MultiMeshInstance3D"):
		if not _es_vegetacion(n):
			continue
		var gi := n as GeometryInstance3D
		var id := gi.get_instance_id()
		if not _orig_sombras.has(id):
			_orig_sombras[id] = gi.cast_shadow
		if activar:
			gi.cast_shadow = _orig_sombras[id]
		else:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _es_vegetacion(n: Node) -> bool:
	var r := String(n.get_path()).to_lower()
	return r.contains("trozo_") or r.contains("bosque") or r.contains("vegeta") \
			or r.contains("arbol") or r.contains("arbusto")

## Efectos del entorno. Se trabaja SIEMPRE sobre una COPIA del Environment: el
## recurso de la escena (SubResource compartido del mundo) no se modifica nunca,
## de modo que ningún otro escenario ni el original del proyecto se ensucian.
func _entorno_con_perfil(perfil: Dictionary) -> void:
	var mundo: WorldEnvironment = null
	for n: Node in _buscar_por_clase("WorldEnvironment"):
		mundo = n as WorldEnvironment
		break
	if mundo == null or mundo.environment == null:
		return
	if mundo.environment != _entorno_copia:
		# Entorno nuevo (primera vez, o escena recargada): se copia y se recuerdan
		# los valores originales de los efectos.
		_entorno_original = mundo.environment
		_entorno_copia = _entorno_original.duplicate() as Environment
		mundo.environment = _entorno_copia
		_orig["env_ssao"] = _entorno_original.ssao_enabled
		_orig["env_ssil"] = _entorno_original.ssil_enabled
		_orig["env_glow"] = _entorno_original.glow_enabled
		_orig["env_vol"] = _entorno_original.volumetric_fog_enabled
	var env := _entorno_copia
	env.ssao_enabled = _valor_efecto(perfil["ssao"], "env_ssao")
	env.ssil_enabled = _valor_efecto(perfil["ssil"], "env_ssil")
	env.glow_enabled = _valor_efecto(perfil["glow"], "env_glow")
	env.volumetric_fog_enabled = _valor_efecto(perfil["vol_fog"], "env_vol")
	# La niebla NO se toca aquí: la gobierna el mando de distancia de visión.
	# --- cielo: estático en BAJA, dinámico en MEDIA y ALTA ------------------
	# Se cambia SÓLO el `sky` de la COPIA del entorno. El cielo dinámico
	# original (su Sky, su material, sus texturas y parámetros) nunca se toca:
	# se guarda su referencia y se devuelve tal cual en MEDIA y ALTA.
	if not _orig.has("env_sky"):
		_orig["env_sky"] = _entorno_original.sky
	if bool(perfil.get("cielo_estatico", false)):
		if _cielo_baja == null:
			_cielo_baja = load(RUTA_CIELO_BAJA) as Sky
		if _cielo_baja != null:
			env.sky = _cielo_baja
	else:
		env.sky = _orig["env_sky"] as Sky

## null en la tabla = "lo que traía la escena" (es el caso de ALTA).
func _valor_efecto(v: Variant, clave_original: String) -> bool:
	if v == null:
		return bool(_orig.get(clave_original, false))
	return bool(v)

# ---------------------------------------------------------------- API (menú)
## Cambia el perfil de calidad: aplica, guarda y avisa al menú.
func poner_calidad(n: int) -> void:
	n = clampi(n, 0, PERFILES.size() - 1)
	if n == calidad:
		return
	calidad = n
	_aplicar_calidad()
	_guardar()
	cambiado.emit()

## Paso de la rueda del menú (izquierda/derecha), sin salirse de la lista.
func pasar_calidad(paso: int) -> void:
	poner_calidad(wrapi(calidad + paso, 0, PERFILES.size()))

func texto_calidad() -> String:
	return CALIDAD_NOMBRES[clampi(calidad, 0, CALIDAD_NOMBRES.size() - 1)]

## Cambia el modo de ambiente EN CALIENTE: aplica (perfil + ambiente + distancia),
## guarda y avisa al menú.
func poner_modo_ambiente(n: int) -> void:
	n = clampi(n, 0, AMBIENTE_NOMBRES.size() - 1)
	if n == modo_ambiente:
		return
	modo_ambiente = n
	_reaplicar_todo()
	_guardar()
	cambiado.emit()

func pasar_modo_ambiente(paso: int) -> void:
	poner_modo_ambiente(wrapi(modo_ambiente + paso, 0, AMBIENTE_NOMBRES.size()))

func texto_modo_ambiente() -> String:
	return AMBIENTE_NOMBRES[clampi(modo_ambiente, 0, AMBIENTE_NOMBRES.size() - 1)]


# =============================================================== P10-B: STREAMING
## Opción OPCIONAL del jugador "Optimización agresiva del mundo". Con ella apagada
## el mundo se comporta como siempre (nada se descarga). Con ella encendida se
## habilita el gestor central `StreamingMundo` (que reutiliza los gestores ya
## probados de ciudad y bosque).
##
## Los valores NO son arbitrarios ni copiados de otro juego: la ciudad usa sectores
## de 42 m y el bosque trozos de 200 m, así que las barras se expresan en METROS
## reales del mapa, no en "chunks" homogéneos:
##   · Distancia de carga    -> radio ACTIVO (lo que se mantiene cargado) 60..600 m
##   · Distancia de precarga -> margen que se SUMA a la carga              20..300 m
##   · Histéresis de descarga-> +60 m (el sector no oscila cerca del límite)
## La "distancia de visión" NO se duplica: es el ajuste gráfico ya existente
## (`distancia`, far de la cámara + niebla), independiente del radio de carga.
const CARGA_NIVELES := 10
const CARGA_MIN := 60.0
const CARGA_MAX := 600.0
const PRECARGA_MIN := 20.0
const PRECARGA_MAX := 300.0
const HISTERESIS_DESCARGA := 60.0

## Radio activo (m) para el nivel de la barra de carga.
func radio_carga_m() -> float:
	return lerpf(CARGA_MIN, CARGA_MAX, float(distancia_carga) / float(CARGA_NIVELES))

## Margen de precarga (m) para el nivel de la barra de precarga.
func margen_precarga_m() -> float:
	return lerpf(PRECARGA_MIN, PRECARGA_MAX, float(distancia_precarga) / float(CARGA_NIVELES))

func texto_carga() -> String:
	return "%d m" % int(round(radio_carga_m()))

func texto_precarga() -> String:
	return "%d m" % int(round(margen_precarga_m()))

## Punto ÚNICO donde la opción de streaming se traduce en el gestor del mundo.
## En el menú (sin mundo) no encuentra el gestor y no hace nada; cuando el mundo se
## carga, `_on_node_added` reaplica y entonces sí lo configura.
func _aplicar_streaming() -> void:
	var mundo := _buscar_streaming()
	if mundo == null:
		return
	var rc := radio_carga_m()
	var rp := rc + margen_precarga_m()
	var rd := rp + HISTERESIS_DESCARGA
	mundo.set("ciudad_r_activo", rc)
	mundo.set("ciudad_r_precarga", rp)
	mundo.set("ciudad_r_descarga", rd)
	mundo.set("bosque_r_activo", rc)
	mundo.set("bosque_r_precarga", rp)
	mundo.set("bosque_r_descarga", rd)
	mundo.set("modo_diagnostico", modo_diagnostico_stream)
	mundo.call("set_activo", optimizacion_agresiva)
	mundo.call("set_diagnostico", modo_diagnostico_stream)
	if optimizacion_agresiva:
		mundo.call("aplicar_radios")

func _buscar_streaming() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	var r := get_tree().root.find_children("*", "GestorStreamingMundo", true, false)
	return r[0] if not r.is_empty() else null

# ---------------------------------------------------------------- API (menú P10-B)
func poner_optimizacion_agresiva(v: bool) -> void:
	if v == optimizacion_agresiva:
		return
	optimizacion_agresiva = v
	_aplicar_streaming()
	_guardar()
	cambiado.emit()

func alternar_optimizacion_agresiva() -> void:
	poner_optimizacion_agresiva(not optimizacion_agresiva)

func poner_distancia_carga(n: int) -> void:
	n = clampi(n, 0, CARGA_NIVELES)
	if n == distancia_carga:
		return
	distancia_carga = n
	if optimizacion_agresiva:
		_aplicar_streaming()
	_guardar()
	cambiado.emit()

func poner_distancia_precarga(n: int) -> void:
	n = clampi(n, 0, CARGA_NIVELES)
	if n == distancia_precarga:
		return
	distancia_precarga = n
	if optimizacion_agresiva:
		_aplicar_streaming()
	_guardar()
	cambiado.emit()

func poner_diagnostico_stream(v: bool) -> void:
	if v == modo_diagnostico_stream:
		return
	modo_diagnostico_stream = v
	if optimizacion_agresiva:
		_aplicar_streaming()
	_guardar()
	cambiado.emit()

func alternar_diagnostico_stream() -> void:
	poner_diagnostico_stream(not modo_diagnostico_stream)

func texto_optimizacion() -> String:
	return "SÍ" if optimizacion_agresiva else "NO"

func texto_diagnostico_stream() -> String:
	return "SÍ" if modo_diagnostico_stream else "NO"