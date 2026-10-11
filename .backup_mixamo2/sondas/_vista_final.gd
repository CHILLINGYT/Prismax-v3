extends Node3D
## Arnés de capturas temporal (render real, ejecutado desde el editor). Guarda imágenes del juego
## de verdad: caminar (perfil y frente), sentado (frente y perfil del banco) y tumbado (cenital y
## oblicua). No fuerza la actividad de nadie: espera a que los ciudadanos hagan su vida.

const DIR := "res://.backup_mixamo2/capturas"

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null
var _cam: Camera3D = null
var _t0 := 0
var _paso := 0
var _proxima := 0.0
var _limite := 0.0
var _objetivo: Node3D = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = 20260707
	add_child(_juego)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.05
	add_child(_cam)
	_cam.make_current()
	_t0 = Time.get_ticks_msec()
	print("[Vista] cargando la ciudad...")


func _process(_d: float) -> void:
	if _dir == null:
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
		return
	_cam.make_current()
	var real := float(Time.get_ticks_msec() - _t0) / 1000.0
	match _paso:
		0:
			if real > 9.0:
				print("[Vista] ciudad lista")
				_paso = 1
				_proxima = real + 0.5
		1:
			if real >= _proxima:
				_caminar("perfil")
				_capturar("cam_perfil")
				_paso = 2
				_proxima = real + 0.4
		2:
			if real >= _proxima:
				_caminar("frente")
				_capturar("cam_frente")
				_paso = 3
				_proxima = real + 0.4
		3:
			if real >= _proxima:
				_caminar("espalda")
				_capturar("cam_espalda")
				# A partir de aquí el reloj va rápido para que alguien se siente y se tumbe.
				Engine.time_scale = 8.0
				_paso = 4
				_proxima = real + 0.5
				_limite = real + 9.0
		4:
			if real >= _proxima:
				if _esperar_a("sentarse") or real > _limite:
					Engine.time_scale = 1.0
					_paso = 5
					_proxima = real + 0.4
				else:
					_proxima = real + 0.5
		5:
			if real >= _proxima:
				_sentado("frente")
				_capturar("sentado_frente")
				_paso = 6
				_proxima = real + 0.4
		6:
			if real >= _proxima:
				_sentado("lado")
				_capturar("sentado_perfil")
				Engine.time_scale = 8.0
				_paso = 7
				_proxima = real + 0.5
				_limite = real + 9.0
		7:
			if real >= _proxima:
				if _esperar_a("recostarse") or real > _limite:
					Engine.time_scale = 1.0
					_paso = 8
					_proxima = real + 0.4
				else:
					_proxima = real + 0.5
		8:
			if real >= _proxima:
				_tumbado("cenital")
				_capturar("tumb_cenital")
				_paso = 9
				_proxima = real + 0.4
		9:
			if real >= _proxima:
				_tumbado("oblicua")
				_capturar("tumb_oblicua")
				print("[Vista] fin")
				get_tree().quit()


## Elige un ciudadano por su estado y devuelve si hay alguno.
func _esperar_a(postura: String) -> bool:
	for c in _dir.peatones:
		if c.en_postura() and c.fase_postura() == "reposar" and c.postura_actual() == postura:
			return true
	return false


func _caminar(tipo: String) -> void:
	var c: Node3D = null
	for p in _dir.peatones:
		if p.is_walking() and p.velocidad_real() > 0.6:
			c = p
			break
	if c == null:
		print("[Vista] nadie andando")
		return
	_objetivo = c
	var avance: Vector3 = Basis(Vector3.UP, c.rotation.y) * Vector3(0, 0, 1)
	var lado: Vector3 = avance.cross(Vector3.UP).normalized()
	match tipo:
		"perfil":
			_cam.global_position = c.global_position + lado * 3.4 + Vector3.UP * 1.45
		"frente":
			_cam.global_position = c.global_position + avance * 3.4 + Vector3.UP * 1.45
		_:
			_cam.global_position = c.global_position - avance * 3.4 + Vector3.UP * 1.45
	_cam.look_at(c.global_position + Vector3.UP * 0.95)
	print("[Vista] caminar %s: %s modelo %s vel %.2f" % [tipo, c.name,
			String((c as Object).model_scene.resource_path).get_file(), (c as Object).velocidad_real()])


func _postura(postura: String) -> Node3D:
	for p in _dir.peatones:
		if p.en_postura() and p.fase_postura() == "reposar" and p.postura_actual() == postura:
			return p
	return null


func _sentado(tipo: String) -> void:
	var c := _postura("sentarse")
	if c == null:
		print("[Vista] nadie sentado")
		return
	_objetivo = c
	var ref := int((c as Object).get("_postura_ref"))
	var asiento: Dictionary = _dir._asientos[ref] if ref >= 0 and ref < _dir._asientos.size() else {}
	var punto: Vector3 = asiento.get("pos", c.global_position)
	var giro := _giro_banco(punto)
	var frente: Vector3 = Basis(Vector3.UP, giro) * Vector3(0, 0, -1)
	var lado: Vector3 = frente.cross(Vector3.UP).normalized()
	if tipo == "frente":
		_cam.global_position = punto + frente * 3.3 + Vector3.UP * 1.55
	else:
		_cam.global_position = punto + lado * 3.0 + Vector3.UP * 1.2
	_cam.look_at(punto + Vector3.UP * 0.8)
	print("[Vista] sentado %s: modelo %s" % [tipo,
			String((c as Object).model_scene.resource_path).get_file()])


func _tumbado(tipo: String) -> void:
	var c := _postura("recostarse")
	if c == null:
		print("[Vista] nadie tumbado")
		return
	_objetivo = c
	var ref := int((c as Object).get("_postura_ref"))
	var lug: Dictionary = _dir._reposeras[ref] if ref >= 0 and ref < _dir._reposeras.size() else {}
	var base: Vector3 = lug.get("pos", c.global_position)
	var yaw := float(lug.get("yaw", 0.0))
	var eje: Vector3 = Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)
	var lado: Vector3 = eje.cross(Vector3.UP).normalized()
	if tipo == "cenital":
		_cam.global_position = base + Vector3.UP * 3.5 + lado * 0.4
		_cam.look_at(base + Vector3.UP * 0.1)
	else:
		_cam.global_position = base + lado * 2.6 + Vector3.UP * 1.7 - eje * 0.5
		_cam.look_at(base + Vector3.UP * 0.3)
	print("[Vista] tumbado %s: modelo %s" % [tipo,
			String((c as Object).model_scene.resource_path).get_file()])


func _giro_banco(p: Vector3) -> float:
	var mejor := 9999.0
	var giro := 0.0
	for n in _ciudad.find_children("Banco*", "StaticBody3D", true, false):
		var d := (n as Node3D).global_position.distance_to(p)
		if d < mejor:
			mejor = d
			giro = (n as Node3D).rotation.y
	return giro


func _capturar(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [DIR, nombre])
	print("[Vista] captura %s -> %s" % [nombre, "OK" if err == OK else str(err)])