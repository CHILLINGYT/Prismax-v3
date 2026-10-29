extends Node3D

## DIAGNÓSTICO DE CUELLO (sólo medición).
##
## Responde a UNA pregunta: ¿qué subsistema se come el fotograma? Carga el mundo
## real, imprime un INVENTARIO de la geometría generada y luego mide el mismo
## fotograma apagando un subsistema cada vez (y restaurándolo), para atribuir el
## coste. No cambia nada del proyecto.
##
## Uso: godot --path . pruebas/diagnostico_cuello.tscn

const MUNDO := "res://mundo/escena/ziba_prototipo.tscn"
const ESPERA_GENERACION := 22.0
const ASENTAR := 2.0
const MEDIR := 4.0
const VENTANA := Vector2i(1280, 720)

var _mundo: Node3D = null

func _ready() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not Engine.is_embedded_in_editor():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(VENTANA)
		await get_tree().process_frame
	print("===== DIAGNOSTICO DE CUELLO =====")
	print("gpu=", RenderingServer.get_video_adapter_name(), " ventana=", DisplayServer.window_get_size())
	_mundo = (load(MUNDO) as PackedScene).instantiate() as Node3D
	add_child(_mundo)
	await _esperar(ESPERA_GENERACION)
	_inventario()

	await _fase("base", func() -> void: pass, func() -> void: pass)

	# --- Peatones: fuera del todo (ni proceso ni dibujo) --------------------
	var npcs := _nodos_npc()
	await _fase("npcs_off",
		func() -> void:
			for n in npcs:
				n.visible = false
				n.set_process(false)
				n.set_physics_process(false),
		func() -> void:
			for n in npcs:
				n.visible = true
				n.set_process(true)
				n.set_physics_process(true))

	# --- Hierba del terreno (matas) -----------------------------------------
	var hierba := _multimesh_por_nombre("hierba")
	await _fase("hierba_off", _ocultar(hierba), _mostrar(hierba))

	# --- Bosque (árboles y arbustos por trozos) -----------------------------
	var bosque := _hijos(_nodo("Bosque"))
	await _fase("bosque_off", _ocultar(bosque), _mostrar(bosque))

	# --- Ciudad (edificios, props, marcas viales) ---------------------------
	var ciudad := _hijos(_nodo("Ciudad"))
	await _fase("ciudad_off", _ocultar(ciudad), _mostrar(ciudad))

	# --- Sombras de la luz principal ----------------------------------------
	var sol := _nodo("Sol") as DirectionalLight3D
	if sol != null:
		await _fase("sombras_off", func() -> void: sol.shadow_enabled = false,
				func() -> void: sol.shadow_enabled = true)

	# --- SSAO del entorno ---------------------------------------------------
	var entorno := _nodo("Entorno") as WorldEnvironment
	var env_orig: Environment = null
	if entorno != null and entorno.environment != null:
		env_orig = entorno.environment
		entorno.environment = env_orig.duplicate()
		var copia := entorno.environment
		print("[diag] SSAO activo=", copia.ssao_enabled, " glow=", copia.glow_enabled,
				" sdfgi=", copia.sdfgi_enabled, " vol_fog=", copia.volumetric_fog_enabled,
				" fog=", copia.fog_enabled)
		await _fase("ssao_off", func() -> void: copia.ssao_enabled = false,
				func() -> void: copia.ssao_enabled = true)
		entorno.environment = env_orig

	# --- ¿Qué cambia al APLICAR el perfil ALTA frente al estado pristino? ----
	print("--- PROYECTO (valores de sombra) ---")
	for clave in ["rendering/lights_and_shadows/directional_shadow/size",
			"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
			"rendering/lights_and_shadows/directional_shadow/use_16_bits",
			"rendering/lights_and_shadows/positional_shadow/atlas_size",
			"rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality",
			"rendering/anti_aliasing/quality/msaa_3d",
			"rendering/scaling_3d/scale"]:
		print("   ", clave, " = ", ProjectSettings.get_setting(clave, "<no definido>"))
	_volcar_estado("pristino")
	if AjustesGraficos != null and AjustesGraficos.has_method("poner_calidad"):
		AjustesGraficos.poner_calidad(2)          # ALTA
		await _esperar(1.0)
		_volcar_estado("alta_aplicada")
		await _fase("alta_aplicada", func() -> void: pass, func() -> void: pass)

	print("===== FIN DEL DIAGNOSTICO =====")
	get_tree().quit(0)

