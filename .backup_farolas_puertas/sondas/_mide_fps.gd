extends Node3D
## Mide FPS con el juego REAL (render real, ventana, ciudad llena) y lo imprime.
## No modifica el juego: sólo carga el prototipo, pone una cámara a la altura de un peatón
## en una calle y cuenta fotogramas durante 15 s reales con la población ya completa.

const SEMILLA := 20260707
const SEGUNDOS := 15.0

var _juego: Node = null
var _ciudad: Node = null
var _cam: Camera3D = null
var _t0 := 0
var _fase := 0
var _t_medir := 0
var _vals: Array[float] = []
var _total := 0


func _ready() -> void:
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = SEMILLA
	add_child(_juego)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.05
	add_child(_cam)
	# Vista de calle a la altura de un peatón (mira a lo largo de la acera con gente, farolas
	# y árboles en pantalla: es la carga típica del juego).
	_cam.global_position = Vector3(72.0, 1.7, -132.4)
	_cam.look_at(Vector3(96.0, 1.7, -132.4))
	_cam.make_current()
	_t0 = Time.get_ticks_msec()
	get_tree().create_timer(200.0).timeout.connect(func() -> void:
		print("[FPS] RESCATE")
		get_tree().quit())


func _process(_d: float) -> void:
	var real := float(Time.get_ticks_msec() - _t0) / 1000.0
	var dir := _ciudad.get_node_or_null("CiudadGenerada/Peatones")
	if dir == null:
		return
	_cam.make_current()
	var t := float(dir.get("_t_ahora"))
	if _fase == 0:
		var total := int(dir.call("resumen")["total"])
		# Mide en cuanto la ciudad está razonablemente llena (o, como muy tarde, a los 90 s
		# de juego: si el relleno escalonado se retrasa, se mide igual y se dice el total).
		if (t > 25.0 and total >= 60) or t > 90.0:
			_fase = 1
			_t_medir = real
			print("[FPS] midiendo %.0f s con %d ciudadanos (ventana %s, %s, vsync %s)" % [
					SEGUNDOS, total, str(DisplayServer.window_get_size()),
					RenderingServer.get_video_adapter_name(),
					str(DisplayServer.window_get_vsync_mode())])
	elif _fase == 1:
		_vals.append(Engine.get_frames_per_second())
		_total += 1
		if real - _t_medir >= SEGUNDOS:
			_fase = 2
			var suma := 0.0
			var peor := 1e9
			var mejor := 0.0
			for v in _vals:
				suma += v
				peor = minf(peor, v)
				mejor = maxf(mejor, v)
			var media := suma / maxf(float(_vals.size()), 1.0)
			_vals.sort()
			var p5 := _vals[int(float(_vals.size()) * 0.05)] if _vals.size() > 20 else peor
			print("[FPS] ciudadanos=%d | muestras=%d | media=%.1f | mejor=%.1f | peor=%.1f | p5=%.1f" % [
					int(dir.call("resumen")["total"]), _vals.size(), media, mejor, peor, p5])
			print("[FPS] estado: %s" % str(dir.call("resumen")))
			print("[FPS] fin")
			get_tree().quit()