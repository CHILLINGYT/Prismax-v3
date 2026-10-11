extends SceneTree

## Prueba headless del spawner de enemigos de prueba
## (res://enemigos prueba/scripts/test_enemy_spawner.gd).
##
## Comprueba: activación (6 en anillo válido), no duplicación, reposición al
## desaparecer un enemigo, desactivación (sólo retira los suyos y no repone),
## reactivación con el jugador desplazado y el aviso cuando no hay espacio.
##
## Ejecutar: godot --headless -s "res://enemigos prueba/test/prueba_spawner.gd"
## (o desde el editor con la herramienta de ejecución de scripts).

const SPAWNER := preload("res://enemigos prueba/scripts/test_enemy_spawner.gd")

var _fallos: int = 0


func _initialize() -> void:
	await _run()
	if _fallos == 0:
		print("=== RESULTADO: TODAS LAS PRUEBAS PASAN ===")
		quit(0)
	else:
		print("=== RESULTADO: ", _fallos, " FALLOS ===")
		quit(1)


func _check(condicion: bool, mensaje: String) -> void:
	if condicion:
		print("  PASA:  ", mensaje)
	else:
		_fallos += 1
		print("  FALLA: ", mensaje)


func _run() -> void:
	print("--- 1) Activación: 6 enemigos en anillo alrededor del jugador")
	var arena := _montar_arena(60.0, true)
	var jugador: Node3D = arena["jugador"]
	var spawner: Node = arena["spawner"]
	await _esperar_frames(5)

	_check(spawner.contar() == 0 and not spawner.esta_activo(), "el sistema arranca desactivado y vacío")
	spawner.activar()
	var enemigos: Array = _enemigos_de(spawner)
	_check(enemigos.size() == 6, "se generan 6 enemigos (hay %d)" % enemigos.size())
	if enemigos.size() != 6:
		_limpiar(arena["raiz"])
		await _esperar_frames(4)
		await _run_sin_espacio()
		return

	var centro: Vector3 = jugador.global_position
	var en_rango := true
	var sobre_suelo := true
	var fuera_edificio := true
	var lejos_del_jugador := true
	var posiciones: Array = []
	for e in enemigos:
		var p: Vector3 = (e as Node3D).global_position
		posiciones.append(p)
		var d := Vector2(p.x - centro.x, p.z - centro.z).length()
		if d < 4.0 or d > 8.6:
			en_rango = false
		if absf(p.y) > 0.5:
			sobre_suelo = false
		if d < 2.0:
			lejos_del_jugador = false
		# Huella del edificio (x 3-11, z -4..4) ampliada por el radio de la cápsula
		# del enemigo (0.5 m) menos 2 cm de tolerancia para contactos a ras.
		if p.x > 2.52 and p.x < 11.48 and p.z > -4.48 and p.z < 4.48:
			fuera_edificio = false
			print("      (aparición que invade el edificio: ", p, ")")
	_check(en_rango, "todas las apariciones están en el anillo de 4,5-8 m del jugador")
	_check(sobre_suelo, "todas las apariciones están apoyadas en el terreno (no en el aire)")
	_check(fuera_edificio, "ninguna aparición quedó dentro del edificio")
	_check(lejos_del_jugador, "ninguna aparición solapa al personaje")
	var separacion_ok := true
	for i in posiciones.size():
		for j in range(i + 1, posiciones.size()):
			var d2 := Vector2(posiciones[i].x - posiciones[j].x, posiciones[i].z - posiciones[j].z).length()
			if d2 < 2.0:
				separacion_ok = false
	_check(separacion_ok, "sin solapes entre enemigos (separación >= 2 m)")

	print("--- 2) Volver a activar no duplica")
	spawner.activar()
	_check(_enemigos_de(spawner).size() == 6, "sigue habiendo 6 tras una segunda activación")
	spawner.alternar()
	await _esperar_frames(2)
	_check(not spawner.esta_activo(), "alternar() estando activo lo desactiva")
	spawner.activar()
	_check(_enemigos_de(spawner).size() == 6, "reactivar genera 6 (no 12)")

	print("--- 3) Reposición: si un enemigo desaparece, se repone")
	# Deja que los enemigos corran su primer frame de física (resuelven
	# configuración y objetivo) antes de matar a uno.
	await _esperar_frames(4)
	var victima: Node = _enemigos_de(spawner)[0]
	if victima.has_method("take_hit"):
		victima.take_hit(999.0, Vector3.ZERO, 0.0, 0.0)
	await create_timer(1.8).timeout
	_check(_enemigos_de(spawner).size() == 6, "vuelve a haber 6 tras morir uno (hay %d)" % _enemigos_de(spawner).size())

	print("--- 4) Desactivar: retira sólo los suyos y no repone")
	spawner.desactivar()
	await _esperar_frames(3)
	_check(_enemigos_de(spawner).size() == 0, "tras desactivar hay 0 enemigos")
	await create_timer(0.8).timeout
	_check(_enemigos_de(spawner).size() == 0, "desactivado no repone nada")
	_check(not spawner.esta_activo(), "esta_activo() es false")

	print("--- 5) Reactivar con el jugador desplazado: nuevo anillo")
	jugador.global_position = Vector3(20.0, 0.2, 20.0)
	await _esperar_frames(5)
	spawner.activar()
	enemigos = _enemigos_de(spawner)
	_check(enemigos.size() == 6, "vuelve a generar 6 tras desplazarse (hay %d)" % enemigos.size())
	var centro2: Vector3 = jugador.global_position
	var anillo_ok := true
	for e in enemigos:
		var p2: Vector3 = (e as Node3D).global_position
		var d3 := Vector2(p2.x - centro2.x, p2.z - centro2.z).length()
		if d3 < 4.0 or d3 > 8.6:
			anillo_ok = false
	_check(anillo_ok, "el anillo se forma alrededor de la posición actual del jugador")

	spawner.desactivar()
	_limpiar(arena["raiz"])
	await _esperar_frames(5)
	await _run_sin_espacio()


