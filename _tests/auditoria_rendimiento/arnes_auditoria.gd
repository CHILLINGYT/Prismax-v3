extends Node3D
## =============================================================================
##  ARNÉS DE AUDITORÍA DE RENDIMIENTO — FASE 2 (SOLO MIDE)
## =============================================================================
##  Qué hace:
##   · Carga el mundo REAL (res://ziba/escenas/ziba_prototipo.tscn) como escena
##     INDEPENDIENTE (no embebida en el editor), con una semilla FIJA, para que
##     dos ejecuciones construyan exactamente la misma ciudad.
##   · Separa: carga de recursos, instanciación, generación síncrona (add_child),
##     y gameplay estable. Mide cada fase por separado.
##   · Mide tiempos de fotograma y devuelve MEDIANA, p95 y p99 (no solo el FPS
##     medio, que engaña con picos térmicos del equipo).
##   · Aplica y RESTAURA toggles temporales (sombras, vegetación, escala, ciudad,
##     NPC, agua) sobre nodos de la escena. NO escribe preferencias persistentes
##     y NO llama a poner_calidad() ni a ningún setter que guarde en user://.
##
##  AISLAMIENTO: se lanza con XDG_DATA_HOME apuntando a una carpeta temporal, de
##  modo que cualquier escritura en user:// cae fuera de las preferencias reales.
##  La cabecera imprime la ruta EFECTIVA de user:// para verificarlo.
##
##  Uso:
##    XDG_DATA_HOME=/tmp/prismax_audit/xdg \
##      godot --path . res://_tests/auditoria_rendimiento/arnes_auditoria.tscn
##
##  Variables de entorno:
##    PRISMAX_AUDIT_NOCHE=1  -> el mundo arranca de noche (fase_inicial 0.9).
##    PRISMAX_AUDIT_MEDIR=<s> -> segundos de cada ventana de medida (por defecto 4).
##    PRISMAX_AUDIT_SOLO=<a,b,..> -> limita las fases ejecutadas (por nombre).
##  Fases de diagnóstico P4 (apagan y RESTAURAN en memoria; no persisten):
##    terreno_off -> oculta el nodo Terreno  |  cielo_off -> oculta Cielo3D y quita
##    el `sky` del entorno  |  niebla_off -> apaga `fog_enabled` del entorno.
## =============================================================================

const MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"
const SEMILLA := 20261011
const VENTANA := Vector2i(1280, 720)
const ASENTAR := 1.5
const ESPERA_MAX_GEN := 40.0

# --- Poses de cámara reproducibles (coordenadas del mundo) --------------------
const POS_CIUDAD := Vector3(210.0, 55.0, 210.0)
const MIRA_CIUDAD := Vector3(0.0, 12.0, 0.0)
const POS_BOSQUE := Vector3(-180.0, 35.0, -180.0)
const MIRA_BOSQUE := Vector3(-560.0, 25.0, -560.0)
const POS_HORIZONTE := Vector3(60.0, 620.0, 620.0)
const MIRA_HORIZONTE := Vector3(-80.0, 8.0, -80.0)
const FAR_HORIZONTE := 20000.0
const FAR_TIERRA := 4000.0

var _mundo: Node = null
var _cam: Camera3D
var _medir_s := 4.0
var _noche := false
var _ciclo: Node = null
# --- Diagnóstico P4: estado ORIGINAL guardado para restaurar tras cada fase ---
var _diag_terreno_visible := true
var _diag_cielo_visible := true
var _diag_env: Environment = null
var _diag_sky: Sky = null
var _diag_fog := false
var _diag_fog_dens := 0.0
## Fase del ciclo forzada en modo noche (medianoche).
const FASE_NOCHE := 0.9


