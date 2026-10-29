extends Node3D
## =============================================================================
##  ARNÉS DE PERFILES GRÁFICOS — VALIDACIÓN P7 (SOLO MIDE, NO PERSISTE)
## =============================================================================
##  Objetivo: decidir CON DATOS si el perfil BAJA y su cielo panorámico estático
##  son una mejora real, y descartar la contaminación por compilación de shaders
##  que invalidó la medición anterior (n=1-2, primera fase recién instanciada).
##
##  Qué hace, en orden:
##    1. Carga el mundo REAL con semilla FIJA (misma ciudad en cada corrida).
##    2. CALIENTA 12 s alternando ALTA y BAJA (compila ambos shaders, incluido el
##       del cielo dinámico y el PanoramaSkyMaterial) para que ninguna muestra
##       válida pague compilación.
##    3. VERIFICA el cielo de cada perfil: imprime la clase del `sky` efectivo y,
##       en BAJA, comprueba que el material del Sky es el PanoramaSkyMaterial.
##    4. Guarda CAPTURAS comparables (misma cámara/pose) de BAJA y ALTA.
##    5. MIDE por PARES ALTERNADOS (ALTA,BAJA / BAJA,ALTA / …): cada par mide los
##       dos perfiles seguidos para cancelar la deriva térmica del equipo.
##    6. Imprime, por perfil, n / mediana / p95 / p99 / FPS / draw / prim / obj /
##       VRAM y presenta el resumen.
##
##  NUNCA guarda en user:// : aplica el perfil escribiendo `calidad` y llamando a
##  `_aplicar_calidad()` del autoload (que NO llama a `_guardar()`). Además se debe
##  lanzar con XDG_DATA_HOME aislado, y la cabecera imprime la ruta EFECTIVA.
##
##  Uso:
##    XDG_DATA_HOME=/tmp/prismax_audit/xdg \
##      godot --path . res://pruebas/auditoria_rendimiento/arnes_perfiles.tscn
##
##  Variables de entorno:
##    PRISMAX_PERF_MUESTRA=<s>  segundos por muestra (por defecto 4)
##    PRISMAX_PERF_PARES=<n>    número de pares (por defecto 4)
##    PRISMAX_PERF_WARMUP=<s>   segundos de calentamiento (por defecto 12)
##    PRISMAX_PERF_SIN_CAPTURA=1  no guardar PNG (sólo medir)
## =============================================================================

const MUNDO := "res://mundo/escena/ziba_prototipo.tscn"
const SEMILLA := 20261011
const VENTANA := Vector2i(1280, 720)
const ESPERA_MAX_GEN := 45.0
const DIR_CAPTURAS := "res://pruebas/auditoria_rendimiento/_capturas"

# Poses reproducibles (mismas que el arnés de auditoría).
const POS_CIUDAD := Vector3(210.0, 55.0, 210.0)
const MIRA_CIUDAD := Vector3(0.0, 12.0, 0.0)
const POS_HORIZONTE := Vector3(60.0, 620.0, 620.0)
const MIRA_HORIZONTE := Vector3(-80.0, 8.0, -80.0)
const FAR_HORIZONTE := 20000.0
const FAR_TIERRA := 4000.0

const BAJA := 0
const MEDIA := 1
const ALTA := 2

var _mundo: Node = null
var _cam: Camera3D
var _ag: Node = null                 # autoload AjustesGraficos
var _muestra_s := 4.0
var _n_pares := 4
var _warmup_s := 12.0
var _capturar := true
## muestras por perfil: Array de Dictionary {med, p95, p99, fps, draw, prim, obj, vram}
var _res: Dictionary = {}

var _diag_env: Environment = null


