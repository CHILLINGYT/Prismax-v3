extends Node3D

# SONDA temporal: imprime velocidad/posición/estado del velocista al caminar y
# al esprintar, para diagnosticar por qué la suite midió consumo casi nulo.

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

func _ready() -> void:
	call_deferred("_go")

func _esperar(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _go() -> void:
	var suelo := StaticBody3D.new()
	var forma_s := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(300.0, 1.0, 300.0)
	forma_s.shape = caja
	suelo.add_child(forma_s)
	suelo.position = Vector3(0.0, -0.5, 0.0)
	add_child(suelo)
	var jug := JUGADOR.instantiate() as ControladorLeo
	jug.position = Vector3(0.0, 0.1, 0.0)
	add_child(jug)
	await _esperar(30)
	print("estado inicial: forma=%d estado=%d" % [int(jug.forma), jug.estado])
	jug._on_transformacion_elegida(&"velocista")
	var t := 0
	while (int(jug.forma) != 1 or jug._transformando) and t < 900:
		await get_tree().physics_frame
		t += 1
	await _esperar(15)
	print("tras transformar: forma=%d estado=%d estamina=%.1f" % [
			int(jug.forma), jug.estado, (jug.get_node("Estadisticas") as EstadisticasJugador).stamina])
	Input.action_press("mover_adelante")
	for i in 10:
		await _esperar(6)
		print("  CAMINAR v=%.2f pos=(%.1f,%.1f,%.1f) estado=%d" % [
				Vector2(jug.velocity.x, jug.velocity.z).length(),
				jug.global_position.x, jug.global_position.y, jug.global_position.z, jug.estado])
	Input.action_release("mover_adelante")
	await _esperar(10)
	Input.action_press("mover_adelante")
	Input.action_press("correr")
	for i in 10:
		await _esperar(6)
		print("  CORRER v=%.2f pos=(%.1f,%.1f,%.1f) estado=%d" % [
				Vector2(jug.velocity.x, jug.velocity.z).length(),
				jug.global_position.x, jug.global_position.y, jug.global_position.z, jug.estado])
	Input.action_release("correr")
	Input.action_release("mover_adelante")
	await _esperar(10)
	print("FIN SONDA")