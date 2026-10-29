extends Node3D
## =============================================================================
##  ARNÉS AISLADO DEL CIELO — ¿el PanoramaSkyMaterial de BAJA cuesta menos por
##  fotograma que el shader dinámico de ALTA/MEDIA?
## =============================================================================
##  Escena MÍNIMA (sin ciudad): sólo WorldEnvironment + cámara mirando al cielo.
##  Así la memoria es ínfima y el equipo (3,5 GB, en swap) NO desaloja el proceso,
##  a diferencia del mundo completo. Aísla el coste del CIELO.
##
##  Mide, alternando en PARES (ALTA,BAJA / BAJA,ALTA / …) para cancelar la deriva
##  térmica, el tiempo de fotograma con:
##      · dinámico : res://Cielo/cielo_ciudad.tres (ShaderMaterial del addon)
##      · estatico : res://Cielo/cielo_panorama_baja.tres (PanoramaSkyMaterial)
##
##  Uso:
##    XDG_DATA_HOME=/tmp/prismax_audit/xdg \
##      godot --path . res://pruebas/auditoria_rendimiento/arnes_cielo.tscn
##  Variables: PRISMAX_CIELO_N=<pares> (12) · PRISMAX_CIELO_WIN=<s> (1.5)
##             PRISMAX_CIELO_WARMUP=<s> (4) · PRISMAX_CIELO_CAPTURA=1
## =============================================================================

const CIELO_DINAMICO := "res://Cielo/cielo_ciudad.tres"
const CIELO_ESTATICO := "res://Cielo/cielo_panorama_baja.tres"
const DIR_CAPTURAS := "res://pruebas/auditoria_rendimiento/_capturas"

var _env: Environment
var _sky_din: Sky
var _sky_est: Sky
var _cam: Camera3D
var _n := 12
var _win := 1.5
var _warmup := 4.0
var _capturar := false
var _res: Array = []   # [{"perfil":..,"med":..,"draw":..,"prim":..}]


func _ready() -> void:
	_n = int(_f("PRISMAX_CIELO_N", 12.0))
	_win = _f("PRISMAX_CIELO_WIN", 1.5)
	_warmup = _f("PRISMAX_CIELO_WARMUP", 4.0)
	_capturar = OS.get_environment("PRISMAX_CIELO_CAPTURA") == "1"
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not Engine.is_embedded_in_editor():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await get_tree().process_frame
	print("CIELO|header|gpu=", RenderingServer.get_video_adapter_name(), "|user_data_dir=", OS.get_user_data_dir())
	print("CIELO|header|n=%d|win=%.2f|warmup=%.1f" % [_n, _win, _warmup])

	_sky_din = (load(CIELO_DINAMICO) as Sky).duplicate() as Sky
	# El shader dinámico del juego recibe los uniformes del puente Sky3DPuente; en
	# esta escena aislada se fijan a un sol diurno para que RENDERICE como de día
	# (si no, la parte del cielo podría quedar negra y con coste distinto).
	if _sky_din.sky_material is ShaderMaterial:
		var m := _sky_din.sky_material as ShaderMaterial
		m.set_shader_parameter("sun_direction", Vector3(0.35, 0.72, 0.6).normalized())
		m.set_shader_parameter("moon_direction", Vector3(-0.35, -0.72, -0.6).normalized())
		m.set_shader_parameter("sun_visibility", 1.0)
		m.set_shader_parameter("moon_visibility", 0.0)
		m.set_shader_parameter("sun_light_color", Color(1, 0.95, 0.9))
	_sky_est = load(CIELO_ESTATICO) as Sky

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.sky = _sky_din
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_cam = Camera3D.new()
	_cam.near = 0.1
	_cam.far = 20000.0
	# Mirando hacia arriba: cobertura de cielo alta y estable (lo que domina el coste).
	_cam.rotation_degrees = Vector3(-78.0, 20.0, 0.0)
	add_child(_cam)
	_cam.make_current()

	if _capturar:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR_CAPTURAS))

	# Calentamiento: compila ambos materiales y genera el cubemap del panorama.
	for i in int(_warmup):
		_poner("dinamico"); await _esperar(0.5)
		_poner("estatico"); await _esperar(0.5)
	_poner("dinamico")
	print("CIELO|warmup_done")

	if _capturar:
		for etiqueta in ["dinamico", "estatico", "dinamico2", "estatico2"]:
			var modo := "estatico" if etiqueta.begins_with("estatico") else "dinamico"
			_poner(modo); await _esperar(1.0)
			var mat := _env.sky.sky_material
			var pan: Texture2D = (mat as PanoramaSkyMaterial).panorama if mat is PanoramaSkyMaterial else null
			print("CIELO|cap|%s|mat=%s|panorama=%s" % [etiqueta, mat.get_class(), str(pan)])
			await _captura("cielo_%s.png" % etiqueta)
		# Prueba decisiva de si la CAPTURA refleja el estado actual: fondo rojo.
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = Color(1, 0, 0)
		await _esperar(1.0)
		await _captura("cielo_prueba_color.png")
		_env.background_mode = Environment.BG_SKY

	# Pares alternados.
	for p in _n:
		var orden := ["dinamico", "estatico"] if p % 2 == 0 else ["estatico", "dinamico"]
		print("CIELO|par=%d|orden=%s" % [p, "->".join(orden)])
		for modo in orden:
			await _medir(modo)

	_resumen()
	print("CIELO|FIN")
	get_tree().quit(0)


func _poner(modo: String) -> void:
	_env.sky = _sky_est if modo == "estatico" else _sky_din
	_cam.make_current()


func _medir(modo: String) -> void:
	_poner(modo)
	await _esperar(0.35)
	var ms := PackedFloat32Array()
	var draw := 0.0
	var n := 0
	var t0 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - t0) < _win * 1e6:
		_cam.make_current()
		await get_tree().process_frame
		ms.append(get_process_delta_time() * 1000.0)
		draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		n += 1
	var a := Array(ms)
	a.sort()
	var med: float = a[n / 2] if n > 0 else 0.0
	print("CIELO|perfil=%s|n=%d|med=%.3f|p95=%.3f|fps=%.1f|draw=%d" % [
		modo, n, med, a[mini(n - 1, int(round(n * 0.95)))] if n > 0 else 0.0,
		1000.0 / maxf(med, 0.001), int(draw / maxi(n, 1))])
	_res.append({"perfil": modo, "med": med, "draw": int(draw / maxi(n, 1))})


func _resumen() -> void:
	for modo in ["dinamico", "estatico"]:
		var vals: Array = []
		var draws: Array = []
		for r in _res:
			if r["perfil"] == modo:
				vals.append(float(r["med"])); draws.append(int(r["draw"]))
		if vals.is_empty():
			continue
		vals.sort(); draws.sort()
		var k := vals.size() / 2
		print("CIELO|res|perfil=%s|n=%d|med=%.3f|fps=%.1f|draw=%d" % [
			modo, vals.size(), vals[k], 1000.0 / maxf(vals[k], 0.001), draws[k]])


func _captura(archivo: String) -> void:
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(DIR_CAPTURAS + "/" + archivo)

func _f(nombre: String, def: float) -> float:
	var v := OS.get_environment(nombre)
	return float(v) if v != "" else def

func _esperar(seg: float) -> void:
	await get_tree().create_timer(seg, true, false, true).timeout