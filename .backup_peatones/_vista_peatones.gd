extends Node3D
## Vista de PRUEBAS del sistema de peatones (temporal, no forma parte del juego).
##
## Carga la escena real del juego (ziba_prototipo), deja pasar tiempo de juego para que
## los ciudadanos se pongan en faena y guarda capturas en disco:
##   1) peatones andando por la vereda y cruzando por el paso pintado,
##   2) alguien sentado en un banco de plaza,
##   3) alguien tumbado en una reposera de la playa,
##   4) la playa DE NOCHE (nadie al sol: reposeras vacías).
## Termina sola y deja los PNG en res://.backup_peatones/capturas/.

const DIR_CAP := "res://.backup_peatones/capturas"

var _juego: Node = null
var _ciudad: Node = null
var _ciclo: Node = null
var _dir: Node = null
var _cam: Camera3D = null
var _t0 := 0
var _paso := 0
var _proxima := 0.0
var _limite := 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR_CAP))
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = 20260707
	_ciclo = _juego.get_node("CicloDiaNoche")
	add_child(_juego)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.near = 0.08
	add_child(_cam)
	_cam.make_current()
	_t0 = Time.get_ticks_msec()
	# Los primeros segundos van acelerados (x12) para que la gente se siente, se tumbe
	# y pasee; después se vuelve a velocidad normal para las fotos.
	Engine.time_scale = 12.0
	print("[VistaPeatones] cargada; esperando a la ciudad...")


func _process(_delta: float) -> void:
	if _dir == null:
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
		if _dir == null:
			return
	_cam.make_current()
	var real := float(Time.get_ticks_msec() - _t0) / 1000.0
	match _paso:
		0:
			if real > 7.0:
				Engine.time_scale = 1.0
				_paso = 1
				_proxima = real + 0.6
		1:
			if real >= _proxima:
				_vista_calle()
				_capturar("cap1_calle_vereda")
				_paso = 2
				_proxima = real + 1.2
		2:
			if real >= _proxima:
				_vista_sentado()
				_capturar("cap2_banco_plaza")
				_paso = 3
				_limite = real + 5.0
				_proxima = real
				Engine.time_scale = 3.0   # mientras se espera, el juego sigue corriendo
		3:
			# Se espera (con el reloj acelerado) a que alguien esté tumbado de verdad.
			if real >= _proxima:
				if _vista_tumbado() or real > _limite:
					Engine.time_scale = 1.0
					_capturar("cap3_reposera_playa")
					_paso = 31
					_proxima = real + 0.5
				else:
					_proxima = real + 0.5
		31:
			if real >= _proxima:
				_vista_tumbado_cerca()
				_capturar("cap5_tumbado_cerca")
				_paso = 4
				_proxima = real + 0.8
		4:
			if real >= _proxima:
				_ciclo._fase = 0.86      # noche cerrada: todos deben retirarse
				Engine.time_scale = 10.0
				_paso = 5
				_proxima = real + 2.2
		5:
			if real >= _proxima:
				Engine.time_scale = 1.0
				_paso = 6
				_proxima = real + 0.5
		6:
			if real >= _proxima:
				_vista_playa_noche()
				_capturar("cap4_playa_noche")
				_paso = 7
				_proxima = real + 0.5
		7:
			if real >= _proxima:
				print("[VistaPeatones] fin")
				get_tree().quit()


## Vista 1: peatones por la acera y, si hay suerte, cruzando por el paso pintado.
func _vista_calle() -> void:
	var cruce: Object = null
	var acera: Object = null
	for c in _dir.peatones:
		if not c.is_walking():
			continue
		var t: Array = c.tramo_red()
		var clase := String(t[2]) if t.size() >= 3 else ""
		if clase == "cruce" and cruce == null:
			cruce = c
		elif acera == null:
			acera = c
	var elegido: Object = cruce if cruce != null else acera
	if elegido == null:
		return
	var p: Vector3 = elegido.global_position
	_cam.global_position = p + Vector3(-6.5, 3.0, -6.5)
	_cam.look_at(p + Vector3.UP * 0.8)
	print("[VistaPeatones] vista 1 sobre %s" % ("un cruce" if cruce != null else "una acera"))


