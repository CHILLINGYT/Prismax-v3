extends Node3D
## Arnés de capturas TEMPORAL (render real, lanzado como instancia propia de Godot).
## Guarda imágenes del juego de verdad con los cambios de esta pasada:
##   · farol de acera (frente y perfil), farol de esquina, farol de parque,
##   · calle general con farolas y gente,
##   · entrada de un ciudadano en una casa: parado frente a la puerta, desvaneciéndose y ya dentro.
## No modifica el juego: sólo mira, encuadra y guarda PNG.

const DIR := "res://.backup_farolas_puertas/capturas"
const SEMILLA := 20260707

var _juego: Node = null
var _ciudad: Node = null
var _far: Node = null
var _dir: Node = null
var _cam: Camera3D = null
var _t0 := 0
var _paso := 0
var _proxima := 0.0
var _limite := 0.0
var _objetivo: Node3D = null
var _puerta: Dictionary = {}
var _id_objetivo := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = SEMILLA
	_far = _juego.get_node_or_null("Farolas")
	add_child(_juego)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.05
	add_child(_cam)
	_cam.make_current()
	_t0 = Time.get_ticks_msec()
	print("[Vista] cargando la ciudad...")
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[Vista] RESCATE")
		get_tree().quit())


func _process(_d: float) -> void:
	if _dir == null:
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
		return
	if _far.get_node_or_null("FarolasColision") == null:
		return
	_cam.make_current()
	var real := float(Time.get_ticks_msec() - _t0) / 1000.0
	match _paso:
		0:
			_paso = 1
			_proxima = real + 0.5
		1:
			if real >= _proxima:
				_farol_acera("frente")
				_capturar("farol_acera")
				_paso = 2
				_proxima = real + 0.5
		2:
			if real >= _proxima:
				_farol_acera("perfil")
				_capturar("farol_acera_perfil")
				_paso = 3
				_proxima = real + 0.5
		3:
			if real >= _proxima:
				_farol_esquina()
				_capturar("farol_esquina")
				_paso = 4
				_proxima = real + 0.5
		4:
			if real >= _proxima:
				_farol_parque()
				_capturar("farol_parque")
				_paso = 5
				_proxima = real + 0.5
		5:
			if real >= _proxima:
				_calle()
				_capturar("calle_general")
				# A partir de aquí, entradas forzadas para poder capturar la secuencia.
				_dir.set("entrar_prob", 1.0)
				_dir.set("entrar_prob_tarde", 1.0)
				_dir.set("entrar_max", 6)
				Engine.time_scale = 4.0
				_paso = 6
				_proxima = real + 0.5
				_limite = real + 40.0
		6:
			if real >= _proxima:
				var c := _buscando_entrada(["camino", "acercarse"])
				if c != null:
					_objetivo = c
					_id_objetivo = c.get_instance_id()
					# Tiempo lento mientras se sigue al ciudadano: si no, las fases "mirar"
					# y "penetrar" pasan entre dos sondeos y no se pueden capturar.
					Engine.time_scale = 0.7
					_paso = 7
					_proxima = real + 0.4
				else:
					_proxima = real + 0.5
					if real > _limite:
						print("[Vista] nadie va a una puerta")
						get_tree().quit()
		7:
			if real >= _proxima:
				var fase := _fase_objetivo()
				if fase == "mirar":
					_encuadrar_puerta(4.6, 1.7)
					Engine.time_scale = 0.5
					_capturar("entrada_mirar")
					_paso = 8
					_proxima = real + 0.3
				elif fase == "":
					_paso = 6
				else:
					_proxima = real + 0.25
		8:
			if real >= _proxima:
				var fase2 := _fase_objetivo()
				if fase2 == "penetrar":
					var t_post := float(_objetivo.get("_postura_t"))
					if t_post > 0.78:
						var alpha := _alpha_objetivo()
						_encuadrar_puerta(4.6, 1.7)
						_capturar("entrada_fade")
						print("[Vista] fundido: t=%.2f alpha=%.2f (el cuerpo se desvanece)" % [t_post, alpha])
						Engine.time_scale = 4.0
						_paso = 9
						_proxima = real + 0.4
				elif fase2 == "":
					_paso = 6
				else:
					_proxima = real + 0.1
		9:
			if real >= _proxima:
				_encuadrar_puerta(4.2, 1.7)
				_capturar("entrada_puerta_final")
				_paso = 10
				_proxima = real + 0.5
		10:
			if real >= _proxima:
				Engine.time_scale = 1.0
				_calle()
				_capturar("calle_final")
				# Configuración de vuelta, por si esta instancia dejara nada abierto.
				_dir.set("entrar_prob", 0.012)
				_dir.set("entrar_prob_tarde", 0.022)
				_dir.set("entrar_max", 3)
				print("[Vista] fin")
				get_tree().quit()


