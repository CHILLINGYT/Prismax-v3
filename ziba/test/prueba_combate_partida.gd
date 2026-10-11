extends SceneTree

## Pruebas headless del combate de la PARTIDA (res://ziba/escenas/ziba_prototipo.tscn):
##
##  1) FreeFlow de la forma Combate (integrado desde el módulo de ataque):
##     el clic izquierdo selecciona objetivo y hace daño real; cambiar de
##     enemigo a mitad de combo redirige el SIGUIENTE golpe y reinicia la
##     cadena en el jab (20, no 24); un objetivo muerto no bloquea; en el aire
##     no se inicia la acción (regla aérea).
##  2) Doble salto de la forma Combate: impulso + reinicio REAL de la animación.
##  3) Caminata de la forma Combate: tope de reproducción 1.4x y calibración 2.95.
##  4) Golpe de agua (clic izq.): daño real, una vez por pulsación.
##  5) Combo del velocista (clic izq.): daño + empuje por golpe.
##  6) Supervelocidad (clic der.): daño + empuje del tramo, una vez por enemigo,
##     y el recorrido no se detiene al pasar por encima.
##
## Ejecutar: godot --headless -s "res://ziba/test/prueba_combate_partida.gd"

const ESCENA_PARTIDA := "res://ziba/escenas/ziba_prototipo.tscn"

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
	print("--- 0) Cargar la partida y activar los 6 enemigos")
	var partida: Node = (load(ESCENA_PARTIDA) as PackedScene).instantiate()
	get_root().add_child(partida)
	var ciudad: Node = null
	for i in 2400:
		await process_frame
		ciudad = partida.find_child("CiudadGenerada", true, false)
		if ciudad != null and ciudad.get_child_count() > 0:
			break
	_check(ciudad != null, "la ciudad se generó")
	var jugador: CharacterBody3D = partida.get_node_or_null("Jugador") as CharacterBody3D
	var spawner: Node = partida.get_node_or_null("EnemigosPrueba")
	var gestor: Node = partida.get_node_or_null("GestionEnemigosPrueba")
	_check(jugador != null and spawner != null and gestor != null,
			"jugador, spawner y gestor instalados")
	if jugador == null or spawner == null or gestor == null:
		partida.queue_free()
		return
	# Vida altísima: los enemigos golpean de verdad durante la prueba y no
	# queremos que el personaje muera a mitad de las comprobaciones.
	jugador.estadisticas.vida = 100000.0
	jugador.estadisticas.resistencia = 100000.0
	await _aterrizar(jugador)
	_check(jugador.is_on_floor(), "el jugador está sobre el terreno")
	spawner.activar()
	await _esperar_frames(4)
	var enemigos: Array = _enemigos_de(spawner)
	_check(enemigos.size() == 6, "6 enemigos activos (hay %d)" % enemigos.size())
	if enemigos.size() < 6:
		spawner.desactivar()
		partida.queue_free()
		return
	var a: Node3D = enemigos[0]
	var b: Node3D = enemigos[1]
	var c: Node3D = enemigos[2]

	print("--- 1) FreeFlow de la forma Combate")
	_check(await _transformar(jugador, &"combate"), "transformado a la forma Combate")
	await _preparar_objetivo(jugador, a, _enemigos_de(spawner), 1.4)
	await _pulsar("atacar")
	var elegido := await _hasta(func() -> bool: return jugador.c_objetivo != null, 60)
	_check(elegido and jugador.c_objetivo == a, "el clic izquierdo selecciona al enemigo de delante")
	var golpeado := await _hasta(func() -> bool: return a.health < a.max_health, 180)
	_check(golpeado, "el golpe hace daño real al enemigo")
	_check(absf(a.health - 80.0) < 0.01,
			"el primer golpe del combo es el jab (20 de daño; A quedó en %.1f)" % a.health)
	_check(gestor.combo.count >= 1, "el contador de combo del gestor registra el golpe")

	# Cambio de objetivo a mitad de combo: B delante, A detrás; el siguiente
	# ataque debe ir a B y REINICIAR la cadena en el jab (20 de daño, no 24).
	await _preparar_objetivo(jugador, b, _enemigos_de(spawner), 1.4)
	await _pulsar("atacar")
	var golpeado_b := await _hasta(func() -> bool: return b.health < b.max_health, 240)
	_check(golpeado_b, "el siguiente ataque se dirige al NUEVO objetivo (B)")
	_check(jugador.c_objetivo == b, "el objetivo actual es B")
	_check(absf(b.health - 80.0) < 0.01,
			"la cadena se reinició en jab al cambiar de enemigo (B quedó en %.1f)" % b.health)
	_check(absf(a.health - 80.0) < 0.01, "A no recibió el segundo golpe (siguió en %.1f)" % a.health)

	# Objetivo muerto: no bloquea la selección.
	await _preparar_objetivo(jugador, c, _enemigos_de(spawner), 1.4)
	b.take_hit(9999.0, Vector3.FORWARD, 0.0, 0.0)
	_check(not b.is_alive(), "B quedó derrotado")
	await _pulsar("atacar")
	var golpeado_c := await _hasta(func() -> bool: return c.health < c.max_health, 240)
	_check(golpeado_c, "con un objetivo muerto se elige a otro y se sigue (C)")
	_check(jugador.c_objetivo == c, "el objetivo actual pasó a C sin bloquearse")

	# Guard aéreo: en el aire no se inicia acción de combate.
	# (Los saltos solo arrancan desde el estado libre: se espera al final del
	# golpe anterior antes de pulsar.)
	await _hasta(func() -> bool: return jugador.c_estado == ControladorLeo.C_E.LIBRE, 240)
	await _pulsar("saltar")
	var en_aire := await _hasta(func() -> bool: return not jugador.is_on_floor(), 60)
	_check(en_aire, "salta para la prueba aérea")
	await _pulsar("atacar")
	await _esperar_frames(4)
	_check(jugador.c_estado == ControladorLeo.C_E.LIBRE,
			"en el aire el clic NO inicia acción de combate")
	await _aterrizar(jugador)
	await _preparar_objetivo(jugador, c, _enemigos_de(spawner), 1.4)
	await _pulsar("atacar")
	var golpe_suelo := await _hasta(func() -> bool: return c.health < 80.0, 240)
	_check(golpe_suelo, "en el suelo el ataque vuelve a funcionar (C en %.1f)" % c.health)

	print("--- 2) Doble salto de la forma Combate: la animación se reinicia")
	await _aterrizar(jugador)
	await _hasta(func() -> bool: return jugador.c_estado == ControladorLeo.C_E.LIBRE, 240)
	await _pulsar("saltar")
	var en_aire2 := await _hasta(func() -> bool: return not jugador.is_on_floor(), 60)
	await _esperar_frames(5)
	var pos1: float = jugador.anim_ataque.current_animation_position
	_check(en_aire2 and jugador.anim_ataque.current_animation == "jump",
			"el primer salto reproduce el clip de salto")
	_check(pos1 > 0.04, "y la animación avanza (%.3f s)" % pos1)
	await _pulsar("saltar")
	var vy2: float = jugador.velocity.y
	var pos2: float = jugador.anim_ataque.current_animation_position
	_check(vy2 >= 5.0, "el segundo salto vuelve a impulsar (vy=%.1f)" % vy2)
	_check(jugador.anim_ataque.current_animation == "jump" and pos2 < pos1,
			"y REINICIA la animación de salto (%.3f s -> %.3f s)" % [pos1, pos2])
	_check(pos2 < 0.1, "desde el principio (%.3f s)" % pos2)
	await _aterrizar(jugador)

	print("--- 3) Caminata de la forma Combate: tope 1.4x")
	await _hasta(func() -> bool: return jugador.c_estado == ControladorLeo.C_E.LIBRE, 240)
	Input.action_press("mover_adelante")
	await _esperar_frames(25)
	var rapidez: float = Vector2(jugador.velocity.x, jugador.velocity.z).length()
	var escala: float = jugador.anim_ataque.speed_scale
	Input.action_release("mover_adelante")
	# La calibración del clip corregido es 2.95 m/s; el tope debe ser 1.4
	# (el antiguo era 1.8). La escala también debe seguir a la velocidad real.
	var esperada: float = clampf(rapidez / 2.95, 0.8, 1.4)
	_check(escala <= 1.41, "la escala de caminata nunca pasa del tope 1.4 (mide %.2f)" % escala)
	_check(absf(escala - esperada) < 0.06,
			"la escala acompaña a la velocidad real (esperada %.2f, mide %.2f)" % [esperada, escala])
	print("      (velocidad de caminata medida: %.2f m/s)" % rapidez)
	await _esperar_frames(15)

	print("--- 4) Golpe de agua (clic izq.): daño real")
	_check(await _transformar(jugador, &"pes"), "transformado a la forma acuática")
	var d: Node3D = enemigos[3]
	await _preparar_objetivo(jugador, d, _enemigos_de(spawner), 1.2)
	jugador._iniciar_ataque_acuatico()
	var golpe_agua := await _hasta(func() -> bool: return d.health < d.max_health, 240)
	_check(golpe_agua, "el ataque acuático golpea al enemigo")
	_check(absf(d.health - 92.0) < 0.01,
			"le hizo exactamente 8 de daño (D quedó en %.1f)" % d.health)
	await _esperar_frames(90)
	_check(absf(d.health - 92.0) < 0.01, "el mismo golpe no vuelve a aplicarse (sin daño repetido)")

	print("--- 5) Combo del velocista (clic izq.): daño + empuje")
	_check(await _transformar(jugador, &"velocista"), "transformado a la forma velocista")
	var e: Node3D = enemigos[4]
	await _preparar_objetivo(jugador, e, _enemigos_de(spawner), 1.3)
	jugador.combate.intentar_golpe()
	# El empuje se mide en el MISMO frame: el muñeco aturdido frena a cero en
	# cuanto pasa un frame de física (su aceleración es alta).
	var empuje1: float = e.velocity.length()
	_check(absf(e.health - 93.0) < 0.01,
			"el primer golpe del combo hace 7 de daño (E quedó en %.1f)" % e.health)
	_check(empuje1 > 2.0, "y empuja al enemigo al vuelo (velocidad %.1f m/s)" % empuje1)
	jugador.combate.intentar_golpe()
	var empuje2: float = e.velocity.length()
	_check(absf(e.health - 84.0) < 0.01,
			"el segundo golpe hace 9 de daño (E quedó en %.1f)" % e.health)
	_check(empuje2 > 2.0, "y el segundo también empuja (velocidad %.1f m/s)" % empuje2)

	print("--- 6) Supervelocidad (clic der.): daño + empuje del recorrido")
	var f: Node3D = enemigos[5]
	await _preparar_objetivo(jugador, f, _enemigos_de(spawner), 3.0)
	var dir: Vector3 = _frente(jugador)
	var centro_f: Vector3 = f.global_position + Vector3.UP * 1.0
	jugador._aplicar_golpes_ejecucion(centro_f - dir * 2.0, centro_f + dir * 2.0, dir)
	var empuje_sh: float = f.velocity.length()
	_check(absf(f.health - 70.0) < 0.01,
			"la supervelocidad hace 30 de daño al alcanzarlo (F quedó en %.1f)" % f.health)
	_check(empuje_sh > 6.0, "y lo desplaza con fuerza (velocidad %.1f m/s)" % empuje_sh)
	_check(f.get_state_name() == "STUN", "el impacto lo aturde (estado %s)" % f.get_state_name())
	jugador._aplicar_golpes_ejecucion(centro_f - dir * 2.0, centro_f + dir * 2.0, dir)
	_check(absf(f.health - 70.0) < 0.01,
			"un mismo recorrido no vuelve a golpear al mismo enemigo (F quedó en %.1f)" % f.health)
	jugador._golpeados_ejecucion.clear()

	# Recorrido real: el estado EJECUCION usa el mismo tramo (puntos propios),
	# atraviesa al enemigo y CONTINÚA (no lo trata como pared).
	var dir2: Vector3 = _elegir_direccion_libre(jugador)
	await _preparar_objetivo(jugador, f, _enemigos_de(spawner), 2.6, dir2)
	var puntos: Array[Vector3] = [jugador.global_position + dir2 * 6.0]
	jugador._puntos = puntos
	jugador._idx = 0
	jugador._vel_trayecto = 30.0
	jugador._iniciar_recorrido()
	var atraveso := await _hasta(func() -> bool: return f.health < 70.0, 240)
	_check(atraveso, "el recorrido real golpea al enemigo al pasar (F quedó en %.1f)" % f.health)
	_check(absf(f.health - 40.0) < 0.01,
			"el golpe del recorrido vuelve a ser de 30 (F quedó en %.1f)" % f.health)
	var volvio := await _hasta(
			func() -> bool: return jugador.estado == ControladorLeo.Estado.NORMAL, 240)
	_check(volvio, "el recorrido terminó solo (el enemigo no lo detuvo)")

	spawner.desactivar()
	await _esperar_frames(4)
	partida.queue_free()
	await _esperar_frames(3)


