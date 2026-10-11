extends Node3D
## Vista de POSTURAS de peatones (temporal, no forma parte del juego).
##
## Carga la escena real y guarda primeros planos para juzgar la POSTURA de los modelos y de los
## ciudadanos en juego: de pie andando (frente y perfil), parado, mirando al jugador, sentado en
## banco y tumbado en reposera. Termina sola. PNG en res://.backup_peatones/capturas/.

const DIR_CAP := "res://.backup_peatones/capturas"

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null
var _cam: Camera3D = null
var _jugador: Node3D = null
var _t0 := 0
var _paso := 0
var _proxima := 0.0
var _limite := 0.0
var _objetivo: Node = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR_CAP))
	_juego = (load("res://ziba/escenas/ziba_prototipo.tscn") as PackedScene).instantiate()
	_ciudad = _juego.get_node("Ciudad")
	_ciudad.semilla = 20260707
	add_child(_juego)
	_jugador = _juego.get_node_or_null("Jugador") as Node3D
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.08
	add_child(_cam)
	_cam.make_current()
	_t0 = Time.get_ticks_msec()
	Engine.time_scale = 12.0
	print("[VistaPostura] cargada; esperando a la ciudad...")


func _process(_d: float) -> void:
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
				_proxima = real + 0.8
		1:
			if real >= _proxima:
				_andando("frente")
				_capturar("cap6_andando_frente")
				_paso = 2
				_proxima = real + 0.5
		2:
			if real >= _proxima:
				_andando("perfil")
				_capturar("cap7_andando_perfil")
				_paso = 3
				_proxima = real + 0.5
		3:
			if real >= _proxima:
				_parado("frente")
				_capturar("cap8_parado_frente")
				_paso = 4
				_proxima = real + 0.5
		4:
			if real >= _proxima:
				_parado("perfil")
				_capturar("cap9_parado_perfil")
				_paso = 5
				_proxima = real + 0.5
		5:
			if real >= _proxima:
				_mirando()
				_capturar("cap10_mirando_jugador")
				_paso = 6
				_proxima = real
				_limite = real + 5.0
				Engine.time_scale = 3.0
		6:
			if real >= _proxima:
				if _tumbado() or real > _limite:
					Engine.time_scale = 1.0
					_capturar("cap11_tumbado_perfil")
					_paso = 7
					_proxima = real + 0.6
				else:
					_proxima = real + 0.5
		7:
			if real >= _proxima:
				_sentado()
				_capturar("cap12_sentado_frente")
				_paso = 8
				_proxima = real + 0.5
		8:
			if real >= _proxima:
				print("[VistaPostura] fin")
				get_tree().quit()


# ------------------------------------------------------------------ vistas

## Un ciudadano andando, visto de frente o de perfil, a distancia de retrato.
func _andando(tipo: String) -> void:
	var elegido: Object = null
	for c in _dir.peatones:
		if c.is_walking() and c.velocidad_real() > 0.35:
			elegido = c
			break
	if elegido == null:
		print("[VistaPostura] no hay nadie andando (vista %s)" % tipo)
		return
	_preparar(elegido)
	var p: Vector3 = elegido.global_position
	var ry: float = elegido.rotation.y
	_encuadrar(p, ry, tipo)
	print("[VistaPostura] %s andando: %s (vel %.2f m/s)" % [tipo, _objetivo.name, elegido.velocidad_real()])


## Un ciudadano parado (quieto, no en postura de banco).
func _parado(tipo: String) -> void:
	var elegido: Object = null
	for c in _dir.peatones:
		if c.state == NPCCitizen.State.IDLE and not c.en_postura():
			elegido = c
			break
	if elegido == null:
		print("[VistaPostura] no hay nadie parado (vista %s)" % tipo)
		return
	_preparar(elegido)
	_encuadrar(elegido.global_position, elegido.rotation.y, tipo)
	print("[VistaPostura] %s parado: %s" % [tipo, _objetivo.name])


## Ilustración de la mirada: el jugador se coloca delante del ciudadano y se mira desde un lado.
func _mirando() -> void:
	var elegido: Object = null
	for c in _dir.peatones:
		if c.state == NPCCitizen.State.IDLE and not c.en_postura():
			elegido = c
			break
	if elegido == null:
		print("[VistaPostura] no hay nadie para la vista de mirada")
		return
	_preparar(elegido)
	var p: Vector3 = elegido.global_position
	var ry: float = elegido.rotation.y
	var frente := Vector3(sin(ry), 0.0, cos(ry))
	# El jugador, 2,5 m delante: debe girar la cabeza hacia él (y sólo la cabeza).
	if _jugador != null:
		_jugador.global_position = p + frente * 2.5 + Vector3.UP * 0.2
	# La cámara mira desde un lado, para que se vea el giro de la cabeza.
	var lado := frente.cross(Vector3.UP).normalized()
	_cam.global_position = p + frente * 2.0 + lado * 3.0 + Vector3.UP * 1.3
	_cam.look_at(p + Vector3.UP * 1.35)
	var look: Object = elegido.get_node_or_null("LookTarget")
	print("[VistaPostura] mirando: %s | look=%s" % [_objetivo.name, str(look != null)])


## Un ciudadano tumbado en reposera, de perfil y de cerca.
func _tumbado() -> bool:
	var elegido: Object = null
	for c in _dir.peatones:
		if c.en_postura() and c.fase_postura() == "reposar" and c.postura_actual() == "recostarse":
			elegido = c
			break
	if elegido == null:
		print("[VistaPostura] nadie tumbado todavía")
		return false
	_preparar(elegido)
	var p: Vector3 = elegido.global_position
	var ry: float = elegido.rotation.y
	var der := Vector3(cos(ry), 0.0, -sin(ry))
	_cam.global_position = p + der * 3.2 + Vector3.UP * 1.7
	_cam.look_at(p + Vector3.UP * 0.3)
	print("[VistaPostura] tumbado: %s" % _objetivo.name)
	return true


## Un ciudadano sentado en un banco, de frente y de cerca.
func _sentado() -> void:
	var elegido: Object = null
	for c in _dir.peatones:
		if c.en_postura() and c.fase_postura() == "reposar" and c.postura_actual() == "sentarse":
			elegido = c
			break
	if elegido == null:
		print("[VistaPostura] nadie sentado ahora mismo")
		return
	_preparar(elegido)
	var p: Vector3 = elegido.global_position
	var ry: float = elegido.rotation.y
	var frente := Vector3(sin(ry), 0.0, cos(ry))
	_cam.global_position = p + frente * 3.0 + Vector3.UP * 1.5
	_cam.look_at(p + Vector3.UP * 0.85)
	print("[VistaPostura] sentado: %s" % _objetivo.name)


## Deja al ciudadano elegido en nivel de actividad NEAR: su animación corre aunque el jugador
## esté lejos (el LOD apaga la animación de los lejanos y falsearía la foto).
func _preparar(c: Object) -> void:
	_objetivo = c
	c.set_activity(NPCCitizen.Activity.NEAR)


func _encuadrar(p: Vector3, ry: float, tipo: String) -> void:
	var frente := Vector3(sin(ry), 0.0, cos(ry))
	var lado := frente.cross(Vector3.UP).normalized()
	if tipo == "frente":
		_cam.global_position = p + frente * 3.1 + Vector3.UP * 1.45
	else:
		_cam.global_position = p + lado * 3.1 + Vector3.UP * 1.35
	_cam.look_at(p + Vector3.UP * 0.95)


func _capturar(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [DIR_CAP, nombre])
	print("[VistaPostura] captura %s -> %s" % [nombre, "OK" if err == OK else str(err)])