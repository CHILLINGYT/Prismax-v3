extends SceneTree

# DIAGNÓSTICO TEMPORAL del encolado aéreo de la forma Combate. Imprime, por
# fotograma, el estado del suelo, el estado del ataque y el tamaño del buffer.
# No forma parte del juego: se elimina al terminar la depuración.

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

var _jug: CharacterBody3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var mundo := Node3D.new()
	root.add_child(mundo)
	var suelo := StaticBody3D.new()
	suelo.position = Vector3(0.0, -0.5, 0.0)
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(40.0, 1.0, 40.0)
	forma.shape = caja
	suelo.add_child(forma)
	mundo.add_child(suelo)
	_jug = JUGADOR.instantiate()
	mundo.add_child(_jug)
	_jug.global_position = Vector3(0.0, 0.05, 0.0)
	for _i in 8:
		await physics_frame
	_jug._on_transformacion_elegida(&"combate")
	var t := 0
	while _jug.forma != 4 and t < 300:
		await physics_frame
		t += 1
	while _jug._transformando and t < 900:
		await physics_frame
		t += 1
	for _i in 20:
		await physics_frame
	var buf := func() -> int:
		return _jug._c_combo.peek_buffer().size() if _jug._c_combo != null else -1
	print("buffer inicial=", buf.call(), " estado=", _jug.c_estado, " floor=", _jug.is_on_floor())
	Input.action_press("saltar")
	await physics_frame
	Input.action_release("saltar")
	var aire := 0
	for _i in 60:
		await physics_frame
		if not _jug.is_on_floor():
			break
		aire += 1
	print("en aire tras ", aire, " frames de espera")
	for i in 60:
		Input.action_press("atacar")
		await physics_frame
		Input.action_release("atacar")
		print("i=", i, " floor=", _jug.is_on_floor(), " estado=", _jug.c_estado, " buffer=", buf.call())
		if _jug.is_on_floor():
			break
	for i in 12:
		await physics_frame
		print("post i=", i, " floor=", _jug.is_on_floor(), " estado=", _jug.c_estado, " buffer=", buf.call())
	quit(0)