func _ready() -> void:
	_medir_s = float(OS.get_environment("PRISMAX_AUDIT_MEDIR")) if OS.get_environment("PRISMAX_AUDIT_MEDIR") != "" else 4.0
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not Engine.is_embedded_in_editor():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(VENTANA)
		await get_tree().process_frame
	_imprimir_cabecera()

	_cam = Camera3D.new()
	_cam.name = "CamAuditoria"
	_cam.near = 0.5
	add_child(_cam)

	# --- 1) Carga de recursos ---
	var t := Time.get_ticks_usec()
	var packed := load(MUNDO) as PackedScene
	var load_ms := float(Time.get_ticks_usec() - t) / 1000.0

	# --- 2) Instanciación ---
	t = Time.get_ticks_usec()
	_mundo = packed.instantiate()
	var inst_ms := float(Time.get_ticks_usec() - t) / 1000.0

	# Semilla FIJA antes de añadir al árbol (el generador lee `semilla` en _ready).
	var ciudad := _mundo.get_node_or_null("Ciudad")
	if ciudad != null:
		ciudad.set("semilla", SEMILLA)
	# Noche opcional: el ciclo no expone setter de fase, así que se FUERZA tras
	# add_child (ver más abajo). El CicloDiaNoche SÍ se puede localizar aquí.
	_noche = OS.get_environment("PRISMAX_AUDIT_NOCHE") == "1"
	_ciclo = _mundo.get_node_or_null("CicloDiaNoche")

	# --- 3) add_child: la generación síncrona ocurre AQUÍ (bloquea el fotograma) ---
	t = Time.get_ticks_usec()
	add_child(_mundo)
	var add_ms := float(Time.get_ticks_usec() - t) / 1000.0
	print("AUDIT|phase=gen|load_ms=%.1f|instantiate_ms=%.1f|addchild_ms=%.1f" % [load_ms, inst_ms, add_ms])

	# --- 4) Esperar a que el árbol se estabilice (la cuenta de nodos deja de crecer) ---
	t = Time.get_ticks_usec()
	var estable := 0
	var prev := -1
	while float(Time.get_ticks_usec() - t) / 1e6 < ESPERA_MAX_GEN:
		await get_tree().process_frame
		var n := _contar(_mundo)
		if n == prev:
			estable += 1
			if estable >= 25:
				break
		else:
			estable = 0
		prev = n
	print("AUDIT|phase=gen_ready|primer_frame_util_ms=%.1f|nodos_mundo=%d" % [
			float(Time.get_ticks_usec() - t) / 1000.0, _contar(_mundo)])
	_resumen_escena()

	# Forzar NOCHE (el ciclo no expone setter público de fase: se escribe `_fase`
	# y se aplica; se vuelve a fijar cada fotograma para que no avance).
	if _noche and _ciclo != null:
		_ciclo.set("_fase", FASE_NOCHE)
		_ciclo.call("_aplicar")
		await get_tree().process_frame
		var sol_n := _mundo.get_node_or_null("Sol") as DirectionalLight3D
		print("AUDIT|phase=night|fase=%.3f|sol_energia=%.2f|sol_rotx=%.1f" % [
				float(_ciclo.get("_fase")),
				sol_n.light_energy if sol_n != null else -1.0,
				sol_n.rotation_degrees.x if sol_n != null else -1.0])

	var sol := _mundo.get_node_or_null("Sol") as DirectionalLight3D
	var bosque := _mundo.get_node_or_null("Bosque")
	var oceano := _mundo.get_node_or_null("Oceano")
	var peatones := _buscar_nodo("Peatones")
	var ciudad_gen := _mundo.get_node_or_null("Ciudad")
	var hierba := _multimesh_nombre("hierba")
	var vp := get_viewport()

	var fases_ejecutadas := _fases_pedidas()

	# --- Fase base: cámara del jugador tal cual (referencia "normal") ---
	if fases_ejecutadas.is_empty() or "base" in fases_ejecutadas:
		await _medir("base", false, func() -> void: pass, func() -> void: pass)

	# --- Prueba 2: ciudad abierta ---
	if fases_ejecutadas.is_empty() or "ciudad" in fases_ejecutadas:
		await _medir("ciudad", true, _pose(POS_CIUDAD, MIRA_CIUDAD, FAR_TIERRA), func() -> void: pass)

	# --- Prueba 3: bosque y terreno ---
	if fases_ejecutadas.is_empty() or "bosque" in fases_ejecutadas:
		await _medir("bosque", true, _pose(POS_BOSQUE, MIRA_BOSQUE, FAR_TIERRA), func() -> void: pass)

	# --- Prueba 4: vista abierta y horizonte ---
	if fases_ejecutadas.is_empty() or "horizonte" in fases_ejecutadas:
		await _medir("horizonte", true, _pose(POS_HORIZONTE, MIRA_HORIZONTE, FAR_HORIZONTE), func() -> void: pass)

	# --- Prueba 6a: sombras del sol (en pose de ciudad) ---
	if (fases_ejecutadas.is_empty() or "sombras_off" in fases_ejecutadas) and sol != null:
		await _medir("sombras_off", true, func() -> void:
				_pose(POS_CIUDAD, MIRA_CIUDAD, FAR_TIERRA).call()
				sol.shadow_enabled = false,
			func() -> void: sol.shadow_enabled = true)

	# --- Prueba 6b: vegetación (bosque + hierba) oculta ---
	if (fases_ejecutadas.is_empty() or "vegetacion_off" in fases_ejecutadas):
		await _medir("vegetacion_off", true, func() -> void:
				_pose(POS_BOSQUE, MIRA_BOSQUE, FAR_TIERRA).call()
				for n in hierba:
					n.visible = false
				if bosque != null:
					bosque.visible = false,
			func() -> void:
				for n in hierba:
					n.visible = true
				if bosque != null:
					bosque.visible = true)

	# --- Prueba 7: reducir escala de renderizado (indicio, no prueba de GPU) ---
	if fases_ejecutadas.is_empty() or "escala_0.5" in fases_ejecutadas:
		await _medir("escala_0.5", true, func() -> void:
				_pose(POS_CIUDAD, MIRA_CIUDAD, FAR_TIERRA).call()
				vp.scaling_3d_scale = 0.5,
			func() -> void: vp.scaling_3d_scale = 1.0)

	# --- Ciudad entera oculta (aisla la contribución de la ciudad) ---
	if (fases_ejecutadas.is_empty() or "ciudad_off" in fases_ejecutadas) and ciudad_gen != null:
		await _medir("ciudad_off", true, func() -> void:
				_pose(POS_CIUDAD, MIRA_CIUDAD, FAR_TIERRA).call()
				ciudad_gen.visible = false,
			func() -> void: ciudad_gen.visible = true)

	# --- Prueba 5: NPC (oculta + desactiva proceso de los peatones) ---
	if (fases_ejecutadas.is_empty() or "npc_off" in fases_ejecutadas) and peatones != null:
		var ciudadanos := _nodos_npc()
		await _medir("npc_off", true, func() -> void:
				_pose(POS_CIUDAD, MIRA_CIUDAD, FAR_TIERRA).call()
				for c in ciudadanos:
					c.visible = false
					c.set_process(false)
					c.set_physics_process(false),
			func() -> void:
				for c in ciudadanos:
					c.visible = true
					c.set_process(true)
					c.set_physics_process(true))

	# --- Prueba 8: agua (océano oculto desde el horizonte) ---
	# --- Diagnóstico P4: terreno, cielo y niebla (se restauran tras cada fase) ---
	if fases_ejecutadas.is_empty() or "terreno_off" in fases_ejecutadas:
		await _medir("terreno_off", true, func() -> void:
			var terreno := _mundo.get_node_or_null("Terreno") as Node3D
			if terreno != null:
				_diag_terreno_visible = terreno.visible
				terreno.visible = false
				print("AUDIT|diag|terreno_off|encontrado=%s|visible_original=%s" % [terreno.get_path(), str(_diag_terreno_visible)])
			else:
				print("AUDIT|diag|terreno_off|NO_ENCONTRADO")
		, func() -> void:
			var terreno := _mundo.get_node_or_null("Terreno") as Node3D
			if terreno != null:
				terreno.visible = _diag_terreno_visible
		)

	if fases_ejecutadas.is_empty() or "cielo_off" in fases_ejecutadas:
		await _medir("cielo_off", true, func() -> void:
			var cielo := _mundo.get_node_or_null("Cielo3D") as Node3D
			if cielo != null:
				_diag_cielo_visible = cielo.visible
				cielo.visible = false
			var ent := _mundo.get_node_or_null("Entorno") as WorldEnvironment
			_diag_env = ent.environment if ent != null else null
			_diag_sky = _diag_env.sky if _diag_env != null else null
			if _diag_env != null:
				_diag_env.sky = null
			print("AUDIT|diag|cielo_off|nodo_cielo=%s|entorno=%s|sky_original=%s" % [str(cielo != null), str(_diag_env != null), str(_diag_sky != null)])
		, func() -> void:
			var cielo := _mundo.get_node_or_null("Cielo3D") as Node3D
			if cielo != null:
				cielo.visible = _diag_cielo_visible
			if _diag_env != null:
				_diag_env.sky = _diag_sky
		)

	if fases_ejecutadas.is_empty() or "niebla_off" in fases_ejecutadas:
		await _medir("niebla_off", true, func() -> void:
			var ent := _mundo.get_node_or_null("Entorno") as WorldEnvironment
			var env := ent.environment if ent != null else null
			if env != null:
				_diag_env = env
				_diag_fog = env.fog_enabled
				_diag_fog_dens = env.fog_density
				env.fog_enabled = false
				print("AUDIT|diag|niebla_off|fog_original=%s|densidad_original=%.5f" % [str(_diag_fog), _diag_fog_dens])
			else:
				print("AUDIT|diag|niebla_off|SIN_ENTORNO")
		, func() -> void:
			if _diag_env != null:
				_diag_env.fog_enabled = _diag_fog
				_diag_env.fog_density = _diag_fog_dens
		)

	if (fases_ejecutadas.is_empty() or "agua_off" in fases_ejecutadas) and oceano != null:
		await _medir("agua_off", true, func() -> void:
				_pose(POS_HORIZONTE, MIRA_HORIZONTE, FAR_HORIZONTE).call()
				oceano.visible = false,
			func() -> void: oceano.visible = true)

	print("AUDIT|FIN user_data_dir=", OS.get_user_data_dir())
	get_tree().quit(0)


