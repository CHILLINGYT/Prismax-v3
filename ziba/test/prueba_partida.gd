extends SceneTree

## Prueba headless de la PARTIDA real (res://ziba/escenas/ziba_prototipo.tscn):
##  - el puente del jugador con los sistemas externos (grupo "player",
##    is_alive(), take_damage() delegando en EstadisticasJugador)
##  - el spawner de enemigos (módulo "enemigos prueba") en la ciudad real:
##    activar / 6 en anillo válido / desactivar / reactivar
##  - la forma Combate: transformación por el mismo camino que usa el menú,
##    doble salto con control en el aire y sin tercer salto.
##
## Ejecutar: godot --headless -s "res://ziba/test/prueba_partida.gd"

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
	print("--- 0) Cargar la partida (la ciudad tarda unos segundos)")
	var partida: Node = (load(ESCENA_PARTIDA) as PackedScene).instantiate()
	get_root().add_child(partida)
	var ciudad: Node = null
	for i in 2400:
		await process_frame
		ciudad = partida.find_child("CiudadGenerada", true, false)
		if ciudad != null and ciudad.get_child_count() > 0:
			break
	_check(ciudad != null and ciudad.get_child_count() > 0,
			"la ciudad se generó (%d contenedores)" % (ciudad.get_child_count() if ciudad != null else 0))

	var jugador: CharacterBody3D = partida.get_node_or_null("Jugador") as CharacterBody3D
	_check(jugador != null, "la partida tiene jugador")
	if jugador == null:
		partida.queue_free()
		return
	for i in 600:
		await physics_frame
		if jugador.is_on_floor():
			break
	_check(jugador.is_on_floor(), "el jugador está sobre el terreno de la ciudad")

	print("--- 1) Puente con los sistemas externos")
	_check(jugador.is_in_group("player"), "el jugador está en el grupo \"player\"")
	_check(jugador.has_method("is_alive") and jugador.is_alive(), "is_alive() responde y es verdadero")
	var vida_antes: float = jugador.estadisticas.vida
	jugador.take_damage(5.0)
	_check(jugador.estadisticas.vida < vida_antes,
			"take_damage() integra el daño en el sistema de vida existente (%.0f -> %.0f)"
			% [vida_antes, jugador.estadisticas.vida])

	print("--- 2) Spawner de enemigos en la ciudad real")
	var spawner: Node = partida.get_node_or_null("EnemigosPrueba")
	_check(spawner != null, "el spawner está instalado en la escena de la partida")
	var gestor: Node = partida.get_node_or_null("GestionEnemigosPrueba")
	_check(gestor != null and gestor.is_in_group("combat_manager"), "el gestor de combate está en la escena y en su grupo")
	if spawner == null:
		partida.queue_free()
		return
	spawner.activar()
	await _esperar_frames(3)
	var enemigos: Array = _enemigos_de(spawner)
	_check(enemigos.size() == 6, "6 enemigos generados en la ciudad (hay %d)" % enemigos.size())
	var centro: Vector3 = jugador.global_position
	var anillo_ok := true
	var nivel_ok := true
	var separacion_ok := true
	var posiciones: Array = []
	for e in enemigos:
		var p: Vector3 = (e as Node3D).global_position
		posiciones.append(p)
		var d := Vector2(p.x - centro.x, p.z - centro.z).length()
		if d < 4.0 or d > 8.6:
			anillo_ok = false
			print("      (fuera del anillo: ", p, " a ", snappedf(d, 0.1), " m)")
		if absf(p.y - centro.y) > 1.6:
			nivel_ok = false
			print("      (fuera de nivel: ", p, ")")
	for i in posiciones.size():
		for j in range(i + 1, posiciones.size()):
			if Vector2(posiciones[i].x - posiciones[j].x, posiciones[i].z - posiciones[j].z).length() < 2.0:
				separacion_ok = false
	_check(anillo_ok, "el anillo rodea al jugador en la ciudad (sin aparecer lejos o sobre tejados)")
	_check(nivel_ok, "todas las apariciones están al nivel del jugador (ni techos ni aire)")
	_check(separacion_ok, "sin solapes entre enemigos")
	spawner.desactivar()
	await _esperar_frames(3)
	_check(_enemigos_de(spawner).size() == 0, "desactivar retira los 6 enemigos de la ciudad")
	spawner.activar()
	await _esperar_frames(3)
	_check(_enemigos_de(spawner).size() == 6, "reactivar vuelve a generar 6")
	spawner.desactivar()
	await _esperar_frames(3)

	print("--- 3) Forma Combate: transformación y doble salto")
	jugador._on_transformacion_elegida(&"combate")
	# La transformación es asíncrona: la forma cambia cuando termina su efecto
	# visual (el control queda bloqueado mientras dura). Esperar con tope.
	var llego := false
	for i in 1200:
		await physics_frame
		if jugador._id_forma(jugador.forma) == &"combate":
			llego = true
			break
	_check(llego, "la transformación deja la forma en combate (id=%s)" % jugador._id_forma(jugador.forma))
	# Un momento más para que el efecto termine y devuelva el control.
	await _esperar_frames(40)
	for i in 600:
		await physics_frame
		if jugador.is_on_floor():
			break
	_check(jugador.is_on_floor(), "en el suelo antes de saltar")
	var vy1: float = await _impulso_saltar(jugador)
	_check(vy1 > 5.5, "salto desde el suelo en forma combate (vy máx=%.2f)" % vy1)
	var vy2: float = await _impulso_saltar(jugador)
	_check(vy2 > 5.0, "doble salto en el aire (vy máx=%.2f)" % vy2)
	_check(vy2 < vy1 + 0.1, "el segundo impulso es más suave (%.2f < %.2f)" % [vy2, vy1])
	var vy_antes: float = jugador.velocity.y
	var vy3: float = await _impulso_saltar(jugador)
	_check(vy3 <= vy_antes + 0.6, "sin tercer salto antes de aterrizar (máx %.2f, antes %.2f)" % [vy3, vy_antes])
	# Control direccional en el aire.
	Input.action_press("mover_adelante")
	await _esperar_frames(10)
	Input.action_release("mover_adelante")
	var h := Vector2(jugador.velocity.x, jugador.velocity.z).length()
	_check(h > 0.5, "control direccional en el aire en forma combate (vel. horizontal %.2f)" % h)

	partida.queue_free()
	await _esperar_frames(3)


func _enemigos_de(spawner: Node) -> Array:
	var contenedor := spawner.get_node_or_null("EnemigosActivos")
	if contenedor == null:
		return []
	var lista: Array = []
	for h in contenedor.get_children():
		if is_instance_valid(h):
			lista.append(h)
	return lista


## Pulsa "saltar" manteniendo la tecla varios frames y devuelve el máximo de
## velocity.y (si se suelta antes de que el personaje procese el input, el
## "just pressed" se pierde).
func _impulso_saltar(jugador: CharacterBody3D) -> float:
	Input.action_press("saltar")
	var max_vy: float = -INF
	for i in 3:
		await physics_frame
		max_vy = maxf(max_vy, jugador.velocity.y)
	Input.action_release("saltar")
	return max_vy


func _esperar_frames(n: int) -> void:
	for i in n:
		await physics_frame