func _ready() -> void:
	_muestra_s = _env_float("PRISMAX_PERF_MUESTRA", 4.0)
	_n_pares = int(_env_float("PRISMAX_PERF_PARES", 4.0))
	_warmup_s = _env_float("PRISMAX_PERF_WARMUP", 12.0)
	_capturar = OS.get_environment("PRISMAX_PERF_SIN_CAPTURA") != "1"
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not Engine.is_embedded_in_editor():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(VENTANA)
		await get_tree().process_frame
	_cabecera()

	_ag = get_node_or_null("/root/AjustesGraficos")
	if _ag == null:
		print("PERF|FATAL|sin autoload AjustesGraficos")
		get_tree().quit(1)
		return

	_cam = Camera3D.new()
	_cam.name = "CamPerfiles"
	_cam.near = 0.5
	add_child(_cam)

	# 1) Cargar / instanciar / añadir el mundo (semilla FIJA antes de _ready).
	var t := Time.get_ticks_usec()
	var packed := load(MUNDO) as PackedScene
	var load_ms := float(Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	_mundo = packed.instantiate()
	var inst_ms := float(Time.get_ticks_usec() - t) / 1000.0
	var ciudad := _mundo.get_node_or_null("Ciudad")
	if ciudad != null:
		ciudad.set("semilla", SEMILLA)
	t = Time.get_ticks_usec()
	add_child(_mundo)
	var add_ms := float(Time.get_ticks_usec() - t) / 1000.0
	print("PERF|phase=gen|load_ms=%.1f|instantiate_ms=%.1f|addchild_ms=%.1f" % [load_ms, inst_ms, add_ms])

	# 2) Esperar a que la generación termine (nodos dejan de crecer).
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
	print("PERF|phase=gen_ready|nodos=%d|espera_ms=%.0f" % [_contar(_mundo), float(Time.get_ticks_usec() - t) / 1000.0])

	# 3) CALENTAMIENTO: alterna ALTA y BAJA con la cámara en el horizonte para
	#    compilar el cielo dinámico Y el PanoramaSkyMaterial antes de medir.
	_poner_perfil(ALTA)
	await _esperar(_warmup_s * 0.5)
	_poner_perfil(BAJA)
	await _esperar(_warmup_s * 0.5)
	_poner_perfil(ALTA)
	print("PERF|phase=warmup_done|s=%.1f" % _warmup_s)

	# 4) VERIFICACIÓN DEL CIELO por perfil (clase del Sky efectivo).
	if _capturar:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR_CAPTURAS))
	await _verificar_cielo(ALTA)
	await _verificar_cielo(MEDIA)
	await _verificar_cielo(BAJA)

	# 5) MEDICIÓN POR PARES ALTERNADOS.
	for p in _n_pares:
		var orden := [ALTA, BAJA] if p % 2 == 0 else [BAJA, ALTA]
		print("PERF|par=%d|orden=%s" % [p, "ALTA->BAJA" if orden[0] == ALTA else "BAJA->ALTA"])
		for perfil in orden:
			await _medir(perfil, "ciudad")
	# Un par extra mirando al cielo (donde el coste del cielo pesa más).
	if _n_pares > 0:
		print("PERF|par=cielo|orden=ALTA->BAJA")
		await _medir(ALTA, "horizonte")
		await _medir(BAJA, "horizonte")

	_resumen()

	# 6) Restaurar ALTA (sin guardar) y salir.
	_poner_perfil(ALTA)
	print("PERF|FIN user_data_dir=", OS.get_user_data_dir())
	get_tree().quit(0)


# --------------------------------------------------------------- perfiles
func _poner_perfil(perfil: int) -> void:
	# Escribe `calidad` y aplica SIN persistir (no se llama a poner_calidad()).
	_ag.set("calidad", perfil)
	_ag.call("_aplicar_calidad")


func _verificar_cielo(perfil: int) -> void:
	_poner_perfil(perfil)
	# (1) Cámara al CENIT: el cielo llena el encuadre, para ver el artefacto polar.
	_cam.global_position = POS_HORIZONTE
	_cam.rotation_degrees = Vector3(72.0, 30.0, 0.0)
	_cam.far = FAR_HORIZONTE
	_cam.make_current()
	await _esperar(1.5)
	var ent := _mundo.get_node_or_null("Entorno") as WorldEnvironment
	var env: Environment = ent.environment if ent != null else null
	var clase_sky := "sin_entorno"
	var clase_mat := "-"
	if env != null and env.sky != null:
		clase_sky = env.sky.get_class()
		if env.sky.sky_material != null:
			clase_mat = env.sky.sky_material.get_class()
	print("PERF|cielo|perfil=%s|sky=%s|material=%s" % [_nombre(perfil), clase_sky, clase_mat])
	if _capturar:
		await _captura("%s_cenit.png" % _nombre(perfil).to_lower())
		# (2) Vista normal del horizonte (mirando sobre la ciudad hacia el mar).
		_cam.global_position = Vector3(320.0, 26.0, 320.0)
		_cam.look_at(Vector3(0.0, 40.0, 0.0), Vector3.UP)
		_cam.far = FAR_TIERRA
		_cam.make_current()
		await _esperar(1.5)
		await _captura("%s_vista.png" % _nombre(perfil).to_lower())


