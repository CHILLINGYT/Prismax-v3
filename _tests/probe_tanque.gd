extends Node3D

# SONDA temporal: replica la secuencia 1→2→3 de la suite de Fuerza (salto corto,
# carga a medias y carga al tope) imprimiendo el estado interno del tanque, para
# ver por qué el salto cargado dejaba de responder tras el segundo salto.

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

var _jug: ControladorLeo
var _stats: EstadisticasJugador

func _ready() -> void:
	call_deferred("_go")

func _esperar(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _estado(marca: String) -> void:
	print("  %-14s cargando=%s carga=%.2f aire=%s suelo=%s recup=%.2f ataque=%s estamina=%.1f vel_y=%.2f" % [
			marca, _jug.f_super_cargando, _jug.f_super_carga, _jug.f_salto_aire,
			_jug.is_on_floor(), _jug.f_recuperacion, _jug.f_ataque, _stats.stamina, _jug.velocity.y])

func _go() -> void:
	var suelo := StaticBody3D.new()
	var forma_s := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(200.0, 1.0, 200.0)
	forma_s.shape = caja
	suelo.add_child(forma_s)
	suelo.position = Vector3(0.0, -0.5, 0.0)
	add_child(suelo)
	_jug = JUGADOR.instantiate() as ControladorLeo
	_jug.position = Vector3(0.0, 0.1, 0.0)
	add_child(_jug)
	_stats = _jug.get_node("Estadisticas") as EstadisticasJugador
	await _esperar(25)
	_jug._on_transformacion_elegida(&"tanque")
	var t := 0
	while (int(_jug.forma) != 3 or _jug._transformando) and t < 900:
		await get_tree().physics_frame
		t += 1
	await _esperar(10)
	_estado("tras transformar")

	# 1) toque corto
	Input.action_press("saltar")
	await _esperar(3)
	Input.action_release("saltar")
	await _esperar(2)
	print("1) salto corto: vel=%.2f" % _jug.velocity.y)
	t = 0
	while t < 120 and not _jug.is_on_floor():
		await get_tree().physics_frame
		t += 1
	_estado("1) aterrizado")

	# 2) carga a medias
	Input.action_press("saltar")
	await _esperar(36)
	_estado("2) cargando")
	Input.action_release("saltar")
	await _esperar(2)
	print("2) impulso: vel=%.2f" % _jug.velocity.y)
	t = 0
	while t < 180 and not _jug.is_on_floor():
		await get_tree().physics_frame
		t += 1
	_estado("2) aterrizado")

	# 3) carga al tope (el caso que fallaba): seguir el estado cada 0.2 s
	Input.action_press("saltar")
	for i in 8:
		await _esperar(12)
		_estado("3) t=%.1f" % ((i + 1) * 0.2))
	Input.action_release("saltar")
	await _esperar(2)
	print("3) impulso: vel=%.2f" % _jug.velocity.y)
	await _esperar(30)
	_estado("3) después")
	print("FIN SONDA TANQUE")