# ------------------------------------------------------------------ cabecera
func _imprimir_cabecera() -> void:
	print("AUDIT|phase=header|godot=", Engine.get_version_info().string)
	print("AUDIT|phase=header|renderer=", ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	print("AUDIT|phase=header|gpu=", RenderingServer.get_video_adapter_name())
	print("AUDIT|phase=header|ventana=", DisplayServer.window_get_size(),
			"|vsync=", DisplayServer.window_get_vsync_mode(), "|max_fps=", Engine.max_fps)
	print("AUDIT|phase=header|noche=", OS.get_environment("PRISMAX_AUDIT_NOCHE") == "1",
			"|semilla=", SEMILLA)
	print("AUDIT|phase=header|user_data_dir=", OS.get_user_data_dir())
	print("AUDIT|phase=header|mem_total_mb=%d" % (OS.get_static_memory_peak_usage() / 1048576))


# ------------------------------------------------------------------ resumen de escena
func _resumen_escena() -> void:
	var luces := 0
	var meshes := 0
	var mms := 0
	var skel := 0
	for n in _mundo.find_children("*", "Light3D", true, false):
		luces += 1
	for n in _mundo.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
	for n in _mundo.find_children("*", "MultiMeshInstance3D", true, false):
		mms += 1
	for n in _mundo.find_children("*", "Skeleton3D", true, false):
		skel += 1
	print("AUDIT|phase=scene|nodos=%d|meshes=%d|multimesh=%d|luces=%d|esqueletos=%d|npc=%d" % [
			_contar(_mundo), meshes, mms, luces, skel, _nodos_npc().size()])


# ------------------------------------------------------------------ fases
func _medir(nombre: String, usar_cam: bool, prep: Callable, rest: Callable) -> void:
	prep.call()
	await _esperar(ASENTAR)
	var ms := PackedFloat32Array()
	var proc := 0.0
	var phys := 0.0
	var draw := 0.0
	var prim := 0.0
	var obj := 0.0
	var n := 0
	var t0 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - t0) < _medir_s * 1e6:
		if _noche and _ciclo != null:
			_ciclo.set("_fase", FASE_NOCHE)
		if usar_cam:
			_cam.make_current()
		await get_tree().process_frame
		ms.append(get_process_delta_time() * 1000.0)
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		n += 1
	rest.call()
	await get_tree().process_frame
	if n == 0:
		print("AUDIT|phase=%s|SIN_MUESTRAS" % nombre)
		return
	var e := _estadisticas(ms, n)
	var mem_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var vram_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	print("AUDIT|phase=%s|n=%d|fps=%.1f|med=%.1f|p95=%.1f|p99=%.1f|max=%.1f|media=%.1f|proc_ms=%.2f|phys_ms=%.2f|draw=%d|prim=%d|obj=%d|mem_mb=%.0f|vram_mb=%.0f" % [
			nombre, n, 1000.0 / maxf(e["med"], 0.001), e["med"], e["p95"], e["p99"], e["max"], e["media"],
			(proc / float(n)) * 1000.0, (phys / float(n)) * 1000.0,
			int(draw / float(n)), int(prim / float(n)), int(obj / float(n)), mem_mb, vram_mb])