func _medir(perfil: int, pose: String) -> void:
	_poner_perfil(perfil)
	if pose == "horizonte":
		_cam.global_position = POS_HORIZONTE
		_cam.look_at(MIRA_HORIZONTE, Vector3.UP)
		_cam.far = FAR_HORIZONTE
	else:
		_cam.global_position = POS_CIUDAD
		_cam.look_at(MIRA_CIUDAD, Vector3.UP)
		_cam.far = FAR_TIERRA
	_cam.make_current()
	await _esperar(0.8)   # asentar tras el cambio de perfil
	var ms := PackedFloat32Array()
	var draw := 0.0
	var prim := 0.0
	var obj := 0.0
	var n := 0
	var t0 := Time.get_ticks_usec()
	# Ventana por tiempo, pero garantizando un mínimo de fotogramas (en esta
	# máquina cargada el proceso se desaloja y la pared del reloj avanza entre
	# fotogramas): se para al pasar la ventana CON >=15 fotogramas, o al llegar a
	# 5x la ventana. Así n nunca queda en 1-2.
	var limite := int(_muestra_s * 1e6)
	var limite_max := limite * 5
	while true:
		_cam.make_current()
		await get_tree().process_frame
		ms.append(get_process_delta_time() * 1000.0)
		draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		n += 1
		var el := int(Time.get_ticks_usec() - t0)
		if (el >= limite and n >= 15) or el >= limite_max:
			break
	var elapsed_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if n == 0:
		print("PERF|perfil=%s|pose=%s|SIN_MUESTRAS" % [_nombre(perfil), pose])
		return
	var a := Array(ms)
	a.sort()
	var med: float = a[n / 2]
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	print("PERF|perfil=%s|pose=%s|n=%d|elapsed_ms=%.0f|med=%.1f|p95=%.1f|p99=%.1f|fps=%.1f|draw=%d|prim=%d|obj=%d|vram_mb=%.0f" % [
		_nombre(perfil), pose, n, elapsed_ms, med,
		a[mini(n - 1, int(round(n * 0.95)))], a[mini(n - 1, int(round(n * 0.99)))],
		1000.0 / maxf(med, 0.001),
		int(draw / n), int(prim / n), int(obj / n), vram])
	var clave := "%s_%s" % [_nombre(perfil), pose]
	if not _res.has(clave):
		_res[clave] = []
	(_res[clave] as Array).append({"med": med, "draw": int(draw / n), "prim": int(prim / n),
			"obj": int(obj / n), "vram": vram})


func _resumen() -> void:
	print("PERF|===== RESUMEN POR PERFIL (mediana de medianas) =====")
	for pose in ["ciudad", "horizonte"]:
		for perfil in [BAJA, MEDIA, ALTA]:
			var clave := "%s_%s" % [_nombre(perfil), pose]
			if not _res.has(clave):
				continue
			var arr: Array = _res[clave]
			var meds: Array = []
			var draws: Array = []
			var prims: Array = []
			var objs: Array = []
			var vrams: Array = []
			for m in arr:
				meds.append(float(m["med"]))
				draws.append(int(m["draw"]))
				prims.append(int(m["prim"]))
				objs.append(int(m["obj"]))
				vrams.append(float(m["vram"]))
			meds.sort()
			var k := meds.size() / 2
			var med_med: float = meds[k]
			draws.sort(); prims.sort(); objs.sort(); vrams.sort()
			print("PERF|res|pose=%s|perfil=%s|n=%d|med=%.1f|fps=%.1f|draw=%d|prim=%d|obj=%d|vram_mb=%.0f" % [
				pose, _nombre(perfil), meds.size(), med_med, 1000.0 / maxf(med_med, 0.001),
				draws[k], prims[k], objs[k], vrams[k]])


# --------------------------------------------------------------- captura
func _captura(archivo: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(DIR_CAPTURAS + "/" + archivo)


# --------------------------------------------------------------- utilidad
func _nombre(perfil: int) -> String:
	return ["BAJA", "MEDIA", "ALTA"][clampi(perfil, 0, 2)]

func _env_float(nombre: String, def: float) -> float:
	var v := OS.get_environment(nombre)
	return float(v) if v != "" else def

func _esperar(seg: float) -> void:
	await get_tree().create_timer(seg, true, false, true).timeout

func _contar(n: Node) -> int:
	var t := 0
	for c in n.get_children():
		t += 1 + _contar(c)
	return t

func _cabecera() -> void:
	print("PERF|phase=header|godot=", Engine.get_version_info().string)
	print("PERF|phase=header|renderer=", ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	print("PERF|phase=header|gpu=", RenderingServer.get_video_adapter_name())
	print("PERF|phase=header|ventana=", DisplayServer.window_get_size(), "|vsync=", DisplayServer.window_get_vsync_mode())
	print("PERF|phase=header|user_data_dir=", OS.get_user_data_dir())
	print("PERF|phase=header|semilla=", SEMILLA, "|muestra_s=%.1f|pares=%d|warmup_s=%.1f" % [_muestra_s, _n_pares, _warmup_s])