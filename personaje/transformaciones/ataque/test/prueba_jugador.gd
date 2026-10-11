extends SceneTree

## Pruebas headless del jugador del módulo ataque
## (res://personaje/transformaciones/ataque/scenes/player.tscn).
##
## Comprueba: doble salto con control direccional en el aire y sin tercer salto,
## bloqueo de la selección de objetivo mientras está en el aire (y su vuelta al
## aterrizar) y la velocidad de reproducción del jab frente al resto de clips.
##
## Ejecutar: godot --headless -s "res://personaje/transformaciones/ataque/test/prueba_jugador.gd"

const PLAYER_SCENE := "res://personaje/transformaciones/ataque/scenes/player.tscn"
const ENEMY_SCENE := "res://enemigos prueba/scenes/enemy.tscn"
const LIBRERIA := "res://personaje/transformaciones/ataque/animations/player_anim_library.tres"

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
	print("--- 0) Librería: el clip walk es el corregido")
	var lib: AnimationLibrary = load(LIBRERIA)
	var walk: Animation = lib.get_animation("walk")
	_check(absf(walk.length - 0.6333) < 0.01, "walk dura 0.633 s (corregido), dura %.3f" % walk.length)
	_check(walk.loop_mode == Animation.LOOP_LINEAR, "walk está en bucle")
	_check(lib.get_animation("jab").length > 0.4 and lib.get_animation("jump") != null, "el resto de clips siguen en la librería")

	print("--- 1) Jab: velocidad de reproducción")
	var jugador: CharacterBody3D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	var mundo := _montar_mundo()
	mundo["raiz"].add_child(jugador)
	await _esperar_frames(6)
	var animador: AnimationPlayer = jugador.get_node("AnimationPlayer")
	animador.play_action("jab")
	var v_jab: float = animador.get_playing_speed()
	animador.play_action("dos")
	var v_dos: float = animador.get_playing_speed()
	animador.play_action("cros")
	var v_cros: float = animador.get_playing_speed()
	_check(absf(v_jab - 1.15) < 0.02, "el jab se reproduce a 1.15x (mide %.3f)" % v_jab)
	_check(absf(v_dos - 1.0) < 0.02, "el segundo golpe (dos) sigue a 1.0x (mide %.3f)" % v_dos)
	_check(absf(v_cros - 1.0) < 0.02, "el tercer golpe (cros) sigue a 1.0x (mide %.3f)" % v_cros)
	# Duración efectiva en pantalla = longitud del clip / velocidad de
	# reproducción. La lógica de daño y de encadenamiento usa los temporizadores
	# de SPRINT (que no se tocan): esto sólo mide el clip visual.
	var dur_jab: float = lib.get_animation("jab").length / v_jab
	var dur_dos: float = lib.get_animation("dos").length / v_dos
	_check(dur_jab > 0.38 and dur_jab < 0.44, "el jab dura ~0.41 s en pantalla (%.3f s)" % dur_jab)
	_check(dur_dos > 0.55 and dur_dos < 0.65, "el dos conserva su duración de 0.6 s (%.3f s)" % dur_dos)

	print("--- 1b) Caminata: tope de reproducción moderado (1.4x)")
	# update_locomotion es el único sitio donde el ciclo de caminar se escala:
	# a velocidad plena (6 m/s) el tope 1.4x limita el clip. La referencia sigue
	# siendo la calibración medida del clip corregido (2.95 m/s sin patinar).
	animador.update_locomotion(6.0, true)
	_check(absf(animador.speed_scale - 1.4) < 0.01,
			"a velocidad plena el ciclo va a 1.4x (mide %.2f)" % animador.speed_scale)
	_check(animador.current_animation == "walk", "y el clip sigue siendo walk (el corregido)")
	animador.update_locomotion(2.95, true)
	_check(absf(animador.speed_scale - 1.0) < 0.02,
			"a la velocidad de referencia (2.95) el ciclo va a 1.0x (mide %.2f)" % animador.speed_scale)

	print("--- 2) Salto simple y doble salto")
	await _aterrizar(jugador)
	_check(jugador.is_on_floor(), "el personaje está en el suelo antes de saltar")
	var vy_salto1: float = await _impulso_saltar(jugador)
	_check(vy_salto1 > 5.5, "salto desde el suelo: impulso hacia arriba (vy máx=%.2f)" % vy_salto1)
	_check(not jugador.is_on_floor(), "tras el primer salto está en el aire")
	# La animación de salto lleva un momento sonando: el segundo salto debe
	# REINICIARLA desde el principio (no continuarla a medias).
	await _esperar_frames(5)
	var pos_jump_1: float = animador.current_animation_position
	_check(pos_jump_1 > 0.04, "la animación de salto avanza durante el primer salto (%.3f s)" % pos_jump_1)
	var vy_salto2: float = await _impulso_saltar(jugador)
	_check(vy_salto2 > 5.5, "segundo salto en el aire: vuelve a impulsar (vy máx=%.2f)" % vy_salto2)
	var pos_jump_2: float = animador.current_animation_position
	_check(animador.current_animation == "jump" and pos_jump_2 < pos_jump_1,
			"el segundo salto reinicia la animación de salto (%.3f s -> %.3f s)" % [pos_jump_1, pos_jump_2])
	_check(pos_jump_2 < 0.1, "y vuelve a empezar desde el principio (%.3f s)" % pos_jump_2)
	_check(vy_salto2 < vy_salto1 + 0.1, "el segundo impulso es algo más suave, no infinito (%.2f < %.2f)" % [vy_salto2, vy_salto1])
	# Tercer intento en el mismo salto: no debe reimpulsar (sólo decrecer).
	var vy_antes_tercero: float = jugador.velocity.y
	var vy_tercero: float = await _impulso_saltar(jugador)
	_check(vy_tercero <= vy_antes_tercero + 0.6, "un tercer salto antes de aterrizar NO reimpulsa (máx %.2f, antes %.2f)" % [vy_tercero, vy_antes_tercero])

	print("--- 3) Control direccional en el aire")
	Input.action_press("mover_adelante")
	await _esperar_frames(10)
	Input.action_release("mover_adelante")
	var h_aire := Vector2(jugador.velocity.x, jugador.velocity.z).length()
	_check(h_aire > 0.5, "el personaje se desplaza con WASD en el aire (vel. horizontal %.2f)" % h_aire)

	print("--- 4) Selección de objetivo: bloqueada en el aire, activa en el suelo")
	await _aterrizar(jugador)
	# Enemigo de prueba a 2 m al frente (el personaje mira hacia -Z).
	var enemigo: Node3D = (load(ENEMY_SCENE) as PackedScene).instantiate()
	enemigo.position = jugador.global_position + Vector3(0, 0, -2.2)
	mundo["raiz"].add_child(enemigo)
	# Salud muy alta: sólo se prueba la selección, no queremos que el enemigo
	# (que sí golpea al jugador) mate al personaje durante la prueba.
	jugador.max_health = 100000.0
	jugador.health = 100000.0
	await _esperar_frames(3)
	Input.action_press("atacar")
	await _esperar_frames(2)
	Input.action_release("atacar")
	var objetivo_suelo: Node3D = jugador.get_target()
	_check(objetivo_suelo != null, "en el suelo ataca y selecciona al enemigo cercano (objetivo=%s)" % str(objetivo_suelo))
	# Deja terminar la acción por completo (vuelve al estado libre).
	for i in 400:
		await physics_frame
		if jugador.get_state_name() == "FREE":
			break
	# En el aire: salta y ataca; no debe seleccionar ni iniciar.
	Input.action_press("saltar")
	await _esperar_frames(2)
	Input.action_release("saltar")
	_check(not jugador.is_on_floor(), "está en el aire para la prueba de bloqueo")
	Input.action_press("atacar")
	await _esperar_frames(2)
	Input.action_release("atacar")
	await _esperar_frames(3)
	var estado_aire: String = jugador.get_state_name()
	_check(estado_aire == "FREE", "en el aire atacar no inicia acción (estado=%s)" % estado_aire)
	# Aterriza y ataca: vuelve a funcionar.
	await _aterrizar(jugador)
	Input.action_press("atacar")
	await _esperar_frames(2)
	Input.action_release("atacar")
	var objetivo_post: Node3D = jugador.get_target()
	_check(objetivo_post != null, "al aterrizar la selección de objetivo vuelve a funcionar (objetivo=%s)" % str(objetivo_post))

	# Limpieza.
	mundo["raiz"].queue_free()
	await _esperar_frames(2)