func _run_sin_espacio() -> void:
	print("--- 6) Sin espacio válido: informa y no genera")
	# Plataforma de 6x6: todo el anillo (>= 4,5 m) cae fuera de ella.
	var arena := _montar_arena(6.0, false)
	var spawner: Node = arena["spawner"]
	await _esperar_frames(5)
	spawner.activar()
	_check(spawner.contar() == 0, "sin suelo válido alrededor no genera enemigos (hay %d)" % spawner.contar())
	_limpiar(arena["raiz"])
	await _esperar_frames(3)


func _montar_arena(tamano_suelo: float, con_edificio: bool) -> Dictionary:
	var raiz := Node3D.new()
	raiz.name = "ArenaPrueba"
	get_root().add_child(raiz)

	var suelo := StaticBody3D.new()
	var forma_suelo := BoxShape3D.new()
	forma_suelo.size = Vector3(tamano_suelo, 1.0, tamano_suelo)
	var cs := CollisionShape3D.new()
	cs.shape = forma_suelo
	suelo.add_child(cs)
	suelo.position = Vector3(0, -0.5, 0)
	raiz.add_child(suelo)

	if con_edificio:
		var edificio := StaticBody3D.new()
		var forma_ed := BoxShape3D.new()
		forma_ed.size = Vector3(8, 8, 8)
		var cse := CollisionShape3D.new()
		cse.shape = forma_ed
		edificio.add_child(cse)
		edificio.position = Vector3(7, 4, 0)
		raiz.add_child(edificio)

	# Jugador ficticio: grupo "player", es lo único que el spawner consulta.
	var jugador := CharacterBody3D.new()
	jugador.name = "JugadorPrueba"
	var capsula := CapsuleShape3D.new()
	capsula.radius = 0.5
	capsula.height = 1.8
	var csj := CollisionShape3D.new()
	csj.shape = capsula
	csj.position = Vector3(0, 0.9, 0)
	jugador.add_child(csj)
	jugador.add_to_group("player")
	jugador.position = Vector3(0, 0.05, 0)
	raiz.add_child(jugador)

	var spawner := SPAWNER.new()
	spawner.name = "SpawnerPrueba"
	raiz.add_child(spawner)
	return {"raiz": raiz, "jugador": jugador, "spawner": spawner}


func _enemigos_de(spawner: Node) -> Array:
	var contenedor := spawner.get_node_or_null("EnemigosActivos")
	if contenedor == null:
		return []
	var lista: Array = []
	for h in contenedor.get_children():
		if is_instance_valid(h):
			lista.append(h)
	return lista


func _limpiar(raiz: Node) -> void:
	raiz.queue_free()


func _esperar_frames(n: int) -> void:
	for i in n:
		await physics_frame