## Estado real de los ajustes que toca el perfil, para comparar sin suposiciones.
func _volcar_estado(etiqueta: String) -> void:
	var vp := get_viewport()
	var sol := _nodo("Sol") as DirectionalLight3D
	var terr := _primer("Terrain3D") as Terrain3D
	var mundo := _nodo("Entorno") as WorldEnvironment
	var sin_sombra := 0
	for n in _mundo.find_children("*", "MultiMeshInstance3D", true, false):
		if (n as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			sin_sombra += 1
	print("[estado %s] escala=%.2f lod=%.1f atlas_pos=%d | sol: sombra=%s dist=%.1f | terreno_sombra=%s | ssao=%s | multimesh_sin_sombra=%d" % [
		etiqueta, vp.scaling_3d_scale, vp.mesh_lod_threshold, vp.positional_shadow_atlas_size,
		str(sol.shadow_enabled) if sol != null else "?",
		sol.directional_shadow_max_distance if sol != null else -1.0,
		str(terr.cast_shadows) if terr != null else "?",
		str(mundo.environment.ssao_enabled) if mundo != null and mundo.environment != null else "?",
		sin_sombra])

func _primer(clase: String) -> Node:
	var l := _buscar_por_clase(clase)
	return l[0] if not l.is_empty() else null

func _buscar_por_clase(clase: String) -> Array:
	return get_tree().root.find_children("*", clase, true, false)

# ------------------------------------------------------------------ fases
func _fase(etiqueta: String, aplicar: Callable, restaurar: Callable) -> void:
	aplicar.call()
	await _esperar(ASENTAR)
	var muestras: Array[float] = []
	var proc := 0.0
	var phys := 0.0
	var draw := 0.0
	var prim := 0.0
	var obj := 0.0
	var n := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(MEDIR * 1000.0):
		await get_tree().process_frame
		muestras.append(get_process_delta_time() * 1000.0)
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		n += 1
	restaurar.call()
	await get_tree().process_frame
	if n == 0:
		print("MEDICION perfil=", etiqueta, " SIN MUESTRAS")
		return
	muestras.sort()
	var suma := 0.0
	for m in muestras:
		suma += m
	var media := suma / float(n)
	print("MEDICION perfil=%s fps=%.1f frame_ms=%.1f p95_ms=%.1f proc_ms=%.2f phys_ms=%.2f draw=%d prim=%d obj=%d" % [
		etiqueta, 1000.0 / maxf(media, 0.001), media,
		muestras[mini(n - 1, int(round(float(n) * 0.95)))],
		(proc / float(n)) * 1000.0, (phys / float(n)) * 1000.0,
		int(draw / float(n)), int(prim / float(n)), int(obj / float(n))])

# ------------------------------------------------------------------ inventario
func _inventario() -> void:
	print("--- INVENTARIO ---")
	for ruta in ["Terreno", "Bosque", "Ciudad", "Ciudad/CiudadGenerada", "Farolas"]:
		var n := _mundo.get_node_or_null(ruta)
		if n == null:
			print(ruta, ": NO EXISTE")
			continue
		print(ruta, ": tipo=", n.get_class(), " hijos=", n.get_child_count(),
				" nodos_totales=", _contar(n))
	var mms: Array = []
	for n in _mundo.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (n as MultiMeshInstance3D).multimesh
		mms.append({"ruta": String(_mundo.get_path_to(n)), "inst": mm.instance_count if mm != null else 0,
				"sup": (mm.mesh.get_surface_count() if mm != null and mm.mesh != null else 0)})
	mms.sort_custom(func(a, b): return int(a["inst"]) > int(b["inst"]))
	print("MultiMeshInstance3D: ", mms.size())
	for i in mini(18, mms.size()):
		print("   ", mms[i]["ruta"], " instancias=", mms[i]["inst"], " superficies=", mms[i]["sup"])
	var total_mi := 0
	var luces := 0
	var chars := 0
	for n in _mundo.find_children("*", "MeshInstance3D", true, false):
		total_mi += 1
	for n in _mundo.find_children("*", "Light3D", true, false):
		luces += 1
	for n in _mundo.find_children("*", "Skeleton3D", true, false):
		chars += 1
	print("MeshInstance3D=", total_mi, " luces=", luces, " esqueletos=", chars,
			" nodos_totales_mundo=", _contar(_mundo))

# ------------------------------------------------------------------ utilidad
func _contar(n: Node) -> int:
	var total := 0
	for c in n.get_children():
		total += 1 + _contar(c)
	return total

func _nodo(ruta: String) -> Node:
	return _mundo.get_node_or_null(ruta)

func _hijos(n: Node) -> Array:
	return n.get_children() if n != null else []

func _nodos_npc() -> Array:
	var out: Array = []
	for n in _mundo.find_children("*", "CharacterBody3D", true, false):
		var s: Script = n.get_script() as Script
		if s != null and String(s.resource_path).ends_with("npc_citizen.gd"):
			out.append(n)
	return out

## MultiMeshInstance3D cuya ruta contiene `texto` (la hierba del terreno).
func _multimesh_por_nombre(texto: String) -> Array:
	var out: Array = []
	for n in _mundo.find_children("*", "MultiMeshInstance3D", true, false):
		if String(_mundo.get_path_to(n)).to_lower().contains(texto):
			out.append(n)
	return out

func _ocultar(lista: Array) -> Callable:
	return func() -> void:
		for n in lista:
			n.visible = false

func _mostrar(lista: Array) -> Callable:
	return func() -> void:
		for n in lista:
			n.visible = true

func _esperar(segundos: float) -> void:
	await get_tree().create_timer(segundos, true, false, true).timeout