func _montar_mundo() -> Dictionary:
	var raiz := Node3D.new()
	raiz.name = "MundoPrueba"
	get_root().add_child(raiz)
	var suelo := StaticBody3D.new()
	var forma := BoxShape3D.new()
	forma.size = Vector3(40, 1, 40)
	var cs := CollisionShape3D.new()
	cs.shape = forma
	suelo.add_child(cs)
	suelo.position = Vector3(0, -0.5, 0)
	raiz.add_child(suelo)
	return {"raiz": raiz}


## Espera hasta que el personaje esté en el suelo (con tope de seguridad).
func _aterrizar(jugador: CharacterBody3D) -> void:
	jugador.velocity = Vector3.ZERO
	for i in 400:
		await physics_frame
		if jugador.is_on_floor():
			return


func _esperar_frames(n: int) -> void:
	for i in n:
		await physics_frame


## Pulsa "saltar" MANTENIENDO la tecla varios frames (si se suelta antes de que
## el personaje procese el input, el "just pressed" se pierde) y devuelve el
## máximo de velocity.y alcanzado durante esos frames.
func _impulso_saltar(jugador: CharacterBody3D) -> float:
	Input.action_press("saltar")
	var max_vy: float = -INF
	for i in 3:
		await physics_frame
		max_vy = maxf(max_vy, jugador.velocity.y)
	Input.action_release("saltar")
	return max_vy