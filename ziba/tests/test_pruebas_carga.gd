extends Node3D

# PRUEBAS 3, 4 y 5 para la correccion de la carga del poder.

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _pos_y(j: Node) -> float:
	return (j.get_node("Visual/Pose") as Node3D).position.y

func _ready() -> void:
	await _frames(80)
	var j: Node3D = $ZibaPrototipo.get_node("Jugador")
	var combate: Node = j.get_node("Combate")

	# PRUEBA 4: activar/desactivar la carga varias veces (sin acumular offset).
	for c in 4:
		Input.action_press("cargar_poder")
		await _frames(45)
		print("[P4] ciclo ", c, " EN carga:   pose.y=", snappedf(_pos_y(j), 0.001), " estado=", j.estado_actual())
		Input.action_release("cargar_poder")
		await _frames(45)
		print("[P4] ciclo ", c, " tras soltar: pose.y=", snappedf(_pos_y(j), 0.001), " estado=", j.estado_actual())

	# PRUEBA 3/5: tras la carga, los sistemas siguen funcionando.
	await _frames(30)
	print("[P3] pose.y en reposo final = ", snappedf(_pos_y(j), 0.001), " (debe ~0)")

	Input.action_press("atacar")
	await _frames(3)
	Input.action_release("atacar")
	await _frames(4)
	print("[P5] ataque: golpe_actual=", combate.golpe_actual())

	Input.action_press("mover_adelante")
	await _frames(20)
	print("[P5] caminar: vel_h=", snappedf(Vector3(j.velocity.x, 0, j.velocity.z).length(), 0.01))
	Input.action_release("mover_adelante")
	await _frames(20)

	Input.action_press("saltar")
	await _frames(2)
	Input.action_release("saltar")
	await _frames(3)
	print("[P5] salto: anim=", j._anim_actual, " vel_y=", snappedf(j.velocity.y, 0.01))
	await _frames(60)

	Input.action_press("dash")
	await _frames(2)
	Input.action_release("dash")
	await _frames(4)
	print("[P5] dash: estado=", j.estado_actual(), " (1=DASH)")

	print("[P] FIN")
	get_tree().quit()