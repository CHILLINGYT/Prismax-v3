extends Node
## MEDICIÓN + FOTOS del modo de ambiente (REALISTA vs PS2) en el MUNDO REAL.
## Ventana 1280x720, sin vsync ni tope de FPS, ciudad con semilla fija. Mide por
## PARES alternados (R, P, R, P) para que la deriva térmica pese igual en ambos.
## Comprueba además que PS2 se aplica/retira bien. Restaura la preferencia del
## jugador y se cierra sola.
##   godot --path . res://_tests/medir_ambiente_ps2.tscn   (con timeout externo)

const MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"
const CFG := "user://ajustes_graficos.cfg"
const SEMILLA := 20261011
const MEDIR := 4.0
const ASENTAR := 1.5
var _ok := 0
var _fallos := 0
var _copia := PackedByteArray()


func _ready() -> void:
	call_deferred("_correr")


func _correr() -> void:
	_copia = FileAccess.get_file_as_bytes(CFG) if FileAccess.file_exists(CFG) else PackedByteArray()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not Engine.is_embedded_in_editor():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var tam := Vector2i(1280, 720)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--res="):
				var p := a.trim_prefix("--res=").split("x")
				tam = Vector2i(int(p[0]), int(p[1]))
		DisplayServer.window_set_size(tam)
	AjustesGraficos.poner_modo_ambiente(AjustesGraficos.Ambiente.REALISTA)
	var vieja := get_tree().current_scene
	reparent(get_tree().root)
	var mundo := (load(MUNDO) as PackedScene).instantiate()
	var ciudad := mundo.get_node_or_null("Ciudad")
	if ciudad != null:
		ciudad.set("semilla", SEMILLA)
	get_tree().root.add_child(mundo)
	get_tree().current_scene = mundo
	if vieja != null and vieja != self:
		vieja.queue_free()
	# Espera a que la ciudad termine (sondeo, con tope), no a ciegas.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
		var est: Variant = ciudad.get("_est") if ciudad != null else null
		if est is Dictionary and int(est.get("ciudad_lista", 0)) == 1:
			break
	await _esperar(3.0)
	var ciclo := get_tree().get_first_node_in_group("ciclo_dia_noche")
	if ciclo != null:
		ciclo.call("poner_fase", ciclo.call("fase_dia_pleno"))
	print("[ps2] mundo listo en %.1f s | gpu=%s | ventana=%s" % [
			float(Time.get_ticks_msec() - t0) / 1000.0, RenderingServer.get_video_adapter_name(),
			str(DisplayServer.window_get_size())])
	var vp := get_viewport()
	var esc_r := vp.scaling_3d_scale
	var bias_r := vp.texture_mipmap_bias
	# --- Medición por pares ---------------------------------------------------
	var res := {"REALISTA": [], "PS2": []}
	for vuelta in 2:
		for modo in [0, 1]:
			AjustesGraficos.poner_modo_ambiente(modo)
			var m := await _medir()
			res[AjustesGraficos.AMBIENTE_NOMBRES[modo]].append(m)
			print("MEDICION modo=%s v%d fps=%.1f med_ms=%.2f p95_ms=%.2f draw=%d prim=%d escala=%.3f" % [
					AjustesGraficos.AMBIENTE_NOMBRES[modo], vuelta + 1, m["fps"], m["med"], m["p95"],
					m["draw"], m["prim"], vp.scaling_3d_scale])
	# --- Experimento (sólo diagnóstico): palancas extra sobre PS2 -------------
	if "--experimento" in OS.get_cmdline_user_args():
		AjustesGraficos.poner_modo_ambiente(1)
		var sol: DirectionalLight3D = get_tree().root.find_children("*", "DirectionalLight3D", true, false)[0]
		sol.shadow_enabled = false
		var m1 := await _medir()
		print("EXPERIMENTO ps2+sin_sombra_sol fps=%.1f draw=%d prim=%d proc=%.2f phys=%.2f" % [m1["fps"], m1["draw"], m1["prim"], m1["proc"], m1["phys"]])
		vp.get_camera_3d().far = 250.0
		var m2 := await _medir()
		print("EXPERIMENTO ps2+sin_sombra+far250 fps=%.1f draw=%d prim=%d" % [m2["fps"], m2["draw"], m2["prim"]])
		sol.shadow_enabled = true
		var m3 := await _medir()
		print("EXPERIMENTO ps2+far250 (con sombra) fps=%.1f draw=%d prim=%d proc=%.2f phys=%.2f" % [m3["fps"], m3["draw"], m3["prim"], m3["proc"], m3["phys"]])
		AjustesGraficos.poner_modo_ambiente(0)
		var m4 := await _medir()
		print("EXPERIMENTO realista fps=%.1f proc=%.2f phys=%.2f" % [m4["fps"], m4["proc"], m4["phys"]])
	# --- Comprobaciones -------------------------------------------------------
	AjustesGraficos.poner_modo_ambiente(1)
	await get_tree().process_frame
	var capa := AjustesGraficos.get_node_or_null("AmbientePS2") as CanvasLayer
	_check(capa != null and capa.visible, "PS2: el post-proceso está activo con mundo 3D")
	_check(capa != null and capa.layer < 5, "PS2: el post-proceso va por DEBAJO del HUD (capa %d)" % (capa.layer if capa else -1))
	var lineas: float = float(vp.size.y) * vp.scaling_3d_scale
	_check(absf(lineas - 448.0) < 2.0, "PS2: el 3D se dibuja a ~448 líneas (%.1f)" % lineas)
	var cam := vp.get_camera_3d()
	_check(cam != null and cam.far <= 450.5, "PS2: distancia de dibujo corta (far %.0f m)" % (cam.far if cam else -1.0))
	var cm := get_tree().root.find_children("CamaraMinimapa", "Camera3D", true, false)
	var cam_m: Camera3D = cm[0] as Camera3D if not cm.is_empty() else null
	_check(cam_m != null and cam_m.environment != null and not cam_m.environment.fog_enabled,
			"PS2: el minimapa usa un entorno SIN niebla (%s)" % ("sin cámara" if cam_m == null else str(cam_m.environment)))
	await _esperar(1.0)
	await _foto("ps2_dia")
	if ciclo != null:
		ciclo.call("poner_fase", 0.85)
	await _esperar(0.6)
	await _foto("ps2_noche")
	AjustesGraficos.poner_modo_ambiente(0)
	await _esperar(0.6)
	await _foto("realista_noche")
	if ciclo != null:
		ciclo.call("poner_fase", ciclo.call("fase_dia_pleno"))
	await _esperar(0.6)
	await _foto("realista_dia")
	_check(capa != null and not capa.visible, "REALISTA: sin post-proceso")
	_check(is_equal_approx(vp.scaling_3d_scale, esc_r) and is_equal_approx(vp.texture_mipmap_bias, bias_r),
			"REALISTA: escala y bias vuelven exactamente (%.2f / %.2f)" % [vp.scaling_3d_scale, vp.texture_mipmap_bias])
	# --- Resumen --------------------------------------------------------------
	var fr := (float(res["REALISTA"][0]["fps"]) + float(res["REALISTA"][1]["fps"])) * 0.5
	var fp := (float(res["PS2"][0]["fps"]) + float(res["PS2"][1]["fps"])) * 0.5
	print("RESUMEN fps REALISTA=%.1f PS2=%.1f mejora=%+.0f%%" % [fr, fp, (fp / maxf(fr, 0.01) - 1.0) * 100.0])
	print("==================== AMBIENTE PS2: %d OK / %d FALLO ====================" % [_ok, _fallos])
	_restaurar()
	get_tree().quit()


func _medir() -> Dictionary:
	await _esperar(ASENTAR)
	var muestras: Array[float] = []
	var draw := 0.0
	var prim := 0.0
	var proc := 0.0
	var phys := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(MEDIR * 1000.0):
		await get_tree().process_frame
		muestras.append(get_process_delta_time() * 1000.0)
		draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	muestras.sort()
	var n := muestras.size()
	var med := muestras[n / 2]
	return {"fps": 1000.0 / maxf(med, 0.001), "med": med,
			"p95": muestras[mini(n - 1, int(n * 0.95))], "draw": int(draw / n), "prim": int(prim / n),
			"proc": proc / n * 1000.0, "phys": phys / n * 1000.0}


func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://_tests/capturas/ambiente_%s.png" % nombre))


func _esperar(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _restaurar() -> void:
	if _copia.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	else:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		f.store_buffer(_copia)
		f.close()


func _check(c: bool, t: String) -> void:
	if c:
		_ok += 1
		print("[ps2] OK   ", t)
	else:
		_fallos += 1
		print("[ps2] FALLO ", t)