func _esperando() -> bool:
	return false


## Farola de acera: la primera del listado que esté a 6,45 m del eje del vial.
func _farol_acera(tipo: String) -> void:
	var col := _far.get_node_or_null("FarolasColision")
	var tra: Dictionary = _ciudad.get("_trazado")
	var x0: float = float(tra["off"].x)
	var z0: float = float(tra["off"].y)
	var paso: float = float(tra["paso"])
	for n in col.get_children():
		var p: Vector3 = (n as CollisionShape3D).position
		var dx := absf(p.x - (x0 + roundf((p.x - x0) / paso) * paso))
		var dz := absf(p.z - (z0 + roundf((p.z - z0) / paso) * paso))
		if absf(minf(dx, dz) - 6.45) > 0.06:
			continue
		var hacia := Vector3.ZERO
		if dx < dz:
			hacia = Vector3(signf((x0 + roundf((p.x - x0) / paso) * paso) - p.x), 0.0, 0.0)
		else:
			hacia = Vector3(0.0, 0.0, signf((z0 + roundf((p.z - z0) / paso) * paso) - p.z))
		if tipo == "frente":
			_cam.global_position = p + hacia * 5.5 + Vector3.UP * 1.75
		else:
			var largo := Vector3(hacia.z, 0.0, -hacia.x)
			_cam.global_position = p + largo * 5.0 + hacia * 2.2 + Vector3.UP * 1.75
		_cam.look_at(p + Vector3.UP * 2.7)
		print("[Vista] farol de acera %s en (%.1f,%.1f) d_eje=%.2f" % [tipo, p.x, p.z, minf(dx, dz)])
		return
	print("[Vista] no encontré farola de acera")


func _farol_esquina() -> void:
	var col := _far.get_node_or_null("FarolasColision")
	var tra: Dictionary = _ciudad.get("_trazado")
	var x0: float = float(tra["off"].x)
	var z0: float = float(tra["off"].y)
	var paso: float = float(tra["paso"])
	for n in col.get_children():
		var p: Vector3 = (n as CollisionShape3D).position
		var xl: float = x0 + roundf((p.x - x0) / paso) * paso
		var zl: float = z0 + roundf((p.z - z0) / paso) * paso
		if absf(absf(p.x - xl) - 6.85) < 0.06 and absf(absf(p.z - zl) - 6.85) < 0.06:
			# Vista de tres cuartos desde el cruce: la farola contra la esquina del edificio, con
			# el paso de cebra delante. Es la orientación de esquina de siempre (sin tocar).
			var fuera := (p - Vector3(xl, 0.0, zl)).normalized()
			var lado := Vector3(fuera.z, 0.0, -fuera.x)
			_cam.global_position = p + fuera * -7.0 + lado * 3.5 + Vector3.UP * 1.9
			_cam.look_at(p + Vector3.UP * 2.3)
			print("[Vista] farol de esquina en (%.1f,%.1f) cruce en (%.1f,%.1f)" % [p.x, p.z, xl, zl])
			return
	print("[Vista] no encontré farola de esquina")