func _estadisticas(ms: PackedFloat32Array, n: int) -> Dictionary:
	var a := Array(ms)
	a.sort()
	var suma := 0.0
	for v in a:
		suma += v
	return {
		"med": a[n / 2],
		"p95": a[mini(n - 1, int(round(float(n) * 0.95)))],
		"p99": a[mini(n - 1, int(round(float(n) * 0.99)))],
		"max": a[n - 1],
		"media": suma / float(n),
	}


# ------------------------------------------------------------------ utilidad
func _pose(pos: Vector3, mira: Vector3, far: float) -> Callable:
	return func() -> void:
		_cam.global_position = pos
		_cam.look_at(mira, Vector3.UP)
		_cam.far = far
		_cam.make_current()

func _esperar(seg: float) -> void:
	await get_tree().create_timer(seg, true, false, true).timeout

func _contar(n: Node) -> int:
	var t := 0
	for c in n.get_children():
		t += 1 + _contar(c)
	return t

func _buscar_nodo(nombre: String) -> Node:
	var l := _mundo.find_children(nombre, "", true, false)
	return l[0] if not l.is_empty() else null

func _multimesh_nombre(texto: String) -> Array:
	var out: Array = []
	for n in _mundo.find_children("*", "MultiMeshInstance3D", true, false):
		if String(_mundo.get_path_to(n)).to_lower().contains(texto):
			out.append(n)
	return out

func _nodos_npc() -> Array:
	var out: Array = []
	for n in _mundo.find_children("*", "CharacterBody3D", true, false):
		var s: Script = n.get_script() as Script
		if s != null and String(s.resource_path).ends_with("npc_citizen.gd"):
			out.append(n)
	return out

func _fases_pedidas() -> Array:
	var v := OS.get_environment("PRISMAX_AUDIT_SOLO")
	if v == "":
		return []
	var out: Array = []
	for p in v.split(",", false):
		out.append(p.strip_edges())
	return out