## --- ayuda -------------------------------------------------------------

func _transformar(jugador: Node, id: StringName) -> bool:
	jugador._on_transformacion_elegida(id)
	var llego := false
	for i in 1200:
		await physics_frame
		if jugador._id_forma(jugador.forma) == id:
			llego = true
			break
	if not llego:
		return false
	await _esperar_frames(45)
	await _aterrizar(jugador)
	return true


func _pulsar(nombre: String) -> void:
	Input.action_press(nombre)
	await _esperar_frames(2)
	Input.action_release(nombre)


func _hasta(condicion: Callable, tope: int = 240) -> bool:
	for i in tope:
		await physics_frame
		if bool(condicion.call()):
			return true
	return false


func _aterrizar(jugador: CharacterBody3D) -> void:
	for i in 400:
		await physics_frame
		if jugador.is_on_floor():
			return


func _esperar_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _enemigos_de(spawner: Node) -> Array:
	var contenedor := spawner.get_node_or_null("EnemigosActivos")
	if contenedor == null:
		return []
	var lista: Array = []
	for h in contenedor.get_children():
		if is_instance_valid(h) and h.has_method("is_alive") and h.is_alive():
			lista.append(h)
	return lista


## Dirección horizontal que usa la cámara del jugador (frente "natural").
func _frente(jugador: CharacterBody3D) -> Vector3:
	var f: Vector3 = jugador._direccion_camara_horizontal()
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