func _farol_parque() -> void:
	var parques: Array = _ciudad.get("_parques_datos")
	var col := _far.get_node_or_null("FarolasColision")
	var obs: Array = _ciudad.get("_obstaculos_peatones")
	# Se elige la farola de parque MÁS DESPEJADA (la que tiene el árbol más lejos): en los
	# parques las farolas quedan entre el arbolado y una puede estar tapada por una copa.
	var mejor := Vector3.ZERO
	var mejor_hueco := -1e9
	for n in col.get_children():
		var p: Vector3 = (n as CollisionShape3D).position
		var en_parque := false
		for rc: Rect2 in parques:
			if rc.grow(-0.5).has_point(Vector2(p.x, p.z)):
				en_parque = true
				break
		if not en_parque:
			continue
		var hueco := 1e9
		for o: Dictionary in obs:
			hueco = minf(hueco, Vector2(float(o["x"]) - p.x, float(o["z"]) - p.z).length())
		if hueco > mejor_hueco:
			mejor_hueco = hueco
			mejor = p
	if mejor_hueco < -1e8:
		print("[Vista] no encontré farola de parque")
		return
	# Vista baja y oblicua desde el césped: el poste se ve bajo la copa de los árboles.
	var centro := Vector3.ZERO
	for rc2: Rect2 in parques:
		if rc2.grow(-0.5).has_point(Vector2(mejor.x, mejor.z)):
			centro = Vector3(rc2.get_center().x, 0.0, rc2.get_center().y)
			break
	var hacia_centro := (centro - mejor).normalized()
	_cam.global_position = mejor + hacia_centro * 7.0 + Vector3.UP * 1.7
	_cam.look_at(mejor + Vector3.UP * 2.2)
	print("[Vista] farol de parque en (%.1f,%.1f), árbol más cercano a %.2f m" % [
			mejor.x, mejor.z, mejor_hueco])


## Vista general de una calle con farolas y peatones.
func _calle() -> void:
	var col := _far.get_node_or_null("FarolasColision")
	var cual := (col.get_child_count() / 3) as int
	var p: Vector3 = (col.get_child(cual) as CollisionShape3D).position
	_cam.global_position = p + Vector3(14.0, 6.0, 14.0)
	_cam.look_at(p + Vector3.UP * 1.0)
	print("[Vista] calle general sobre (%.1f,%.1f)" % [p.x, p.z])


func _buscando_entrada(fases: Array) -> Node3D:
	for c in _dir.get("peatones"):
		if not is_instance_valid(c):
			continue
		if c.en_postura() and c.postura_actual() == "entrar" and fases.has(String(c.fase_postura())):
			return c
	return null


func _fase_objetivo() -> String:
	if _objetivo == null or not is_instance_valid(_objetivo):
		return ""
	return String(_objetivo.get("_postura_fase"))


## Alfa actual del material con el que se funde el ciudadano objetivo (1 = opaco).
func _alpha_objetivo() -> float:
	if _objetivo == null:
		return -1.0
	var mats: Array = _objetivo.get("_fade_mats")
	if mats.is_empty():
		return -1.0
	return (mats[0] as StandardMaterial3D).albedo_color.a


## Encuadra la puerta del ciudadano objetivo: mira su punto de parada desde el lado.
func _encuadrar_puerta(dist: float, alto: float) -> void:
	if _objetivo == null:
		return
	var pie: Vector3 = _objetivo.get("_postura_punto_ini")
	var dir: Vector3 = _objetivo.get("_postura_dir")
	var lado := Vector3(dir.z, 0.0, -dir.x).normalized()
	_cam.global_position = pie + dir * dist + lado * 2.0 + Vector3.UP * alto
	_cam.look_at(pie + Vector3.UP * 1.3)
	print("[Vista] puerta: pie=(%.1f,%.1f) dir=(%.2f,%.2f) fase=%s" % [
			pie.x, pie.z, dir.x, dir.z, _fase_objetivo()])


func _capturar(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [DIR, nombre])
	print("[Vista] captura %s -> %s" % [nombre, "OK" if err == OK else str(err)])