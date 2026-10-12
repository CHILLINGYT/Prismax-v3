extends Node3D
## Sonda de MIRADA (temporal): pone al jugador delante de varios ciudadanos y lee los contadores
## del propio modificador de mirada (NPCLookAt): cuánto gira la cabeza (last_yaw), cuánto le
## queda de error respecto al objetivo (debug_error_deg) y con qué límite. Sirve para saber si la
## "cabeza girada" que se ve en juego la produce la mirada y si el giro es correcto o torcido.

var _juego: Node = null
var _ciudad: Node = null
var _dir: Node = null
var _cam: Camera3D = null
var _jugador: Node3D = null
var _t0 := 0
var _paso := 0
var _proxima := 0.0
var _i := 0
var _objetivos: Array = []


func _ready() -> void:
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
	Engine.time_scale = 8.0
	print("[SondaMirada] cargada")


func _process(_d: float) -> void:
	if _dir == null:
		_dir = _ciudad.get_node_or_null("CiudadGenerada/Peatones")
		if _dir == null:
			return
	var real := float(Time.get_ticks_msec() - _t0) / 1000.0
	match _paso:
		0:
			if real > 7.0:
				Engine.time_scale = 1.0
				for c in _dir.peatones:
					if not c.en_postura() and c.state == NPCCitizen.State.IDLE:
						_objetivos.append(c)
					if _objetivos.size() >= 6:
						break
				print("[SondaMirada] ciudadanos quietos elegidos: %d" % _objetivos.size())
				_paso = 1
				_proxima = real + 0.2
		1:
			if real >= _proxima:
				if _i >= _objetivos.size():
					print("[SondaMirada] fin")
					get_tree().quit()
					return
				var c: Object = _objetivos[_i]
				c.set_activity(NPCCitizen.Activity.NEAR)
				var ry: float = c.rotation.y
				var frente := Vector3(sin(ry), 0.0, cos(ry))
				if _jugador != null:
					_jugador.global_position = c.global_position + frente * 2.5
				# Cámara al lado, para ver la cabeza de perfil.
				var lado := frente.cross(Vector3.UP).normalized()
				_cam.global_position = c.global_position + frente * 2.2 + lado * 2.8 + Vector3.UP * 1.35
				_cam.look_at(c.global_position + Vector3.UP * 1.3)
				_paso = 2
				_proxima = real + 0.9
		2:
			if real >= _proxima:
				var c: Object = _objetivos[_i]
				var look: Object = c.get_node_or_null("LookAt")
				var watch: float = c.get("_watch")
				var linea := "sin modificador"
				if look != null:
					linea = "límite %.0f° | gira %.1f° (cabeza) %.1f° (pitch) | error al objetivo %.1f° | activo=%s" % [
							rad_to_deg(look.yaw_limit), look.last_yaw, look.last_pitch,
							look.debug_error_deg, str(look.last_applied)]
				print("[SondaMirada] %-22s watch=%.2f dist=%.1f m | %s" % [c.name, watch,
						(c.global_position.distance_to(_jugador.global_position) if _jugador != null else -1.0),
						linea])
				if _i == 0:
					await RenderingServer.frame_post_draw
					var img := get_viewport().get_texture().get_image()
					img.save_png("res://.backup_peatones/capturas/cap13_mirando_cerca.png")
					print("[SondaMirada] captura cap13_mirando_cerca -> OK")
				_i += 1
				_paso = 1
				_proxima = real + 0.15