func _orientar(jugador: CharacterBody3D, dir: Vector3) -> void:
	var yaw := atan2(-dir.x, -dir.z)
	jugador.ataque_visual.rotation.y = yaw
	jugador.acuatico.rotation.y = yaw
	jugador.visual.rotation.y = yaw


## Coloca a [param objetivo] a [param dist] del jugador, con el resto de enemigos
## detrás (fuera del cono de selección) y aturdidos: la elección de objetivo de
## cada ataque queda determinista. Devuelve la dirección usada.
func _preparar_objetivo(jugador: CharacterBody3D, objetivo: Node3D, todos: Array,
		dist: float, frente: Vector3 = Vector3.ZERO) -> Vector3:
	var dir: Vector3 = frente
	if dir.length_squared() < 0.0001:
		dir = _frente(jugador)
	else:
		dir = Vector3(dir.x, 0.0, dir.z).normalized()
	_orientar(jugador, dir)
	for e in todos:
		var t: Variant = e
		if t == objetivo:
			continue
		t.global_position = jugador.global_position - dir * 7.0
		t.velocity = Vector3.ZERO
		t.stun(30.0)
	objetivo.global_position = jugador.global_position + dir * dist
	objetivo.velocity = Vector3.ZERO
	objetivo.stun(30.0)
	await _esperar_frames(2)
	return dir


## Primera dirección con el camino despejado (para el recorrido de supervelocidad).
func _elegir_direccion_libre(jugador: CharacterBody3D) -> Vector3:
	var base := _frente(jugador)
	for giro in [0.0, PI * 0.5, -PI * 0.5, PI]:
		var dir: Vector3 = base.rotated(Vector3.UP, giro)
		var desde: Vector3 = jugador.global_position + Vector3.UP * 1.2
		var consulta := PhysicsRayQueryParameters3D.create(desde, desde + dir * 8.0)
		consulta.exclude = [jugador.get_rid()]
		var golpe := jugador.get_world_3d().direct_space_state.intersect_ray(consulta)
		if golpe.is_empty() or (golpe["position"] as Vector3).distance_to(desde) > 6.5:
			return dir
	return base