## Vista 2: un ciudadano sentado en un banco (plaza o parque).
func _vista_sentado() -> void:
	var hallado := false
	for c in _dir.peatones:
		if c.en_postura() and c.fase_postura() == "reposar" and c.postura_actual() == "sentarse":
			var p: Vector3 = c.global_position
			var frente := Vector3(sin(c.rotation.y), 0.0, cos(c.rotation.y))
			_cam.global_position = p + frente * 4.6 + Vector3.UP * 1.9
			_cam.look_at(p + Vector3.UP * 0.9)
			hallado = true
			break
	print("[VistaPeatones] vista 2: %s" % ("sentado encontrado" if hallado else "NADIE sentado ahora mismo"))


## Vista 3: un ciudadano tumbado en una reposera, desde el lado del mar.
## Devuelve false si ahora mismo no hay nadie tumbado (la vista reintenta).
func _vista_tumbado() -> bool:
	var hallado := false
	for c in _dir.peatones:
		if c.en_postura() and c.fase_postura() == "reposar" and c.postura_actual() == "recostarse":
			var p: Vector3 = c.global_position
			# Perfil: la cámara se pone al costado del cuerpo, algo elevada, para verse
			# el apoyo de la espalda en la lona y la cabeza en el cabezal.
			var ry: float = c.rotation.y
			var der := Vector3(cos(ry), 0.0, -sin(ry))
			_cam.global_position = p + der * 6.5 + Vector3.UP * 3.0
			_cam.look_at(p + Vector3.UP * 0.4)
			hallado = true
			break
	print("[VistaPeatones] vista 3: %s" % ("tumbado encontrado" if hallado else "nadie tumbado todavía"))
	return hallado


## Vista 5: el mismo cuerpo tumbado, de cerca y en perfil, para comprobar el apoyo
## sobre la lona (sin hundirse ni flotar) y la cabeza en el cabezal.
func _vista_tumbado_cerca() -> void:
	for c in _dir.peatones:
		if c.en_postura() and c.fase_postura() == "reposar" and c.postura_actual() == "recostarse":
			var p: Vector3 = c.global_position
			var ry: float = c.rotation.y
			var der := Vector3(cos(ry), 0.0, -sin(ry))
			_cam.global_position = p + der * 3.4 + Vector3.UP * 1.9
			_cam.look_at(p + Vector3.UP * 0.25)
			return


## Vista 4: la playa de noche: las reposeras vacías, la ciudad encendida detrás.
func _vista_playa_noche() -> void:
	var lista: Array = _ciudad._reposeras_datos
	if lista.is_empty():
		return
	var p: Vector3 = lista[int(lista.size() / 2.0)]["pos"]
	var hacia: Vector2 = Vector2(p.x, p.z).normalized()
	# La cámara se pone mar adentro mirando a la orilla: reposeras vacías delante y la
	# ciudad al fondo (para ver también las ventanas encendidas de la noche).
	_cam.global_position = p + Vector3(hacia.x, 0.0, hacia.y) * 11.0 + Vector3.UP * 3.2
	_cam.look_at(p + Vector3.UP * 1.2)
	var n := 0
	for c in _dir.peatones:
		if c.en_postura() and c.postura_actual() == "recostarse" and c.fase_postura() == "reposar":
			n += 1
	print("[VistaPeatones] vista 4 (noche): tumbados en este instante = %d" % n)


## Guarda la vista actual en disco (tras dibujar el fotograma).
func _capturar(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var ruta := "%s/%s.png" % [DIR_CAP, nombre]
	var err := img.save_png(ruta)
	print("[VistaPeatones] captura %s -> %s (%s)" % [nombre, ruta, "OK" if err == OK else str(err)])