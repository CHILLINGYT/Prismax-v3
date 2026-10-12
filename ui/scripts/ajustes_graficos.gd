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

## Tabla por perfil. `ALTA` == configuración original del proyecto (escala 1.0,
## SSAO encendido, sombras del sol sin recortar, sin tocar la vegetación).
const PERFILES: Array[Dictionary] = [
	{	# --- BAJA ---
		"escala_3d": 0.70,
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

## Valores ORIGINALES del proyecto, capturados la primera vez que se aplica un
## perfil (no se escriben a mano: así ALTA devuelve de verdad lo que había).
var _orig: Dictionary = {}
## Sombras originales de cada MultiMeshInstance3D de vegetación, por instance id.
var _orig_sombras: Dictionary = {}
## Entorno duplicado en el que se aplican los efectos (nunca el recurso de la
## escena: si se compartiera, se ensuciarían otros escenarios).
var _entorno_copia: Environment = null
var _entorno_original: Environment = null

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
	cf.set_value(SECCION, "calidad", calidad)
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
	return true

# =============================================================== CALIDAD (aplicar)
## Reaplica TODO lo que depende del mundo cargado: distancia de visión + perfil de
## calidad. Se llama al arrancar, al cambiar de escena y al cambiar de perfil.
func _reaplicar_todo() -> void:
	_aplicar_distancia()
	_aplicar_calidad()

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